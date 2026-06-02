-- ============================================================================
-- TIV SPIKE ANIMATION - Server side
-- ============================================================================

TIV.SpikeAnim = TIV.SpikeAnim or {}

util.AddNetworkString("TIV_SpikeAnimStart")
util.AddNetworkString("TIV_SpikeAnimRetract")
util.AddNetworkString("TIV_SpikeAnimImpact")
util.AddNetworkString("TIV_SpikeAnimPhase")

TIV.SpikeAnim.ActiveJobs = TIV.SpikeAnim.ActiveJobs or {}
TIV.SpikeAnim._sessionCounter = TIV.SpikeAnim._sessionCounter or 0

-- ============================================================================
-- SHARED THINK
-- ============================================================================
timer.Create("TIV_SpikeAnimThink", 0.02, 0, function()
    for jobKey, job in pairs(TIV.SpikeAnim.ActiveJobs) do
        -- Don't pre-empt the job's own invalidity handling; it needs to
        -- update completion counters before being removed.
        local ok = job.fn(job)
        if ok == false then
            TIV.SpikeAnim.ActiveJobs[jobKey] = nil
        end
    end
end)

-- ============================================================================
-- HELPERS
-- ============================================================================
local function TraceGround(veh, worldPos, data, downDir)
    local traceDir = (downDir and downDir:LengthSqr() > 0)
        and downDir:GetNormalized() or Vector(0, 0, -1)
    return util.TraceLine({
        start  = worldPos,
        endpos = worldPos + (traceDir * 300),
        filter = function(ent)
            if ent == veh then return false end
            if data and data.spikes then
                for _, sd in ipairs(data.spikes) do
                    if sd.entity == ent then return false end
                end
            end
            return true
        end,
        mask = MASK_SOLID,
    })
end

local function GetParentedLocalPos(spikeOffset)
    -- SpikeHoverOffset is positive-up (used to be the double-negative `-SpikeHoverHeight`).
    return spikeOffset.pos + Vector(0, 0, TIV.Config.SpikeHoverOffset)
end

local function GetSpikeDownAngle(veh)
    local yaw = IsValid(veh) and veh:GetAngles().y or 0
    return Angle(90, yaw, 0)
end

local function GetParentedLocalAngle()
    return Angle(90, 0, 0)
end

TIV.SpikeAnim.GetSpikeDownAngle    = GetSpikeDownAngle
TIV.SpikeAnim.GetParentedLocalAngle = GetParentedLocalAngle

-- ============================================================================
-- GET OFFSETS FOR VEHICLE
-- ============================================================================
local function GetOffsetsForVehicle(veh)
    if not IsValid(veh) then
        return TIV.Config.SpikeOffsets.jeep
    end

    local model = string.lower(veh:GetModel() or "")
    local class = string.lower(veh:GetClass() or "")

    if class == "prop_vehicle_apc" or string.find(model, "apc", 1, true) then
        return TIV.Config.SpikeOffsets.prop_vehicle_apc or TIV.Config.SpikeOffsets.jeep
    end
    if class == "prop_vehicle_jalopy" or string.find(model, "jalopy", 1, true) then
        return TIV.Config.SpikeOffsets.jalopy or TIV.Config.SpikeOffsets.jeep
    end
    return TIV.Config.SpikeOffsets.jeep
end

