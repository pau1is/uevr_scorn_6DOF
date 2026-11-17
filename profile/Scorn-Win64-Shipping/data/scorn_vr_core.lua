--[[
  Scorn VR 6DOF (UEVR) - core
  https://github.com/pau1is/uevr_scorn_6DOF
  ---------------------------------------------------------------------------
  Loaded and hot-reloaded by scripts/scorn_vr.lua.

  * Snap / smooth turn on the right stick (45 deg by default)
  * Full body, turns with the headset (yaw)
  * Visible body = PoseableMesh copy of the game mesh (pose copied every frame).
    Both arms are bent with two-bone IK onto the motion controllers; the weapon and
    body attachments follow the copy, so game animations (reload, recoil, weapon insert)
    still play inside the VR hands. Forearm twist is distributed over the twist bones.
  * Parasite arms stay on the body and only reach for the nearest hand during
    hand-over animations (ammo apparatus on reload)
  * Aim: head without a weapon, right controller with a weapon
  * Interactions (consoles, items, scripted events; from AScornCharacter.CharacterState):
    the native animation owns the body - no IK, no body yaw from the headset, no stick turning
  * Settings: UEVR menu -> "Script UI" -> "Scorn VR"
  * Files in UnrealVRMod/Scorn-Win64-Shipping/data:
      scorn_vr_config.json  - settings
      scorn_vr_log.txt      - log (attach it to bug reports)
      scorn_vr_dump.json    - skeleton / component dump (written on first weapon draw)
      scorn_vr_debug.json   - developer debug channel (see dev/README.md)

  Based on the original Scorn UEVR profile scripts by Tensai37.
  License: MIT
]]

UEVR_UObjectHook.activate()

local api = uevr.api
local vr = uevr.params.vr
local callbacks = uevr.sdk.callbacks

local VERSION = "1.1.0"
local COMPAT_CONFIG_VERSIONS = { ["1.0.0"] = true, ["1.1.0"] = true }
local CONFIG_FILE = "scorn_vr_config.json"
local DUMP_FILE = "scorn_vr_dump.json"
local STATUS_FILE = "scorn_vr_status.json"
local LOG_FILE = "scorn_vr_log.txt"

-- Scorn skeleton (SK_MainCharacter)
local BONE = {
    r_shoulder = "mc_shoulder_SH_r_jnt",
    r_elbow    = "mc_elbow_SH_r_jnt",
    r_wrist    = "mc_wrist_SH_r_jnt",
    l_shoulder = "mc_shoulder_SH_l_jnt",
    l_elbow    = "mc_elbow_SH_l_jnt",
    l_wrist    = "mc_wrist_SH_l_jnt",
    head       = "mc_head_SH_01_jnt",
    camera     = "camera_rot_x_SH_jnt",
    camera_base = "camera_SH_jnt",
    root       = "mc_root_SH_jnt",
}

-- parasite arm chains (children of the root) that must follow the IK'd arm
local P_CHAIN = {
    r = { { "p_shoulder_SH_r_jnt", "mc_shoulder_SH_r_jnt" }, { "p_elbow_SH_r_jnt", "mc_elbow_SH_r_jnt" }, { "p_wrist_SH_r_jnt", "mc_wrist_SH_r_jnt" } },
    l = { { "p_shoulder_SH_l_jnt", "mc_shoulder_SH_l_jnt" }, { "p_elbow_SH_l_jnt", "mc_elbow_SH_l_jnt" }, { "p_wrist_SH_l_jnt", "mc_wrist_SH_l_jnt" } },
}

-- AScornCharacter.CharacterState (native enum ECharacterState, declaration order from the game
-- binary). Verified at runtime through KismetNodeHelperLibrary when possible.
local CHAR_STATE_NAMES = { [0] = "Idle", "Aiming", "Reloading", "InInventory", "WeaponSwitching", "Healing",
    "UsingConsole", "UsingItem", "UsingItem_Fail", "UsingGeneric", "Paralyzed", "InWorldEventAnim",
    "Resurrected", "InGloryKill", "ThrownOnGround", "Grabbed", "LockedByParasite", "UsingConsole_Fail",
    "WaitingForParasiteAttack", "SentryRail" }

-- states in which the developers' animation owns the body and the arms (consoles, items,
-- scripted events): no IK, no body yaw from the headset, no stick turning
local LOCK_STATES = {
    InInventory = true, Healing = true,
    UsingConsole = true, UsingConsole_Fail = true, UsingItem = true, UsingItem_Fail = true, UsingGeneric = true,
    Paralyzed = true, InWorldEventAnim = true, Resurrected = true, InGloryKill = true,
    ThrownOnGround = true, Grabbed = true, LockedByParasite = true, WaitingForParasiteAttack = true,
}

---------------------------------------------------------------------------
-- Config
---------------------------------------------------------------------------
local TURN_MODES = { "Snap", "Smooth" }
local TURN_STICKS = { "Right stick", "Left stick" }
local ARMS_MODES = {
    "Weapon only (no body, legacy)",
    "Full body + IK arm on controller",
    "Full body, no IK (flat-style arms)",
}

local defaults = {
    turn_enabled = true,
    turn_mode = 1,
    turn_stick = 1,
    snap_angle = 45,
    smooth_speed = 180.0,
    snap_press = 0.60,
    snap_release = 0.35,

    arms_mode = 2,
    body_follow_head = true,
    body_yaw_deadzone = 0.0,
    hide_head = true,
    left_hand_follow = true,
    keep_anim_offsets = false,
    block_stick_pitch = true,
    disable_player_shadows = true,
    auto_aim_switch = true,
    lock_on_interaction = true,

    -- wrist placement relative to the controller (controller space: X fwd, Y right, Z up)
    grip_pitch = 0.0,
    grip_yaw = 0.0,
    grip_roll = 0.0,
    grip_x = -8.0,
    grip_y = 0.0,
    grip_z = -3.0,
    elbow_down = 0.5,

    debug_files = false,
}

local cfg = {}

local function deep_copy(t)
    if type(t) ~= "table" then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = deep_copy(v) end
    return r
end

local function load_config()
    cfg = deep_copy(defaults)
    local ok, data = pcall(json.load_file, CONFIG_FILE)
    if ok and type(data) == "table" and COMPAT_CONFIG_VERSIONS[data.version] then
        for k, v in pairs(data) do
            if defaults[k] ~= nil and type(v) == type(defaults[k]) then cfg[k] = v end
        end
    end
end

local config_dirty, config_save_timer = false, 0.0
local function save_config_now()
    local t = deep_copy(cfg)
    t.version = VERSION
    pcall(json.dump_file, CONFIG_FILE, t, 4)
    config_dirty = false
end
local function mark_dirty() config_dirty = true; config_save_timer = 1.0 end

load_config()
pcall(function() vr.set_mod_value("UObjectHook_AttachLerpEnabled", "false") end)

---------------------------------------------------------------------------
-- Logging (print + file in data/)
---------------------------------------------------------------------------
local log_lines, log_dirty = {}, false
local function log(msg)
    local line = os.date("%H:%M:%S ") .. tostring(msg)
    print("[ScornVR] " .. line)
    log_lines[#log_lines + 1] = line
    if #log_lines > 300 then table.remove(log_lines, 1) end
    log_dirty = true
end

local last_errors = {}
local function log_error_once(key, err)
    local s = tostring(err)
    if last_errors[key] ~= s then
        last_errors[key] = s
        log("ERROR " .. key .. ": " .. s)
    end
end

local function flush_log()
    if not log_dirty then return end
    log_dirty = false
    pcall(fs.write, LOG_FILE, table.concat(log_lines, "\n") .. "\n")
end

---------------------------------------------------------------------------
-- Math (UE conventions: X fwd, Y right, Z up, degrees)
---------------------------------------------------------------------------
local DEG = 180.0 / math.pi
local RAD = math.pi / 180.0

local function quat_from_rot(pitch, yaw, roll)
    local hp, hy, hr = pitch * RAD * 0.5, yaw * RAD * 0.5, roll * RAD * 0.5
    local SP, CP = math.sin(hp), math.cos(hp)
    local SY, CY = math.sin(hy), math.cos(hy)
    local SR, CR = math.sin(hr), math.cos(hr)
    return {
        x =  CR * SP * SY - SR * CP * CY,
        y = -CR * SP * CY - SR * CP * SY,
        z =  CR * CP * SY - SR * SP * CY,
        w =  CR * CP * CY + SR * SP * SY,
    }
end

local function normalize_axis(a)
    a = a % 360.0
    if a > 180.0 then a = a - 360.0 end
    return a
end

local function rot_from_quat(q)
    local X, Y, Z, W = q.x, q.y, q.z, q.w
    local singularity = Z * X - W * Y
    local yawY = 2.0 * (W * Z + X * Y)
    local yawX = 1.0 - 2.0 * (Y * Y + Z * Z)
    local THRESH = 0.4999995
    local pitch, yaw, roll
    if singularity < -THRESH then
        pitch = -90.0
        yaw = math.atan(yawY, yawX) * DEG
        roll = normalize_axis(-yaw - (2.0 * math.atan(X, W) * DEG))
    elseif singularity > THRESH then
        pitch = 90.0
        yaw = math.atan(yawY, yawX) * DEG
        roll = normalize_axis(yaw - (2.0 * math.atan(X, W) * DEG))
    else
        local s = 2.0 * singularity
        if s > 1.0 then s = 1.0 elseif s < -1.0 then s = -1.0 end
        pitch = math.asin(s) * DEG
        yaw = math.atan(yawY, yawX) * DEG
        roll = math.atan(-2.0 * (W * X + Y * Z), 1.0 - 2.0 * (X * X + Y * Y)) * DEG
    end
    return pitch, yaw, roll
end

local function qmul(a, b)
    return {
        w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
        x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
        z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
    }
end

local function qinv(q)
    local n = q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w
    if n < 1e-12 then return { x = 0, y = 0, z = 0, w = 1 } end
    return { x = -q.x / n, y = -q.y / n, z = -q.z / n, w = q.w / n }
end

local function qnorm(q)
    local n = math.sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
    if n < 1e-12 then return { x = 0, y = 0, z = 0, w = 1 } end
    return { x = q.x / n, y = q.y / n, z = q.z / n, w = q.w / n }
end

local function qrot(q, v)
    local tx = 2.0 * (q.y * v.z - q.z * v.y)
    local ty = 2.0 * (q.z * v.x - q.x * v.z)
    local tz = 2.0 * (q.x * v.y - q.y * v.x)
    return {
        x = v.x + q.w * tx + (q.y * tz - q.z * ty),
        y = v.y + q.w * ty + (q.z * tx - q.x * tz),
        z = v.z + q.w * tz + (q.x * ty - q.y * tx),
    }
end

local function vadd(a, b) return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z } end
local function vsub(a, b) return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z } end
local function vscale(a, s) return { x = a.x * s, y = a.y * s, z = a.z * s } end
local function vdot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function vcross(a, b) return { x = a.y * b.z - a.z * b.y, y = a.z * b.x - a.x * b.z, z = a.x * b.y - a.y * b.x } end
local function vlen(a) return math.sqrt(vdot(a, a)) end
local function vnorm(a)
    local l = vlen(a)
    if l < 1e-9 then return { x = 1, y = 0, z = 0 } end
    return vscale(a, 1.0 / l)
