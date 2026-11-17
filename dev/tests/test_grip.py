import sys
from lupa import lua54
src = open(sys.argv[1], encoding='utf-8').read()
a = src.index("local DEG = 180.0"); b = src.index("-- Two-bone IK solve")
chunk = src[a:b].replace("local function ", "function ").replace("local DEG", "DEG").replace("local RAD", "RAD")
L = lua54.LuaRuntime(); L.execute(chunk)
print(L.execute(open(sys.argv[2], encoding='utf-8').read()))
