-- run: python -c "from lupa import lua54; L=lua54.LuaRuntime(); print(L.execute(open('test_uemath.lua').read()))"  (from this folder)
local M = dofile("uemath.lua")
local function close(a, b) return math.abs(a - b) < 1e-3 end
math.randomseed(7)
for i = 1, 2000 do
  local q = M.quat_from_rot(math.random() * 170 - 85, math.random() * 360 - 180, math.random() * 360 - 180)
  local q2 = M.quat_from_rot(M.rot_from_quat(q))
  assert(M.qangle_deg(q, q2) < 0.01, "rotator roundtrip")
end
assert(close(M.qrot(M.quat_from_rot(0, 90, 0), {x=1,y=0,z=0}).y, 1), "yaw")
assert(close(M.qrot(M.quat_from_rot(90, 0, 0), {x=1,y=0,z=0}).z, 1), "pitch")
assert(close(M.qrot(M.quat_from_rot(0, 0, 90), {x=0,y=1,z=0}).z, -1), "roll (UE: Y -> -Z)")
-- IK reaches reachable targets and keeps bone lengths
for i = 1, 300 do
  local S = {x=0,y=0,z=0}; local E = {x=28,y=0,z=-5}; local W = {x=55,y=0,z=-2}
  local T = {x=math.random()*40-20+20, y=math.random()*40-20, z=math.random()*40-20}
  local E2, W2 = M.solve_two_bone(S, E, W, T, {x=0,y=0,z=-1})
  assert(math.abs(M.vlen(M.vsub(E2,S)) - M.vlen(M.vsub(E,S))) < 1e-6, "upper length")
  assert(math.abs(M.vlen(M.vsub(W2,E2)) - M.vlen(M.vsub(W,E))) < 1e-6, "lower length")
end
-- frame_q maps local axes onto world axes
for i = 1, 300 do
  local a = {x=math.random()-.5,y=math.random()-.5,z=math.random()-.5}
  local n = {x=math.random()-.5,y=math.random()-.5,z=math.random()-.5}
  local aw = {x=math.random()-.5,y=math.random()-.5,z=math.random()-.5}
  local nw = {x=math.random()-.5,y=math.random()-.5,z=math.random()-.5}
  local q = M.frame_q(a, n, aw, nw)
  assert(M.vdot(M.qrot(q, M.vnorm(a)), M.vnorm(aw)) > 0.9999, "frame axis")
end
return "uemath OK"