end
local function vlerp(a, b, t) return vadd(a, vscale(vsub(b, a), t)) end

local function qangle_deg(a, b)
    local d = math.abs(a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w)
    if d > 1.0 then d = 1.0 end
    return 2.0 * math.acos(d) * DEG
end

local function qnlerp(a, b, t)
    local d = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w
    local s = (d < 0) and -1.0 or 1.0
    return qnorm({
        x = a.x + (s * b.x - a.x) * t, y = a.y + (s * b.y - a.y) * t,
        z = a.z + (s * b.z - a.z) * t, w = a.w + (s * b.w - a.w) * t,
    })
end

-- rotation that takes direction u to direction v (UE FQuat::FindBetweenNormals)
local function qbetween(u, v)
    u, v = vnorm(u), vnorm(v)
    local w = 1.0 + vdot(u, v)
    if w < 1e-6 then
        local axis = (math.abs(u.x) > math.abs(u.z)) and { x = -u.y, y = u.x, z = 0 } or { x = 0, y = -u.z, z = u.y }
        axis = vnorm(axis)
        return { x = axis.x, y = axis.y, z = axis.z, w = 0 }
    end
    local c = vcross(u, v)
    return qnorm({ x = c.x, y = c.y, z = c.z, w = w })
end

local function qyaw(deg) return quat_from_rot(0, deg, 0) end

-- rotation matrix (rows) -> quaternion; q rotates v as R*v
local function quat_from_rows(r0, r1, r2)
    local m00, m01, m02 = r0.x, r0.y, r0.z
    local m10, m11, m12 = r1.x, r1.y, r1.z
    local m20, m21, m22 = r2.x, r2.y, r2.z
    local tr = m00 + m11 + m22
    local x, y, z, w
    if tr > 0 then
        local s = math.sqrt(tr + 1.0) * 2.0
        w = 0.25 * s; x = (m21 - m12) / s; y = (m02 - m20) / s; z = (m10 - m01) / s
    elseif m00 > m11 and m00 > m22 then
        local s = math.sqrt(1.0 + m00 - m11 - m22) * 2.0
        w = (m21 - m12) / s; x = 0.25 * s; y = (m01 + m10) / s; z = (m02 + m20) / s
    elseif m11 > m22 then
        local s = math.sqrt(1.0 + m11 - m00 - m22) * 2.0
        w = (m02 - m20) / s; x = (m01 + m10) / s; y = 0.25 * s; z = (m12 + m21) / s
    else
        local s = math.sqrt(1.0 + m22 - m00 - m11) * 2.0
        w = (m10 - m01) / s; x = (m02 + m20) / s; y = (m12 + m21) / s; z = 0.25 * s
    end
    return qnorm({ x = x, y = y, z = z, w = w })
end

-- hand frame from finger bones: forward = wrist -> middle knuckle, up = pinky -> index (thumb side).
-- returns q such that (wrist world rot) = (controller rot) * q  puts the hand forward along the
-- controller's forward axis with the thumb up, i.e. a natural grip.
local function hand_grip_q(fwd_local, side_local)
    local f = vnorm(fwd_local)
    local s = vsub(side_local, vscale(f, vdot(side_local, f)))
    s = vnorm(s)
    local y = vcross(s, f)
    return quat_from_rows(f, y, s)
end

---------------------------------------------------------------------------
-- Two-bone IK solve (pure math, world space)
-- returns new elbow and wrist positions
---------------------------------------------------------------------------
local function solve_two_bone(S, E, W, T, hint_dir)
    local a = vlen(vsub(E, S))
    local b = vlen(vsub(W, E))
    local to_t = vsub(T, S)
    local d = vlen(to_t)
    local dir = vnorm(to_t)
    local max_d = (a + b) * 0.999
    local min_d = math.abs(a - b) + 0.01
    if d > max_d then d = max_d elseif d < min_d then d = min_d end
    local cos_a = (a * a + d * d - b * b) / (2.0 * a * d)
    if cos_a > 1.0 then cos_a = 1.0 elseif cos_a < -1.0 then cos_a = -1.0 end
    local sin_a = math.sqrt(1.0 - cos_a * cos_a)
    local perp = vsub(hint_dir, vscale(dir, vdot(hint_dir, dir)))
    if vlen(perp) < 1e-4 then perp = { x = 0, y = 0, z = -1 } end
    perp = vnorm(perp)
    local E2 = vadd(S, vadd(vscale(dir, a * cos_a), vscale(perp, a * sin_a)))
    local W2 = vadd(S, vscale(dir, d))
    return E2, W2
end

---------------------------------------------------------------------------
-- UObject helpers
---------------------------------------------------------------------------
local function exists(obj)
    if obj == nil then return false end
    local ok, r = pcall(UEVR_UObjectHook.exists, obj)
    return ok and r == true
end

local function addr(obj)
    if obj == nil then return 0 end
    local ok, a = pcall(function() return obj:get_address() end)
    if ok and a then return a end
    return 0
end

local function fname_str(x)
    if x == nil then return "" end
    if type(x) == "string" then return x end
    local ok, s = pcall(function() return x:to_string() end)
    if ok and s then return s end
    return tostring(x)
end

local function short_name(obj)
    if obj == nil then return "nil" end
    local ok, n = pcall(function() return obj:get_fname():to_string() end)
    if ok and n then return n end
    return "?"
end

local function full_name(obj)
    if obj == nil then return "nil" end
    local ok, n = pcall(function() return obj:get_full_name() end)
    if ok and n then return n end
    return "?"
end

local function class_name(obj)
    if obj == nil then return "nil" end
    local ok, n = pcall(function() return obj:get_class():get_fname():to_string() end)
    if ok and n then return n end
    return "?"
end

local function V(t) return { x = t.X, y = t.Y, z = t.Z } end

local function get_world_tf(comp)
    local l = comp:K2_GetComponentLocation()
    local r = comp:K2_GetComponentRotation()
    return V(l), quat_from_rot(r.Pitch, r.Yaw, r.Roll)
end

local function set_world_tf(comp, p, q)
    local pitch, yaw, roll = rot_from_quat(q)
    comp:K2_SetWorldLocationAndRotation({ X = p.x, Y = p.y, Z = p.z },
        { Pitch = pitch, Yaw = yaw, Roll = roll }, false, {}, true)
end

local function get_relative(comp)
    local rl = comp.RelativeLocation
    local rr = comp.RelativeRotation
    if rl == nil or rr == nil then return nil end
    return { loc = { X = rl.X, Y = rl.Y, Z = rl.Z }, rot = { Pitch = rr.Pitch, Yaw = rr.Yaw, Roll = rr.Roll } }
end

local function set_relative(comp, rel)
    comp:K2_SetRelativeLocationAndRotation(rel.loc, rel.rot, false, {}, true)
end

-- poseable bone access (world space = 0)
local function pbone_get(pm, bone)
    local l = pm:GetBoneLocationByName(bone, 0)
    local r = pm:GetBoneRotationByName(bone, 0)
    return V(l), quat_from_rot(r.Pitch, r.Yaw, r.Roll)
end

local function pbone_set_rot(pm, bone, q)
    local p, y, r = rot_from_quat(q)
    pm:SetBoneRotationByName(bone, { Pitch = p, Yaw = y, Roll = r }, 0)
end

local function pbone_set_loc(pm, bone, v)
    pm:SetBoneLocationByName(bone, { X = v.x, Y = v.y, Z = v.z }, 0)
end

local function has_bone(comp, bone)
    local ok, idx = pcall(function() return comp:GetBoneIndex(bone) end)
    return ok and type(idx) == "number" and idx >= 0
end

local skeletal_mesh_c = api:find_uobject("Class /Script/Engine.SkeletalMeshComponent")
local scene_component_c = api:find_uobject("Class /Script/Engine.SceneComponent")
local poseable_c = api:find_uobject("Class /Script/Engine.PoseableMeshComponent")
local gameplay_statics = nil
pcall(function()
    gameplay_statics = api:find_uobject("Class /Script/Engine.GameplayStatics"):get_class_default_object()
end)

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local S = {}
local function fresh_state()
    return {
        pawn = nil, pawn_addr = 0,
        mesh = nil, mesh_addr = 0,
        camera = nil,
        pm = nil, pm_ok = false, pm_failed = false,
        mesh_hidden_mode = nil,
        remastered = {},          -- [addr] = comp
        weapon_actor = nil, weapon_mesh = nil, weapon_mesh_addr = 0,
        weapon_class = "", weapon_active = false, weapon_active_time = 0.0,
        helper = nil,
        legacy_weapon = nil,
        parts = {}, scan_timer = 0.0,
        hidden_by_us = {},
        moved = {},
        frame_done = false,
        ik_alpha = 0.0, left_alpha = 0.0,
        anim_base = nil,
        body_yaw = nil,
        status = "waiting for pawn",
        last_aim = -1, stable_want = -1, stable_time = 0.0,
        gameplay_active = false,
        char_state = nil, char_state_name = nil,
        locked = false, lock_alpha = 0.0, yaw_resync = false, cam_yaw = nil, view_shift = nil,
        shadow_done = {},
        stats = { frames = 0, ik_frames = 0, yaw_frames = 0, last_yaw_delta = 0, reach = 0, weapon_follow = "?" },
    }
end
S = fresh_state()

local turn = { snap_pending = 0, latched = false, smooth_input = 0.0 }

-- debug channel: data/scorn_vr_debug.json (read twice per second)
local DBG = {}
local dbg_timer = 0.0
local function read_debug(dt)
    dbg_timer = dbg_timer - dt
    if dbg_timer > 0 then return end
    dbg_timer = 0.5
    local ok, d = pcall(json.load_file, "scorn_vr_debug.json")
    if ok and type(d) == "table" then DBG = d else DBG = {} end
end
local M_ = {}  -- measurements for the status file

---------------------------------------------------------------------------
-- Visibility helpers
---------------------------------------------------------------------------
local function set_hidden_by_us(comp, hide)
    local a = addr(comp)
    if a == 0 then return end
    if hide then
        if not S.hidden_by_us[a] then
            local visible = true
            pcall(function() visible = comp:IsVisible() end)
            if visible then
                pcall(function() comp:SetVisibility(false, false) end)
                S.hidden_by_us[a] = comp
            end
        end
    else
        local c = S.hidden_by_us[a]
        if c then
            if exists(c) then pcall(function() c:SetVisibility(true, false) end) end
            S.hidden_by_us[a] = nil
        end
    end
