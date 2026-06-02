-- ============================================================================
-- TIV HUD
-- ============================================================================

TIV.HUD = TIV.HUD or {}

-- Added "raising" state (was missing from both color and name tables).
local STATE_COLORS = {
    idle             = Color(100, 255, 100),
    lowering         = Color(255, 255, 100),
    deploying_spikes = Color(255, 150, 50),
    anchored         = Color(50, 200, 255),
    retracting       = Color(255, 255, 100),
    raising          = Color(255, 255, 100),
    lofted           = Color(255, 50, 50),
}

local APC_STATE_COLORS = {
    idle             = Color(120, 160, 90),    -- desat green
    lowering         = Color(220, 190, 60),    -- gold
    deploying_spikes = Color(230, 140, 40),    -- amber
    anchored         = Color(80, 140, 220),    -- steel blue
    retracting       = Color(220, 190, 60),
    raising          = Color(220, 190, 60),
    lofted           = Color(220, 50, 50),
}

local STATE_NAMES = {
    idle             = "IDLE - MOBILE",
    lowering         = "LOWERING...",
    deploying_spikes = "DEPLOYING SPIKES...",
    anchored         = "ANCHORED",
    retracting       = "RETRACTING...",
    raising          = "RAISING...",
    lofted           = "LOFTED",
}

local SPIKE_NAMES = {
    [1] = "FR", [2] = "FL",
    [3] = "MR", [4] = "ML",
    [5] = "RR", [6] = "RL",
}

TIV.HUD.LastBeepTime     = 0
TIV.HUD.BeepInterval     = 1.0
TIV.HUD.FastBeepInterval = 0.3

