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

-- holster: alpha goes back to 0
wm._vis = false
for i = 1, 90 do frame() end
local W3 = PM:GetBoneLocationByName("mc_wrist_SH_r_jnt", 0)
local N3 = mesh:GetSocketLocation("mc_wrist_SH_r_jnt")
check(math.abs(W3.X - N3.X) < 0.01, "holstered: copy wrist == native wrist")

-- status file + log file
check(FILES["scorn_vr_status.json"] == nil, "no status file without debug mode")
check(type(FILES["scorn_vr_log.txt"]) == "string", "log written")

CB.on_draw_ui()
CB.on_script_reset()
check(mesh._render == true, "reset: game mesh visible again")
check(corruption._master == mesh, "reset: follower back to game mesh")
for _, l in ipairs(LOG) do check(not l:find("ERROR"), "error logged: " .. l) end
return "v2 scenario OK\n" .. table.concat(LOG, "\n")
