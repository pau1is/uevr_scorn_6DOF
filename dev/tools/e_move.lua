-- movement direction vs the game's yaw values (sample it while walking with the left stick)
local p = S.pawn
local pc = api:get_player_controller(0)
local v = V(p:GetVelocity())
local spd = math.sqrt(v.x * v.x + v.y * v.y)
local function r1(x) return math.floor(x * 10 + 0.5) / 10 end
local cr = pc:GetControlRotation()
local o = {
  speed = r1(spd),
  move_yaw = spd > 1 and r1(math.atan(v.y, v.x) * 180 / math.pi) or nil,
  ctrl = r1(cr.Yaw), pawn = r1(p:K2_GetActorRotation().Yaw), cam = r1(p.CameraYaw), stat = r1(p.StationaryCameraYaw),
  head = M.head_yaw and r1(M.head_yaw), mf = p.MovementForward, ms = p.MovementSide, st = S.char_state_name,
}
pcall(function() o.camc = r1(S.camera:K2_GetComponentRotation().Yaw) end)
pcall(function() local r = p:GetCameraReferenceRotation() o.cam_ref = r1(r.Yaw) end)
return o
