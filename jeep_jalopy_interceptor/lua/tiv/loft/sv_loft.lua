-- ============================================================================
-- TIV LOFT SYSTEM
-- ============================================================================

TIV.Loft = TIV.Loft or {}

util.AddNetworkString("TIV_LoftEvent")
util.AddNetworkString("TIV_AnchorWarning")

TIV.Loft.WindTimers    = TIV.Loft.WindTimers    or {}
TIV.Loft.FailingGroups = TIV.Loft.FailingGroups or {}

TIV.Loft.SpikeGroups = {
    rear  = { 5, 6 },
    mid   = { 3, 4 },
    front = { 1, 2 },
}

-- Drives StartDirectionalFailure (was dead config that lied about the timing).
TIV.Loft.FailureSequence = {
    { group = "rear",  startTime = 0.0, duration = 0.9 },
    { group = "mid",   startTime = 1.0, duration = 0.9 },
    { group = "front", startTime = 2.0, duration = 0.9 },
}

local function ReleaseSpikesOnLoft()
    local cv = GetConVar("tiv_loft_release_spikes")
    return cv and cv:GetBool() or false
end

CreateConVar("tiv_loft_release_spikes", "0",
    { FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED },
    "If 1, spikes fly free as debris on loft. If 0, they stay parented to the vehicle.")

-- ============================================================================
-- STRESS CALCULATION
-- ============================================================================
function TIV.Loft.CalculateStress(windMPH)
    if windMPH < 100 then return 0 end
    local ratio = windMPH / TIV.Config.LoftWindThreshold
    return math.Clamp(ratio * ratio, 0, 1)
end

local function GetWindScale()
    if TIV.Compat and TIV.Compat.Enabled then
        return TIV.Compat.AnchoredWindForceScale or 0.65
    end
    return 1
end
TIV.Loft.GetWindScale = GetWindScale

local function ClearGroupFailTimers(prefix)
    for _, step in ipairs(TIV.Loft.FailureSequence) do
        timer.Remove(prefix .. "_" .. step.group)
    end
end

-- ============================================================================
-- FAIL GROUP
-- ============================================================================
function TIV.Loft.FailGroup(veh, data, groupName, duration)
    local spikeIndices = TIV.Loft.SpikeGroups[groupName]
    if not spikeIndices then return end

    -- Skip if no live spikes remain in this group.
    local liveCount = 0
    for _, idx in ipairs(spikeIndices) do
        for _, sd in ipairs(data.spikes or {}) do
            if sd.index == idx and IsValid(sd.entity) then
                liveCount = liveCount + 1
                break
            end
        end
    end
    if liveCount == 0 then return end

    if IsValid(veh) then
        veh:EmitSound("physics/metal/metal_box_break1.wav", 80, 50)
    end

    local staggerPerSpike = duration / #spikeIndices

    for i, spikeIdx in ipairs(spikeIndices) do
        local delay = (i - 1) * staggerPerSpike
            + math.Rand(0, staggerPerSpike * 0.3)

        timer.Simple(delay, function()
            if not IsValid(veh) then return end
            if data.state ~= "anchored" then return end

            -- Real bug fix: was re-enabling gravity on every spike. Now only
            -- the first failed spike triggers the gravity release.
            if not data.gravityReleased then
                data.gravityReleased = true
                local vehPhys = veh:GetPhysicsObject()
                if IsValid(vehPhys) then
                    vehPhys:EnableGravity(true)
                end
            end

            local spikeEnt, spikeData
            for _, sd in ipairs(data.spikes or {}) do
                if sd.index == spikeIdx and IsValid(sd.entity) then
                    spikeEnt  = sd.entity
                    spikeData = sd
                    break
                end
            end

            if IsValid(spikeEnt) then
                local spikePhys = spikeEnt:GetPhysicsObject()
                if IsValid(spikePhys) then
                    spikePhys:EnableMotion(true)
                    spikePhys:EnableGravity(true)
                    spikePhys:Wake()

                    local windScale = GetWindScale()
                    local windForce = TIV.Wind.GetForceVector(veh) * spikePhys:GetMass() * 1.5 * windScale
                    local upForce   = Vector(0, 0, 1) * spikePhys:GetMass() * 700
                    -- Pull force reduced from 1200 -> 200; was so high spikes
                    -- visibly teleported into the underside before reparent.
                    local pullToVeh = (veh:GetPos() - spikeEnt:GetPos()):GetNormalized()
                        * spikePhys:GetMass() * 200

                    spikePhys:ApplyForceCenter(windForce + upForce + pullToVeh)
                    spikePhys:ApplyTorqueCenter(VectorRand() * 500)
                end

                spikeEnt:SetCollisionGroup(COLLISION_GROUP_NONE)

                local sparkFX = EffectData()
                sparkFX:SetOrigin(spikeEnt:GetPos())
                sparkFX:SetMagnitude(8)
                sparkFX:SetScale(3)
                util.Effect("Sparks", sparkFX)

                spikeEnt:EmitSound("physics/metal/metal_box_break"
                    .. math.random(1, 2) .. ".wav", 90, math.random(60, 80))
                util.ScreenShake(spikeEnt:GetPos(), 12, 14, 0.8, 400)
            end

            TIV.Anchor.BreakSpike(veh, data, spikeIdx)

            -- Reparent spike to vehicle after a brief moment.
            timer.Simple(0.12, function()
                if not IsValid(veh) or not IsValid(spikeEnt) or not spikeData then return end
                if TIV.SpikeAnim and TIV.SpikeAnim.ReparentSpike then
                    TIV.SpikeAnim.ReparentSpike(veh, spikeEnt, spikeData)
                end
                if data.spikeAnims and spikeIdx then
                    data.spikeAnims[spikeIdx] = "idle"
                end
            end)

            local remainingBS = 0
            for _, c in ipairs(data.constraints or {}) do
                if c.type == "ballsocket" and IsValid(c.constraint) then
                    remainingBS = remainingBS + 1
                end
            end

            net.Start("TIV_AnchorWarning")
                net.WriteEntity(veh)
                net.WriteUInt(spikeIdx, 8)
            net.Broadcast()

            if remainingBS == 0 then
                TIV.Loft.TriggerLoft(veh, data)
            end
        end)
    end
