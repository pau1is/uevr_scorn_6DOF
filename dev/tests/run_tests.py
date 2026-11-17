"""Run the offline Lua tests (UEVR is mocked, no game needed).

    pip install lupa
    python dev/tests/run_tests.py
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
PROFILE = os.path.join(ROOT, "profile", "Scorn-Win64-Shipping")
CORE = os.path.join(PROFILE, "data", "scorn_vr_core.lua")

tests = [
    [sys.executable, os.path.join(HERE, "test_grip.py"), CORE, os.path.join(HERE, "test_grip.lua")],
    [sys.executable, os.path.join(HERE, "test_v21.py"), PROFILE],
]

failed = 0
for cmd in tests:
    r = subprocess.run(cmd, capture_output=True, text=True)
    out = r.stdout + r.stderr
    ok = r.returncode == 0 and "FAIL" not in out and "Error" not in out
    name = os.path.basename(cmd[1])
    print(("PASS " if ok else "FAIL ") + name)
    if not ok:
        failed += 1
        print(out[-3000:])
sys.exit(1 if failed else 0)
