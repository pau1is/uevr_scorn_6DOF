local out = {}
local pc = api:get_player_controller(0)
local cm = pc.PlayerCameraManager
local cr = cm:GetCameraRotation()
local cl = V(cm:GetCameraLocation())
local ctl = pc:GetControlRotation()
local comp_p, comp_q = get_world_tf(S.camera)
local cp_, cy_, cr_ = rot_from_quat(comp_q)
local f = function(v) return string.format("%.2f,%.2f,%.2f", v.x, v.y, v.z) end
out.cm_rot = string.format("P%.1f Y%.1f R%.1f", cr.Pitch, cr.Yaw, cr.Roll)
out.control_rot = string.format("P%.1f Y%.1f R%.1f", ctl.Pitch, ctl.Yaw, ctl.Roll)
out.cam_comp_rot = string.format("P%.1f Y%.1f R%.1f", cp_, cy_, cr_)
out.pawn_yaw = S.pawn:K2_GetActorRotation().Yaw
out.cm_loc_minus_comp = f(vsub(cl, comp_p))
local q = quat_from_rot(cr.Pitch, cr.Yaw, cr.Roll)
local qi = qinv(q)
local function rel(b)
  local p = V(S.mesh:GetSocketLocation(b))
  local rr = S.mesh:GetSocketRotation(b)
  local lq = qmul(qi, quat_from_rot(rr.Pitch, rr.Yaw, rr.Roll))
  return { p = f(qrot(qi, vsub(p, cl))), X = f(qrot(lq, {x=1,y=0,z=0})), Y = f(qrot(lq, {x=0,y=1,z=0})), Z = f(qrot(lq, {x=0,y=0,z=1})) }
end
out.wrist = rel("mc_wrist_SH_r_jnt")
out.handgun_root = rel("handgun_root_SH_jnt")
out.hand_snap = rel("handgun_hand_snap_SH_jnt")
out.bone_top = rel("handgun_bone_top_SH_01_jnt")
out.ball = rel("handgun_ball_SH_jnt")
out.cam_bone = rel("camera_rot_x_SH_jnt")
return out
