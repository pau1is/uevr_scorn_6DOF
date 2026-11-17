-- controller diagnostics: indices, poses, a few action states
local o = {}
local function pose(i)
  local p, r = UEVR_Vector3f.new(), UEVR_Quaternionf.new()
  vr.get_pose(i, p, r)
  return { math.floor(p.x * 1000) / 1000, math.floor(p.y * 1000) / 1000, math.floor(p.z * 1000) / 1000 }
end
pcall(function() o.li = vr.get_left_controller_index() end)
pcall(function() o.ri = vr.get_right_controller_index() end)
pcall(function() o.hmd = pose(0) end)
pcall(function() o.lp = pose(o.li) end)
pcall(function() o.rp = pose(o.ri) end)
o.using = vr.is_using_controllers()
pcall(function() o.helper_r = { V(S.helper:K2_GetComponentLocation()).x, V(S.helper:K2_GetComponentLocation()).y } end)
local acts = {}
for _, n in ipairs({ "Trigger", "Grip", "AButtonRight", "BButtonRight", "AButtonLeft", "Joystick", "JoystickClick" }) do
  pcall(function()
    local h = vr.get_action_handle("/actions/default/in/" .. n)
    acts[n] = { r = vr.is_action_active(h, vr.get_right_joystick_source()), l = vr.is_action_active(h, vr.get_left_joystick_source()) }
  end)
end
o.acts = acts
pcall(function()
  local a = UEVR_Vector2f.new()
  vr.get_joystick_axis(vr.get_left_joystick_source(), a)
  o.lstick = { a.x, a.y }
end)
return o