end

local function unhide_all_parts()
    for a, c in pairs(S.hidden_by_us) do
        if exists(c) then pcall(function() c:SetVisibility(true, false) end) end
        S.hidden_by_us[a] = nil
    end
end

local function disable_shadow(comp)
    local a = addr(comp)
    if a == 0 or S.shadow_done[a] then return end
    pcall(function() comp:SetCastShadow(false) end)
    pcall(function() comp:SetCastHiddenShadow(false) end)
    S.shadow_done[a] = true
end

---------------------------------------------------------------------------
-- Controller helper: scene component moved by UObjectHook to the right hand
---------------------------------------------------------------------------
local function destroy_one_helper(key)
    local h = S[key]
    if h and exists(h) then
        pcall(function() UEVR_UObjectHook.remove_motion_controller_state(h) end)
        pcall(function() h:K2_DestroyComponent(h) end)
    end
    S[key] = nil
end

local function destroy_helper()
    destroy_one_helper("helper")
    destroy_one_helper("helper_l")
end

-- key "helper" = right hand (1), "helper_l" = left hand (0)
local function ensure_helper(key, hand)
    key = key or "helper"
    hand = hand or 1
    if S[key] and exists(S[key]) then return true end
    S[key] = nil
    if not exists(S.pawn) or not scene_component_c then return false end
    local ok, comp = pcall(function() return api:add_component_by_class(S.pawn, scene_component_c) end)
    if not ok or comp == nil then
        log_error_once("helper", comp)
        return false
    end
    local st = UEVR_UObjectHook.get_or_add_motion_controller_state(comp)
    if st == nil then return false end
    st:set_hand(hand)
    if not pcall(function() st:set_permanent(true) end) then
        pcall(function() st:set_permanant(true) end)
    end
    local zero = UEVR_Vector3f.new()
    zero.x, zero.y, zero.z = 0, 0, 0
    pcall(function() st:set_location_offset(zero) end)
    local ident = UEVR_Quaternionf.new()
    ident.x, ident.y, ident.z, ident.w = 0, 0, 0, 1
    pcall(function() st:set_rotation_offset(ident) end)
    S[key] = comp
    log("controller helper created: " .. key)
    return true
end

---------------------------------------------------------------------------
-- Legacy weapon-only attach (original Tensai37 offsets)
---------------------------------------------------------------------------
local LEGACY_LOC = { x = 0.18228530883789063, y = 166.2379150390625, z = -70.33699035644531 }
local LEGACY_ROT = { w = 0.9644434452056885, x = 0.1105697751045227, y = 0.22468142211437225, z = -0.08450811356306076 }

local function detach_legacy_weapon()
    if S.legacy_weapon then
        if exists(S.legacy_weapon) then
            pcall(function() UEVR_UObjectHook.remove_motion_controller_state(S.legacy_weapon) end)
        end
        S.legacy_weapon = nil
    end
end

local function attach_legacy_weapon(wm)
    if S.legacy_weapon and addr(S.legacy_weapon) == addr(wm) then return end
    detach_legacy_weapon()
    local st = UEVR_UObjectHook.get_or_add_motion_controller_state(wm)
    if st == nil then return end
    st:set_hand(1)
    if not pcall(function() st:set_permanent(true) end) then
        pcall(function() st:set_permanant(true) end)
    end
    local l = UEVR_Vector3f.new()
    l.x, l.y, l.z = LEGACY_LOC.x, LEGACY_LOC.y, LEGACY_LOC.z
    st:set_location_offset(l)
    local q = UEVR_Quaternionf.new()
    q.x, q.y, q.z, q.w = LEGACY_ROT.x, LEGACY_ROT.y, LEGACY_ROT.z, LEGACY_ROT.w
    st:set_rotation_offset(q)
    S.legacy_weapon = wm
end

---------------------------------------------------------------------------
-- Poseable body copy
---------------------------------------------------------------------------
local function set_mesh_render(mesh, render)
    -- keep the game mesh animating but optionally invisible in the main pass
    if S.mesh_hidden_mode == nil and not render then
        if pcall(function() mesh:SetRenderInMainPass(false) end) then
            S.mesh_hidden_mode = "mainpass"
        else
            pcall(function() mesh:SetVisibility(false, false) end)
            S.mesh_hidden_mode = "visibility"
        end
        pcall(function() mesh.VisibilityBasedAnimTickOption = 0 end) -- AlwaysTickPoseAndRefreshBones
        log("game body mesh hidden via " .. S.mesh_hidden_mode)
    elseif S.mesh_hidden_mode ~= nil and render then
        if S.mesh_hidden_mode == "mainpass" then
            pcall(function() mesh:SetRenderInMainPass(true) end)
        else
            pcall(function() mesh:SetVisibility(true, false) end)
        end
        S.mesh_hidden_mode = nil
        log("game body mesh visible again")
    end
end

local function unmaster_all()
    for a, c in pairs(S.remastered) do
        if exists(c) and exists(S.mesh) then
            pcall(function() c:SetMasterPoseComponent(S.mesh, true) end)
        end
        S.remastered[a] = nil
    end
end

local function destroy_poseable()
    unmaster_all()
    if exists(S.mesh) then set_mesh_render(S.mesh, true) end
    if S.pm and exists(S.pm) then
        pcall(function() S.pm:K2_DestroyComponent(S.pm) end)
    end
    S.pm, S.pm_ok = nil, false
end

local function create_poseable()
    if S.pm_failed or not poseable_c or not exists(S.pawn) or not exists(S.mesh) then return false end
    local ok, err = pcall(function()
        local pm = api:add_component_by_class(S.pawn, poseable_c)
        if pm == nil then error("add_component_by_class returned nil") end
        pm:K2_AttachToComponent(S.mesh, "None", 2, 2, 2, false) -- SnapToTarget
        pm:SetSkeletalMesh(S.mesh.SkeletalMesh, true)
        local n = S.mesh:GetNumMaterials()
        for i = 0, n - 1 do
            pm:SetMaterial(i, S.mesh:GetMaterial(i))
        end
        pcall(function() pm:SetCastShadow(false) end)
        pcall(function() pm:SetCastHiddenShadow(false) end)
        pm:CopyPoseFromSkeletalComponent(S.mesh)
        S.pm = pm
    end)
    if not ok then
        log_error_once("create_poseable", err)
        S.pm_failed = true
        S.pm = nil
        return false
    end
    -- sanity check: the copy must have our bones
    if not has_bone(S.pm, BONE.r_wrist) then
        log("poseable copy has no " .. BONE.r_wrist .. ", disabling body copy")
        destroy_poseable()
        S.pm_failed = true
        return false
    end
    S.pm_ok = true
    if cfg.hide_head then pcall(function() S.pm:HideBoneByName(BONE.head, 0) end) end
    set_mesh_render(S.mesh, false)
    log("poseable body copy created")
    return true
end

