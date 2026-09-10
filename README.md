# i_wanna_see

A Darktide mod that reduces or removes the sources of VFX that block your vision.

## Options

| Option | Effect |
| --- | --- |
| Inferno Staff intensity | Purgatus flame, scorch marks and pilot light |
| Zealot Flamer intensity | Flamer gas stream, scorch marks and pilot light |
| Smite lightning intensity | Smite beams and the arc drawn when nothing is targeted |
| Electrokinetic Staff lightning intensity | The staff's chains, tracked separately from Smite |
| Enemy flamers | The jet, hit sparks and ground fire that AI flamers draw |
| Psyker Shield Settings | Remove the shield mesh, remove its sound, and/or draw an AoE radius on the floor in a colour you pick |

Intensities run from 0% to 100%:

- **100% is untouched vanilla.** The mod's hooks fall straight through and nothing else runs.
- **0% removes the effect**, which is the mod's default and what the checkboxes used to do.
- **In between** scales what is drawn: flame particles live for that share of their
  normal life, which is what the stream's cost is made of, and its scorch decals are
  thinned by the same ratio. Chain lightning spawns that share of its links, keeping
  every other one at 50% rather than flipping a coin per link.

The enemy flamer option is the exception: it defaults to 100%, because that flame is
also a warning, and it drops a share of *enemies* rather than a share of frames. Each
enemy is decided once, so a flame that goes away stays away.

Options are read once at load and refreshed when they change, so they can be toggled
in the mod options menu without a restart.

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
whenever an effect is left at 100%:

- `FlamerGasEffects._update_effects` — vanilla runs untouched unless the current fire
  configuration is one that is being scaled down. Both the singular and plural
  `fire_configuration(s)` shapes the game uses are handled, and the cached particle
  variable index avoids vanilla's per-frame `find_particles_variable`.
- `ChainLightningTarget.add_child` — the only place links are added, including the
  ones created by `ChainLightning.jump`. The spawn callback is substituted while the
  node tree, vanilla's own cleanup and its `hit_units` bookkeeping are left alone.
- `PsykerForceFieldUnitExtension.init` / `_trigger_death_effects` — vanilla runs
  first and only the unwanted parts are removed afterwards, so shield behaviour
  (width, deployable durations, particles, sounds, flow events) stays the game's.
- `Flamer.start_shooting_fx` / `Flamer.update_shooting_fx` — the driver every AI flame
  effect template uses (the flamers, the beast of nurgle's vomit, linked beams). Both
  are hooked because the update creates the hit sparks and ground fire itself. Enemy
  units are identified through the game's own side system, so the player and their
  allies are never touched, and an unknown unit is left alone.
- The partial flame intensity mirrors the game's own `distance / speed` life
  calculation. If that data is ever missing, the scaling is skipped and the effect is
  simply drawn at full strength.
