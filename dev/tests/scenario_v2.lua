local function VR(p, y, r) return {x=p, y=y, z=r, Pitch=p, Yaw=y, Roll=r} end
local function check(c, msg) if not c then error("FAIL: "..msg.."\nLOG:\n"..table.concat(LOG,"\n")) end end
local dt = 1/90
local view = VR(0, 0, 0)
local ctrl_p = {x=1040, y=2015, z=150}
local ctrl_q = M.quat_from_rot(0, 0, 0)
local function frame()
  CB.on_pre_engine_tick(nil, dt)
  if HELPER then HELPER._lp = ctrl_p; HELPER._lq = ctrl_q; HELPER._parent = nil end
  if HELPER_L then HELPER_L._lp = {x=ctrl_p.x, y=ctrl_p.y-40, z=ctrl_p.z}; HELPER_L._lq = ctrl_q; HELPER_L._parent = nil end
  CB.on_post_calculate_stereo_view_offset(nil, 0, 100, nil, view, false)
  CB.on_post_calculate_stereo_view_offset(nil, 1, 100, nil, view, false)
end
local function wait(sec) local t0 = os.clock() while os.clock() - t0 < sec do end end

-- unarmed: body copy created, game mesh hidden in main pass, no IK
wm._vis = false
for i = 1, 5 do frame() end
check(PM ~= nil and PM._parent == mesh, "poseable created and attached to the mesh")
check(mesh._render == false, "game mesh hidden in main pass")
check(PM._hidden["mc_head_SH_01_jnt"], "head hidden on copy")
check(corruption._master == PM, "same-skeleton follower remastered to copy")
check(corruption.bUseBoundsFromMasterPoseComponent == true, "follower uses the copy bounds")
check(parasite.bUseBoundsFromMasterPoseComponent == nil, "foreign skeleton bounds untouched")
check(parasite._master == nil, "foreign skeleton not remastered")
check(PM._copies and PM._copies >= 5, "pose copied every frame")

-- head turn: body yaw follows (pawn yaw 0, head yaw 60)
view = VR(0, 60, 0)
frame()
local _, mq = mesh:world()
local _, _, _ = 0
local p, y, r = M.rot_from_quat(mq)
check(math.abs(y - 60) < 0.1, "body rotated to head yaw, got " .. y)
local cam_before = mesh:GetSocketLocation("camera_rot_x_SH_jnt")
CB.on_pre_engine_tick(nil, dt)  -- restore
local _, mq2 = mesh:world()
local _, y2 = M.rot_from_quat(mq2)
check(math.abs(y2) < 0.1, "body restored to game yaw at next tick")
-- pivot: camera position unchanged by body yaw
view = VR(0, 60, 0)
if HELPER then HELPER._lp = ctrl_p end
CB.on_post_calculate_stereo_view_offset(nil, 1, 100, nil, view, false)
local cam_after = mesh:GetSocketLocation("camera_rot_x_SH_jnt")
check(math.abs(cam_after.X - cam_before.X) + math.abs(cam_after.Y - cam_before.Y) < 0.01, "camera stays at pivot")
view = VR(0, 0, 0)

-- draw weapon: IK should bring the wrist to the controller
wm._vis = true
for i = 1, 90 do frame() end
check(AIM == 2, "aim -> right controller")
check(wm._master == PM, "weapon follows copy via master pose")
local Wp = PM:GetBoneLocationByName("mc_wrist_SH_r_jnt", 0)
local Wr = PM:GetBoneRotationByName("mc_wrist_SH_r_jnt", 0)
-- expected target (anim offsets ~0 in static pose)
local exp = M.vadd(ctrl_p, M.qrot(ctrl_q, {x=-8, y=0, z=-3}))
local err = math.abs(Wp.X-exp.x)+math.abs(Wp.Y-exp.y)+math.abs(Wp.Z-exp.z)
check(err < 0.5, "wrist at controller target, err=" .. err)
-- rotation: hand forward (wrist -> middle knuckle) along controller forward, thumb side up
local Mp = PM:GetBoneLocationByName("mc_middle_SH_r_01_jnt", 0)
local fwd = M.qrot(ctrl_q, {x=1,y=0,z=0})
local hd = {x=Mp.X-Wp.X, y=Mp.Y-Wp.Y, z=Mp.Z-Wp.Z}
local hl = M.vlen(hd)
local dot = (hd.x*fwd.x + hd.y*fwd.y + hd.z*fwd.z) / hl
check(dot > 0.999, "hand forward along controller, dot=" .. dot)
-- bone lengths preserved
local S_ = PM:GetBoneLocationByName("mc_shoulder_SH_r_jnt", 0)
local E_ = PM:GetBoneLocationByName("mc_elbow_SH_r_jnt", 0)
local up = M.vlen(M.vsub({x=E_.X,y=E_.Y,z=E_.Z}, {x=S_.X,y=S_.Y,z=S_.Z}))
check(math.abs(up - math.sqrt(20*20+5*5+20*20)) < 0.01, "upper arm length preserved")
-- weapon bone follows wrist (master pose)
local wl = wm:GetSocketLocation("mc_wrist_SH_r_jnt")
check(math.abs(wl.X - Wp.X) < 0.01, "weapon wrist == copy wrist")

