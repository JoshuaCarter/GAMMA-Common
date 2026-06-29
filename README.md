# Dorns Common

Shared library for Dorn's G.A.M.M.A. mods:

- `dorn_dbg.script` — on-screen debug HUD (`_G.dorn_dbg`)
- `dorn_mcm.script` — MCM getter helpers (`_G.dorn_mcm`)

GitHub repo: **GAMMA-Common** → MO2 install folder **Dorns_Common**.

## MO2 install

1. Install **Dorns_Common** from [releases](https://github.com/JoshuaCarter/GAMMA-Common/releases).
2. Enable it **above** your other Dorn mods in load order.
3. Feature mods do not bundle these scripts; this mod provides them at runtime.

## Dev / submodule

Feature mods pin this repo as the `GAMMA-common` submodule. CI copies the two scripts into release zips before packaging.

```bash
git submodule add -b main https://github.com/JoshuaCarter/GAMMA-Common.git GAMMA-common
git submodule update --init --recursive
```

### Auto-sync on push

Feature mods ship `githooks/pre-push` (one file). Enable once per clone:

```bash
git config core.hooksPath githooks
```

If Common moved on `main`, the hook commits the submodule bump and asks you to `git push` again.

## API quick reference

```lua
local dbg = _G.dorn_dbg
dbg.set_enabled("my_mod_id", true)
dbg.write("my_mod_id", 0, "status line", dbg.COLORS.green)

local mcm = _G.dorn_mcm
local scale = mcm.number("my_mod_id", "main/foo", 1.0)
```
