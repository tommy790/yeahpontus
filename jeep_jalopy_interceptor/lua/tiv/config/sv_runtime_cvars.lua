-- ============================================================================
-- TIV RUNTIME SERVER CVARS
-- ============================================================================

TIV = TIV or {}
TIV.Config = TIV.Config or {}

local function clampInt(value, minValue, maxValue)
    return math.Clamp(math.floor(tonumber(value) or minValue), minValue, maxValue)
end

local function applyRuntimeSpikeConfig()
    local count = clampInt(
        GetConVar("tiv_spike_count"):GetInt(),
        TIV.Config.SpikeCountConvarMin,
        TIV.Config.SpikeCountConvarMax
    )
    local force = clampInt(
        GetConVar("tiv_spike_force"):GetInt(),
        TIV.Config.SpikeForceConvarMin,
        TIV.Config.SpikeForceConvarMax
    )

    TIV.Config.SpikeCount           = count
    TIV.Config.SpikeForceLimit      = force
    TIV.Config.BallSocketForceLimit = force
end

local function applyRuntimeCompatConfig()
    TIV.Compat = TIV.Compat or {}
    TIV.Compat.Enabled = GetConVar("tiv_compat_mode"):GetBool()

    TIV.Compat.MaxDeployLinearVelocity = math.Clamp(
        GetConVar("tiv_compat_max_deploy_linear"):GetFloat(),
        TIV.Config.CompatMaxDeployLinearMin,
        TIV.Config.CompatMaxDeployLinearMax
    )
    TIV.Compat.MaxDeployAngularVelocity = math.Clamp(
        GetConVar("tiv_compat_max_deploy_angular"):GetFloat(),
        TIV.Config.CompatMaxDeployAngularMin,
        TIV.Config.CompatMaxDeployAngularMax
    )
    TIV.Compat.RecoveryCooldown = math.Clamp(
        GetConVar("tiv_compat_recovery_cooldown"):GetFloat(),
        TIV.Config.CompatRecoveryCooldownMin,
        TIV.Config.CompatRecoveryCooldownMax
    )
    TIV.Compat.AnchoredWindForceScale = math.Clamp(
        GetConVar("tiv_compat_anchored_wind_scale"):GetFloat(),
        TIV.Config.CompatWindForceScaleMin,
        TIV.Config.CompatWindForceScaleMax
    )
end

local function applyRuntimeLoftConfig()
    local threshold = math.Clamp(
        GetConVar("tiv_loft_wind_threshold"):GetFloat(),
        TIV.Config.LoftWindMin,
        TIV.Config.WindMaxSimulated or 350
    )
    TIV.Config.LoftWindThreshold = threshold
end

CreateConVar(
    "tiv_spike_count",
    tostring(TIV.Config.SpikeCount),
    { FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED },
    "Number of TIV spikes used during deploy.",
    TIV.Config.SpikeCountConvarMin,
    TIV.Config.SpikeCountConvarMax
)

CreateConVar(
    "tiv_compat_mode",
    "1",
    { FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED },
    "Enable TIV compatibility safety guards for external tornado/vehicle addons."
)

CreateConVar(
    "tiv_compat_max_deploy_linear",
    "650",
    { FCVAR_ARCHIVE, FCVAR_REPLICATED },
    "Max linear velocity allowed before deploy starts (compat mode).",
    TIV.Config.CompatMaxDeployLinearMin,
    TIV.Config.CompatMaxDeployLinearMax
)

CreateConVar(
    "tiv_compat_max_deploy_angular",
    "300",
    { FCVAR_ARCHIVE, FCVAR_REPLICATED },
    "Max angular velocity allowed before deploy starts (compat mode).",
    TIV.Config.CompatMaxDeployAngularMin,
    TIV.Config.CompatMaxDeployAngularMax
)

CreateConVar(
    "tiv_compat_recovery_cooldown",
    "3.0",
    { FCVAR_ARCHIVE, FCVAR_REPLICATED },
    "Cooldown seconds after a compatibility safety recovery.",
    TIV.Config.CompatRecoveryCooldownMin,
    TIV.Config.CompatRecoveryCooldownMax
)

CreateConVar(
    "tiv_compat_anchored_wind_scale",
    "0.65",
    { FCVAR_ARCHIVE, FCVAR_REPLICATED },
    "Scales anchored wind force while compat mode is enabled.",
    TIV.Config.CompatWindForceScaleMin,
    TIV.Config.CompatWindForceScaleMax
)

CreateConVar(
    "tiv_spike_force",
    tostring(TIV.Config.SpikeForceLimit),
    { FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED },
    "Force limit for spike/world and vehicle/spike anchors (0 = unbreakable by force).",
    TIV.Config.SpikeForceConvarMin,
    TIV.Config.SpikeForceConvarMax
)

CreateConVar(
    "tiv_loft_wind_threshold",
    tostring(TIV.Config.LoftWindThreshold),
    { FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED },
    "Wind MPH threshold where anchored spikes fail and loft begins.",
    TIV.Config.LoftWindMin,
    TIV.Config.WindMaxSimulated or 350
)

-- Real bug fix: callbacks had `*,*` paste artifacts (function(_, _, _) is correct).
cvars.AddChangeCallback("tiv_spike_count", function(_, old, new)
    applyRuntimeSpikeConfig()
    print(string.format("[TIV] Spike count: %s -> %s (next deploy)", tostring(old), tostring(new)))
end, "TIV_RuntimeSpikeCount")

cvars.AddChangeCallback("tiv_spike_force", function(_, _, _)
    applyRuntimeSpikeConfig()
end, "TIV_RuntimeSpikeForce")

cvars.AddChangeCallback("tiv_compat_mode", function(_, _, _)
    applyRuntimeCompatConfig()
end, "TIV_RuntimeCompatMode")

cvars.AddChangeCallback("tiv_compat_max_deploy_linear", function(_, _, _)
    applyRuntimeCompatConfig()
end, "TIV_RuntimeCompatMaxDeployLinear")

cvars.AddChangeCallback("tiv_compat_max_deploy_angular", function(_, _, _)
    applyRuntimeCompatConfig()
end, "TIV_RuntimeCompatMaxDeployAngular")

cvars.AddChangeCallback("tiv_compat_recovery_cooldown", function(_, _, _)
    applyRuntimeCompatConfig()
end, "TIV_RuntimeCompatRecoveryCooldown")

cvars.AddChangeCallback("tiv_compat_anchored_wind_scale", function(_, _, _)
    applyRuntimeCompatConfig()
end, "TIV_RuntimeCompatWindScale")

cvars.AddChangeCallback("tiv_loft_wind_threshold", function(_, _, _)
    applyRuntimeLoftConfig()
end, "TIV_RuntimeLoftThreshold")

-- Single init path (was duplicated: Initialize hook + 3 timer.Simple calls).
hook.Add("Initialize", "TIV_ApplyRuntimeCvars", function()
    applyRuntimeSpikeConfig()
    applyRuntimeCompatConfig()
    applyRuntimeLoftConfig()
end)

print("[TIV] Runtime convars loaded")