-- animation independence: roll the animated upper arm around its own axis -> IK result must not change
local function arm_rots()
  local a = PM:GetBoneRotationByName("mc_shoulder_SH_r_jnt", 0)
  local b = PM:GetBoneRotationByName("mc_elbow_SH_r_jnt", 0)
  return M.quat_from_rot(a.Pitch, a.Yaw, a.Roll), M.quat_from_rot(b.Pitch, b.Yaw, b.Roll)
end
local s1, e1 = arm_rots()
local axis = {x=20, y=5, z=-20}
local l = math.sqrt(axis.x^2 + axis.y^2 + axis.z^2)
local h = math.rad(40) / 2
local roll = {x = axis.x/l*math.sin(h), y = axis.y/l*math.sin(h), z = axis.z/l*math.sin(h), w = math.cos(h)}
local si = 0
for i, b in ipairs(SKEL) do if b[1] == "mc_shoulder_SH_r_jnt" then si = i end end
local saved = mesh._pose[si].q
mesh._pose[si] = { p = mesh._pose[si].p, q = M.qmul(saved, roll) }
frame()
local s2, e2 = arm_rots()
check(M.qangle_deg(s1, s2) < 0.5 and M.qangle_deg(e1, e2) < 0.5, string.format("arm independent of animated roll (%.2f, %.2f deg)", M.qangle_deg(s1, s2), M.qangle_deg(e1, e2)))
mesh._pose[si] = { p = mesh._pose[si].p, q = saved }
frame()

-- moving controller: target out of reach gets clamped, no NaN
ctrl_p = {x=1300, y=2015, z=150}
frame(); wait(0.01); frame()
local W2 = PM:GetBoneLocationByName("mc_wrist_SH_r_jnt", 0)
check(W2.X == W2.X and W2.X > 1040, "far target: arm extended, no NaN")

-- interaction (console): the native animation owns the body and the arms
local function xinput(rx)
  local st = { Gamepad = { sThumbRX = rx, sThumbRY = 0, sThumbLX = 0, sThumbLY = 0, wButtons = 0, bLeftTrigger = 0, bRightTrigger = 0 } }
  CB.on_xinput_get_state(0, 0, st)
  return st
