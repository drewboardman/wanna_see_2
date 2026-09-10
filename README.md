# i_wanna_see

A Darktide mod that removes the sources of VFX that block your vision.

## Options

| Option | Effect |
| --- | --- |
| Remove Inferno Staff Effects | Removes the Purgatus (warpfire) gas stream, impacts and pilot light |
| Remove Zealot Flamer Effects | Removes the Zealot flamer (burning) gas stream, impacts and pilot light |
| Remove Smite Lightning Effects | Removes the Smite chain lightning beams and no-target arc |
| Remove Electro Staff Lightning Effects | Also removes the Electrokinetic staff chains, which are otherwise kept while Smite removal is on |
| Psyker Shield Settings | Removes the shield mesh, its sound, and/or draws an AoE radius decal on the floor with a configurable colour |

Options are read once at load and refreshed when they change, so they can be
toggled in the mod options menu without a restart.

## Installing

Drop the `i_wanna_see` folder into your Darktide `mods` folder, add `i_wanna_see`
to `mod_load_order.txt` if it is not listed, then restart the game. Requires the
[Darktide Mod Framework](https://github.com/Darktide-Mod-Framework/Darktide-Mod-Framework).

Release zips are built as `mods/i_wanna_see/`, so they can be extracted straight in.

## Development

```sh
luarocks --lua-version=5.1 --lua-dir="$(brew --prefix luajit)" --tree=lua_modules test
./lua_modules/bin/busted
```

See `tests/README.md` for the fixture, which rebuilds the slice of the game the mod
hooks so behaviour can be checked without launching Darktide, and `tools/package.sh`
for the release archive.

Pushing a `v*` tag runs the tests and publishes the packaged mod as a GitHub release.

## Notes on the implementation

The mod wraps the vanilla methods rather than replacing them, and calls through
whenever an option is off:

- `FlamerGasEffects._update_effects` — vanilla runs untouched unless the current
  fire configuration is one the user asked to remove. Both the singular and plural
  `fire_configuration(s)` shapes the game uses are handled.
- `ChainLightningTarget.add_child` — the only place links are added, including the
  ones created by `ChainLightning.jump`. The spawn callback is substituted while the
  node tree, vanilla's own cleanup and its `hit_units` bookkeeping are left alone.
- `PsykerForceFieldUnitExtension.init` / `_trigger_death_effects` — vanilla runs
  first and only the unwanted parts are removed afterwards, so shield behaviour
  (width, deployable durations, particles, sounds, flow events) stays the game's.