-- ============================================================================
-- CREATE SPIKES ON VEHICLE
-- ============================================================================
function TIV.SpikeAnim.CreateSpikes(veh, data)
    if not IsValid(veh) then return end

    local offsets    = GetOffsetsForVehicle(veh)
    local spikeCount = math.Clamp(
        TIV.Config.SpikeCount,
        TIV.Config.SpikeCountConvarMin,
        TIV.Config.SpikeCountConvarMax
    )

    -- Session ID: include a global counter to defeat same-tick collisions.
    TIV.SpikeAnim._sessionCounter = TIV.SpikeAnim._sessionCounter + 1
    data.sessionID = tostring(TIV.Config.SessionSeed)
        .. "_" .. veh:EntIndex()
        .. "_" .. tostring(CurTime())
        .. "_" .. TIV.SpikeAnim._sessionCounter

    -- Always set session ID first, even in 0-spike mode.
    if spikeCount <= 0 then
        TIV.Spikes.RemoveAll(data, veh:EntIndex())
        data.spikes = {}
        data.spikeAnims = {}
        return
    end

    TIV.Spikes.RemoveAll(data, veh:EntIndex())
    data.spikes     = {}
    data.spikeAnims = {}

    for i = 1, spikeCount do
        local offsetData = offsets[i]
        if offsetData then
            local spike = ents.Create("prop_physics")
            if IsValid(spike) then
                local worldPos = veh:LocalToWorld(GetParentedLocalPos(offsetData))
                local downAng  = GetSpikeDownAngle(veh)

                spike:SetModel(TIV.Config.SpikeModel)
                spike:SetPos(worldPos)
                spike:SetAngles(downAng)
                spike:Spawn()
                spike:Activate()

                spike:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
                spike:SetColor(Color(80, 80, 80, 255))
                spike:SetMaterial("models/props_combine/metal_combinebridge001")

                -- Signal to tornado mods that this is not a debris prop.
                -- Different mods check different conventions; cover the
                -- common ones so prop-unweld features skip our spikes.
                spike:SetNWBool("TIV_Spike", true)
                spike:SetNWEntity("TIV_OwnerVehicle", veh)
                spike:SetNWBool("GStormsIgnore", true)
                spike:SetNWBool("XT3Ignore", true)
                spike.IsTIVSpike       = true
                spike.PhysgunDisabled  = true
                spike.DoNotDuplicate   = true
                -- Some addons check this to skip cleanup entirely.
                spike:SetCustomCollisionCheck(true)

                local spikePhys = spike:GetPhysicsObject()
                if IsValid(spikePhys) then
                    spikePhys:SetMass(50)
                    spikePhys:EnableMotion(false)
                    spikePhys:EnableGravity(false)
                end

                spike:SetParent(veh)
                spike:SetLocalPos(GetParentedLocalPos(offsetData))
                spike:SetLocalAngles(GetParentedLocalAngle())

                table.insert(data.spikes, {
                    entity      = spike,
                    offset      = offsetData.pos,
                    localPos    = GetParentedLocalPos(offsetData),
                    index       = i,
                    phase       = "idle",
                    deployAngle = GetSpikeDownAngle(veh),
                    name        = offsetData.name,
                    group       = offsetData.group,
                })
                data.spikeAnims[i] = "idle"
            end
        end
    end
end

-- ============================================================================
-- REPARENT SPIKE TO VEHICLE
-- ============================================================================
function TIV.SpikeAnim.ReparentSpike(veh, spike, spikeData)
    if not IsValid(veh) or not IsValid(spike) then return end

    local spikePhys = spike:GetPhysicsObject()
    if IsValid(spikePhys) then
        spikePhys:EnableMotion(false)
        spikePhys:EnableGravity(false)
    end

    spike:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    spike:SetParent(veh)
    spike:SetLocalPos(spikeData.localPos)
    spike:SetLocalAngles(GetParentedLocalAngle())
    spikeData.phase = "idle"
end

