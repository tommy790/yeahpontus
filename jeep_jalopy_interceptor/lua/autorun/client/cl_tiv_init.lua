-- ============================================================================
-- TIV CLIENT INIT
-- ============================================================================
print("[TIV] Loading client modules...")

include("tiv/config/sh_config.lua")
include("tiv/config/cl_settings.lua")
include("tiv/hud/cl_hud.lua")
include("tiv/instruments/cl_instruments.lua")
include("tiv/deploy/cl_deploy.lua")
include("tiv/animation/cl_spike_anim.lua")

print("[TIV] Client modules loaded!")