-- ============================================================================
-- TIV WIND SYSTEM
-- Per-vehicle wind sampling (was global). One sample per vehicle per tick.
-- TIV_WindUpdate broadcast removed (was redundant with TIV_InstrumentData).
-- ApplyToEntity now takes an explicit scale instead of hard-coding 0.01.
-- ============================================================================

TIV.Wind = TIV.Wind or {}

TIV.Wind.CurrentMPH    = TIV.Config.WindDefault   -- last global sample (fallback)
TIV.Wind.Direction     = Vector(1, 0, 0)
TIV.Wind.PerVehicle    = TIV.Wind.PerVehicle or {} -- [entIndex] = { mph, dir }

TIV.Wind.ManualMode    = false
TIV.Wind.ManualMPH     = 0
TIV.Wind.ManualDir     = Vector(1, 0, 0)
TIV.Wind.ManualUntil   = 0   -- 0 = no auto-expire

local MANUAL_AUTO_EXPIRE = 900 -- 15 minutes

-- Force constants (centralized magic numbers).
TIV.Wind.FORCE_PER_MPH_PER_KG = 25  -- empirical scaling

-- ============================================================================
-- INTERNAL: SAMPLE WORLD WIND AT A POSITION
-- Returns (mph, direction) without mutating globals. Caller decides what to
-- do with the value. Returns (nil, nil) if no provider responded.
-- ============================================================================
local function SampleGStormsTornadoWindAt(pos)
    if not GSGetGlobalWindspeedAndVectors then return nil, nil end
    if not gs_env or not gs_weatherEntityList then return nil, nil end
    local envEnt = gs_env.server or gs_env
    if not IsValid(envEnt) then return nil, nil end

    local entityList = gs_weatherEntityList.server or gs_weatherEntityList or {}
    local inflowCVar = GetConVar("gstorms_inflow_jet")
    local inflowJet  = inflowCVar and inflowCVar:GetBool() or false

    local ok, blendedMPH, windVector, _, tornadoMPH = pcall(
        GSGetGlobalWindspeedAndVectors, pos, entityList, inflowJet, envEnt, CurTime()
    )
    if not ok then return nil, nil end

    -- Prefer tornado component for TIV behavior.
    if tornadoMPH and tornadoMPH == tornadoMPH and tornadoMPH > 0 then
        local dir = (windVector and windVector:LengthSqr() > 0.1)
            and windVector:GetNormalized() or Vector(1, 0, 0)
        return math.Clamp(tornadoMPH, 0, TIV.Config.WindMaxSimulated), dir
    end

    -- Only fall back to blended if GStorms reports a real positive value;
    -- 0 means "no wind here, but I'm authoritative". Was `>= 0`, now `> 0`
    -- so a broken GStorms returning 0 falls through to XT3.
    if blendedMPH and blendedMPH == blendedMPH and blendedMPH > 0 then
        local dir = (windVector and windVector:LengthSqr() > 0.1)
            and windVector:GetNormalized() or Vector(1, 0, 0)
        return math.Clamp(blendedMPH, 0, TIV.Config.WindMaxSimulated), dir
    end

    return nil, nil
end

local function SampleWorldWindAt(pos)
    local mph, dir = SampleGStormsTornadoWindAt(pos)
    if mph then return mph, dir end

    if not GetGlobalWindspeed then return nil, nil end
    local ok, windVelocity, windSpeed = pcall(GetGlobalWindspeed, pos)
    if not ok or not windSpeed then return nil, nil end

    local d = (windVelocity and windVelocity:LengthSqr() > 0.1)
        and windVelocity:GetNormalized() or Vector(1, 0, 0)
    return windSpeed, d
end

TIV.Wind.SampleWorldWindAt = SampleWorldWindAt

-- ============================================================================
-- PUBLIC API
-- ============================================================================
local function ManualActive()
    if not TIV.Wind.ManualMode then return false end
    if TIV.Wind.ManualUntil > 0 and CurTime() > TIV.Wind.ManualUntil then
        TIV.Wind.ManualMode  = false
        TIV.Wind.ManualUntil = 0
        print("[TIV] Wind manual override auto-expired.")
        return false
    end
    return true
end

function TIV.Wind.GetSpeed(veh)
    if ManualActive() then return TIV.Wind.ManualMPH end
    if IsValid(veh) then
        local entry = TIV.Wind.PerVehicle[veh:EntIndex()]
        if entry then return entry.mph end
    end
    return TIV.Wind.CurrentMPH
end

function TIV.Wind.GetDirection(veh)
    if ManualActive() then return TIV.Wind.ManualDir end
    if IsValid(veh) then
        local entry = TIV.Wind.PerVehicle[veh:EntIndex()]
        if entry then return entry.dir end
    end
    return TIV.Wind.Direction
end

-- Returns an unscaled wind force vector. Callers multiply by mass and any
-- scenario-specific scalar.
function TIV.Wind.GetForceVector(veh)
    return TIV.Wind.GetDirection(veh) * TIV.Wind.GetSpeed(veh) * TIV.Wind.FORCE_PER_MPH_PER_KG
end

function TIV.Wind.SetSpeed(mph)
    TIV.Wind.ManualMode  = true
    TIV.Wind.ManualMPH   = math.Clamp(mph, 0, TIV.Config.WindMaxSimulated)
    TIV.Wind.ManualUntil = CurTime() + MANUAL_AUTO_EXPIRE
end