-- make weapon / body attachments follow the poseable copy instead of the game mesh
local function remaster_followers()
    if not S.pm_ok or not exists(S.pm) then return end
    local list = {}
    for _, part in ipairs(S.parts) do
        if part.direct_child and part.same_skeleton then list[#list + 1] = part.comp end
    end
    if exists(S.weapon_mesh) and has_bone(S.weapon_mesh, BONE.root) then
        list[#list + 1] = S.weapon_mesh
    end
    for _, c in ipairs(list) do
        local a = addr(c)
        local ok, err = pcall(function() c:SetMasterPoseComponent(S.pm, false) end)
        if ok then
            if not S.remastered[a] then
                S.remastered[a] = c
                log("follower -> body copy: " .. short_name(c))
            end
        else
            log_error_once("remaster " .. short_name(c), err)
        end
    end
end

---------------------------------------------------------------------------
-- Pawn / weapon tracking
---------------------------------------------------------------------------
local function reset_pawn_state()
    pcall(destroy_poseable)
    pcall(detach_legacy_weapon)
    pcall(destroy_helper)
    pcall(unhide_all_parts)
    local old_log = S.stats
    S = fresh_state()
    S.stats = old_log
end

local function scan_parts()
    S.parts = {}
    if not skeletal_mesh_c or not exists(S.pawn) then return end
    local ok, objs = pcall(function() return skeletal_mesh_c:get_objects_matching(false) end)
    if not ok or not objs then return end
    for _, obj in ipairs(objs) do
        local outer = nil
        pcall(function() outer = obj:get_outer() end)
        if outer and addr(outer) == S.pawn_addr then
            local a = addr(obj)
            if a ~= S.mesh_addr and a ~= S.weapon_mesh_addr and a ~= addr(S.pm) then
                local parent, sock = nil, "None"
                pcall(function() parent = obj:GetAttachParent() end)
                pcall(function() sock = fname_str(obj:GetAttachSocketName()) end)
                local direct = parent ~= nil and addr(parent) == S.mesh_addr and (sock == "None" or sock == "")
                S.parts[#S.parts + 1] = {
                    comp = obj, addr = a, name = short_name(obj),
                    direct_child = direct,
                    same_skeleton = direct and has_bone(obj, BONE.root) or false,
                }
            end
        end
    end
end

local function update_weapon(dt)
    local wm, actor = nil, nil
    pcall(function()
        local wc = S.pawn.WeaponController
        if wc then
            actor = wc.CurrentWeapon
            if actor then wm = actor.WeaponMesh end
        end
    end)
    local active = false
    if wm ~= nil and exists(wm) then
        local visible = true
        pcall(function() visible = wm:IsVisible() end)
        local actor_hidden = false
        pcall(function() actor_hidden = actor.bHidden == true end)
        active = visible and not actor_hidden
    end
    local na = addr(wm)
    if na ~= S.weapon_mesh_addr then
        S.weapon_mesh, S.weapon_actor, S.weapon_mesh_addr = wm, actor, na
        S.weapon_class = actor and class_name(actor) or ""
        S.weapon_active_time = 0.0
        if wm then log("weapon: " .. S.weapon_class) end
        S.scan_timer = 0.0
    end
    if active then S.weapon_active_time = S.weapon_active_time + dt else S.weapon_active_time = 0.0 end
    S.weapon_active = active
end

local function update_pawn()
    local pawn = api:get_local_pawn(0)
    if pawn == nil or not exists(pawn) then
        if S.pawn ~= nil then reset_pawn_state() end
        S.status = "waiting for pawn"
        return false
    end
    local pa = addr(pawn)
    if pa ~= S.pawn_addr then
        reset_pawn_state()
        S.pawn, S.pawn_addr = pawn, pa
        log("pawn: " .. full_name(pawn))
    end
    local mesh = nil
    pcall(function() mesh = pawn.Mesh end)
    if mesh == nil or not exists(mesh) then
        S.status = "pawn has no Mesh"
        return false
    end
    if addr(mesh) ~= S.mesh_addr then
        pcall(destroy_poseable)
        S.mesh, S.mesh_addr = mesh, addr(mesh)
        S.pm_failed = false
        S.camera = nil
        pcall(function() S.camera = pawn.PlayerCamera end)
        log("body mesh: " .. short_name(mesh) .. ", camera: " .. short_name(S.camera))
    end
    return true
end

---------------------------------------------------------------------------
-- Per-frame render update (after UObjectHook moved the controller helper)
---------------------------------------------------------------------------
local function restore_moved()
    for _, m in ipairs(S.moved) do
        if exists(m.comp) then pcall(set_relative, m.comp, m.rel) end
    end
    S.moved = {}
end

local function remember_and_move(comp, p, q)
    local ok, rel = pcall(get_relative, comp)
    if ok and rel then S.moved[#S.moved + 1] = { comp = comp, rel = rel } end
    set_world_tf(comp, p, q)
end

-- 1) body yaw follows the headset: rotate the whole game mesh around the camera
local function apply_body_yaw(view_rotation)
    if not cfg.body_follow_head then return end
    local mesh = S.mesh
    local pawn_rot = S.pawn:K2_GetActorRotation()
    local head_yaw = view_rotation.Yaw or view_rotation.y
    if DBG.sim_head_yaw then head_yaw = normalize_axis(pawn_rot.Yaw + DBG.sim_head_yaw) end
    M_.head_yaw, M_.pawn_yaw = head_yaw, pawn_rot.Yaw
    if S.body_yaw == nil then S.body_yaw = head_yaw end
    local diff = normalize_axis(head_yaw - S.body_yaw)
    local dz = cfg.body_yaw_deadzone
    if math.abs(diff) > dz then
        S.body_yaw = normalize_axis(S.body_yaw + (math.abs(diff) - dz) * (diff > 0 and 1 or -1))
    end
    local delta = normalize_axis(S.body_yaw - pawn_rot.Yaw)
    -- interaction animations: the body keeps the game's orientation (blended in/out)
    delta = delta * (1.0 - S.lock_alpha)
    S.stats.last_yaw_delta = delta
    M_.body_delta = delta
    if math.abs(delta) < 0.05 then return end

    local pivot
    local ok = pcall(function() pivot = V(mesh:GetSocketLocation(BONE.camera)) end)
    if not ok or pivot == nil then
        if exists(S.camera) then pivot = V(S.camera:K2_GetComponentLocation()) else return end
    end
    local p_mesh, q_mesh = get_world_tf(mesh)
    local qy = qyaw(delta)
    local rel = vsub(p_mesh, pivot)
    local p_new = vadd(pivot, qrot(qy, rel))
    p_new.z = p_mesh.z
    remember_and_move(mesh, p_new, qnorm(qmul(qy, q_mesh)))
    S.stats.yaw_frames = S.stats.yaw_frames + 1
end

-- twist part of q around unit axis a (swing-twist decomposition), shortest form
local function qtwist(q, a)
    local d = q.x * a.x + q.y * a.y + q.z * a.z
    local t = { x = a.x * d, y = a.y * d, z = a.z * d, w = q.w }
    local n = math.sqrt(t.x * t.x + t.y * t.y + t.z * t.z + t.w * t.w)
    if n < 1e-9 then return { x = 0, y = 0, z = 0, w = 1 } end
    t = { x = t.x / n, y = t.y / n, z = t.z / n, w = t.w / n }
    if t.w < 0 then t = { x = -t.x, y = -t.y, z = -t.z, w = -t.w } end
    return t
end

-- fraction f of a rotation (slerp from identity)
local function qfrac(q, f)
    if q.w < 0 then q = { x = -q.x, y = -q.y, z = -q.z, w = -q.w } end
    local s = math.sqrt(q.x * q.x + q.y * q.y + q.z * q.z)
    if s < 1e-9 then return { x = 0, y = 0, z = 0, w = 1 } end
    local ang = 2.0 * math.atan(s, q.w)
    local h = ang * f * 0.5
    local k = math.sin(h) / s
    return { x = q.x * k, y = q.y * k, z = q.z * k, w = math.cos(h) }
end

-- forearm twist bones per elbow (fraction of the wrist twist they receive)
local TWIST = {
    mc_elbow_SH_r_jnt = { { "mc_forearm_twist_01_SH_r_jnt", 0.25 }, { "mc_forearm_twist_02_SH_r_jnt", 0.5 }, { "mc_forearm_twist_03_SH_r_jnt", 0.75 } },
    mc_elbow_SH_l_jnt = { { "mc_forearm_twist_01_SH_l_jnt", 0.25 }, { "mc_forearm_twist_02_SH_l_jnt", 0.5 }, { "mc_forearm_twist_03_SH_l_jnt", 0.75 } },
}

local function distribute_twist(pm, el, wr, Eq0, Wq0, Wq1)
    local list = TWIST[el]
    if not list or DBG.no_twist then return end
    local Ep, Eq = pbone_get(pm, el)
    local Wp = pbone_get(pm, wr)
    local Eqi = qinv(Eq)
    local axis = vnorm(qrot(Eqi, vsub(Wp, Ep)))                 -- forearm axis in elbow space
    local tw0 = qtwist(qmul(qinv(Eq0), Wq0), axis)               -- native wrist twist rel. to elbow
    local tw1 = qtwist(qmul(Eqi, Wq1), axis)                     -- new wrist twist rel. to elbow
    local delta = qmul(tw1, qinv(tw0))
    for _, e in ipairs(list) do
        local ok = pcall(function()
            local _, tq = pbone_get(pm, e[1])
            local local_q = qmul(Eqi, tq)
            pbone_set_rot(pm, e[1], qnorm(qmul(Eq, qmul(qfrac(delta, e[2]), local_q))))
        end)
        if not ok then return end
    end
end

-- rotation that maps local axes (a_l along the bone, n_l = hinge normal) onto world axes (a_w, n_w)
local function frame_q(a_l, n_l, a_w, n_w)
    local la = vnorm(a_l)
    local ln = vnorm(vsub(n_l, vscale(la, vdot(n_l, la))))
    local lc = vcross(la, ln)
    local wa = vnorm(a_w)
    local wn = vnorm(vsub(n_w, vscale(wa, vdot(n_w, wa))))
    local wc = vcross(wa, wn)
    -- R = Wa*La^T + Wn*Ln^T + Wc*Lc^T
    local function row(i)
        local function g(v) return (i == 1 and v.x) or (i == 2 and v.y) or v.z end
        return {
            x = g(wa) * la.x + g(wn) * ln.x + g(wc) * lc.x,
            y = g(wa) * la.y + g(wn) * ln.y + g(wc) * lc.y,
            z = g(wa) * la.z + g(wn) * ln.z + g(wc) * lc.z,
        }
    end
    return quat_from_rows(row(1), row(2), row(3))
end

-- local bone axes of an arm, sampled once from a bent animated pose
local function arm_axes(pm, sh, el, wr)
    S.arm_axes = S.arm_axes or {}
    local c = S.arm_axes[sh]
    if c then return c end
    local Sp, Sq = pbone_get(pm, sh)
    local Ep, Eq = pbone_get(pm, el)
    local Wp = pbone_get(pm, wr)
    local u, f = vsub(Ep, Sp), vsub(Wp, Ep)
    local n = vcross(u, f)
    if vlen(n) < 0.25 * vlen(u) * vlen(f) then return nil end -- elbow too straight (< ~15 deg)
    n = vnorm(n)
    c = {
        s_a = qrot(qinv(Sq), vnorm(u)), s_n = qrot(qinv(Sq), n),
        e_a = qrot(qinv(Eq), vnorm(f)), e_n = qrot(qinv(Eq), n),
    }
    S.arm_axes[sh] = c
    log("arm axes cached for " .. sh)
    return c
end

local function ik_arm(pm, sh, el, wr, T, Tq, alpha, down_bias, outward)
    local Sp, Sq = pbone_get(pm, sh)
    local Ep, Eq0 = pbone_get(pm, el)
    local Wp, Wq = pbone_get(pm, wr)

    -- blend the target with the animated pose
    local target_p = vlerp(Wp, T, alpha)
    local target_q = qnlerp(Wq, Tq, alpha)

    local hint
    if type(down_bias) == "table" then
        hint = down_bias                                   -- explicit, body-relative elbow direction
    else
        hint = vsub(Ep, vlerp(Sp, Wp, 0.5))                -- legacy: from the animated elbow
        hint = vadd(vadd(vnorm(hint), { x = 0, y = 0, z = -(down_bias or 0) }), outward or { x = 0, y = 0, z = 0 })
    end
    local E2, W2 = solve_two_bone(Sp, Ep, Wp, target_p, hint)

    local axes = (not DBG.legacy_arm) and arm_axes(pm, sh, el, wr) or nil
    if axes then
        -- deterministic orientation: bone axis + elbow hinge normal, independent of the animation
        local u = vsub(E2, Sp)
        local f = vsub(W2, E2)
        local n = vcross(u, f)
        if vlen(n) < 1e-3 then n = vcross(u, hint) end
        n = vnorm(n)
        S.arm_n = S.arm_n or {}
        if vdot(n, S.arm_n[sh] or n) < 0 and vlen(vcross(u, f)) < 1.0 then n = S.arm_n[sh] end
        S.arm_n[sh] = n
        pbone_set_rot(pm, sh, frame_q(axes.s_a, axes.s_n, u, n))
        pbone_set_rot(pm, el, frame_q(axes.e_a, axes.e_n, f, n))
    else
        -- upper arm
        local q1 = qbetween(vsub(Ep, Sp), vsub(E2, Sp))
        pbone_set_rot(pm, sh, qnorm(qmul(q1, Sq)))
        -- forearm (re-read after parent change)
        local Ep2, Eq2 = pbone_get(pm, el)
        local Wp2 = pbone_get(pm, wr)
        local q2 = qbetween(vsub(Wp2, Ep2), vsub(W2, Ep2))
        pbone_set_rot(pm, el, qnorm(qmul(q2, Eq2)))
    end
    -- hand
    pbone_set_rot(pm, wr, target_q)
    -- spread the wrist roll over the forearm twist bones (avoids the "candy wrapper")
    local ok_t, err_t = pcall(distribute_twist, pm, el, wr, Eq0, Wq, target_q)
    if not ok_t then log_error_once("twist", err_t) end
    pbone_set_rot(pm, wr, target_q)
    return vlen(vsub(target_p, W2))
end

local function read_chain(pm, chain)
    local t = {}
    for i, pair in ipairs(chain) do
        local ok, a, b = pcall(function()
            local pp, pq = pbone_get(pm, pair[1])
            local mp, mq = pbone_get(pm, pair[2])
            return { p = pp, q = pq }, { p = mp, q = mq }
        end)
        if not ok then return nil end
        t[i] = { pb = a, mb = b }
    end
    return t
end

-- parasite arms grow from the body (back). They stay on the body and only reach for the
-- player's hand when the animation brings them together (item hand-over), via their own IK.
local function proximity_weight(d, near, far)
    if d <= near then return 1.0 end
    if d >= far then return 0.0 end
    return (far - d) / (far - near)
end

local function follow_chain(pm, chain, before, hand_alpha)
    if not before then return end
    local n = #chain
    local o = before[n]
    local w = proximity_weight(vlen(vsub(o.pb.p, o.mb.p)), 15.0, 30.0) * (hand_alpha or 1.0)
    M_["pchain_w_" .. chain[1][1]] = w
    if w < 0.01 then return end
    local mwp, mwq = pbone_get(pm, chain[n][2])
    local dq = qmul(mwq, qinv(o.mb.q))
    local T = vadd(mwp, qrot(dq, vsub(o.pb.p, o.mb.p)))
    local Tq = qnorm(qmul(dq, o.pb.q))
    ik_arm(pm, chain[1][1], chain[2][1], chain[n][1], T, Tq, w, 0.0, nil)
end

-- parasite arm reaches for whichever player hand it is close to in the animation
-- (e.g. it presents the ammo apparatus to the gun during reloads)
local function parasite_follow(pm, chain, before, R0, L0, hand_alpha)
    if not before then return end
    local n = #chain
    local P0 = before[n].pb
    local near, far = DBG.p_near or 15.0, DBG.p_far or 30.0
    local function target(native_hand, bone)
        local hp, hq = pbone_get(pm, bone)
        local dq = qmul(hq, qinv(native_hand.q))
        return vadd(hp, qrot(dq, vsub(P0.p, native_hand.p))), qnorm(qmul(dq, P0.q))
    end
    local wr = R0 and proximity_weight(vlen(vsub(P0.p, R0.p)), near, far) or 0.0
    local wl = L0 and proximity_weight(vlen(vsub(P0.p, L0.p)), near, far) or 0.0
    M_["pw_" .. chain[1][1]] = { r = wr, l = wl }
    local w = math.max(wr, wl) * (hand_alpha or 1.0)
    if w < 0.01 then return end
    local T, Tq
    if wr > 0 and wl > 0 then
        local Tr, Trq = target(R0, BONE.r_wrist)
        local Tl, Tlq = target(L0, BONE.l_wrist)
        local f = wl / (wr + wl)
        T, Tq = vlerp(Tr, Tl, f), qnlerp(Trq, Tlq, f)
    elseif wr > 0 then
        T, Tq = target(R0, BONE.r_wrist)
    else
        T, Tq = target(L0, BONE.l_wrist)
    end
    ik_arm(pm, chain[1][1], chain[2][1], chain[n][1], T, Tq, w, 0.0, nil)
end

-- stun gun hose (chain from the root to the hand): blend each bone towards the wrist motion
local HOSE = {}
for i = 1, 10 do HOSE[i] = string.format("stungun_hose_SH_%02d_jnt", i) end

local function read_bones_world(pm, list)
    local t = {}
    for i, b in ipairs(list) do
        local ok, p, q = pcall(pbone_get, pm, b)
        if not ok then return nil end
        t[i] = { p = p, q = q }
    end
    return t
end

local function follow_hose(pm, before, w_old_p, w_old_q, w_new_p, w_new_q)
    if not before then return end
    local dq = qmul(w_new_q, qinv(w_old_q))
    local n = #HOSE
    local near = proximity_weight(vlen(vsub(before[n].p, w_old_p)), 20.0, 40.0)
    M_.hose_w = near
    if near < 0.01 then return end
    for i, b in ipairs(HOSE) do
        local t = i / n
        local w = t * t * (3 - 2 * t) * near -- smoothstep: base stays, end follows the hand
        local o = before[i]
        local moved_p = vadd(w_new_p, qrot(dq, vsub(o.p, w_old_p)))
        local moved_q = qnorm(qmul(dq, o.q))
        pbone_set_rot(pm, b, qnlerp(o.q, moved_q, w))
        pbone_set_loc(pm, b, vlerp(o.p, moved_p, w))
    end
end

local function update_anim_base(rel_p, dt)
    if S.anim_base == nil then S.anim_base = rel_p return end
    local k = math.min(1.0, dt * 1.5)
    S.anim_base = vlerp(S.anim_base, rel_p, k)
end

local function render_update(view_rotation)
    S.stats.frames = S.stats.frames + 1
    local mesh = S.mesh
    if not exists(mesh) or not exists(S.pawn) then return end

    if cfg.arms_mode == 1 then return end

    -- 1) whole body yaw follows the head (also moves weapon/attachments/camera for this frame)
    local ok, err = pcall(apply_body_yaw, view_rotation)
    if not ok then log_error_once("body_yaw", err) end

    -- 2) body copy pose
    local pm = S.pm
    if not (S.pm_ok and exists(pm)) then return end
    pm:CopyPoseFromSkeletalComponent(mesh)

    -- debug toggles / measurements
    if (DBG.show_game_mesh == true) ~= (S.dbg_show_game == true) then
        S.dbg_show_game = DBG.show_game_mesh == true
        pcall(function() mesh:SetRenderInMainPass(S.dbg_show_game) end)
    end
    if (DBG.hide_copy == true) ~= (S.dbg_hide_copy == true) then
        S.dbg_hide_copy = DBG.hide_copy == true
        pcall(function() pm:SetVisibility(not S.dbg_hide_copy, false) end)
    end
    pcall(function()
        local mw = V(mesh:GetSocketLocation(BONE.r_wrist))
        local cw = pbone_get(pm, BONE.r_wrist)
        local ml = V(mesh:GetSocketLocation(BONE.l_wrist))
        local cl = pbone_get(pm, BONE.l_wrist)
        local mc = V(mesh:GetSocketLocation(BONE.camera))
        local p_mesh, q_mesh = get_world_tf(mesh)
        local qi = qinv(q_mesh)
        M_.copy_vs_mesh_r = vlen(vsub(mw, cw))
        M_.copy_vs_mesh_l = vlen(vsub(ml, cl))
        M_.mesh_r_wrist_local = qrot(qi, vsub(mw, p_mesh))
        M_.copy_r_wrist_local = qrot(qi, vsub(cw, p_mesh))
        M_.mesh_cam_local = qrot(qi, vsub(mc, p_mesh))
        if exists(S.weapon_mesh) then
            local ww = V(S.weapon_mesh:GetSocketLocation(BONE.r_wrist))
            M_.weapon_r_wrist_local = qrot(qi, vsub(ww, p_mesh))
        end
    end)

    -- debug recorder: native (animated) bone positions in mesh space, per frame
    if DBG.record then
        S.rec = S.rec or { frames = {}, t0 = os.clock() }
        if #S.rec.frames >= 1500 then table.remove(S.rec.frames, 1) end
        do
            pcall(function()
                local p_mesh, q_mesh = get_world_tf(mesh)
                local qi = qinv(q_mesh)
                local fr = { t = os.clock() - S.rec.t0 }
                for _, b in ipairs(DBG.record_bones or {}) do
                    local bp = pbone_get(pm, b)
                    local v = qrot(qi, vsub(bp, p_mesh))
                    fr[b] = { math.floor(v.x * 10) / 10, math.floor(v.y * 10) / 10, math.floor(v.z * 10) / 10 }
                end
                pcall(function() fr.ammo = S.pawn.WeaponController:GetAmmoCount() end)
                S.rec.frames[#S.rec.frames + 1] = fr
            end)
        end
    elseif S.rec then
        pcall(json.dump_file, "scorn_vr_record.json", S.rec, 0)
        log("record saved: " .. #S.rec.frames .. " frames")
        S.rec = nil
    end

    -- 3) IK
    local dt = math.min(0.1, math.max(0.0, S.last_dt or 0.011))

    local using = true
    pcall(function() using = vr.is_using_controllers() end)
    local sim = type(DBG.sim_ctrl) == "table"
    local want_ik = cfg.arms_mode == 2 and not S.locked
        and (S.weapon_active and S.weapon_active_time > 0.25 or DBG.force_ik)
        and (using or sim) and (sim or (S.helper ~= nil and exists(S.helper)))
    M_.want_ik, M_.using = want_ik, using
    local target_alpha = want_ik and 1.0 or 0.0
    local step = dt * 4.0
    if S.ik_alpha < target_alpha then S.ik_alpha = math.min(target_alpha, S.ik_alpha + step)
    elseif S.ik_alpha > target_alpha then S.ik_alpha = math.max(target_alpha, S.ik_alpha - step) end
    if S.ik_alpha <= 0.0 or not (sim or (S.helper and exists(S.helper))) then
        S.anim_base = nil
        return
    end

    -- reference frame of the flat game view
    local p_cam, q_cam
    if exists(S.camera) then
        p_cam, q_cam = get_world_tf(S.camera)
    else
        p_cam, q_cam = pbone_get(pm, BONE.camera)
    end
    local q_cam_inv = qinv(q_cam)

    local p_ctrl, q_ctrl
    if sim then
        -- simulated controller in the (flat) camera frame: cm forward/right/up + optional rotation
        local o = DBG.sim_ctrl
        local qv = quat_from_rot(0, M_.head_yaw or select(2, rot_from_quat(q_cam)), 0)
        p_ctrl = vadd(p_cam, qrot(qv, { x = o[1] or 40, y = o[2] or 20, z = o[3] or -25 }))
        local r = DBG.sim_rot or { 0, 0, 0 }
        q_ctrl = qmul(qv, quat_from_rot(r[1], r[2], r[3]))
    else
        p_ctrl, q_ctrl = get_world_tf(S.helper)
    end
    M_.ctrl_rel_cam = qrot(q_cam_inv, vsub(p_ctrl, p_cam))

    local Wp, Wq = pbone_get(pm, BONE.r_wrist)
    local Lp, Lq = pbone_get(pm, BONE.l_wrist)

    -- native wrist relative to the view: rotation is kept 1:1 (aiming), position only as animation delta
    local rel_q = qmul(q_cam_inv, Wq)
    local rel_p = qrot(q_cam_inv, vsub(Wp, p_cam))
    update_anim_base(rel_p, dt)
    local anim_delta = { x = 0, y = 0, z = 0 }
    if cfg.keep_anim_offsets and S.anim_base then
        anim_delta = vsub(rel_p, S.anim_base)
        local l = vlen(anim_delta)
        if l > 25.0 then anim_delta = vscale(anim_delta, 25.0 / l) end
    end

    -- natural grip: hand forward along the controller, thumb up (from finger bones of the copy)
    local function hand_locals(wr, mid, idx, pnk)
        local wp, wq = pbone_get(pm, wr)
        local qi = qinv(wq)
        local f = qrot(qi, vsub(pbone_get(pm, mid), wp))
        local sd = qrot(qi, vsub(pbone_get(pm, idx), pbone_get(pm, pnk)))
        return f, sd
    end
    local rf, rs = hand_locals(BONE.r_wrist, "mc_middle_SH_r_01_jnt", "mc_index_SH_r_01_jnt", "mc_pinky_SH_r_01_jnt")
    local lf, ls = hand_locals(BONE.l_wrist, "mc_middle_SH_l_01_jnt", "mc_index_SH_l_01_jnt", "mc_pinky_SH_l_01_jnt")
    local r_grip = hand_grip_q(rf, rs)
    local l_grip = hand_grip_q(lf, ls)

    local q_manual = quat_from_rot(cfg.grip_pitch, cfg.grip_yaw, cfg.grip_roll)
    local q_manual_l = quat_from_rot(cfg.grip_pitch, -cfg.grip_yaw, -cfg.grip_roll)
    local Tq = qnorm(qmul(q_ctrl, qmul(q_manual, r_grip)))
    local T = vadd(p_ctrl, qrot(q_ctrl, vadd({ x = cfg.grip_x, y = cfg.grip_y, z = cfg.grip_z }, anim_delta)))

    -- left hand relation to the right hand in the animation (two-handed grips, reloads)
    local qW_inv = qinv(Wq)
    local l_rel_p = qrot(qW_inv, vsub(Lp, Wp))
    local l_rel_q = qmul(qW_inv, Lq)
    local l_dist = vlen(vsub(Lp, Wp))

    local _, q_mesh = get_world_tf(mesh)
    local body_right = qrot(q_mesh, { x = 0, y = 1, z = 0 })
    local r_before = read_chain(pm, P_CHAIN.r)
    local l_before = read_chain(pm, P_CHAIN.l)
    local hose_before = (not DBG.no_hose) and read_bones_world(pm, HOSE) or nil

    local body_fwd = qrot(q_mesh, { x = 1, y = 0, z = 0 })
    local function elbow_hint(side)
        -- down, outward and slightly back: stable, independent of the animation
        return vadd(vadd({ x = 0, y = 0, z = -1.0 }, vscale(body_right, 0.6 * side)), vscale(body_fwd, -0.25 - 0.3 * cfg.elbow_down))
    end
    local reach = ik_arm(pm, BONE.r_shoulder, BONE.r_elbow, BONE.r_wrist, T, Tq, S.ik_alpha, elbow_hint(1))
    S.stats.reach = reach
    S.stats.ik_frames = S.stats.ik_frames + 1

    if hose_before then
        local Wn_p, Wn_q = pbone_get(pm, BONE.r_wrist)
        local ok_h, err_h = pcall(follow_hose, pm, hose_before, Wp, Wq, Wn_p, Wn_q)
        if not ok_h then log_error_once("hose", err_h) end
    end

    local Wp_chk = pbone_get(pm, BONE.r_wrist)
    M_.wrist_err = vlen(vsub(Wp_chk, vlerp(Wp, T, S.ik_alpha)))
    M_.ik_alpha = S.ik_alpha

    if not DBG.no_left then
        -- left hand: on the left controller; blends onto the weapon when the animation
        -- holds the weapon with both hands (shotgun, reloads)
        local follow_w = 0.0
        if cfg.left_hand_follow then
            follow_w = (l_dist < 20.0) and 1.0 or ((l_dist < 35.0) and (35.0 - l_dist) / 15.0 or 0.0)
        end
        M_.l_dist = l_dist
        S.left_alpha = S.left_alpha + (follow_w - S.left_alpha) * math.min(1.0, dt * 6.0)

        local sim_l = type(DBG.sim_ctrl_l) == "table"
        local have_l = sim_l or (using and S.helper_l ~= nil and exists(S.helper_l))
        local Wp_new, Wq_new = pbone_get(pm, BONE.r_wrist)
        local LTw = vadd(Wp_new, qrot(Wq_new, l_rel_p))
        local LTqw = qnorm(qmul(Wq_new, l_rel_q))
        local LT, LTq, alpha_l
        if have_l then
            local p_l, q_l
            if sim_l then
                local o = DBG.sim_ctrl_l
                local qv = quat_from_rot(0, M_.head_yaw or select(2, rot_from_quat(q_cam)), 0)
                p_l = vadd(p_cam, qrot(qv, { x = o[1] or 35, y = o[2] or -20, z = o[3] or -30 }))
                local r = DBG.sim_rot_l or { 0, 0, 0 }
                q_l = qmul(qv, quat_from_rot(r[1], r[2], r[3]))
            else
                p_l, q_l = get_world_tf(S.helper_l)
            end
            local LTc = vadd(p_l, qrot(q_l, { x = cfg.grip_x, y = -cfg.grip_y, z = cfg.grip_z }))
            local LTqc = qnorm(qmul(q_l, qmul(q_manual_l, l_grip)))
            LT = vlerp(LTc, LTw, S.left_alpha)
            LTq = qnlerp(LTqc, LTqw, S.left_alpha)
            alpha_l = S.ik_alpha
        else
            LT, LTq, alpha_l = LTw, LTqw, S.ik_alpha * S.left_alpha
        end
        M_.left_mode = have_l and "controller" or "weapon"
        if alpha_l > 0.01 then
            ik_arm(pm, BONE.l_shoulder, BONE.l_elbow, BONE.l_wrist, LT, LTq, alpha_l, elbow_hint(-1))
        end
    end

    -- parasite arms (after both player arms are final)
    if not DBG.no_pchain then
        local R0 = r_before and r_before[3] and r_before[3].mb
        local L0 = l_before and l_before[3] and l_before[3].mb
        local ok_p, err_p = pcall(parasite_follow, pm, P_CHAIN.l, l_before, R0, L0, S.ik_alpha)
        if not ok_p then log_error_once("pchain_l", err_p) end
        ok_p, err_p = pcall(parasite_follow, pm, P_CHAIN.r, r_before, R0, L0, S.ik_alpha)
        if not ok_p then log_error_once("pchain_r", err_p) end
    end

    -- measurement only: weapon wrist bone vs copy wrist (master pose lag indicator)
    if exists(S.weapon_mesh) and S.weapon_active then
        pcall(function()
            local wl = V(S.weapon_mesh:GetSocketLocation(BONE.r_wrist))
            M_.weapon_vs_copy = vlen(vsub(wl, pbone_get(pm, BONE.r_wrist)))
        end)
    end
end

local function apply_debug_cam(position, rotation)
    local c = DBG.cam
    if type(c) ~= "table" then return end
    if c.abs and exists(S.camera) and exists(S.pawn) then
        -- absolute debug camera: relative to the game camera and pawn yaw (independent of the HMD)
        local cp = V(S.camera:K2_GetComponentLocation())
        local pyaw = S.pawn:K2_GetActorRotation().Yaw
        local o = qrot(quat_from_rot(0, pyaw, 0), { x = c.fwd or 0, y = c.right or 0, z = c.up or 0 })
        position.x, position.y, position.z = cp.x + o.x, cp.y + o.y, cp.z + o.z
        rotation.x, rotation.y, rotation.z = c.pitch or 0, pyaw + (c.turn or 0), 0
        return
    end
    local yaw = (rotation.Yaw or rotation.y)
    local q = quat_from_rot(0, yaw, 0)
    local off = qrot(q, { x = c.fwd or 0, y = c.right or 0, z = c.up or 0 })
    position.x = position.x + off.x
    position.y = position.y + off.y
    position.z = position.z + off.z
    if c.turn then rotation.y = yaw + c.turn end
    if c.yaw then rotation.y = c.yaw end -- absolute view yaw (position untouched)
    if c.pitch then rotation.x = c.pitch end
end

callbacks.on_pre_calculate_stereo_view_offset(function(device, view_index)
    M_.pre_calls = (M_.pre_calls or 0) + 1
end)

-- While the pawn is held by an interaction, head yaw turns the game's camera bone (CameraYaw,
-- clamped around the console) and that bone orbits camera_SH_jnt (~17 cm). In VR this slides the
-- eyes sideways against the console. Returns the world offset that puts the eyes back on the
-- orbit point for the body's forward direction (horizontal only; pitch behaves as in gameplay).
local function lock_view_shift()
    if S.lock_alpha <= 0.0 or S.cam_yaw == nil or DBG.no_view_shift then return nil end
    local mesh = S.mesh
    if not exists(mesh) or not exists(S.pawn) then return nil end
    local rel = normalize_axis(S.cam_yaw - S.pawn:K2_GetActorRotation().Yaw)
    M_.lock_cam_rel_yaw = rel
    if math.abs(rel) < 0.05 then return nil end
    local c0 = V(mesh:GetSocketLocation(BONE.camera_base))
    local cb = V(mesh:GetSocketLocation(BONE.camera))
    local v = { x = cb.x - c0.x, y = cb.y - c0.y, z = 0.0 }
    local r = qrot(qyaw(-rel * S.lock_alpha), v)
    local shift = { x = r.x - v.x, y = r.y - v.y, z = 0.0 }
    M_.lock_view_shift = vlen(shift)
    return shift
