# Tests

Requires LuaJIT (or Lua 5.1), LuaRocks, and a C compiler.

Setup on macOS:

```sh
brew install luajit luarocks
luarocks --lua-version=5.1 --lua-dir="$(brew --prefix luajit)" --tree=lua_modules test
```

On other platforms, set `--lua-dir` to your LuaJIT installation path.

Run from the repository root after setup:

```sh
./lua_modules/bin/busted
```

The specs drive the real mod file through `tests/support/i_wanna_see_fixture.lua`,
which rebuilds the slice of the game the mod hooks (`World`, `Unit`, `WwiseWorld`,
`Quaternion`, `Vector3`, `ScriptUnit`, `Managers`, `CLASS`, DMF's `mod:hook`) and
hands back the registered hooks plus fake extension instances. Nothing here launches
Darktide, so the fixture is also the place to check a hook's behaviour when the game
changes underneath it.
