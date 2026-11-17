"""Build the release zip of the UEVR profile.

    python tools/build_release.py
    -> dist/Scorn-Win64-Shipping.zip  (import it in UEVR: "Import Config")
"""
import os
import re
import zipfile

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
PROFILE = os.path.join(ROOT, "profile", "Scorn-Win64-Shipping")
DIST = os.path.join(ROOT, "dist")

core = open(os.path.join(PROFILE, "data", "scorn_vr_core.lua"), encoding="utf-8").read()
version = re.search(r'local VERSION = "([^"]+)"', core).group(1)

os.makedirs(DIST, exist_ok=True)
out = os.path.join(DIST, "Scorn-Win64-Shipping.zip")
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for d, _, files in os.walk(PROFILE):
        for f in sorted(files):
            p = os.path.join(d, f)
            z.write(p, os.path.relpath(p, PROFILE).replace(os.sep, "/"))
print(f"version {version}: {out}")
for n in zipfile.ZipFile(out).namelist():
    print("  ", n)