-- ============================================================================
-- DEPLOY TO GROUND
-- ============================================================================
function TIV.SpikeAnim.DeployToGround(veh, data, onAllDeployed)
    if not IsValid(veh) then return end
    if not data.spikes or #data.spikes == 0 then return end

    local sessionID   = data.sessionID or tostring(veh:EntIndex())
    local totalSpikes = #data.spikes
    local deployedCount = 0

    -- Guard against double-fire of the completion callback.
    local completionFired = false
    local function fireCompletion()
        if completionFired then return end
        completionFired = true
        if onAllDeployed then onAllDeployed() end
    end

    local function tickCompletion()
        deployedCount = deployedCount + 1
        if deployedCount >= totalSpikes then fireCompletion() end
    end

    net.Start("TIV_SpikeAnimStart")
        net.WriteEntity(veh)
        net.WriteUInt(totalSpikes, 8)
    net.Broadcast()

    for i, spikeData in ipairs(data.spikes) do
        if not IsValid(spikeData.entity) then
            tickCompletion()
        else
            local spike   = spikeData.entity
            local index   = spikeData.index
            local stagger = (i - 1) * 0.08

            timer.Simple(stagger, function()
                if not IsValid(veh) or not IsValid(spike) then
                    tickCompletion()
                    return
                end

                local worldPos = spike:GetPos()
                local worldAng = spike:GetAngles()
                spike:SetParent(nil)
                spike:SetPos(worldPos)
                spike:SetAngles(worldAng)

                local downDir = -veh:GetUp()

                local spikePhys = spike:GetPhysicsObject()
                if IsValid(spikePhys) then
                    spikePhys:EnableMotion(false)
                end

                local groundTrace  = TraceGround(veh, worldPos, data, downDir)
                local groundPos    = groundTrace.Hit and groundTrace.HitPos
                    or (worldPos + downDir * 60)
                local groundNormal = groundTrace.HitNormal or Vector(0, 0, 1)

                spikeData.groundPos    = groundPos
                spikeData.groundNormal = groundNormal
                spikeData.deployAngle  = worldAng
                spikeData.phase        = "deploying"
                data.spikeAnims[index] = "deploying"

                net.Start("TIV_SpikeAnimPhase")
                    net.WriteEntity(veh)
                    net.WriteUInt(index, 8)
                    net.WriteString("deploying")
                net.Broadcast()

                local driveStart    = CurTime()
                local driveDuration = TIV.Config.SpikeDriveDuration
                local startPos      = worldPos
                local endPos        = groundPos + (downDir * TIV.Config.SpikeDriveDepth)

                local hasContactedGround = false
                local hasFullyDeployed   = false

                local jobKey = sessionID .. "_deploy_" .. index

                TIV.SpikeAnim.ActiveJobs[jobKey] = {
                    veh   = veh,
                    spike = spike,
                    fn    = function(job)
                        if not IsValid(veh) or not IsValid(spike) then
                            tickCompletion()
                            return false
                        end

                        local elapsed = CurTime() - driveStart
                        local frac    = math.Clamp(elapsed / driveDuration, 0, 1)

                        local easeFrac
                        if frac < 0.2 then
                            easeFrac = (frac / 0.2)^2 * 0.2
                        elseif frac > 0.85 then
                            local endFrac = (frac - 0.85) / 0.15
                            easeFrac = 0.85 + (1 - (1 - endFrac)^2) * 0.15
                        else
                            easeFrac = frac
                        end

                        local newPos = LerpVector(easeFrac, startPos, endPos)
                        if hasContactedGround then
                            local vibStr = 0.4 * (1 - frac)
                            local vib    = math.sin(CurTime() * 50) * vibStr
                            newPos = newPos + Vector(vib, vib * 0.7, 0)
                        end
                        spike:SetPos(newPos)
                        spike:SetAngles(worldAng)

                        local alongToGround = (newPos - groundPos):Dot(downDir)
                        if not hasContactedGround and alongToGround >= -2 then
                            hasContactedGround = true
                        end

                        if frac >= 1 and not hasFullyDeployed then
                            hasFullyDeployed = true
                            spikeData.phase        = "deployed"
                            data.spikeAnims[index] = "deployed"

                            spike:SetPos(endPos)
                            spike:SetAngles(worldAng)
                            spike:SetCollisionGroup(COLLISION_GROUP_WORLD)
                            local sp = spike:GetPhysicsObject()
                            if IsValid(sp) then sp:EnableMotion(false) end

                            -- Settle bounce: two delayed teleports, matches original.
                            timer.Simple(0.05, function()
                                if IsValid(spike) then spike:SetPos(endPos + Vector(0, 0, 1.5)) end
                            end)
                            timer.Simple(0.12, function()
                                if IsValid(spike) then spike:SetPos(endPos) end
                            end)

                            net.Start("TIV_SpikeAnimPhase")
                                net.WriteEntity(veh)
                                net.WriteUInt(index, 8)
                                net.WriteString("deployed")
                            net.Broadcast()

                            net.Start("TIV_SpikeAnimImpact")
                                net.WriteEntity(veh)
                                net.WriteUInt(index, 8)
                                net.WriteVector(groundPos)
                                net.WriteVector(groundNormal)
                            net.Broadcast()

                            TIV.Anchor.AttachSingle(veh, data, spikeData, i)

                            tickCompletion()
                            return false
                        end

                        return true
                    end
                }
            end)
        end
    end