end

callbacks.on_post_calculate_stereo_view_offset(function(device, view_index, world_to_meters, position, rotation, is_double)
    M_.post_calls = (M_.post_calls or 0) + 1
    M_.last_view_index = view_index
    M_.frame_done_at_post = S.frame_done
    if view_index % 2 == 1 and not S.frame_done then
        S.frame_done = true
        -- before render_update: it may rotate the game mesh for this frame
        local ok_v, v = pcall(lock_view_shift)
        if ok_v then S.view_shift = v else S.view_shift = nil; log_error_once("view_shift", v) end
        local ok, err = pcall(render_update, rotation)
        if not ok then log_error_once("render_update", err) end
    end
    if S.view_shift and position then
        local sh = S.view_shift
        position.x, position.y, position.z = position.x + sh.x, position.y + sh.y, position.z + sh.z
    end
    if view_index % 2 == 1 and position and next(DBG) ~= nil then
        M_.eye_w = { x = position.x, y = position.y, z = position.z }
    end
    if DBG.cam then pcall(apply_debug_cam, position, rotation) end
end)

---------------------------------------------------------------------------
-- Turning
---------------------------------------------------------------------------
local function stick_value(raw)
    local v = raw / 32767.0
    if v > 1.0 then v = 1.0 elseif v < -1.0 then v = -1.0 end
    return v
