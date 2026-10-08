"""Run with Python 3 and --lua-dll PATH_TO_BALATRO/lua51.dll (Windows x64)."""
import argparse
import ctypes
import os
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--lua-dll', required=True)
args = p.parse_args()
root = Path(__file__).resolve().parents[1]
dll = Path(args.lua_dll).resolve()
search = os.add_dll_directory(str(dll.parent))
lua = ctypes.CDLL(str(dll))
lua.luaL_newstate.restype = ctypes.c_void_p
lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
lua.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lua.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
lua.lua_tolstring.restype = ctypes.c_char_p
lua.lua_close.argtypes = [ctypes.c_void_p]
state = lua.luaL_newstate()
if not state:
    raise RuntimeError('Could not create Lua state')
try:
    lua.luaL_openlibs(state)
    os.chdir(root)
    script = b"for _,f in ipairs({'main.lua','core.lua','config.lua','predict.lua','ui.lua','toolbar.lua'}) do assert(loadfile(f)) end; dofile('tests/spec.lua')"
    code = lua.luaL_loadstring(state, script)
    if code == 0:
        code = lua.lua_pcall(state, 0, 0, 0)
    if code:
        raise RuntimeError(lua.lua_tolstring(state, -1, None).decode('utf-8', errors='replace'))
finally:
    lua.lua_close(state)
    search.close()
