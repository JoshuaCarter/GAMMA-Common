# Dorns Common

Shared library for Dorn's G.A.M.M.A. mods:

- `dorn_dbg.script` — on-screen debug HUD (`_G.dorn_dbg`)
- `dorn_mcm.script` — MCM getter helpers (`_G.dorn_mcm`)
- `dorn_sys.script` — mod bind/sync/ready helpers (`_G.dorn_sys`)

GitHub repo: **GAMMA-Common** → MO2 install folder **Dorns_Common**.

## MO2 install

1. Install **Dorns_Common** from [releases](https://github.com/JoshuaCarter/GAMMA-Common/releases).
2. Enable it **above** your other Dorn mods in load order.
3. Feature mods do not bundle these scripts; this mod provides them at runtime.

## Dev / submodule

Feature mods pin this repo as the `GAMMA-common` submodule. Release CI merges all of `gamedata/` into each mod zip via `tools/vendor-gamedata.sh` (no per-mod file list to maintain).

```bash
git submodule add -b main https://github.com/JoshuaCarter/GAMMA-Common.git GAMMA-common
git submodule update --init --recursive
```

Release workflow step:

```bash
bash GAMMA-common/tools/vendor-gamedata.sh gamedata
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
dbg.log("my_mod_id", { order = 0, color = "green" }, "status line", "MyMod")

local mcm = _G.dorn_mcm
local scale = mcm.number("my_mod_id", "main/foo")  -- use `def` in on_mcm_load only
local blur = mcm.range("my_mod_id", "main/blur_min", "main/blur_max", 50, 0)
local intensity = blur:normalize(msv)

local sys = _G.dorn_sys
RegisterScriptCallback("on_option_change", on_option_change)

local ctx, actor = sys.ready("my_mod_id", db, on_option_change)
if not ctx then return end
```