end

callbacks.on_xinput_get_state(function(retval, user_index, state)
    M_.xinput_calls = (M_.xinput_calls or 0) + 1
    M_.xinput_user = user_index
    -- debug: inject gamepad input ({"hold":{"buttons":16384,"lt":255,"rt":255}})
    if state and type(DBG.hold) == "table" then
        local h = DBG.hold
        pcall(function()
            if h.buttons then state.Gamepad.wButtons = state.Gamepad.wButtons | math.tointeger(h.buttons) end
            if h.lt then state.Gamepad.bLeftTrigger = math.tointeger(h.lt) end
            if h.rt then state.Gamepad.bRightTrigger = math.tointeger(h.rt) end
        end)
    end
    if not cfg.turn_enabled or not state or not vr then return end
    local ok_idx, lowest = pcall(function() return vr.get_lowest_xinput_index() end)
    if ok_idx and lowest ~= nil and user_index ~= lowest then return end
    local using = true
    pcall(function() using = vr.is_using_controllers() end)
    if not using or not S.gameplay_active then
        turn.latched = false
        turn.smooth_input = 0.0
        return
    end
    local raw
    if cfg.turn_stick == 2 then raw = state.Gamepad.sThumbLX else raw = state.Gamepad.sThumbRX end
    local v = stick_value(raw)
    local av = math.abs(v)
    if cfg.turn_mode == 1 then
        if not turn.latched and av >= cfg.snap_press then
            turn.latched = true
            turn.snap_pending = (v > 0) and 1 or -1
        elseif turn.latched and av <= cfg.snap_release then
            turn.latched = false
        end
        turn.smooth_input = 0.0
    else
        local dz = 0.2
        if av < dz then
            turn.smooth_input = 0.0
        else
            local s = ((av - dz) / (1.0 - dz)) ^ 1.35
            turn.smooth_input = (v < 0) and -s or s
        end
    end
    if cfg.turn_stick == 2 then state.Gamepad.sThumbLX = 0 else state.Gamepad.sThumbRX = 0 end
    -- in VR the head/controller set the pitch; stick pitch only bends the body and twists the arms
    if cfg.block_stick_pitch then
        if cfg.turn_stick == 2 then state.Gamepad.sThumbLY = 0 else state.Gamepad.sThumbRY = 0 end
    end
end)