end
local function mesh_yaw() local _, q = mesh:world() local _, y = M.rot_from_quat(q) return y end
-- game camera yaw (Scorn's own) follows the synced pawn yaw outside interactions
pawn.CameraYaw, pawn.StationaryCameraYaw = -78, -78
pc._rot = {Pitch=0, Yaw=25, Roll=0}
frame()
check(pawn.CameraYaw == 25 and pawn.StationaryCameraYaw == 25, "unlocked: game camera yaw on the view yaw, got " .. pawn.CameraYaw)
pawn.bOverrideYaw = true; pawn.CameraYaw = -5
frame()
check(pawn.CameraYaw == -5, "game override: camera yaw left alone")
pawn.bOverrideYaw = nil; pawn.CameraYaw, pawn.StationaryCameraYaw = nil, nil
pc._rot = {Pitch=0, Yaw=0, Roll=0}
frame()
pawn.CharacterState = 6 -- UsingConsole
pawn._rot = {Pitch=0, Yaw=10, Roll=0}; capsule._lq = M.quat_from_rot(0, 10, 0) -- game turned the pawn to the console
pc._rot = {Pitch=0, Yaw=0, Roll=0}
view = VR(0, 60, 0)
for i = 1, 90 do frame() end
check(math.abs(pawn._rot.Yaw - 10) < 0.01, "locked: pawn yaw left to the game, got " .. pawn._rot.Yaw)
check(MODS.VR_RoomscaleMovement == "false", "locked: roomscale movement paused")
check(FILES["scorn_vr_roomscale.json"].paused == true, "locked: roomscale marker written")
check(math.abs(mesh_yaw() - 10) < 0.1, "locked: body keeps the game yaw, got " .. mesh_yaw())
local W4 = PM:GetBoneLocationByName("mc_wrist_SH_r_jnt", 0)
local N4 = mesh:GetSocketLocation("mc_wrist_SH_r_jnt")
check(math.abs(W4.X - N4.X) + math.abs(W4.Y - N4.Y) + math.abs(W4.Z - N4.Z) < 0.01, "locked: no IK, copy wrist == native wrist")
-- head yaw at the console: the game turns the camera bone around camera_SH_jnt (CameraYaw);
-- the eyes must stay on the orbit point for the body's forward direction
local ci = 0
for i, b in ipairs(SKEL) do if b[1] == "camera_translate_rotate_y_z_SH_jnt" then ci = i end end
mesh._pose[ci] = { p = mesh._pose[ci].p, q = M.quat_from_rot(0, 50, 0) }
pawn.CameraYaw = 60 -- pawn yaw 10 + 50
pawn.StationaryCameraYaw = 33
frame()
local pos = {x=0, y=0, z=0}
CB.on_pre_engine_tick(nil, dt)
CB.on_post_calculate_stereo_view_offset(nil, 1, 100, pos, view, false)
local pos2 = {x=0, y=0, z=0}
CB.on_post_calculate_stereo_view_offset(nil, 2, 100, pos2, view, false)
local cb = mesh:GetSocketLocation("camera_rot_x_SH_jnt")
local c0 = mesh:GetSocketLocation("camera_SH_jnt")
local fwd10 = M.qrot(M.quat_from_rot(0, 10, 0), {x=5, y=0, z=0})
local ex, ey = c0.X + fwd10.x - cb.X, c0.Y + fwd10.y - cb.Y
check(math.abs(pos.x - ex) + math.abs(pos.y - ey) + math.abs(pos.z) < 0.01,
  string.format("locked: eyes back on the neutral orbit point (%.2f,%.2f) vs (%.2f,%.2f)", pos.x, pos.y, ex, ey))
check(math.abs(pos2.x - pos.x) + math.abs(pos2.y - pos.y) < 1e-6, "locked: same eye shift for both eyes")
check(pawn.CameraYaw == 60 and pawn.StationaryCameraYaw == 33, "locked: game camera left to the game")
mesh._pose[ci] = { p = mesh._pose[ci].p, q = {x=0,y=0,z=0,w=1} }
pawn.CameraYaw, pawn.StationaryCameraYaw = nil, nil
local st = xinput(32767)
check(st.Gamepad.sThumbRX == 0, "locked: turn stick still swallowed")
frame(); xinput(0); frame()
check(math.abs(pc._rot.Yaw) < 0.01, "locked: no snap turn, control yaw " .. pc._rot.Yaw)
-- release: pawn turns back smoothly, no queued snap, body follows the head again
pawn.CharacterState = 0
frame()
check(pawn._rot.Yaw > 0.5 and pawn._rot.Yaw < 10, "unlock: pawn yaw resyncs smoothly, got " .. pawn._rot.Yaw)
for i = 1, 60 do frame() end
check(math.abs(pawn._rot.Yaw) < 0.01, "unlock: pawn yaw back on control yaw, got " .. pawn._rot.Yaw)
check(math.abs(pc._rot.Yaw) < 0.01, "unlock: no queued snap turn")
check(MODS.VR_RoomscaleMovement == "true", "unlock: roomscale movement restored")
check(FILES["scorn_vr_roomscale.json"].paused == false, "unlock: roomscale marker cleared")
check(math.abs(mesh_yaw() - 60) < 0.1, "unlock: body follows the head again, got " .. mesh_yaw())
-- debug override off: same state does not lock
pawn.CharacterState = 6
DEBUG_OVERRIDE = { force_lock = false }
for i = 1, 90 do frame() end
check(math.abs(mesh_yaw() - 60) < 0.1, "force_lock=false: body follows the head")
DEBUG_OVERRIDE = nil
pawn.CharacterState = nil
for i = 1, 90 do frame() end
FILES["scorn_vr_status.json"] = nil -- written while the debug override was set
view = VR(0, 0, 0)
for i = 1, 5 do frame() end

-- holster: alpha goes back to 0
wm._vis = false
for i = 1, 90 do frame() end
local W3 = PM:GetBoneLocationByName("mc_wrist_SH_r_jnt", 0)
local N3 = mesh:GetSocketLocation("mc_wrist_SH_r_jnt")
check(math.abs(W3.X - N3.X) < 0.01, "holstered: copy wrist == native wrist")

-- status file + log file
check(FILES["scorn_vr_status.json"] == nil, "no status file without debug mode")
check(type(FILES["scorn_vr_log.txt"]) == "string", "log written")

-- script reset in the middle of an interaction restores roomscale
pawn.CharacterState = 6
for i = 1, 5 do frame() end
check(MODS.VR_RoomscaleMovement == "false", "locked again: roomscale paused")
CB.on_draw_ui()
CB.on_script_reset()
check(MODS.VR_RoomscaleMovement == "true", "reset: roomscale restored")
pawn.CharacterState = nil
check(mesh._render == true, "reset: game mesh visible again")
check(corruption._master == mesh, "reset: follower back to game mesh")
check(corruption.bUseBoundsFromMasterPoseComponent == false, "reset: follower bounds flag restored")
for _, l in ipairs(LOG) do check(not l:find("ERROR"), "error logged: " .. l) end
return "v2 scenario OK\n" .. table.concat(LOG, "\n")