end

-- ============================================================================
-- START FAILURE SEQUENCE
-- Driven by TIV.Loft.FailureSequence (was hardcoded inline).
-- ============================================================================
function TIV.Loft.StartDirectionalFailure(veh, data)
    if not IsValid(veh) or not data then return end
    if data.state ~= "anchored" then return end

    local entIndex = veh:EntIndex()
    if TIV.Loft.WindTimers[entIndex] then return end

    local prefix = "TIV_GroupFail_" .. entIndex

    TIV.Loft.WindTimers[entIndex]    = CurTime()
    TIV.Loft.FailingGroups[entIndex] = true

    print(string.format(
        "[TIV] Vehicle #%d exceeded %.0f MPH. Failure order: REAR -> MID -> FRONT",
        entIndex, TIV.Config.LoftWindThreshold))

    veh:EmitSound("ambient/alarms/warningbell1.wav", 80)

    for _, step in ipairs(TIV.Loft.FailureSequence) do
        local stepGroup, stepDuration = step.group, step.duration
        timer.Create(prefix .. "_" .. stepGroup, step.startTime, 1, function()
            if not IsValid(veh) or data.state ~= "anchored" then return end
            TIV.Loft.FailGroup(veh, data, stepGroup, stepDuration)
        end)
    end
end

-- Centralized cleanup of failure timers + tracking tables.
local function CleanupLoftTracking(entIdx)
    TIV.Loft.WindTimers[entIdx]    = nil
    TIV.Loft.FailingGroups[entIdx] = nil
    ClearGroupFailTimers("TIV_GroupFail_" .. entIdx)
end
TIV.Loft.CleanupTracking = CleanupLoftTracking