end

-- ============================================================================
-- RETRACT FROM GROUND
-- ============================================================================
function TIV.SpikeAnim.RetractFromGround(veh, data, callback)
    if not IsValid(veh) then
        if callback then callback() end
        return
    end
    if not data.spikes or #data.spikes == 0 then
        if callback then callback() end
        return
    end

    net.Start("TIV_SpikeAnimRetract")
        net.WriteEntity(veh)
    net.Broadcast()

    local sessionID      = data.sessionID or tostring(veh:EntIndex())
    local totalSpikes    = #data.spikes
    local retractedCount = 0

    local completionFired = false
    local function fireCompletion()
        if completionFired then return end
        completionFired = true
        if callback then callback() end
    end
    local function tickCompletion()
        retractedCount = retractedCount + 1
        if retractedCount >= totalSpikes then fireCompletion() end
    end

    for i, spikeData in ipairs(data.spikes) do
        local spike = spikeData.entity
        if not IsValid(spike) then
            tickCompletion()
        else
            local index   = spikeData.index
            local stagger = (i - 1) * 0.1

            timer.Simple(stagger, function()
                if not IsValid(spike) or not IsValid(veh) then
                    tickCompletion()
                    return
                end

                spikeData.phase        = "retracting"
                data.spikeAnims[index] = "retracting"

                net.Start("TIV_SpikeAnimPhase")
                    net.WriteEntity(veh)
                    net.WriteUInt(index, 8)
                    net.WriteString("retracting")
                net.Broadcast()

                local pullStart    = CurTime()
                local pullDuration = TIV.Config.SpikeRetractDuration
                local startPos     = spike:GetPos()
                local startAng     = spikeData.deployAngle or spike:GetAngles()

                local jobKey = sessionID .. "_retract_" .. index

                TIV.SpikeAnim.ActiveJobs[jobKey] = {
                    veh   = veh,
                    spike = spike,
                    fn    = function(job)
                        if not IsValid(spike) or not IsValid(veh) then
                            tickCompletion()
                            return false
                        end

                        local elapsed  = CurTime() - pullStart
                        local frac     = math.Clamp(elapsed / pullDuration, 0, 1)
                        local easeFrac = 1 - (1 - frac)^2

                        local targetWorldPos = veh:LocalToWorld(spikeData.localPos)
                        local targetAng      = veh:LocalToWorldAngles(GetParentedLocalAngle())

                        local newPos = LerpVector(easeFrac, startPos, targetWorldPos)
                        local newAng = LerpAngle(easeFrac, startAng, targetAng)

                        spike:SetPos(newPos)
                        spike:SetAngles(newAng)

                        if frac >= 1 then
                            spike:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
                            TIV.SpikeAnim.ReparentSpike(veh, spike, spikeData)
                            data.spikeAnims[index] = "idle"

                            net.Start("TIV_SpikeAnimPhase")
                                net.WriteEntity(veh)
                                net.WriteUInt(index, 8)
                                net.WriteString("idle")
                            net.Broadcast()

                            tickCompletion()
                            return false
                        end

                        return true
                    end
                }
            end)
        end
    end
end

print("[TIV] Spike animation system loaded")
