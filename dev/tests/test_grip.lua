-- hand_grip_q maps local forward -> X, local side -> Z
local function chk(f, s)
  local q = hand_grip_q(f, s)
  local a = qrot(q, vnorm(f))
  local sn = vnorm(vsub(s, vscale(vnorm(f), vdot(s, vnorm(f)))))
  local b = qrot(q, sn)
  assert(math.abs(a.x - 1) < 1e-6 and math.abs(b.z - 1) < 1e-6, string.format("grip %f %f", a.x, b.z))
end
chk({x=-9.21,y=-0.58,z=0.9}, {x=-5.55,y=-0.7,z=5.65})
math.randomseed(3)
for i=1,500 do
  local f = {x=math.random()-0.5,y=math.random()-0.5,z=math.random()-0.5}
  local s = {x=math.random()-0.5,y=math.random()-0.5,z=math.random()-0.5}
  chk(f, s)
end
return "grip OK"
