-- Mock of the UEVR Lua API + a pawn with a hierarchical skeleton (bone names from Scorn; adapt SKEL for your game).
-- Requires uemath functions as globals (see tools/run_smoke.py).
M = { quat_from_rot = quat_from_rot, rot_from_quat = rot_from_quat, qmul = qmul, qinv = qinv, qrot = qrot,
      vadd = vadd, vsub = vsub, vlen = vlen, qangle_deg = qangle_deg, qnorm = qnorm }
LOG = {}
print = function(...) local t = {} for _, v in ipairs({...}) do t[#t+1] = tostring(v) end LOG[#LOG+1] = table.concat(t, " ") end
local next_addr = 1000
local function fname(s) return { to_string = function() return s end } end
local function V(x,y,z) return {X=x,Y=y,Z=z,x=x,y=y,z=z} end
local function R(p,y,r) return {Pitch=p,Yaw=y,Roll=r} end
local function rot_of(q) local p,y,r = rot_from_quat(q) return R(p,y,r) end
local IDQ = {x=0,y=0,z=0,w=1}

-- skeleton: name, parent, local pos (cm), local rot
SKEL = {
  {"mc_root_SH_jnt", nil, {x=0,y=0,z=0}},
  {"camera_SH_jnt", "mc_root_SH_jnt", {x=0,y=0,z=165}},
  {"camera_translate_rotate_y_z_SH_jnt", "camera_SH_jnt", {x=0,y=0,z=0}},
  {"camera_rot_x_SH_jnt", "camera_translate_rotate_y_z_SH_jnt", {x=5,y=0,z=0}},
  {"mc_spine_SH_01_jnt", "mc_root_SH_jnt", {x=0,y=0,z=100}},
  {"mc_spine_SH_06_jnt", "mc_spine_SH_01_jnt", {x=0,y=0,z=40}},
  {"mc_neck_SH_01_jnt", "mc_spine_SH_06_jnt", {x=0,y=0,z=15}},
  {"mc_head_SH_01_jnt", "mc_neck_SH_01_jnt", {x=0,y=0,z=10}},
  {"mc_clavicle_SH_r_jnt", "mc_spine_SH_06_jnt", {x=0,y=8,z=10}},
  {"mc_shoulder_SH_r_jnt", "mc_clavicle_SH_r_jnt", {x=0,y=12,z=0}},
  {"mc_elbow_SH_r_jnt", "mc_shoulder_SH_r_jnt", {x=20,y=5,z=-20}},
  {"mc_forearm_twist_01_SH_r_jnt", "mc_elbow_SH_r_jnt", {x=12,y=0,z=5}},
  {"mc_wrist_SH_r_jnt", "mc_elbow_SH_r_jnt", {x=25,y=0,z=10}},
  {"handgun_root_SH_jnt", "mc_wrist_SH_r_jnt", {x=5,y=0,z=0}},
  {"mc_middle_SH_r_01_jnt", "mc_wrist_SH_r_jnt", {x=-9,y=-0.5,z=1}},
  {"mc_index_SH_r_01_jnt", "mc_wrist_SH_r_jnt", {x=-9,y=-0.5,z=3}},
  {"mc_pinky_SH_r_01_jnt", "mc_wrist_SH_r_jnt", {x=-3.5,y=0,z=-2.5}},
  {"mc_clavicle_SH_l_jnt", "mc_spine_SH_06_jnt", {x=0,y=-8,z=10}},
  {"mc_shoulder_SH_l_jnt", "mc_clavicle_SH_l_jnt", {x=0,y=-12,z=0}},
  {"mc_elbow_SH_l_jnt", "mc_shoulder_SH_l_jnt", {x=20,y=-5,z=-20}},
  {"mc_wrist_SH_l_jnt", "mc_elbow_SH_l_jnt", {x=25,y=10,z=10}},
  {"mc_middle_SH_l_01_jnt", "mc_wrist_SH_l_jnt", {x=9,y=0.5,z=1}},
  {"mc_index_SH_l_01_jnt", "mc_wrist_SH_l_jnt", {x=9,y=0.5,z=3}},
  {"mc_pinky_SH_l_01_jnt", "mc_wrist_SH_l_jnt", {x=3.5,y=0,z=-2.5}},
  {"mc_hip_SH_l_jnt", "mc_root_SH_jnt", {x=0,y=-10,z=95}},
}
local IDX = {}
for i, b in ipairs(SKEL) do IDX[b[1]] = i end

local function new_pose()
  local pose = {}
  for i, b in ipairs(SKEL) do pose[i] = { p = {x=b[3].x,y=b[3].y,z=b[3].z}, q = (b[1] == "mc_wrist_SH_r_jnt") and quat_from_rot(5,10,-80) or IDQ } end
  return pose
end

-- component-space transform of bone i
local function cs(pose, i)
  local b = SKEL[i]
  local lp, lq = pose[i].p, pose[i].q
  if not b[2] then return lp, lq end
  local pp, pq = cs(pose, IDX[b[2]])
  return vadd(pp, qrot(pq, lp)), qmul(pq, lq)
end

function make_comp(name, cls)
  next_addr = next_addr + 8
  local c = { _name=name, _cls=cls or "SceneComponent", _addr=next_addr, _lp={x=0,y=0,z=0}, _lq=IDQ, _vis=true, _render=true }
  function c:get_address() return self._addr end
  function c:get_fname() return fname(self._name) end
  function c:get_full_name() return self._cls.." "..self._name end
  function c:get_class() local s=self return { get_fname = function() return fname(s._cls) end } end
  function c:get_outer() return self._outer end
  function c:world()
    if self._parent then
      local pp, pq
      if self._socket and self._parent._pose then
        local bp, bq = cs(self._parent._pose, IDX[self._socket])
        local wp, wq = self._parent:world()
        pp, pq = vadd(wp, qrot(wq, bp)), qmul(wq, bq)
      else
        pp, pq = self._parent:world()
      end
      return vadd(pp, qrot(pq, self._lp)), qmul(pq, self._lq)
    end
    return self._lp, self._lq
  end
  function c:K2_GetComponentLocation() local p = self:world() return V(p.x,p.y,p.z) end
  function c:K2_GetComponentRotation() local _, q = self:world() return rot_of(q) end
  function c:K2_SetWorldLocationAndRotation(l, r, sweep, hit, tele)
    assert(type(hit) == "table" and tele == true)
    local wp, wq = {x=l.X,y=l.Y,z=l.Z}, quat_from_rot(r.Pitch, r.Yaw, r.Roll)
    if self._parent then
      local pp, pq = self._parent:world()
      local ipq = qinv(pq)
      self._lp, self._lq = qrot(ipq, vsub(wp, pp)), qmul(ipq, wq)
    else
      self._lp, self._lq = wp, wq
    end
    self._moves = (self._moves or 0) + 1
  end
  function c:K2_SetRelativeLocationAndRotation(l, r) self._lp = {x=l.X,y=l.Y,z=l.Z}; self._lq = quat_from_rot(r.Pitch,r.Yaw,r.Roll); self._restores=(self._restores or 0)+1 end
  function c:K2_AttachToComponent(parent, sock, a, b, cc, weld) self._parent = parent; self._lp = {x=0,y=0,z=0}; self._lq = IDQ end
  function c:GetAttachParent() return self._parent end
  function c:GetAttachSocketName() return fname(self._socket or "None") end
  function c:IsVisible() return self._vis end
  function c:SetVisibility(v) self._vis = v end
  function c:SetRenderInMainPass(v) self._render = v end
  function c:SetCastShadow(v) self._shadow = v end
  function c:SetCastHiddenShadow(v) end
  function c:K2_DestroyComponent() self._destroyed = true end
  setmetatable(c, { __index = function(t,k)
    if k == "RelativeLocation" then return V(t._lp.x,t._lp.y,t._lp.z) end
    if k == "RelativeRotation" then return rot_of(t._lq) end
    return nil end })
  return c
end

local function add_skeleton(c, with_pose)
  c._pose = with_pose and new_pose() or nil
  c._hidden = {}
  function c:pose() return self._master and self._master._pose or self._pose end
  function c:GetNumBones() return #SKEL end
  function c:GetBoneName(i) return fname(SKEL[i+1][1]) end
  function c:GetBoneIndex(b) return (IDX[b] or 0) - 1 end
  function c:GetParentBone(b) local i = IDX[b] return fname(i and SKEL[i][2] or "None") end
  function c:HideBoneByName(b, op) self._hidden[b] = true end
  function c:UnHideBoneByName(b) self._hidden[b] = nil end
  function c:IsBoneHiddenByName(b) return self._hidden[b] == true end
  function c:bone_world(b)
    local bp, bq = cs(self:pose(), IDX[b])
    local wp, wq = self:world()
    return vadd(wp, qrot(wq, bp)), qmul(wq, bq)
  end
  function c:GetSocketLocation(b) local p = self:bone_world(b) return V(p.x,p.y,p.z) end
  function c:GetSocketRotation(b) local _, q = self:bone_world(b) return rot_of(q) end
  function c:SetMasterPoseComponent(m) self._master = m end
  function c:GetNumMaterials() return 2 end
  function c:GetMaterial(i) return "mat"..i end
  function c:SetMaterial(i, m) self._mats = self._mats or {}; self._mats[i] = m end
  function c:SetSkeletalMesh(m) self.SkeletalMesh = m end
end

-- game mesh (animated)
mesh = make_comp("CharacterMesh0", "SkeletalMeshComponent")
add_skeleton(mesh, true)
mesh.SkeletalMesh = { get_full_name = function() return "SkeletalMesh SK_MainCharacter" end }
capsule = make_comp("CollisionCylinder", "CapsuleComponent")
capsule._lp = {x=1000, y=2000, z=100}
mesh._parent = capsule
mesh._lp = {x=0,y=0,z=-96.7}

camera = make_comp("PlayerCamera", "CameraComponent")
camera._parent = mesh; camera._socket = "camera_rot_x_SH_jnt"

wm = make_comp("WeaponMesh", "SkeletalMeshComponent"); add_skeleton(wm, false); wm._parent = mesh; wm._master = mesh
weapon_actor = { bHidden = false, WeaponMesh = wm }
function weapon_actor:get_class() return { get_fname = function() return fname("BP_Handgun_C") end } end
function weapon_actor:get_address() return 77 end

corruption = make_comp("NODE_AddSkeletalMeshComponent-3_5", "SkeletalMeshComponent"); add_skeleton(corruption, false)
corruption._parent = mesh; corruption._master = mesh
parasite = make_comp("NODE_AddSkeletalMeshComponent-3", "SkeletalMeshComponent")
parasite._parent = mesh
function parasite:GetBoneIndex(b) return -1 end
function parasite:SetMasterPoseComponent(m) error("parasite must not be remastered") end

pawn = { Mesh = mesh, PlayerCamera = camera, WeaponController = { CurrentWeapon = weapon_actor }, bUseControllerRotationYaw = true, _rot = R(0,0,0) }
function pawn:get_address() return 5 end
function pawn:get_full_name() return "BP_MainCharacter_C PersistentLevel.BP_MainCharacter_C_0" end
function pawn:K2_GetActorRotation() return R(self._rot.Pitch, self._rot.Yaw, self._rot.Roll) end
function pawn:K2_SetActorRotation(r) self._rot = R(r.Pitch, r.Yaw, r.Roll); capsule._lq = quat_from_rot(0, r.Yaw, 0) end
for _, c in ipairs({mesh, corruption, parasite, camera}) do c._outer = pawn end
wm._outer = weapon_actor

pc = { _rot = R(0, 0, 0) }
function pc:GetControlRotation() return R(self._rot.Pitch, self._rot.Yaw, self._rot.Roll) end
function pc:SetControlRotation(r) self._rot = R(r.Pitch, r.Yaw, r.Roll) end

-- poseable mock
function make_poseable()
  local pm = make_comp("PoseableMeshComponent_0", "PoseableMeshComponent")
  add_skeleton(pm, true)
  function pm:CopyPoseFromSkeletalComponent(src)
    for i, b in ipairs(src._pose) do self._pose[i] = { p = b.p, q = b.q } end
    self._copies = (self._copies or 0) + 1
  end
  function pm:GetBoneLocationByName(b, space) assert(space == 0) local p = self:bone_world(b) return V(p.x,p.y,p.z) end
  function pm:GetBoneRotationByName(b, space) assert(space == 0) local _, q = self:bone_world(b) return rot_of(q) end
  function pm:SetBoneRotationByName(b, r, space)
    assert(space == 0)
    local i = IDX[b]
    local wq = quat_from_rot(r.Pitch, r.Yaw, r.Roll)
    local parent = SKEL[i][2]
    local pq
    if parent then _, pq = self:bone_world(parent) else _, pq = self:world() end
    self._pose[i] = { p = self._pose[i].p, q = qmul(qinv(pq), wq) }
  end
  function pm:SetBoneLocationByName() error("not used") end
  return pm
end

HELPER = nil
local skel_class = { get_objects_matching = function() local t = {mesh, wm, corruption, parasite} if PM then t[#t+1] = PM end return t end }
local scene_class = { get_objects_matching = function() return {mesh, wm, corruption, parasite, camera} end }
local gs_class = { get_class_default_object = function() return { IsGamePaused = function() return false end } end }
local pm_class = { _is_pm = true }
uevr = {
  api = {
    find_uobject = function(self, n)
      if n:find("PoseableMeshComponent") then return pm_class end
      if n:find("SkeletalMeshComponent") then return skel_class end
      if n:find("SceneComponent") then return scene_class end
      if n:find("GameplayStatics") then return gs_class end
    end,
    get_local_pawn = function() return pawn end,
    get_player_controller = function() return pc end,
    add_component_by_class = function(self, actor, cls)
      if cls == pm_class then PM = make_poseable(); PM._outer = pawn; PM._parent = capsule; return PM end
      local h = make_comp("Helper"); if HELPER == nil then HELPER = h else HELPER_L = h end; return h
    end,
  },
  params = { vr = { get_lowest_xinput_index = function() return 0 end, is_using_controllers = function() return true end,
                    set_aim_method = function(m) AIM = m end } },
  sdk = { callbacks = {} },
}
CB = {}
for _, n in ipairs({"on_pre_engine_tick","on_post_engine_tick","on_pre_calculate_stereo_view_offset","on_post_calculate_stereo_view_offset","on_xinput_get_state","on_draw_ui","on_script_reset"}) do
  uevr.sdk.callbacks[n] = function(f) CB[n] = f end
end
MC = {}
UEVR_UObjectHook = {
  activate = function() end,
  exists = function(o) return o ~= nil and not o._destroyed end,
  get_or_add_motion_controller_state = function(o) local s = { obj=o }
     function s:set_hand(h) self.hand=h end function s:set_permanent(p) self.perm=p end
     function s:set_location_offset(v) self.loc=v end function s:set_rotation_offset(q) self.rot=q end
     MC[o] = s return s end,
  remove_motion_controller_state = function(o) MC[o] = nil end,
}
UEVR_Vector3f = { new = function() return {x=0,y=0,z=0} end }
UEVR_Quaternionf = { new = function() return {x=0,y=0,z=0,w=1} end }
FILES = {}
json = { load_file = function(f) if f:find("debug") then return DEBUG_OVERRIDE end return CONFIG_OVERRIDE end,
         dump_file = function(f, t) FILES[f] = t return true end }
SRC = {}
fs = { write = function(f, d) FILES[f] = d end, read = function(f) return SRC[f] end }
imgui = setmetatable({ collapsing_header = function() return true end, tree_node = function() return true end,
  tree_pop = function() end, text = function() end, same_line = function() end, button = function() return false end },
  { __index = function(t,k) return function(label, v) return false, v end end })
