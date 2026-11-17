--[[
  UEVR mod core skeleton (template). Loaded by templates/loader.lua from <profile>/data/mod_core.lua.
  Contains the proven building blocks; fill in the game-specific parts marked TODO.

  Building blocks:
    - versioned config in data/, autosave
    - log file in data/ (print() does NOT reach UEVR's log.txt)
    - debug channel data/mod_debug.json: status file, eval, debug camera, simulated controllers
    - controller/HMD helper components positioned by UObjectHook (world-space controller poses)
    - render-only edits in post_calculate_stereo_view_offset (first eye) + restore in pre_engine_tick
    - snap turn through XInput + SetControlRotation
    - settings panel (UEVR menu -> Script UI)
]]

UEVR_UObjectHook.activate()

local api = uevr.api
local vr = uevr.params.vr
local callbacks = uevr.sdk.callbacks

local VERSION = "0.1.0"
local P = "mod_"                       -- file prefix in data/
local M = load(fs.read("uemath.lua"))() -- copy templates/uemath.lua into data/ (or paste it here)

---------------------------------------------------------------------------
-- config
---------------------------------------------------------------------------
local defaults = { snap_turn = true, snap_angle = 45, block_stick_pitch = true, debug_files = false }
local cfg = {}
local function load_config()
    cfg = {}
    for k, v in pairs(defaults) do cfg[k] = v end
    local ok, d = pcall(json.load_file, P .. "config.json")
    if ok and type(d) == "table" and d.version == VERSION then
        for k, v in pairs(d) do if defaults[k] ~= nil and type(v) == type(defaults[k]) then cfg[k] = v end end
    end
end
local dirty, save_t = false, 0
local function save_config()
    local t = { version = VERSION }
    for k, v in pairs(cfg) do t[k] = v end
    pcall(json.dump_file, P .. "config.json", t, 4)
    dirty = false
end
load_config()
-- UObjectHook attach smoothing adds ~60 ms latency to anything driven by controller poses
pcall(function() vr.set_mod_value("UObjectHook_AttachLerpEnabled", "false") end)

---------------------------------------------------------------------------
-- logging
---------------------------------------------------------------------------
local lines, log_dirty = {}, false
local function log(msg)
    local l = os.date("%H:%M:%S ") .. tostring(msg)
    print(l)
    lines[#lines + 1] = l
    if #lines > 300 then table.remove(lines, 1) end
    log_dirty = true
end
local errs = {}
local function log_error_once(key, e)
    if errs[key] ~= tostring(e) then errs[key] = tostring(e); log("ERROR " .. key .. ": " .. tostring(e)) end
end

---------------------------------------------------------------------------
-- UObject helpers (FVector/FRotator come back as Vector3f with X/Y/Z and Pitch/Yaw/Roll aliases)
---------------------------------------------------------------------------
local function exists(o) if o == nil then return false end local ok, r = pcall(UEVR_UObjectHook.exists, o) return ok and r == true end
local function addr(o) if o == nil then return 0 end local ok, a = pcall(function() return o:get_address() end) return ok and a or 0 end
local function V(t) return { x = t.X, y = t.Y, z = t.Z } end
local function get_world_tf(c)
    local l, r = c:K2_GetComponentLocation(), c:K2_GetComponentRotation()
    return V(l), M.quat_from_rot(r.Pitch, r.Yaw, r.Roll)
end
local function set_world_tf(c, p, q)
    local pi, ya, ro = M.rot_from_quat(q)
    -- tables work for struct params; {} = out param (SweepHitResult) to ignore
    c:K2_SetWorldLocationAndRotation({ X = p.x, Y = p.y, Z = p.z }, { Pitch = pi, Yaw = ya, Roll = ro }, false, {}, true)
end
local function get_relative(c)
    local l, r = c.RelativeLocation, c.RelativeRotation
    return { loc = { X = l.X, Y = l.Y, Z = l.Z }, rot = { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll } }
end
local scene_c = api:find_uobject("Class /Script/Engine.SceneComponent")

---------------------------------------------------------------------------
-- state
---------------------------------------------------------------------------
local S = { pawn = nil, pawn_addr = 0, helpers = {}, moved = {}, frame_done = false, dt = 0.011 }
local DBG, dbg_t, MEAS = {}, 0, {}

-- helper scene component that UObjectHook moves to a controller every frame (hand 0 = left, 1 = right, 2 = HMD)
local function ensure_helper(hand)
    local h = S.helpers[hand]
    if h and exists(h) then return h end
    if not exists(S.pawn) then return nil end
    local ok, c = pcall(function() return api:add_component_by_class(S.pawn, scene_c) end)
    if not ok or c == nil then return nil end
    local st = UEVR_UObjectHook.get_or_add_motion_controller_state(c)
    st:set_hand(hand)
    if not pcall(function() st:set_permanent(true) end) then pcall(function() st:set_permanant(true) end) end
    S.helpers[hand] = c
    return c
end
local function destroy_helpers()
    for k, h in pairs(S.helpers) do
        if exists(h) then
            pcall(function() UEVR_UObjectHook.remove_motion_controller_state(h) end)
            pcall(function() h:K2_DestroyComponent(h) end)
        end
        S.helpers[k] = nil
    end
end

-- render-only edit: remember the relative transform, restore it before the next game tick
local function move_for_render(c, p, q)
    local ok, rel = pcall(get_relative, c)
    if ok then S.moved[#S.moved + 1] = { c = c, rel = rel } end
    set_world_tf(c, p, q)
end
local function restore_moved()
    for _, m in ipairs(S.moved) do
        if exists(m.c) then pcall(function() m.c:K2_SetRelativeLocationAndRotation(m.rel.loc, m.rel.rot, false, {}, true) end) end
    end
    S.moved = {}
end

---------------------------------------------------------------------------
-- per-frame render update: runs after UObjectHook moved its components for this frame
---------------------------------------------------------------------------
local function render_update(view_rot)
    -- view_rot is a Vector3f: x = pitch, y = yaw, z = roll (NOT .yaw)
    MEAS.head_yaw = view_rot.Yaw or view_rot.y
    local r = ensure_helper(1)
    if r then
        local p, q = get_world_tf(r)
        MEAS.right_ctrl = p
    end
    -- TODO: game-specific pose work (body copy, IK, ...) using move_for_render()/poseable bones
end

local function apply_debug_cam(pos, rot)
    local c = DBG.cam
    if type(c) ~= "table" then return end
    local yaw = rot.Yaw or rot.y
    local o = M.qrot(M.quat_from_rot(0, yaw, 0), { x = c.fwd or 0, y = c.right or 0, z = c.up or 0 })
    pos.x, pos.y, pos.z = pos.x + o.x, pos.y + o.y, pos.z + o.z
    if c.turn then rot.y = yaw + c.turn end
    if c.pitch then rot.x = c.pitch end
end

callbacks.on_post_calculate_stereo_view_offset(function(device, view_index, wtm, position, rotation, is_double)
    -- UE4 passes view indices 1 and 2; UObjectHook ticks attachments when (view_index + 1) % 2 == 0
    if view_index % 2 == 1 and not S.frame_done then
        S.frame_done = true
        local ok, e = pcall(render_update, rotation)
        if not ok then log_error_once("render", e) end
    end
    if DBG.cam then pcall(apply_debug_cam, position, rotation) end
end)

---------------------------------------------------------------------------
-- input: snap turn on the right stick, block stick pitch
---------------------------------------------------------------------------
local turn = { latched = false, pending = 0 }
callbacks.on_xinput_get_state(function(retval, user_index, state)
    if not state then return end
    local ok, low = pcall(function() return vr.get_lowest_xinput_index() end)
    if ok and low ~= nil and user_index ~= low then return end
    if not vr.is_using_controllers() then return end
    local v = state.Gamepad.sThumbRX / 32767.0
    if cfg.snap_turn then
        if not turn.latched and math.abs(v) > 0.6 then turn.latched = true; turn.pending = v > 0 and 1 or -1
        elseif turn.latched and math.abs(v) < 0.35 then turn.latched = false end
        state.Gamepad.sThumbRX = 0
    end
    if cfg.block_stick_pitch then state.Gamepad.sThumbRY = 0 end
end)

---------------------------------------------------------------------------
-- debug channel
---------------------------------------------------------------------------
local function debug_tick(dt)
    dbg_t = dbg_t - dt
    if dbg_t > 0 then return end
    dbg_t = 0.5
    local ok, d = pcall(json.load_file, P .. "debug.json")
    DBG = (ok and type(d) == "table") and d or {}
    -- eval: run a snippet once per new eval_id, result into status.m.eval
    if type(DBG.eval) == "string" then
        local key = DBG.eval .. tostring(DBG.eval_id)
        if key ~= S.last_eval then
            S.last_eval = key
            local env = setmetatable({ S = S, M = M, api = api, vr = vr, V = V, get_world_tf = get_world_tf, exists = exists }, { __index = _ENV })
            local f, e = load(DBG.eval, "=eval", "t", env)
            if f then local ok2, r = pcall(f); MEAS.eval = ok2 and r or ("error: " .. tostring(r)) else MEAS.eval = "compile: " .. tostring(e) end
        end
    end
    if log_dirty then pcall(fs.write, P .. "log.txt", table.concat(lines, "\n") .. "\n"); log_dirty = false end
    if cfg.debug_files or next(DBG) ~= nil then
        local hmd = nil
        pcall(function() hmd = vr.is_hmd_active() end)
        pcall(json.dump_file, P .. "status.json", { version = VERSION, hmd_active = hmd, m = MEAS, debug = DBG, fps = 1 / S.dt }, 2)
    end
end

---------------------------------------------------------------------------
-- tick
---------------------------------------------------------------------------
callbacks.on_pre_engine_tick(function(engine, dt)
    S.dt = dt
    restore_moved()
    S.frame_done = false
    local ok, e = pcall(function()
        debug_tick(dt)
        local pawn = api:get_local_pawn(0)
        if pawn == nil or not exists(pawn) then S.pawn, S.pawn_addr = nil, 0; return end
        if addr(pawn) ~= S.pawn_addr then
            destroy_helpers()
            S.pawn, S.pawn_addr = pawn, addr(pawn)
            log("pawn: " .. pawn:get_full_name())
        end
        local pc = api:get_player_controller(0)
        if pc and turn.pending ~= 0 then
            local r = pc:GetControlRotation()
            r.Yaw = r.Yaw + turn.pending * cfg.snap_angle
            pc:SetControlRotation(r)
            turn.pending = 0
        end
        if dirty then save_t = save_t - dt; if save_t <= 0 then save_config() end end
    end)
    if not ok then log_error_once("tick", e) end
end)

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
callbacks.on_draw_ui(function()
    if not imgui.collapsing_header("My VR mod v" .. VERSION) then return end
    local ch, v = imgui.checkbox("Snap turn", cfg.snap_turn)
    if ch then cfg.snap_turn = v; dirty = true; save_t = 1 end
    ch, v = imgui.slider_int("Snap angle", cfg.snap_angle, 15, 90)
    if ch then cfg.snap_angle = v; dirty = true; save_t = 1 end
end)

callbacks.on_script_reset(function()
    restore_moved()
    destroy_helpers()
    if dirty then save_config() end
end)

log("core " .. VERSION .. " loaded")
