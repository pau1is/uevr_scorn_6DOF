-- weapon bones in the native pose, expressed in the game camera frame (x fwd, y right, z up)
local out = {}
local wa = S.weapon_actor
pcall(function() out.bullet_socket = fname_str(wa.BulletSocketNameInMCHand) end)
pcall(function() out.ammo_socket = fname_str(wa:GetAmmoSocketNameInMCHand()) end)
local cp, cq = get_world_tf(S.camera)
local ci = qinv(cq)
local mesh = S.mesh
local function rel(b)
  local ok, r = pcall(function()
    local p = V(mesh:GetSocketLocation(b))
    local rr = mesh:GetSocketRotation(b)
    local q = quat_from_rot(rr.Pitch, rr.Yaw, rr.Roll)
    local lp = qrot(ci, vsub(p, cp))
    local lq = qmul(ci, q)
    local fx = qrot(lq, {x=1,y=0,z=0})
    local fy = qrot(lq, {x=0,y=1,z=0})
    local fz = qrot(lq, {x=0,y=0,z=1})
    local function r1(v) return string.format("%.2f,%.2f,%.2f", v.x, v.y, v.z) end
    return { p = r1(lp), X = r1(fx), Y = r1(fy), Z = r1(fz) }
  end)
  return ok and r or tostring(r)
end
for _, b in ipairs({ "mc_wrist_SH_r_jnt", "mc_weapon_snap_SH_r_jnt", "handgun_root_SH_jnt", "handgun_hand_snap_SH_jnt",
                     "handgun_ball_SH_jnt", "handgun_bone_top_SH_01_jnt", "hg_bullet_root_SH_jnt",
                     "handgun_bullet_hole_a_SH_01_jnt", "handgun_meet_SH_jnt", out.bullet_socket or "None" }) do
  out[b] = rel(b)
end
return out
