# Dorns Common

Shared library for Dorn's G.A.M.M.A. mods:

- `dorn_dbg.script` — on-screen debug HUD (`_G.dorn_dbg`)
- `dorn_mcm.script` — MCM getter helpers (`_G.dorn_mcm`)

## MO2 install

1. Enable this mod in Mod Organizer 2.
2. Keep it **above** your other Dorn mods in load order (the `000-` prefix helps).
3. Each feature mod (Bleed Fix, Prone Fix, etc.) depends on these scripts at runtime.

## Source repo / submodule

This folder is also the **`dorn-common`** git repo. Feature mods vendor it as a submodule at `dorn-common/` for development and copy the scripts into release zips.

After creating the GitHub repo:

```bash
git submodule add https://github.com/JoshuaCarter/dorn-common.git dorn-common
git submodule update --init --recursive
```

## Dev: vendor into a feature mod zip

From a feature mod repo root:

```bash
bash scripts/vendor-dorn-common.sh
```

Copies `dorn-common/gamedata/scripts/dorn_*.script` into that mod's `gamedata/scripts/` (used by CI before zipping).

## API quick reference

```lua
local dbg = _G.dorn_dbg
dbg.set_enabled("my_mod_id", true)
dbg.write("my_mod_id", 0, "status line", dbg.COLORS.green)

local mcm = _G.dorn_mcm
local scale = mcm.number("my_mod_id", "main/foo", 1.0)
```
