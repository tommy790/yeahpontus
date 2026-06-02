-- ============================================================================
-- TIV SPIKE SYSTEM
-- Thin façade over sv_spike_anim. Offsets live in TIV.Config.SpikeOffsets.
-- ============================================================================

TIV.Spikes = TIV.Spikes or {}

-- ============================================================================
-- CREATE
-- ============================================================================
function TIV.Spikes.Create(veh, data)
    if not IsValid(veh) then return end
    if TIV.SpikeAnim and TIV.SpikeAnim.CreateSpikes then
        TIV.SpikeAnim.CreateSpikes(veh, data)
    end
end

-- ============================================================================
-- DEPLOY
-- ============================================================================
function TIV.Spikes.Deploy(veh, data, callback)
    if not IsValid(veh) then
        if callback then callback() end
        return
    end
    if TIV.SpikeAnim and TIV.SpikeAnim.DeployToGround then
        TIV.SpikeAnim.DeployToGround(veh, data, callback)
        return
    end

    -- Instant fallback (anim module missing). Filters all spikes, not just veh.
    local function spikeFilter(ent)
        if ent == veh then return false end
        if data and data.spikes then
            for _, sd in ipairs(data.spikes) do
                if sd.entity == ent then return false end
            end
        end
        return true
    end

    for _, spikeData in ipairs(data.spikes or {}) do
        if IsValid(spikeData.entity) then
            spikeData.entity:SetParent(nil)
            local worldPos = veh:LocalToWorld(spikeData.localPos or spikeData.offset)
            local tr = util.TraceLine({
                start  = worldPos,
                endpos = worldPos - Vector(0, 0, 300),
                filter = spikeFilter,
                mask   = MASK_SOLID,
            })
            local gp = tr.Hit and tr.HitPos or (worldPos - Vector(0, 0, 60))
            spikeData.entity:SetPos(gp - Vector(0, 0, TIV.Config.SpikeDriveDepth))
            local downAng = (TIV.SpikeAnim and TIV.SpikeAnim.GetSpikeDownAngle)
                and TIV.SpikeAnim.GetSpikeDownAngle(veh) or Angle(90, veh:GetAngles().y, 0)
            spikeData.entity:SetAngles(downAng)
            spikeData.groundPos   = gp
            spikeData.deployAngle = downAng
            spikeData.phase       = "deployed"
            data.spikeAnims[spikeData.index] = "deployed"
        end
    end

    TIV.Anchor.AttachAll(veh, data)
    if callback then callback() end
end

-- ============================================================================
-- RETRACT
-- ============================================================================
function TIV.Spikes.Retract(veh, data, callback)
    if not IsValid(veh) then
        if callback then callback() end
        return
    end
    if TIV.SpikeAnim and TIV.SpikeAnim.RetractFromGround then
        TIV.SpikeAnim.RetractFromGround(veh, data, callback)
        return
    end

    for _, spikeData in ipairs(data.spikes or {}) do
        if IsValid(spikeData.entity) and TIV.SpikeAnim.ReparentSpike then
            TIV.SpikeAnim.ReparentSpike(veh, spikeData.entity, spikeData)
            data.spikeAnims[spikeData.index] = "idle"
        end
    end
    if callback then callback() end
end