-- ============================================================================
-- VERTICAL VELOCITY BAR
-- ============================================================================
local function DrawVerticalVelocityBar(x, y, w, h, velMPH)
    -- velMPH because server now sends vertical velocity in MPH (was units/s).
    local clamped = math.Clamp(velMPH, -45, 45)
    local frac    = clamped / 45
    local midY    = y + h / 2

    draw.RoundedBox(3, x, y, w, h, Color(20, 20, 25))
    draw.SimpleText("^", "DermaDefault", x + w / 2, y - 2,
        Color(100, 200, 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
    draw.SimpleText("v", "DermaDefault", x + w / 2, y + h + 2,
        Color(200, 100, 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

    if math.abs(frac) > 0.01 then
        local barH   = (h / 2) * math.abs(frac)
        local barCol = frac > 0 and Color(100, 255, 100) or Color(255, 100, 100)
        local barY   = frac > 0 and (midY - barH) or midY
        draw.RoundedBox(2, x + 2, barY, w - 4, barH, barCol)
    end

    surface.SetDrawColor(80, 80, 90)
    surface.DrawLine(x, midY, x + w, midY)
end

-- ============================================================================
-- MAIN HUD PAINT
-- ============================================================================
hook.Add("HUDPaint", "TIV_DrawHUD", function()
    if not TIV.Config or not TIV.Config.HUDEnabled then return end

    -- Real bug fix: guard against TIV.Instruments / Data being nil on first frame.
    if not TIV.Instruments or not TIV.Instruments.Data then return end

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    -- Resolve via shared helper if loaded, fall back to GetVehicle.
    local veh = (TIV.ResolveVehicle and TIV.ResolveVehicle(ply)) or ply:GetVehicle()
    if not IsValid(veh) then return end
    -- Guard: TIV.IsSupportedVehicle may not exist yet on first HUDPaint.
    if TIV.IsSupportedVehicle and not TIV.IsSupportedVehicle(veh) then
        -- Try seat parent before giving up
        local parent = veh:GetParent()
        if IsValid(parent) and TIV.IsSupportedVehicle(parent) then
            veh = parent
        else
            return
        end
    end

    local cls   = string.lower(veh:GetClass() or "")
    local model = string.lower(veh:GetModel() or "")
    local isAPC = cls == "prop_vehicle_apc" or string.find(model, "apc", 1, true) ~= nil

    local data = TIV.Instruments.Data

    -- Defensive defaults so a partially-populated Data table never errors.
    local windSpeed         = data.windSpeed         or 0
    local vehicleSpeed      = data.vehicleSpeed      or 0
    local altitude          = data.altitude          or 0
    local activeConstraints = data.activeConstraints or 0
    local stress            = data.stress            or 0
    local verticalVelocity  = data.verticalVelocity  or 0

    local sw, sh = ScrW(), ScrH()
    local panelW = 360
    local panelH = 340
    local panelX = sw - panelW - 20
    local panelY = sh - panelH - 20

    local state      = data.deployState or "idle"
    local colorTable = isAPC and APC_STATE_COLORS or STATE_COLORS
    local headerCol  = colorTable[state] or Color(100, 100, 100)

    draw.RoundedBox(8, panelX - 2, panelY - 2, panelW + 4, panelH + 4,
        Color(headerCol.r * 0.5, headerCol.g * 0.5, headerCol.b * 0.5, 120))
    draw.RoundedBox(8, panelX, panelY, panelW, panelH, Color(10, 10, 15, 230))

    -- Per-vehicle state flash (multiplayer-correct).
    local flashAge
    if TIV.Deploy.GetFlashFor then
        flashAge = CurTime() - TIV.Deploy.GetFlashFor(veh)
    else
        flashAge = CurTime() - (TIV.Deploy.LastStateFlash or 0)
    end
    if flashAge < 0.4 then
        local alpha = (1 - flashAge / 0.4) * 80
        draw.RoundedBox(8, panelX, panelY, panelW, panelH,
            Color(headerCol.r, headerCol.g, headerCol.b, alpha))
    end

    draw.RoundedBoxEx(8, panelX, panelY, panelW, 32,
        Color(headerCol.r * 0.2, headerCol.g * 0.2, headerCol.b * 0.2, 230),
        true, true, false, false)
    draw.SimpleText("* TIV INSTRUMENTS *", "DermaDefaultBold",
        panelX + panelW / 2, panelY + 8, Color(255, 255, 255), TEXT_ALIGN_CENTER)

    local y     = panelY + 40
    local lineH = 22
    local lm    = panelX + 15
    local rm    = panelX + panelW - 15

    -- Status
    local stateColor = colorTable[state] or Color(255, 255, 255)
    local stateName  = STATE_NAMES[state]  or string.upper(state)
    if state == "deploying_spikes" then
        local blink = math.abs(math.sin(CurTime() * 4))
        stateColor  = Color(stateColor.r, stateColor.g, stateColor.b, 155 + blink * 100)
    end

    draw.SimpleText("STATUS", "DermaDefault", lm, y, Color(150, 150, 150))
    draw.SimpleText(stateName, "DermaDefaultBold", rm, y, stateColor, TEXT_ALIGN_RIGHT)
    y = y + lineH

    surface.SetDrawColor(40, 40, 50)
    surface.DrawLine(lm, y, rm, y)
    y = y + 5

    -- Wind speed
    local threshold = TIV.Config.LoftWindThreshold or 180
    local windColor = Color(100, 255, 100)
    if windSpeed > 80  then windColor = Color(200, 255, 50)  end
    if windSpeed > 120 then windColor = Color(255, 255, 50)  end
    if windSpeed > 150 then windColor = Color(255, 150, 50)  end
    if windSpeed >= threshold then windColor = Color(255, 50, 50) end

    draw.SimpleText("WIND SPEED", "DermaDefault", lm, y, Color(150, 150, 150))
    draw.SimpleText(math.floor(windSpeed) .. " MPH", "DermaDefaultBold",
        rm, y, windColor, TEXT_ALIGN_RIGHT)
    y = y + lineH

    draw.SimpleText("VEHICLE", "DermaDefault", lm, y, Color(150, 150, 150))
    draw.SimpleText(math.floor(vehicleSpeed) .. " MPH", "DermaDefaultBold",
        rm, y, Color(150, 200, 255), TEXT_ALIGN_RIGHT)
    y = y + lineH

    draw.SimpleText("ALTITUDE", "DermaDefault", lm, y, Color(150, 150, 150))
    draw.SimpleText(math.floor(altitude) .. " u", "DermaDefaultBold",
        rm, y, Color(180, 180, 200), TEXT_ALIGN_RIGHT)
    y = y + lineH

    draw.SimpleText("ANCHORS", "DermaDefault", lm, y, Color(150, 150, 150))
    local anchorCol  = activeConstraints > 0 and Color(50, 255, 100) or Color(100, 100, 100)
    local anchorText = activeConstraints > 0
        and (activeConstraints .. " HOLDING") or "NONE"
    draw.SimpleText(anchorText, "DermaDefaultBold", rm, y, anchorCol, TEXT_ALIGN_RIGHT)
    y = y + lineH

    surface.SetDrawColor(40, 40, 50)
    surface.DrawLine(lm, y, rm, y)
    y = y + 5

    -- Spike overall + per-spike row
    draw.SimpleText("SPIKES", "DermaDefault", lm, y, Color(150, 150, 150))
    local spikeState  = data.spikeState or "idle"
    local spikeTxts   = {
        idle       = "ON VEHICLE",
        deploying  = "DRIVING IN",
        deployed   = "IN GROUND",
        retracting = "PULLING OUT",
        released   = "RELEASED",
        none       = "-",
    }
    local spikeColMap = {
        idle       = Color(120, 120, 120),
        deploying  = Color(255, 150, 50),
        deployed   = Color(50,  255, 50),
        retracting = Color(200, 200, 100),
        released   = Color(255, 80,  80),
        none       = Color(80, 80, 80),
    }
    draw.SimpleText(spikeTxts[spikeState] or spikeState, "DermaDefaultBold",
        rm, y, spikeColMap[spikeState] or Color(120, 120, 120), TEXT_ALIGN_RIGHT)
    y = y + lineH + 3

    -- Per-spike grid (uses TIV.SpikeAnim.ActiveAnims phases)
    do
        local animData = TIV.SpikeAnim and TIV.SpikeAnim.ActiveAnims
            and TIV.SpikeAnim.ActiveAnims[veh:EntIndex()]
        if animData and animData.phases then
            local cellW = (panelW - 30) / 6
            for i = 1, 6 do
                local phase = animData.phases[i]
                local c = spikeColMap[phase] or Color(60, 60, 70)
                local cx = lm + (i - 1) * cellW
                draw.RoundedBox(3, cx + 2, y, cellW - 4, 16, c)
                draw.SimpleText(SPIKE_NAMES[i] or tostring(i), "DermaDefault",
                    cx + cellW / 2, y + 8,
                    Color(0, 0, 0, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            y = y + 18
        end
    end

    -- Stress bar
    draw.SimpleText("ANCHOR STRESS", "DermaDefault", lm, y, Color(150, 150, 150))
    y = y + 16

    local barW = panelW - 80
    local barH = 18
    local barX = lm

    draw.RoundedBox(4, barX, y, barW, barH, Color(20, 20, 25))
    draw.RoundedBox(4, barX + 1, y + 1, barW - 2, barH - 2, Color(30, 30, 35))

    local stressW = (barW - 2) * math.Clamp(stress, 0, 1)
    local sr = math.Clamp(stress * 2, 0, 1) * 255
    local sg = math.Clamp(2 - stress * 2, 0, 1) * 255

    if stressW > 2 then
        draw.RoundedBox(3, barX + 1, y + 1, stressW, barH - 2, Color(sr, sg, 0))
        if stress > (TIV.Config.Stress.HUDPulse or 0.7) then
            local pulse = math.abs(math.sin(CurTime() * 6)) * 50
            draw.RoundedBox(3, barX + 1, y + 1, stressW, barH - 2,
                Color(255, 255, 255, pulse))
        end
    end

    draw.SimpleText(math.floor(stress * 100) .. "%", "DermaDefaultBold",
        barX + barW / 2, y + 1, Color(255, 255, 255, 200), TEXT_ALIGN_CENTER)

    -- Marker matches pulse threshold (was 0.8 vs pulse 0.7 -- inconsistent).
    local markerFrac = TIV.Config.Stress.HUDMarker or 0.7
    local threshX    = barX + barW * markerFrac
    surface.SetDrawColor(255, 50, 50, 180)
    surface.DrawLine(threshX, y, threshX, y + barH)

    local vvX = barX + barW + 5
    local vvW = panelW - barW - 25
    DrawVerticalVelocityBar(vvX, y, vvW, barH, verticalVelocity)

    y = y + barH + 10

    surface.SetDrawColor(40, 40, 50)
    surface.DrawLine(lm, y, rm, y)
    y = y + 5

    -- Warning dot + beep (was wired to nothing -- beep code dead).
    local warningLevel = 0
    if windSpeed >= threshold then
        warningLevel = 2
    elseif windSpeed >= 150 then
        warningLevel = 1
    end

    local anchorFail = TIV.Instruments.GetAnchorFail and TIV.Instruments.GetAnchorFail(veh)
    if anchorFail then
        warningLevel = 2
    end

    if warningLevel > 0 then
        local dotAreaW = panelW - 30
        local dotAreaH = 30
        local dotAreaX = lm
        local dotAreaY = y
        draw.RoundedBox(4, dotAreaX, dotAreaY, dotAreaW, dotAreaH,
            Color(15, 15, 20, 200))

        local dotColor, dotLabel, beepInterval
        if warningLevel == 2 then
            local blink  = math.abs(math.sin(CurTime() * 6))
            dotColor     = Color(255, 20, 20, 155 + blink * 100)
            -- Latch failure label even if wind also extreme.
            dotLabel     = anchorFail and "ANCHOR FAILURE" or "EXTREME WIND"
            beepInterval = TIV.HUD.FastBeepInterval
        else
            local blink  = math.abs(math.sin(CurTime() * 3))
            dotColor     = Color(255, 160, 30, 155 + blink * 100)
            dotLabel     = "HIGH WIND"
            beepInterval = TIV.HUD.BeepInterval
        end

        local dotX = dotAreaX + 18
        local dotY = dotAreaY + dotAreaH / 2
        local dotR = 8
        local glowPulse = math.abs(math.sin(CurTime() * (warningLevel == 2 and 8 or 4)))
        local glowR     = dotR + 4 + glowPulse * 4

        draw.RoundedBox(glowR, dotX - glowR, dotY - glowR, glowR * 2, glowR * 2,
            Color(dotColor.r, dotColor.g, dotColor.b, 30 + glowPulse * 40))
        draw.RoundedBox(dotR, dotX - dotR, dotY - dotR, dotR * 2, dotR * 2, dotColor)
        local iR = dotR * 0.5
        draw.RoundedBox(iR, dotX - iR, dotY - iR, iR * 2, iR * 2,
            Color(255, 255, 255, dotColor.a * 0.5))

        draw.SimpleText(dotLabel, "DermaDefaultBold",
            dotX + dotR + 8, dotY,
            dotColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(math.floor(windSpeed) .. " MPH", "DermaDefaultBold",
            dotAreaX + dotAreaW - 6, dotY,
            dotColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

        -- Wire up the beep that was previously dead code.
        if CurTime() - (TIV.HUD.LastBeepTime or 0) > beepInterval then
            surface.PlaySound(warningLevel == 2
                and "buttons/blip2.wav" or "buttons/blip1.wav")
            TIV.HUD.LastBeepTime = CurTime()
        end

        y = dotAreaY + dotAreaH + 5
    end

    -- Hint
    if state == "idle" then
        draw.SimpleText("[B] DEPLOY", "DermaDefault",
            panelX + panelW / 2, y, Color(200, 200, 100), TEXT_ALIGN_CENTER)
    elseif state == "anchored" then
        draw.SimpleText("[B] RETRACT", "DermaDefault",
            panelX + panelW / 2, y, Color(200, 200, 100), TEXT_ALIGN_CENTER)
    elseif state == "deploying_spikes" then
        draw.SimpleText("DRIVING INTO GROUND...", "DermaDefault",
            panelX + panelW / 2, y, Color(255, 150, 50), TEXT_ALIGN_CENTER)
    elseif state == "lowering" or state == "raising" or state == "retracting" then
        draw.SimpleText("PLEASE WAIT...", "DermaDefault",
            panelX + panelW / 2, y, Color(200, 200, 100), TEXT_ALIGN_CENTER)
    elseif state == "lofted" then
        draw.SimpleText("VEHICLE DETACHED", "DermaDefaultBold",
            panelX + panelW / 2, y, Color(255, 80, 80), TEXT_ALIGN_CENTER)
    end
end)

print("[TIV] HUD loaded")