-- ============================================================================
-- TRIGGER FULL LOFT
-- ============================================================================
function TIV.Loft.TriggerLoft(veh, data)
    if not IsValid(veh) then return end
    if data.state == "lofted" then return end

    local entIdx     = veh:EntIndex()
    local sessionID  = data.sessionID  -- capture for closure identity check

    print("[TIV] ================================")
    print("[TIV] === TIV LOFT TRIGGERED       ===")
    print(string.format("[TIV] === Wind: %.0f MPH at t=%.2f ===",
        TIV.Wind.GetSpeed(veh), CurTime()))
    print("[TIV] ================================")

    TIV.Anchor.ForceDetach(veh, data)

    data.state    = "lofted"
    data.anchored = false

    local phys = veh:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableGravity(true)
        phys:EnableMotion(true)
        phys:Wake()

        local upForce   = Vector(0, 0, 1) * phys:GetMass() * TIV.Config.LoftForceMultiplier
        local windForce = TIV.Wind.GetForceVector(veh) * phys:GetMass() * 0.5
        local tumble    = VectorRand() * TIV.Config.LoftTumbleForce

        phys:ApplyForceCenter(upForce)
        phys:ApplyForceCenter(windForce)
        phys:ApplyTorqueCenter(tumble)
    end

    -- Either fling spikes as debris or keep them parented (admin's choice).
    if ReleaseSpikesOnLoft() then
        if TIV.Spikes.ReleaseAll then
            TIV.Spikes.ReleaseAll(data)
        end
    else
        for _, sd in ipairs(data.spikes or {}) do
            if IsValid(sd.entity) and TIV.SpikeAnim and TIV.SpikeAnim.ReparentSpike then
                TIV.SpikeAnim.ReparentSpike(veh, sd.entity, sd)
                if data.spikeAnims and sd.index then
                    data.spikeAnims[sd.index] = "idle"
                end
            end
        end
    end

    util.ScreenShake(veh:GetPos(), 25, 15, 3, 800)

    net.Start("TIV_LoftEvent")
        net.WriteEntity(veh)
    net.Broadcast()

    TIV.Deploy.BroadcastState(veh, "lofted")

    CleanupLoftTracking(entIdx)

    -- Real bug fix: previously captured `data` and `veh` directly; if the
    -- vehicle was removed and EntIndex reused in 15s, the closure would
    -- mutate orphaned state. Now re-fetches by EntIndex and verifies session.
    timer.Simple(15, function()
        local liveVeh  = Entity(entIdx)
        local liveData = TIV.Deploy.Vehicles and TIV.Deploy.Vehicles[entIdx]

        -- Vehicle gone or replaced with a different session -- bail out.
        if not liveData then return end
        if liveData.sessionID ~= sessionID then return end

        if liveData.spikes then
            for _, sd in ipairs(liveData.spikes) do
                if IsValid(sd.entity) then SafeRemoveEntity(sd.entity) end
            end
        end
        liveData.spikes        = {}
        liveData.spikeAnims    = {}
        liveData.spikesCreated = false
        liveData.state         = "idle"
        liveData.anchored      = false
        liveData.gravityReleased = false

        if IsValid(liveVeh) then
            TIV.Deploy.BroadcastState(liveVeh, "idle")
        end
    end)
end

-- ============================================================================
-- MAIN LOFT THINK
-- Reindented so structure matches nesting (was visually misleading).
-- ============================================================================
timer.Create("TIV_LoftThink", 0.05, 0, function()
    for entIndex, data in pairs(TIV.Deploy.Vehicles or {}) do
        if data.state == "anchored" then
            local veh = Entity(entIndex)
            if IsValid(veh) then
                local phys = veh:GetPhysicsObject()
                if IsValid(phys) then
                    local windMPH = TIV.Wind.GetSpeed(veh)
                    local stress  = TIV.Loft.CalculateStress(windMPH)
                    local windScale = GetWindScale()
                    -- Cache the force vector once per vehicle per tick.
                    local windForceVec = TIV.Wind.GetForceVector(veh)

                    -- ===== ANCHOR GUARD =====
                    -- Tornado mods (GStorms, XT3) have a "prop unweld"
                    -- feature that calls constraint.RemoveAll() on props in
                    -- high wind. Our spikes look like regular props to them.
                    --
                    -- Defense in depth:
                    --   1) Re-freeze any spike whose motion got turned back on.
                    --   2) Re-create the vehicle->spike ballsocket if it's
                    --      gone but the spike entity still exists.
                    --   3) Mark spikes with networked vars some mods respect.
                    for _, sd in ipairs(data.spikes or {}) do
                        if sd.phase == "deployed" and IsValid(sd.entity) and sd.groundPos then
                            -- Position / motion guard
                            local sp = sd.entity:GetPhysicsObject()
                            if IsValid(sp) and sp:IsMotionEnabled() then
                                local plantedZ = sd.groundPos.z - (TIV.Config.SpikeDriveDepth or 15)
                                local target = Vector(sd.groundPos.x, sd.groundPos.y, plantedZ)
                                sd.entity:SetPos(target)
                                sp:SetVelocity(Vector(0, 0, 0))
                                sp:SetAngleVelocity(Vector(0, 0, 0))
                                sp:EnableMotion(false)
                                sp:EnableGravity(false)
                            end

                            -- Ballsocket-still-exists guard
                            local hasBS = false
                            for _, c in ipairs(data.constraints or {}) do
                                if c.spikeIndex == sd.index
                                        and c.type == "ballsocket"
                                        and IsValid(c.constraint) then
                                    hasBS = true
                                    break
                                end
                            end
                            if not hasBS then
                                -- The tornado mod (or something else) yanked
                                -- our ballsocket. Recreate it.
                                if TIV.Anchor and TIV.Anchor.AttachSingle then
                                    -- Clean up any stale entries for this spike
                                    for i = #(data.constraints or {}), 1, -1 do
                                        if data.constraints[i].spikeIndex == sd.index then
                                            table.remove(data.constraints, i)
                                        end
                                    end
                                    TIV.Anchor.AttachSingle(veh, data, sd, sd.index)
                                end
                            end
                        end
                    end

                    -- ===== ALWAYS APPLY WIND FORCE =====
                    if windMPH > TIV.Config.Stress.TurbulenceMinMPH then
                        local windForce = windForceVec
                            * phys:GetMass()
                            * TIV.Config.AnchoredWindForce
                            * windScale

                        local turbulence = VectorRand() * phys:GetMass() * (stress * 20)
                        phys:ApplyForceCenter(windForce + turbulence)

                        if stress > TIV.Config.Stress.TorqueMin then
                            local rockScale = tonumber(TIV.Config.AnchoredRockTorque) or 5.5
                            local rockTorque = VectorRand() * phys:GetMass()
                                * stress * rockScale * windScale
                            phys:ApplyTorqueCenter(rockTorque)
                        end
                    end

                    -- ===== STRESS SOUNDS =====
                    local soundChance
                    if stress > TIV.Config.Stress.SoundCrit then
                        soundChance = TIV.Config.StressCritChance
                    elseif stress > TIV.Config.Stress.SoundHigh then
                        soundChance = TIV.Config.StressHighSoundChance
                    else
                        soundChance = TIV.Config.StressLowSoundChance
                    end
                    if math.random() < soundChance then
                        veh:EmitSound("physics/metal/metal_box_strain"
                            .. math.random(1, 4) .. ".wav", 70, math.random(40, 65))
                    end

                    -- ===== BELOW / ABOVE THRESHOLD BRANCHES =====
                    if windMPH < TIV.Config.LoftWindThreshold then
                        if TIV.Loft.WindTimers[entIndex] then
                            print(string.format(
                                "[TIV] Wind dropped to %.0f MPH - sequence reset for #%d",
                                windMPH, entIndex))
                            CleanupLoftTracking(entIndex)
                        end

                        if TIV.Spikes.GetCount(data) > 0 then
                            if not TIV.Anchor.CheckIntegrity(veh, data) then
                                if TIV.Compat and TIV.Compat.Enabled then
                                    TIV.Anchor.ForceDetach(veh, data)
                                    data.state         = "idle"
                                    data.anchored      = false
                                    data.spikesCreated = false
                                    data.compatRecoverUntil = CurTime() + (TIV.Compat.RecoveryCooldown or 3)
                                    TIV.Deploy.BroadcastState(veh, "idle")
                                    print(string.format(
                                        "[TIV] Compat recovery: integrity lost on #%d, returning to idle for %.1fs.",
                                        entIndex, TIV.Compat.RecoveryCooldown or 3))
                                else
                                    TIV.Loft.TriggerLoft(veh, data)
                                end
                            end
                        end
                    else
                        if TIV.Spikes.GetCount(data) == 0 then
                            if not TIV.Loft.FailingGroups[entIndex] then
                                print(string.format("[TIV] 0-spike mode - instant loft at %.0f MPH", windMPH))
                                TIV.Loft.TriggerLoft(veh, data)
                            end
                        else
                            -- If ballsockets are silently breaking from raw
                            -- force before the staged failure fires, we'd
                            -- otherwise sit in "anchored" state being dragged.
                            -- Force loft when anchor integrity is gone.
                            if not TIV.Anchor.CheckIntegrity(veh, data) then
                                print(string.format(
                                    "[TIV] Anchors blown by force at %.0f MPH - forcing loft for #%d",
                                    windMPH, entIndex))
                                TIV.Loft.TriggerLoft(veh, data)
                            else
                                TIV.Loft.StartDirectionalFailure(veh, data)
                            end
                        end
                    end
                end
            else
                CleanupLoftTracking(entIndex)
            end
        end
    end
end)

-- ============================================================================
-- CLEANUP
-- Event-driven: prune tracking when state transitions away from anchored.
-- ============================================================================
hook.Add("Think", "TIV_LoftCleanup", function()
    for entIndex in pairs(TIV.Loft.WindTimers) do
        local data = TIV.Deploy.Vehicles[entIndex]
        if not data or data.state ~= "anchored" then
            CleanupLoftTracking(entIndex)
        end
    end
end)

print("[TIV] Loft system loaded")
