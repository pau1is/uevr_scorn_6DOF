-- one sample: control/camera yaw + native wrists, spine and camera in pawn space (game mesh, no copy)
local p = S.pawn
local pc = api:get_player_controller(0)
local function r1(x) return math.floor(x * 10 + 0.5) / 10 end
local function r3(v) return { r1(v.x), r1(v.y), r1(v.z) } end
local pr = p:K2_GetActorRotation()
local pl = V(p:K2_GetActorLocation())
local qp = qinv(quat_from_rot(0, pr.Yaw, 0))
local function loc(b) return r3(qrot(qp, vsub(V(S.mesh:GetSocketLocation(b)), pl))) end
local cr = pc:GetControlRotation()
local o = {
  st = S.char_state_name, hmd = vr.is_hmd_active(),
  ctrl_yaw = r1(cr.Yaw), ctrl_pitch = r1(cr.Pitch), pawn_yaw = r1(pr.Yaw),
  cam_yaw = r1(p.CameraYaw), cam_pitch = r1(p.CameraPitch), stat_yaw = r1(p.StationaryCameraYaw),
  wr = loc("mc_wrist_SH_r_jnt"), wl = loc("mc_wrist_SH_l_jnt"),
  sp6 = loc("mc_spine_SH_06_jnt"), camb = loc("camera_rot_x_SH_jnt"),
  pawn_loc = r3(pl),
  cam0 = loc("camera_SH_jnt"), cam1 = loc("camera_translate_rotate_y_z_SH_jnt"), head = loc("mc_head_SH_01_jnt"), neck = loc("mc_neck_SH_01_jnt"),
}
pcall(function() o.camc = r3(qrot(qp, vsub(V(S.camera:K2_GetComponentLocation()), pl))) end)
pcall(function() o.camc_yaw = r1(S.camera:K2_GetComponentRotation().Yaw) end)
return o
