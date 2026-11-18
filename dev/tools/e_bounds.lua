-- render bounds of the body copy, the game mesh and the followers vs where their bones really are
local out = {}
KSL = api:find_uobject("Class /Script/Engine.KismetSystemLibrary"):get_class_default_object()
local function r1(x) return math.floor(x * 10 + 0.5) / 10 end
local function b(c)
  local d = { name = short_name(c), class = class_name(c) }
  local ok, err = pcall(function()
    local o, e, r = {}, {}, {}
    KSL:GetComponentBounds(c, o, e, r)
    local O, E = o.result, e.result
    d.b_origin = { r1(O.X), r1(O.Y), r1(O.Z) }
    d.b_extent = { r1(E.X), r1(E.Y), r1(E.Z) }
    d.b_radius = r.result
  end)
  if not ok then d.b_err = tostring(err) end
  pcall(function() d.scale = c.BoundsScale end)
  pcall(function() d.use_master_bounds = c.bUseBoundsFromMasterPoseComponent end)
  pcall(function() d.fixed_skel = c.bComponentUseFixedSkelBounds end)
  pcall(function() local m = c.MasterPoseComponent; d.master = m and short_name(m) or "" end)
  pcall(function() local l = V(c:K2_GetComponentLocation()) d.loc = { r1(l.x), r1(l.y), r1(l.z) } end)
  pcall(function() d.visible = c:IsVisible() end)
  pcall(function() local sm = c.SkeletalMesh; d.mesh = sm and short_name(sm) or "" end)
  pcall(function() local p = c:GetAttachParent(); d.parent = p and short_name(p) or "" end)
  pcall(function() d.socket = fname_str(c:GetAttachSocketName()) end)
  return d
end
out.copy = S.pm and b(S.pm) or "none"
out.game = b(S.mesh)
out.parts = {}
for _, p in ipairs(S.parts) do out.parts[#out.parts + 1] = b(p.comp) end
if exists(S.weapon_mesh) then out.weapon = b(S.weapon_mesh) end
-- where are the hands of the copy
pcall(function()
  local w = pbone_get(S.pm, BONE.r_wrist)
  out.copy_r_wrist = { r1(w.x), r1(w.y), r1(w.z) }
  local h = pbone_get(S.pm, BONE.head)
  out.copy_head = { r1(h.x), r1(h.y), r1(h.z) }
end)
out.state = S.char_state_name
return out
