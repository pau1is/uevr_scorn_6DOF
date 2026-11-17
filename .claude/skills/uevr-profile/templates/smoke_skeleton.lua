-- smoke test for loader.lua + core_skeleton.lua on the mock (see tools/run_smoke.py)
DEBUG_OVERRIDE = { cam = { fwd = 100, turn = 180 } }
local view = { x = 0, y = 30, z = 0, Pitch = 0, Yaw = 30, Roll = 0 }
local pos = { x = 0, y = 0, z = 0 }
for i = 1, 120 do
  CB.on_pre_engine_tick(nil, 1 / 90)
  CB.on_post_calculate_stereo_view_offset(nil, 1, 100, pos, view, false)
end
local st = { Gamepad = { sThumbRX = 30000, sThumbRY = 20000, sThumbLX = 0 } }
CB.on_xinput_get_state(0, 0, st)
local y0 = pc._rot.Yaw
CB.on_pre_engine_tick(nil, 1 / 90)
CB.on_draw_ui()
CB.on_script_reset()
local errs = {}
for _, l in ipairs(LOG) do if l:find("ERROR") or l:find("error") then errs[#errs + 1] = l end end
assert(#errs == 0, table.concat(errs, " | "))
assert(math.abs(pc._rot.Yaw - y0 - 45) < 1e-6, "snap turn")
assert(st.Gamepad.sThumbRY == 0, "pitch blocked")
assert(FILES["mod_status.json"] ~= nil, "status written in debug mode")
assert(pos.x ~= 0, "debug camera applied")
return "skeleton smoke OK; loader: " .. tostring(FILES["mod_loader.txt"]):gsub("\n", " ")
