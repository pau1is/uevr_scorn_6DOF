"""Offline smoke test: loader.lua + a core on the mocked UEVR API.

    pip install lupa
    python run_smoke.py [core.lua] [scenario.lua]
Defaults: ../templates/core_skeleton.lua and ../templates/smoke_skeleton.lua
"""
import os, sys
from lupa import lua54

T = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "templates")
core = sys.argv[1] if len(sys.argv) > 1 else os.path.join(T, "core_skeleton.lua")
scen = sys.argv[2] if len(sys.argv) > 2 else os.path.join(T, "smoke_skeleton.lua")
rd = lambda p: open(p, encoding="utf-8").read()

L = lua54.LuaRuntime()
# uemath as globals (the mock uses quat_from_rot, qmul, ... directly)
L.execute("local M = load(...)() for k, v in pairs(M) do _G[k] = v end", rd(os.path.join(T, "uemath.lua")))
L.execute(rd(os.path.join(T, "mock_uevr.lua")))
L.globals().SRC["mod_core.lua"] = rd(core)
L.globals().SRC["uemath.lua"] = rd(os.path.join(T, "uemath.lua"))
# allow several registrations per callback name
L.execute("""
local orig = {}
for k, f in pairs(uevr.sdk.callbacks) do orig[k] = f end
for k in pairs(orig) do
  uevr.sdk.callbacks[k] = function(fn)
    local prev = CB[k]
    if prev then CB[k] = function(...) prev(...) return fn(...) end else CB[k] = fn end
  end
end
""")
L.execute(rd(os.path.join(T, "loader.lua")))
print(L.execute(rd(scen)))
