-- ============================================================================
-- TIV CLIENT SETTINGS PANEL
-- Utilities -> TIV -> Spike Controls
-- ============================================================================

hook.Add("PopulateToolMenu", "TIV_AddSettingsPanel", function()
    spawnmenu.AddToolMenuOption(
        "Utilities",
        "TIV",
        "TIV_SpikeControls",
        "Spike Controls",
        "",
        "",
        function(panel)
            panel:ClearControls()
            panel:Help("Adjust spike amount and anchor force for the TIV.")
            panel:Help("Spike Count/Force apply to the next deploy cycle.")
            panel:Help("Compatibility values apply live.")
            panel:Help("Note: server host's settings are authoritative.")

            panel:NumSlider(
                "Spike Count",
                "tiv_spike_count",
                TIV.Config.SpikeCountConvarMin or 0,
                TIV.Config.SpikeCountConvarMax or 6,
                0
            )

            panel:NumSlider(
                "Spike Force",
                "tiv_spike_force",
                TIV.Config.SpikeForceConvarMin or 0,
                TIV.Config.SpikeForceConvarMax or 200000,
                0
            )

            panel:NumSlider(
                "Loft Wind Threshold (MPH)",
                "tiv_loft_wind_threshold",
                TIV.Config.LoftWindMin or 50,
                TIV.Config.WindMaxSimulated or 350,
                0
            )

            panel:Help("Compatibility safety (recommended for tornado/vehicle mod stacks):")
            panel:CheckBox("Compatibility Mode", "tiv_compat_mode")

            panel:NumSlider("Compat Anchored Wind Scale",
                "tiv_compat_anchored_wind_scale",
                TIV.Config.CompatWindForceScaleMin or 0.1,
                TIV.Config.CompatWindForceScaleMax or 1.0, 2)

            panel:NumSlider("Compat Deploy Max Linear Velocity",
                "tiv_compat_max_deploy_linear",
                TIV.Config.CompatMaxDeployLinearMin or 50,
                TIV.Config.CompatMaxDeployLinearMax or 5000, 0)

            panel:NumSlider("Compat Deploy Max Angular Velocity",
                "tiv_compat_max_deploy_angular",
                TIV.Config.CompatMaxDeployAngularMin or 20,
                TIV.Config.CompatMaxDeployAngularMax or 4000, 0)

            panel:NumSlider("Compat Recovery Cooldown (s)",
                "tiv_compat_recovery_cooldown",
                TIV.Config.CompatRecoveryCooldownMin or 0,
                TIV.Config.CompatRecoveryCooldownMax or 30, 1)
        end
    )
end)

print("[TIV] Settings panel loaded")
