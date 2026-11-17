-- interaction lock diagnostics: pawn/control yaw, camera vars, native hand/spine positions in pawn space
local out = {}
local p = S.pawn
local pc = api:get_player_controller(0)
local function r3(v) return { math.floor(v.x * 10 + 0.5) / 10, math.floor(v.y * 10 + 0.5) / 10, math.floor(v.z * 10 + 0.5) / 10 } end
out.state = S.char_state_name
out.locked = S.locked
out.lock_alpha = S.lock_alpha
out.aim = S.last_aim
local pr = p:K2_GetActorRotation()
local cr = pc:GetControlRotation()
out.pawn_yaw = pr.Yaw
out.ctrl = { cr.Pitch, cr.Yaw }
local pl = V(p:K2_GetActorLocation())
out.pawn_loc = r3(pl)
for _, k in ipairs({ "CameraYaw", "CameraPitch", "DeltaYaw", "DeltaPitch", "YawDiff", "TurnDelta", "YawDiffLimit",
    "YawDiffLimitOnConsole", "StationaryCameraYaw", "bOverrideYaw", "bOverridePitch", "PitchLimit", "bUseControllerRotationYaw" }) do
  pcall(function() out["p_" .. k] = p[k] end)
end
pcall(function()
  local ai = S.mesh:GetAnimInstance()
  out.anim_class = class_name(ai)
  for _, k in ipairs({ "CameraYaw", "CameraPitch", "StationaryCameraYaw", "ConsoleTypeInUse", "bIsUpperBodyIdle" }) do
    pcall(function() out["a_" .. k] = ai[k] end)
  end
end)
-- native bones in pawn space (game mesh, not the copy)
local qp = qinv(quat_from_rot(0, pr.Yaw, 0))
local bones = { "mc_root_SH_jnt", "mc_spine_SH_01_jnt", "mc_spine_SH_06_jnt", "mc_wrist_SH_r_jnt", "mc_wrist_SH_l_jnt", "camera_rot_x_SH_jnt" }
out.bones = {}
for _, b in ipairs(bones) do
  pcall(function() out.bones[b] = r3(qrot(qp, vsub(V(S.mesh:GetSocketLocation(b)), pl))) end)
end
local _, mq = get_world_tf(S.mesh)
local _, my = rot_from_quat(mq)
out.mesh_yaw = my
pcall(function() out.mesh_rel = { S.mesh.RelativeRotation.Yaw, S.mesh.RelativeLocation.X, S.mesh.RelativeLocation.Y } end)
out.head_yaw = M.head_yaw
out.body_delta = M.body_delta
return out
