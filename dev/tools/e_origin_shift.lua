-- simulate a head movement: shift UEVR's standing origin by DX metres along the tracking X axis
-- (roomscale then moves the pawn to follow the "head"). Run again with -DX to undo.
-- vr.get_standing_origin fills an out parameter (UEVR_Vector3f).
local DX = tonumber(DBG.dx or 0.10)
local o = UEVR_Vector3f.new()
vr.get_standing_origin(o)
local before = { o.x, o.y, o.z }
o.x = o.x + DX
vr.set_standing_origin(o)
local p = V(S.pawn:K2_GetActorLocation())
return { before = before, pawn = { p.x, p.y, p.z }, dx = DX }