-- ============================================================================
-- REMOVE ALL
-- Kills the actual jobs (was removing nonexistent timer names).
-- ============================================================================
function TIV.Spikes.RemoveAll(data, entIndex)
    if not data then return end

    -- Cancel pending animation jobs for this session.
    if data.sessionID and TIV.SpikeAnim and TIV.SpikeAnim.ActiveJobs then
        local prefix = data.sessionID .. "_"
        for jobKey in pairs(TIV.SpikeAnim.ActiveJobs) do
            if string.sub(jobKey, 1, #prefix) == prefix then
                TIV.SpikeAnim.ActiveJobs[jobKey] = nil
            end
        end
    end

    for _, spikeData in ipairs(data.spikes or {}) do
        if IsValid(spikeData.entity) then
            spikeData.entity:SetParent(nil)
            SafeRemoveEntity(spikeData.entity)
        end
    end

    data.spikes     = {}
    data.spikeAnims = {}
end

-- ============================================================================
-- RELEASE ALL (loft -- physics take over)
-- Now actually used; the loft TriggerLoft path can opt into this via
-- tiv_loft_release_spikes convar (see sv_loft.lua).
-- ============================================================================
function TIV.Spikes.ReleaseAll(data)
    if not data or not data.spikes then return end
    for _, spikeData in ipairs(data.spikes) do
        if IsValid(spikeData.entity) then
            spikeData.entity:SetParent(nil)
            local phys = spikeData.entity:GetPhysicsObject()
            if IsValid(phys) then
                phys:EnableMotion(true)
                phys:EnableGravity(true)
                phys:Wake()
                phys:ApplyForceCenter(VectorRand() * 3000 + Vector(0, 0, 2000))
                phys:ApplyTorqueCenter(VectorRand() * 500)
            end
            spikeData.entity:SetCollisionGroup(COLLISION_GROUP_NONE)
            spikeData.phase = "released"
        end
    end
end

-- ============================================================================
-- UTILITIES
-- ============================================================================
function TIV.Spikes.GetCount(data)
    if not data or not data.spikes then return 0 end
    local count = 0
    for _, sd in ipairs(data.spikes) do
        if IsValid(sd.entity) then count = count + 1 end
    end
    return count
end

-- Real bug fix: motion phases now take priority over rest phases so the
-- HUD doesn't report "IN GROUND" mid-deploy when one spike has finished.
function TIV.Spikes.GetState(data)
    if not data or not data.spikeAnims then return "none" end
    local phases = {}
    for _, phase in pairs(data.spikeAnims) do
        phases[phase] = (phases[phase] or 0) + 1
    end

    if phases["deploying"]  and phases["deploying"]  > 0 then return "deploying"  end
    if phases["retracting"] and phases["retracting"] > 0 then return "retracting" end
    if phases["deployed"]   and phases["deployed"]   > 0 then return "deployed"   end
    if phases["idle"]       and phases["idle"]       > 0 then return "idle"       end
    return "none"
end

-- Real bug fix: was reading TIV.Config.SpikeCount and TIV.Spikes.Offsets
-- (which are stale/dead). Reads actual data.spikes instead.
function TIV.Spikes.AllInPhase(data, phase)
    if not data or not data.spikes or #data.spikes == 0 then return false end
    for _, sd in ipairs(data.spikes) do
        if sd.phase ~= phase then return false end
    end
    return true
end

function TIV.Spikes.ValidateIntegrity(data)
    if not data or not data.spikes then return 0 end
    local removed = 0
    for i = #data.spikes, 1, -1 do
        if not IsValid(data.spikes[i].entity) then
            local idx = data.spikes[i].index
            table.remove(data.spikes, i)
            if data.spikeAnims and idx then
                data.spikeAnims[idx] = nil
            end
            removed = removed + 1
        end
    end
    return removed
end

-- ============================================================================
-- DEBUG COMMAND
-- ============================================================================
concommand.Add("tiv_spike_debug", function(ply, cmd, args)
    if IsValid(ply) and not ply:IsAdmin() then return end

    local veh
    if args[1] then
        veh = Entity(tonumber(args[1]) or 0)
    end
    if not IsValid(veh) and IsValid(ply) then
        veh = ply:GetVehicle()
    end
    if not IsValid(veh) then
        print("[TIV] Get in a vehicle or pass an entity index!")
        return
    end

    local data = TIV.Deploy.GetState(veh)
    if not data then
        print("[TIV] No data")
        return
    end

    local lines = {
        "[TIV] === SPIKE DEBUG ===",
        "Vehicle state : " .. (data.state or "nil"),
        "Spike overall : " .. TIV.Spikes.GetState(data),
        "Spike count   : " .. TIV.Spikes.GetCount(data),
        "Created flag  : " .. tostring(data.spikesCreated),
        "Session ID    : " .. tostring(data.sessionID),
        "Constraints   : " .. #(data.constraints or {}),
    }

    -- Iterate by spike index in deterministic order.
    for _, sd in ipairs(data.spikes or {}) do
        local i = sd.index
        local phase = (data.spikeAnims or {})[i] or "unknown"
        local valid    = IsValid(sd.entity) and "valid" or "INVALID"
        local parented = (IsValid(sd.entity) and IsValid(sd.entity:GetParent()))
                         and "parented" or "world"
        table.insert(lines, string.format("  Spike #%d (%-12s): %-12s [%s] [%s]",
            i, tostring(sd.name or "?"), phase, valid, parented))
    end

    for _, line in ipairs(lines) do print(line) end
end)

print("[TIV] Spike system loaded")
