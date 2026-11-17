local m = S.mesh
local function P(b) return V(m:GetSocketLocation(b)) end
local function d(a, b) return string.format("%.1f", vlen(vsub(P(a), P(b)))) end
local out = {}
out.pr_mr = d("p_wrist_SH_r_jnt", "mc_wrist_SH_r_jnt")
out.pr_ml = d("p_wrist_SH_r_jnt", "mc_wrist_SH_l_jnt")
out.pl_ml = d("p_wrist_SH_l_jnt", "mc_wrist_SH_l_jnt")
out.pl_mr = d("p_wrist_SH_l_jnt", "mc_wrist_SH_r_jnt")
out.pr_sh = d("p_shoulder_SH_r_jnt", "mc_spine_SH_05_jnt")
out.pl_sh = d("p_shoulder_SH_l_jnt", "mc_spine_SH_05_jnt")
out.pr_len1 = d("p_shoulder_SH_r_jnt", "p_elbow_SH_r_jnt")
out.pr_len2 = d("p_elbow_SH_r_jnt", "p_wrist_SH_r_jnt")
out.pl_len1 = d("p_shoulder_SH_l_jnt", "p_elbow_SH_l_jnt")
out.pl_len2 = d("p_elbow_SH_l_jnt", "p_wrist_SH_l_jnt")
-- which parasite chains are visible / where relative to the pelvis
local function rel(b)
  local mp, mq = get_world_tf(m)
  local v = qrot(qinv(mq), vsub(P(b), mp))
  return string.format("%.0f,%.0f,%.0f", v.x, v.y, v.z)
end
out.p_sh_r = rel("p_shoulder_SH_r_jnt"); out.p_wr_r = rel("p_wrist_SH_r_jnt")
out.p_sh_l = rel("p_shoulder_SH_l_jnt"); out.p_wr_l = rel("p_wrist_SH_l_jnt")
out.mc_wr_r = rel("mc_wrist_SH_r_jnt"); out.mc_wr_l = rel("mc_wrist_SH_l_jnt")
return out