local function apply_turn(pc, dt)
    local delta = 0.0
    if cfg.turn_mode == 1 then
        if turn.snap_pending ~= 0 then
            delta = turn.snap_pending * cfg.snap_angle
            turn.snap_pending = 0
        end
    elseif turn.smooth_input ~= 0.0 then
        delta = turn.smooth_input * cfg.smooth_speed * dt
    end
    if delta == 0.0 then return end
    local rot = pc:GetControlRotation()
    rot.Yaw = rot.Yaw + delta
    pc:SetControlRotation(rot)
    if S.body_yaw then S.body_yaw = normalize_axis(S.body_yaw + delta) end
end

---------------------------------------------------------------------------
-- Aim switching + pawn yaw (from Tensai37's scornfix)
---------------------------------------------------------------------------
local function update_aim(dt)
    if not cfg.auto_aim_switch then return end
    local want = S.weapon_active and 2 or 1
    if want ~= S.stable_want then
        S.stable_want, S.stable_time = want, 0.0
    else
        S.stable_time = S.stable_time + dt
    end
    if S.stable_time >= 0.2 and S.stable_want ~= S.last_aim then
        if pcall(function() vr.set_aim_method(S.stable_want) end) then
            S.last_aim = S.stable_want
        else
            S.last_aim = -1
        end
    end
end

local function sync_pawn_yaw(pc, dt)
    local pawn = S.pawn
    pawn.bUseControllerRotationYaw = false
    -- interaction animations: the game places and turns the character itself
    if S.locked then return end
    local control_rot = pc:GetControlRotation()
    local pawn_rot = pawn:K2_GetActorRotation()
    local yaw = control_rot.Yaw
    if S.yaw_resync then
        -- after an interaction: turn back to the view direction smoothly instead of popping
        local diff = normalize_axis(yaw - pawn_rot.Yaw)
        local max_step = 540.0 * dt
        if math.abs(diff) > max_step then
            yaw = normalize_axis(pawn_rot.Yaw + (diff > 0 and max_step or -max_step))
        else
            S.yaw_resync = false
        end
    end
    pawn:K2_SetActorRotation({ Pitch = pawn_rot.Pitch, Yaw = yaw, Roll = pawn_rot.Roll }, false)
end

---------------------------------------------------------------------------
-- Interaction lock: let the native animation own the body during consoles, items and
-- scripted events (detected from AScornCharacter.CharacterState)
---------------------------------------------------------------------------
-- UEVR roomscale movement moves the pawn after the headset every frame. Turning the head moves
-- the headset a few cm, so at a console the body and hands slid away from the use spot. It is
-- paused while the animation owns the body and restored afterwards (the pawn then catches up
-- with the head in one step, the view stays continuous). Module level: survives pawn changes.
-- A marker file remembers a paused roomscale, so a crash/exit mid-interaction cannot leave it off.
local ROOMSCALE_FILE = "scorn_vr_roomscale.json"
local roomscale = { suspended = false, original = nil }

local function suspend_roomscale(on)
    if on == roomscale.suspended then return end
    if on then
        local ok, v = pcall(function() return vr:get_mod_value("VR_RoomscaleMovement") end)
        if not ok or type(v) ~= "string" then return end
        roomscale.original = v
        if v:find("true") then
            pcall(json.dump_file, ROOMSCALE_FILE, { paused = true }, 0)
            pcall(function() vr.set_mod_value("VR_RoomscaleMovement", "false") end)
            log("roomscale movement paused")
        end
        roomscale.suspended = true
    else
        if roomscale.original and roomscale.original:find("true") then
            pcall(function() vr.set_mod_value("VR_RoomscaleMovement", "true") end)
            pcall(json.dump_file, ROOMSCALE_FILE, { paused = false }, 0)
            log("roomscale movement restored")
        end
        roomscale.suspended, roomscale.original = false, nil
    end
end

do -- left paused by a previous session?
    local ok, d = pcall(json.load_file, ROOMSCALE_FILE)
    if ok and type(d) == "table" and d.paused == true then
        pcall(function() vr.set_mod_value("VR_RoomscaleMovement", "true") end)
        pcall(json.dump_file, ROOMSCALE_FILE, { paused = false }, 0)
        log("roomscale movement restored (left paused by a previous session)")
    end
end

local state_names_checked = false
local function verify_state_names()
    if state_names_checked then return end
    state_names_checked = true
    local ok, err = pcall(function()
        local en = api:find_uobject("Enum /Script/Scorn.ECharacterState")
        local cls = api:find_uobject("Class /Script/Engine.KismetNodeHelperLibrary")
        if en == nil or cls == nil then error("enum or helper library not found") end
        local lib = cls:get_class_default_object()
        local mism = 0
        for i = 0, #CHAR_STATE_NAMES do
            local n = fname_str(lib:GetEnumeratorName(en, i)):gsub("^.*::", "")
            if n ~= "" and n ~= "None" and n ~= CHAR_STATE_NAMES[i] then
                log("character state " .. i .. " is " .. n .. " (expected " .. tostring(CHAR_STATE_NAMES[i]) .. ")")
                CHAR_STATE_NAMES[i] = n
                mism = mism + 1
            end
        end
        log("character state names verified, " .. mism .. " corrected")
    end)
    if not ok then log("character state names not verified (using built-in list): " .. tostring(err)) end
end

local function update_interaction_lock(dt)
    local st = nil
    pcall(function() st = S.pawn.CharacterState end)
    local name = "-"
    if type(st) == "number" then
        verify_state_names()
        name = CHAR_STATE_NAMES[st] or tostring(st)
    end
    local in_inv = false
    pcall(function() in_inv = S.pawn.bInInventoryAnim == true end)
    local locked = cfg.lock_on_interaction and (LOCK_STATES[name] == true or in_inv)
    if DBG.force_lock ~= nil then locked = DBG.force_lock == true end
    S.char_state = st
    S.cam_yaw = nil
    pcall(function() local y = S.pawn.CameraYaw; if type(y) == "number" then S.cam_yaw = y end end)
    if name ~= S.char_state_name or locked ~= S.locked then
        log("character state: " .. name .. (locked and " -> native animation (body locked)" or ""))
        S.char_state_name = name
    end
    if S.locked and not locked then S.yaw_resync = true end
    S.locked = locked
    suspend_roomscale(locked and not DBG.keep_roomscale)
    local target = locked and 1.0 or 0.0
    local step = math.min(0.1, dt) * 4.0
    if S.lock_alpha < target then S.lock_alpha = math.min(target, S.lock_alpha + step)
    elseif S.lock_alpha > target then S.lock_alpha = math.max(target, S.lock_alpha - step) end
    M_.char_state, M_.locked, M_.lock_alpha = name, locked, S.lock_alpha
end

---------------------------------------------------------------------------
-- Diagnostics
---------------------------------------------------------------------------
local function describe_comp(c)
    local d = { name = short_name(c), class = class_name(c) }
    pcall(function() local p = c:GetAttachParent(); d.attach_parent = p and short_name(p) or "" end)
    pcall(function() d.attach_socket = fname_str(c:GetAttachSocketName()) end)
    pcall(function() d.visible = c:IsVisible() end)
    pcall(function() local sm = c.SkeletalMesh; if sm then d.skeletal_mesh = sm:get_full_name() end end)
    pcall(function() d.animation_mode = c.AnimationMode end)
    pcall(function() local ac = c.AnimClass; if ac then d.anim_class = ac:get_full_name() end end)
    pcall(function() d.has_root_bone = has_bone(c, BONE.root) end)
    pcall(function() d.tick_option = c.VisibilityBasedAnimTickOption end)
    return d
end

local function dump_diagnostics(reason)
    local out = { reason = reason, version = VERSION }
    if not exists(S.pawn) then
        out.error = "no pawn"
        pcall(json.dump_file, DUMP_FILE, out, 2)
        return
    end
    out.pawn = full_name(S.pawn)
    out.character_state = { value = S.char_state, name = S.char_state_name, locked = S.locked }
    if exists(S.mesh) then
        out.mesh = describe_comp(S.mesh)
        local parents = {}
        local hidden = {}
        local ok, n = pcall(function() return S.mesh:GetNumBones() end)
        if ok and type(n) == "number" then
            for i = 0, n - 1 do
                local b = fname_str(S.mesh:GetBoneName(i))
                local p = ""
                pcall(function() p = fname_str(S.mesh:GetParentBone(b)) end)
                parents[#parents + 1] = b .. " <- " .. p
                local h = false
                pcall(function() h = S.mesh:IsBoneHiddenByName(b) end)
                if h then hidden[#hidden + 1] = b end
            end
        end
        out.bone_parents = parents
        out.hidden_bones = hidden
    end
    if exists(S.weapon_mesh) then
        out.weapon = describe_comp(S.weapon_mesh)
        out.weapon.actor_class = S.weapon_class
    end
    out.parts = {}
    for _, p in ipairs(S.parts) do
        local d = describe_comp(p.comp)
        d.direct_child, d.same_skeleton = p.direct_child, p.same_skeleton
        out.parts[#out.parts + 1] = d
    end
    out.camera = exists(S.camera) and describe_comp(S.camera) or "none"
    local ok = pcall(json.dump_file, DUMP_FILE, out, 2)
    log("diagnostics dumped (" .. tostring(reason) .. "): " .. tostring(ok))
end

local status_timer = 0.0
local function write_status(dt)
    status_timer = status_timer - dt
    if status_timer > 0 then return end
    status_timer = 0.5
    flush_log()  -- small, only when new lines were logged (useful for bug reports)
    if not cfg.debug_files and next(DBG) == nil then return end
    local t = {
        version = VERSION, status = S.status,
        weapon = S.weapon_class, weapon_active = S.weapon_active,
        poseable = S.pm_ok, poseable_failed = S.pm_failed, mesh_hidden_mode = S.mesh_hidden_mode,
        helper = S.helper ~= nil, ik_alpha = S.ik_alpha, left_alpha = S.left_alpha,
        remastered = 0, parts = #S.parts, stats = S.stats,
        using_controllers = (function() local u = nil pcall(function() u = vr.is_using_controllers() end) return u end)(),
        aim = S.last_aim,
        char_state = S.char_state, char_state_name = S.char_state_name, locked = S.locked, lock_alpha = S.lock_alpha,
        m = M_, debug = DBG,
        hmd_active = (function() local u = nil pcall(function() u = vr.is_hmd_active() end) return u end)(),
        fps = (S.last_dt and S.last_dt > 0) and (1.0 / S.last_dt) or 0,
    }
    for _ in pairs(S.remastered) do t.remastered = t.remastered + 1 end
    pcall(json.dump_file, STATUS_FILE, t, 2)
    flush_log()
end

---------------------------------------------------------------------------
-- Main tick
---------------------------------------------------------------------------
local function is_paused()
    if not gameplay_statics or not exists(S.pawn) then return false end
    local ok, r = pcall(function() return gameplay_statics:IsGamePaused(S.pawn) end)
    return ok and r == true
end

local dumped_this_session = false

-- debug: run a Lua snippet from scorn_vr_debug.json ("eval"), result goes to status.m.eval
local function run_eval()
    if type(DBG.eval) ~= "string" then return end
    local key = DBG.eval .. tostring(DBG.eval_id or "")
    if key == S.last_eval then return end
    S.last_eval = key
    local env = setmetatable({
        S = S, cfg = cfg, M = M_, V = V, BONE = BONE, api = api, vr = vr,
        pbone_get = pbone_get, get_world_tf = get_world_tf, quat_from_rot = quat_from_rot,
        rot_from_quat = rot_from_quat, qinv = qinv, qmul = qmul, qrot = qrot, vsub = vsub, vadd = vadd,
        vlen = vlen, vnorm = vnorm, vdot = vdot, fname_str = fname_str, short_name = short_name,
        full_name = full_name, class_name = class_name, exists = exists,
    }, { __index = _ENV })
    local f, err = load(DBG.eval, "=eval", "t", env)
    if not f then M_.eval = "compile error: " .. tostring(err) return end
    local ok, r = pcall(f)
    M_.eval = ok and r or ("error: " .. tostring(r))
end

local function tick(dt)
    S.last_dt = dt
    read_debug(dt)
    pcall(run_eval)
    restore_moved()
    S.frame_done = false

    if not update_pawn() then
        S.gameplay_active = false
        pcall(suspend_roomscale, false)
        return
    end
    local pc = api:get_player_controller(0)
    if pc == nil then
        S.gameplay_active = false
        pcall(suspend_roomscale, false)
        return
    end
    S.gameplay_active = not is_paused()

    update_weapon(dt)
    do
        local ok, err = pcall(update_interaction_lock, dt)
        if not ok then log_error_once("interaction_lock", err) end
    end

    S.scan_timer = S.scan_timer - dt
    if S.scan_timer <= 0.0 then
        S.scan_timer = 0.5
        scan_parts()
        if cfg.arms_mode ~= 1 then remaster_followers() end
    end

    if cfg.disable_player_shadows then
        if exists(S.mesh) then disable_shadow(S.mesh) end
        if exists(S.weapon_mesh) then disable_shadow(S.weapon_mesh) end
    end

    if cfg.arms_mode == 1 then
        -- legacy: no body, weapon glued to the controller
        if S.pm then destroy_poseable() end
        for _, part in ipairs(S.parts) do set_hidden_by_us(part.comp, true) end
        if exists(S.mesh) then set_hidden_by_us(S.mesh, true) end
        if S.weapon_active and exists(S.weapon_mesh) then attach_legacy_weapon(S.weapon_mesh) end
        S.status = "weapon only (legacy)"
    else
        detach_legacy_weapon()
        -- debug: hide parts by name
        local hide_set = {}
        if type(DBG.hide_parts) == "table" then
            for _, n in ipairs(DBG.hide_parts) do hide_set[n] = true end
        end
        for _, part in ipairs(S.parts) do
            set_hidden_by_us(part.comp, hide_set[part.name] == true)
        end
        if not S.pm and not S.pm_failed and create_poseable() then
            scan_parts()
            remaster_followers()
        end
        if cfg.arms_mode == 2 then
            ensure_helper("helper", 1)
            ensure_helper("helper_l", 0)
        end
        if S.pm_ok then
            S.status = S.weapon_active and (cfg.arms_mode == 2 and "body + IK arm" or "body (flat arms)") or "body"
        else
            S.status = "body copy unavailable (see log)"
        end
    end

    pcall(update_aim, dt)
    if S.locked then
        -- no stick turning while the animation owns the body (and no queued snap afterwards)
        turn.snap_pending = 0
    elseif cfg.turn_enabled and S.gameplay_active then
        local ok, err = pcall(apply_turn, pc, dt)
        if not ok then log_error_once("turn", err) end
    end
    pcall(sync_pawn_yaw, pc, dt)

    if S.weapon_active and S.weapon_active_time > 2.0 and not dumped_this_session then
        dumped_this_session = true
        dump_diagnostics("auto: weapon drawn")
    end

    if config_dirty then
        config_save_timer = config_save_timer - dt
        if config_save_timer <= 0.0 then save_config_now() end
    end
    write_status(dt)
end

callbacks.on_pre_engine_tick(function(engine, delta_time)
    local ok, err = pcall(tick, delta_time)
    if not ok then log_error_once("tick", err) end
end)

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
local function ui_checkbox(label, key)
    local changed, v = imgui.checkbox(label, cfg[key])
    if changed then cfg[key] = v; mark_dirty() end
    return changed
end
local function ui_combo(label, key, values)
    local changed, v = imgui.combo(label, cfg[key], values)
    if changed then cfg[key] = v; mark_dirty() end
    return changed
end
local function ui_drag(label, key, speed, mn, mx)
    local changed, v = imgui.drag_float(label, cfg[key], speed, mn, mx)
    if changed then cfg[key] = v; mark_dirty() end
    return changed
end

callbacks.on_draw_ui(function()
    if not imgui.collapsing_header("Scorn VR v" .. VERSION) then return end
    imgui.text("Status: " .. S.status .. "   Weapon: " .. (S.weapon_class ~= "" and S.weapon_class or "-"))
    imgui.text(string.format("IK %.2f  reach err %.1f cm  weapon: %s", S.ik_alpha, S.stats.reach or 0, S.stats.weapon_follow))
    imgui.text("Character state: " .. tostring(S.char_state_name or "-") .. (S.locked and "  (native animation)" or ""))

    if imgui.tree_node("Turning") then
        ui_checkbox("Enable stick turning", "turn_enabled")
        ui_checkbox("Block stick pitch (look up/down)", "block_stick_pitch")
        ui_combo("Turn mode", "turn_mode", TURN_MODES)
        ui_combo("Turn stick", "turn_stick", TURN_STICKS)
        local changed, v = imgui.slider_int("Snap angle", cfg.snap_angle, 15, 90)
        if changed then cfg.snap_angle = v; mark_dirty() end
        ui_drag("Smooth speed (deg/s)", "smooth_speed", 1.0, 30.0, 360.0)
        imgui.tree_pop()
    end

    if imgui.tree_node("Body / arms") then
        if ui_combo("Mode", "arms_mode", ARMS_MODES) then
            restore_moved()
            unhide_all_parts()
            S.pm_failed = false
        end
        ui_checkbox("Body turns with the headset", "body_follow_head")
        ui_drag("Body turn deadzone (deg)", "body_yaw_deadzone", 0.5, 0.0, 90.0)
        if ui_checkbox("Hide head", "hide_head") and S.pm_ok and exists(S.pm) then
            if cfg.hide_head then pcall(function() S.pm:HideBoneByName(BONE.head, 0) end)
            else pcall(function() S.pm:UnHideBoneByName(BONE.head) end) end
        end
        ui_checkbox("Left hand follows the weapon (two-handed)", "left_hand_follow")
        ui_checkbox("Keep weapon animation offsets (recoil/reload)", "keep_anim_offsets")
        ui_checkbox("Disable player shadows", "disable_player_shadows")
        ui_checkbox("Aim: head without weapon, controller with weapon", "auto_aim_switch")
        ui_checkbox("Native animation during interactions (consoles, items)", "lock_on_interaction")
        imgui.tree_pop()
    end

    if imgui.tree_node("Hand placement") then
        imgui.text("Wrist relative to the controller:")
        ui_drag("Pitch", "grip_pitch", 0.2, -180.0, 180.0)
        ui_drag("Yaw", "grip_yaw", 0.2, -180.0, 180.0)
        ui_drag("Roll", "grip_roll", 0.2, -180.0, 180.0)
        ui_drag("Forward (cm)", "grip_x", 0.1, -40.0, 40.0)
        ui_drag("Right (cm)", "grip_y", 0.1, -40.0, 40.0)
        ui_drag("Up (cm)", "grip_z", 0.1, -40.0, 40.0)
        ui_drag("Elbow down bias", "elbow_down", 0.01, 0.0, 3.0)
        if imgui.button("Reset hand placement") then
            for _, k in ipairs({ "grip_pitch", "grip_yaw", "grip_roll", "grip_x", "grip_y", "grip_z", "elbow_down" }) do
                cfg[k] = defaults[k]
            end
            mark_dirty()
        end
        imgui.tree_pop()
    end

    if imgui.tree_node("Diagnostics") then
        ui_checkbox("Write debug files to data/", "debug_files")
        if imgui.button("Write data/scorn_vr_dump.json") then dump_diagnostics("manual") end
        imgui.tree_pop()
    end
    if imgui.button("Save settings") then save_config_now() end
end)

---------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------
callbacks.on_script_reset(function()
    pcall(suspend_roomscale, false)
    pcall(restore_moved)
    pcall(destroy_poseable)
    pcall(unhide_all_parts)
    pcall(detach_legacy_weapon)
    pcall(destroy_helper)
    if config_dirty then save_config_now() end
    log("script reset")
    flush_log()
end)

log("Scorn VR " .. VERSION .. " loaded")