function TIV.Wind.SetDirection(dir)
    TIV.Wind.ManualMode  = true
    TIV.Wind.ManualDir   = dir:GetNormalized()
    TIV.Wind.ManualUntil = CurTime() + MANUAL_AUTO_EXPIRE
end

function TIV.Wind.ClearManual()
    TIV.Wind.ManualMode  = false
    TIV.Wind.ManualUntil = 0
end

-- Apply wind force to a single entity. `scale` defaults to 1.0; pass smaller
-- values (e.g., 0.5) for lighter coupling.
function TIV.Wind.ApplyToEntity(ent, scale, veh)
    if not IsValid(ent) then return end
    local phys = ent:GetPhysicsObject()
    if not IsValid(phys) then return end
    if not phys:IsMotionEnabled() then return end

    local force = TIV.Wind.GetForceVector(veh) * phys:GetMass() * (scale or 1.0)
    phys:ApplyForceCenter(force)
end

-- ============================================================================
-- WIND THINK
-- Per-vehicle sampling. Each vehicle has its own wind value.
-- ============================================================================
timer.Create("TIV_WindThink", 0.1, 0, function()
    -- Build list of active TIV vehicles.
    local activeVehicles = {}
    local seenIdx = {}
    for entIdx, data in pairs(TIV.Deploy.Vehicles or {}) do
        local veh = Entity(entIdx)
        if IsValid(veh) then
            table.insert(activeVehicles, { veh = veh, data = data, idx = entIdx })
            seenIdx[entIdx] = true
        end
    end

    -- Prune per-vehicle cache for vehicles that no longer exist.
    for idx in pairs(TIV.Wind.PerVehicle) do
        if not seenIdx[idx] then
            TIV.Wind.PerVehicle[idx] = nil
        end
    end

    if not ManualActive() then
        if #activeVehicles > 0 then
            for _, entry in ipairs(activeVehicles) do
                local mph, dir = SampleWorldWindAt(entry.veh:GetPos())
                if mph then
                    TIV.Wind.PerVehicle[entry.idx] = { mph = mph, dir = dir }
                    -- Keep the global cache updated as the last-seen sample.
                    TIV.Wind.CurrentMPH = mph
                    TIV.Wind.Direction  = dir
                end
            end
        else
            local ply = player.GetAll()[1]
            if IsValid(ply) then
                local mph, dir = SampleWorldWindAt(ply:GetPos())
                if mph then
                    TIV.Wind.CurrentMPH = mph
                    TIV.Wind.Direction  = dir
                end
            end
        end
    end

    -- Apply forces only to TIV vehicles + released spikes (never all props).
    for _, entry in ipairs(activeVehicles) do
        local windMPH = TIV.Wind.GetSpeed(entry.veh)
        if windMPH >= 50 then
            TIV.Wind.ApplyToEntity(entry.veh, 0.01, entry.veh)

            for _, sd in ipairs(entry.data.spikes or {}) do
                if IsValid(sd.entity) and sd.phase == "released" then
                    -- Released spikes are loose debris: lighter wind coupling.
                    TIV.Wind.ApplyToEntity(sd.entity, 0.5, entry.veh)
                end
            end
        end
    end

    -- No TIV_WindUpdate broadcast: HUD gets wind via TIV_InstrumentData.
end)

-- ============================================================================
-- COMMANDS
-- ============================================================================
local function isAuth(ply)
    if not IsValid(ply) then return true end -- server console
    return ply:IsAdmin()
end

concommand.Add("tiv_wind_set", function(ply, cmd, args)
    if not isAuth(ply) then return end
    local speed = tonumber(args[1]) or 0
    TIV.Wind.SetSpeed(speed)
    print(string.format("[TIV] Wind manual override: %d MPH (auto-expires in %ds)",
        speed, MANUAL_AUTO_EXPIRE))
end)

concommand.Add("tiv_wind_dir", function(ply, cmd, args)
    if not isAuth(ply) then return end
    local x = tonumber(args[1]) or 1
    local y = tonumber(args[2]) or 0
    local z = tonumber(args[3]) or 0
    TIV.Wind.SetDirection(Vector(x, y, z))
    print(string.format("[TIV] Wind direction set to (%s, %s, %s)", x, y, z))
end)

concommand.Add("tiv_wind_clear", function(ply, cmd, args)
    if not isAuth(ply) then return end
    TIV.Wind.ClearManual()
    print("[TIV] Wind manual override cleared.")
end)

concommand.Add("tiv_wind_status", function(ply, cmd, args)
    if not isAuth(ply) then return end
    local manual = ManualActive()
    local remaining = (TIV.Wind.ManualUntil > 0)
        and math.max(0, math.floor(TIV.Wind.ManualUntil - CurTime())) or 0

    print(string.format(
        "[TIV] Wind: %.1f MPH | Dir: %s | Mode: %s%s | GStorms: %s | XT3: %s",
        TIV.Wind.CurrentMPH,
        tostring(TIV.Wind.Direction),
        manual and "MANUAL" or "AUTO",
        manual and string.format(" (%ds left)", remaining) or "",
        GSGetGlobalWindspeedAndVectors and "YES" or "NO",
        GetGlobalWindspeed and "YES" or "NO"
    ))

    for idx, entry in pairs(TIV.Wind.PerVehicle) do
        print(string.format("  Vehicle #%d: %.1f MPH dir=%s", idx, entry.mph, tostring(entry.dir)))
    end
end)

print("[TIV] Wind system loaded (per-vehicle sampling, GStorms tornado + XT3 fallback)")
