import sys, os
from lupa import lua54
here = os.path.dirname(os.path.abspath(__file__))
root = sys.argv[1]
core = open(os.path.join(root, "data", "scorn_vr_core.lua"), encoding='utf-8').read()
loader = open(os.path.join(root, "scripts", "scorn_vr.lua"), encoding='utf-8').read()
L0 = lua54.LuaRuntime()
chk = L0.execute("return function(s, n) local f, e = load(s, n); return e end")
print("syntax core:", chk(core, "core") or "OK", "| loader:", chk(loader, "loader") or "OK")
math_chunk = core[core.index("local DEG = 180.0"):core.index("-- UObject helpers")].rsplit("\n", 2)[0]
math_chunk = math_chunk.replace("local function ", "function ").replace("local DEG", "DEG").replace("local RAD", "RAD")
L = lua54.LuaRuntime()
L.execute(math_chunk)
L.execute(open(os.path.join(here, "mock2.lua"), encoding='utf-8').read())
L.globals().SRC["scorn_vr_core.lua"] = core
# the real loader only registers each callback once per name -> multiple fns; mock stores last only, so chain them
L.execute("""
local orig = {}
for k, f in pairs(uevr.sdk.callbacks) do orig[k] = f end
for k, f in pairs(orig) do
  uevr.sdk.callbacks[k] = function(fn)
    local prev = CB[k]
    if prev then CB[k] = function(...) prev(...) return fn(...) end else CB[k] = fn end
  end
end
""")
L.execute(loader)
print(L.execute(open(os.path.join(here, "scenario_v2.lua"), encoding='utf-8').read()).split("\n")[0])
# hot reload check
L.execute("""
LOG = {}
SRC['scorn_vr_core.lua'] = SRC['scorn_vr_core.lua'] .. ' -- changed'
for i = 1, 100 do CB.on_pre_engine_tick(nil, 1/90) end
""")
print("after hot reload:", [l for l in L.globals().LOG.values()][-3:], L.globals().FILES["scorn_vr_loader.txt"])
L.execute("""
LOG = {}
DEBUG_OVERRIDE = { dev = true }
SRC['scorn_vr_core.lua'] = SRC['scorn_vr_core.lua'] .. ' -- changed again'
for i = 1, 100 do CB.on_pre_engine_tick(nil, 1/90) end
local view = {x=0,y=30,z=0,Pitch=0,Yaw=30,Roll=0}
for i = 1, 50 do
  CB.on_pre_engine_tick(nil, 1/90)
  CB.on_post_calculate_stereo_view_offset(nil, 0, 100, {x=0,y=0,z=0}, view, false)
  CB.on_post_calculate_stereo_view_offset(nil, 1, 100, {x=0,y=0,z=0}, view, false)
end
""")
import json
st = L.globals().FILES["scorn_vr_status.json"]
print("frames after 2nd reload:", st.stats.frames, "yaw_frames:", st.stats.yaw_frames)
