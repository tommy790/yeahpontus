-- ============================================================================
-- TIV INSTRUMENTS SERVER
-- Reindented for clarity. Wind is per-vehicle (TIV.Wind.GetSpeed(veh)).
-- ============================================================================

TIV.Instruments = TIV.Instruments or {}

util.AddNetworkString("TIV_InstrumentData")

local UNITS_TO_MPH = 0.0568182  -- 1 source unit/sec ~= 0.0568182 MPH

timer.Create("TIV_InstrumentUpdate", TIV.Config.InstrumentUpdateRate, 0, function()
    -- Cache packets per vehicle so 2 occupants don't recompute.
    local packets = {}

    for _, ply in ipairs(player.GetAll()) do
        local veh = (TIV.ResolveVehicle and TIV.ResolveVehicle(ply)) or ply:GetVehicle()
        if IsValid(veh) and TIV.Deploy.IsJeep(veh) then
            local packet = packets[veh]
            if not packet then
                local data     = TIV.Deploy.GetState(veh)
                local phys     = veh:GetPhysicsObject()
                local speed    = 0
                local altitude = veh:GetPos().z
                local velZ     = 0

                if IsValid(phys) then
                    local vel = phys:GetVelocity()
                    speed = vel:Length() * UNITS_TO_MPH
                    velZ  = vel.z * UNITS_TO_MPH  -- now consistent MPH
                end

                local activeConstraints = 0
                for _, c in ipairs(data.constraints or {}) do
                    if IsValid(c.constraint) and c.type == "ballsocket" then
                        activeConstraints = activeConstraints + 1
                    end
                end

                local windSpeed = TIV.Wind.GetSpeed(veh)
                local windDir   = TIV.Wind.GetDirection(veh)
                -- Only meaningful while anchored; saves player confusion.
                local stress    = (data.state == "anchored")
                    and TIV.Loft.CalculateStress(windSpeed) or 0

                packet = {
                    windSpeed         = windSpeed,
                    windDir           = windDir,
                    vehicleSpeed      = speed,
                    altitude          = altitude,
                    state             = data.state,
                    activeConstraints = activeConstraints,
                    totalSpikes       = TIV.Spikes.GetCount(data),
                    stress            = stress,
                    spikeState        = TIV.Spikes.GetState(data),
                    verticalVelocity  = velZ,
                }
                packets[veh] = packet
            end

            net.Start("TIV_InstrumentData")
                net.WriteFloat(packet.windSpeed)
                net.WriteVector(packet.windDir)
                net.WriteFloat(packet.vehicleSpeed)
                net.WriteFloat(packet.altitude)
                net.WriteString(packet.state)
                net.WriteUInt(packet.activeConstraints, 8)
                net.WriteUInt(packet.totalSpikes, 8)
                net.WriteFloat(packet.stress)
                net.WriteString(packet.spikeState)
                net.WriteFloat(packet.verticalVelocity)
            net.Send(ply)
        end
    end
end)

print("[TIV] Instruments server loaded")
