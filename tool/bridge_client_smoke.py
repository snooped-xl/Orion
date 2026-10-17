#!/usr/bin/env python3
"""Run the real packaged Lua bridge smoke scenarios using system liblua5.4.

No game/executor, network, external Python packages, or application profile is
used. If a lua5.4 executable is installed, the .lua file can also run directly.
"""
import ctypes
import ctypes.util
import os
from pathlib import Path

project = Path(__file__).resolve().parent.parent
os.chdir(project)
library = ctypes.util.find_library("lua5.4")
if not library:
    raise SystemExit("Lua 5.4 runtime not found; install lua5.4 or liblua5.4-0.")
lua = ctypes.CDLL(library)
lua.luaL_newstate.restype = ctypes.c_void_p
lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
lua.luaL_loadfilex.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
lua.luaL_loadfilex.restype = ctypes.c_int
lua.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int,
                          ctypes.c_int, ctypes.c_ssize_t, ctypes.c_void_p]
lua.lua_pcallk.restype = ctypes.c_int
lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
lua.lua_tolstring.restype = ctypes.c_char_p
lua.lua_close.argtypes = [ctypes.c_void_p]
state = lua.luaL_newstate()
if not state:
    raise SystemExit("Unable to allocate a Lua state.")
try:
    lua.luaL_openlibs(state)
    status = lua.luaL_loadfilex(state, b"tool/bridge_client_smoke.lua", None)
    if not status:
        status = lua.lua_pcallk(state, 0, 0, 0, 0, None)
    if status:
        message = lua.lua_tolstring(state, -1, None)
        raise SystemExit(message.decode("utf-8", errors="replace") if message else
                         "Lua smoke failed without an error message.")
finally:
    lua.lua_close(state)
