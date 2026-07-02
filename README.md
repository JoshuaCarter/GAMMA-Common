# GAMMA-Common (Dorns_Common)

Source for Dorn shared scripts. Feature mods sync the common scripts locally, as flat commit-suffixed files, and commit the result — no submodules, no separate MO2 mod, no mirrored copy of this repo left lying around.

This repo is **not** an installable MO2 mod itself — it has no `meta.ini`, and nothing here ever gets zipped or installed directly. It only exists to be synced *from*, via git, into feature mods' own `gamedata/`.

There's no version number, no tags, no release CI. "Version" is just this repo's current git commit — sync copies its current commit into flat, hash-suffixed script files. Committing here *is* publishing.

## Source scripts (`gamedata/scripts/`)

| File | Role |
|------|------|
| `dorn_mcm.script` | MCM getters (namespace module) |
| `dorn_dbg.script` | Debug HUD (namespace module) |
| `dorn_sys.script` | `ready()` gate (`set_deps` wires it to `mcm`/`dbg`) |

Plus `tools/dorn_common.template.script` — a tiny loader synced as a 4th
file, `dorn_common_<hash>.script` (see "The loader" below).

## The loader, and why it doesn't call `process_file()`

Earlier versions of this synced a generated `<mod_id>_common.script` wrapper
that called `process_file()` to load the three scripts above and exposed a
`get()`/`init()` API. **That's gone — it doesn't work.**

X-Ray's `process_file()` cannot safely be called from within a script that is
itself already being loaded via `process_file()` — doing so throws
`attempt to call global 'process_file' (a nil value)` at runtime, which
silently broke every mod using that pattern. It's also unnecessary: X-Ray
auto-loads *every* `.script` file under `gamedata/scripts` at boot,
regardless of whether anything ever calls `process_file()` on it — that's
exactly how the common scripts end up available at all, no `process_file()`
call required anywhere.

So instead there's `dorn_common_<hash>.script` — synced from
`tools/dorn_common.template.script` (only the `@COMMIT@` placeholder gets
substituted with the current commit hash) — which exposes one function,
`load(mod_id)`, that resolves the three sibling globals, wires them together,
and returns them as a table. A mod's `_main.script` just does:

```lua
DORN = _G[DORN_COMMON_VERSION].load(MOD_ID)
```

instead of duplicating that lookup/wiring logic itself (see "Feature code"
below). This is still just a plain auto-loaded global lookup, not a
`process_file()` call, and it's still resolved inside `on_game_start()` —
by the time any mod's `on_game_start()` runs, every `.script` file has
already finished loading, so this is always safe regardless of alphabetical
load order.

`DORN_COMMON_VERSION` itself is never hand-edited: sync rewrites that
constant's value in place, in whichever `.script` file declares it, on every
run (see "Sync" below), so a stale reference can't survive a sync the way it
used to when this was a manual bump.

## Why mods never step on each other

MO2 merges every enabled mod's `gamedata/` into one VFS. A file only collides
if two mods ship the exact same relative path with different content.

`dorn_mcm.script` / `dorn_dbg.script` / `dorn_sys.script` / the generated
`dorn_common.script` loader are all copied as flat files suffixed with the
commit they came from: `dorn_mcm_<hash>.script`, etc. Different commits ⇒
different filename, zero overlap. Same commit ⇒ same filename **and**
byte-identical content, so a VFS "collision" there is harmless — it doesn't
matter which mod's copy MO2 picks.

Net effect: any mix of mods, any mix of commits, no cross-mod interference.

**Why not a `common_<hash>/` subfolder** (an earlier, also-broken design):
X-Ray's `process_file()` uses the same string for both the file path *and*
the Lua namespace it registers the module under, and its namespace-splitting
code only understands `.` as a nesting separator, not `/`. A namespace like
`"common_a9df1649/dorn_mcm"` has no dot, so the engine treats it as one flat
(and invalid) Lua identifier when generating the assignment that registers
the module — a straight syntax error. Flat, underscore-suffixed filenames
sidestep this entirely (and also sidestep the `process_file` bug above, since
there's no wrapper script trying to load them in the first place).

## Mod ID

Each mod has a `.mod_id` file — one line, committed once, e.g.:

```
dorn_prone_fix
```

This isn't read by the sync script for naming anymore (there's no generated
file to name) — it's the marker `sync-all-dorn-mods.sh` uses to auto-discover
which sibling `Dorns_*` folders actually sync common code, and it documents
the mod's `MOD_ID` constant for reference.

This is **not** stored in `meta.ini`. MO2 owns `meta.ini` and rewrites it
(and its existing `modid=` field is the Nexus mod ID, unrelated to this —
repurposing it would be fragile and confusing). A dedicated file is explicit,
never touched by MO2, and never changes once set.

## No local mirror

Older versions of this setup cloned the whole `Dorns_Common` repo into each
mod's `.dorn-common/` folder just to read 3 files. That's gone. The sync
script now reads directly from:

1. `../Dorns_Common` next to the mod, if present (typical dev setup) — it
   must be a clean checkout (no uncommitted changes to `gamedata/scripts`),
   so the commit hash it reports actually matches what gets copied, or
2. a throwaway `git clone --depth 1` into a temp directory, deleted the
   moment the script exits, if there's no local checkout.

Nothing persists in the mod's repo folder beyond what actually gets
committed (`gamedata/scripts/dorn_{mcm,dbg,sys,common}_<hash>.script`).
Nothing to gitignore for it.

## One canonical copy of the tooling

`sync-dorn-common.sh` lives **only** here, in `tools/`. Feature mods do not
keep their own copy in a `scripts/` folder — they call this repo's copy
directly:

```bash
cd /path/to/Dorns_Prone_Fix   # or any subdirectory of it
bash /path/to/Dorns_Common/tools/sync-dorn-common.sh
```

It finds the target mod's repo root itself — like git, it walks up from the
current directory (`git rev-parse --show-toplevel`) rather than assuming the
cwd *is* the root. That means it doesn't matter which subdirectory of the mod
you're standing in, and it's what lets the editor task below key off
"whatever file you currently have open" instead of a hardcoded list of mods.

Updating the sync logic once here updates every mod immediately — no
copy/paste step, nothing to fall out of sync across repos.

Each mod still keeps its own tiny `githooks/pre-commit` (git hooks are
inherently per-repo) — that's it. The sync tooling and the editor task
definitions live in exactly one place.

## Feature mod layout (after sync)

```
.mod_id                      # committed, one line, e.g. "dorn_prone_fix"
gamedata/scripts/
  dorn_prone_fix_main.script       # local DORN_COMMON_VERSION = "dorn_common_a9f6380b" (kept in sync by the sync script)
  dorn_common_a9f6380b.script      # generated loader — committed
  dorn_mcm_a9f6380b.script         # copied from Dorns_Common — committed
  dorn_dbg_a9f6380b.script
  dorn_sys_a9f6380b.script
```

There's no file recording the synced commit — the commit is just the suffix
on the four filenames. Run `--check` to confirm they're still in sync with
`Dorns_Common`'s current state.

## Setup (once per mod)

```bash
echo dorn_prone_fix > .mod_id   # match the mod's MOD_ID constant
git config core.hooksPath githooks
```

Copy `githooks/pre-commit` from another Dorn mod as a starting point. Set up the User task once (see Sync, below) — it then works for every mod.

## Sync

It's just two commands. Run sync, get Dorns_Common's current commit copied in as four files suffixed with its hash, done.

```bash
cd /path/to/the/mod   # or any subdirectory of it
bash /path/to/Dorns_Common/tools/sync-dorn-common.sh              # get latest commit, done
bash /path/to/Dorns_Common/tools/sync-dorn-common.sh --check      # verify only, no changes
```

There's no version number to look up or pass — sync always takes whatever commit `../Dorns_Common` (or the remote, if there's no local checkout) is currently on. If the local checkout has uncommitted changes to `gamedata/scripts`, sync refuses to run — commit them there first so the hash actually matches what gets copied.

Sync also finds whichever `.script` file declares `local DORN_COMMON_VERSION = "dorn_common_<hash>"` and rewrites `<hash>` in place to match — there's nothing to bump by hand, and `--check` fails if it's ever stale (e.g. if `Dorns_Common` moved on and you forgot to re-sync).

Or from the editor: **Run Task** → `Dorn: Sync Common` / `Dorn: Check Common`. Have a file from the target mod open and focused first — the task runs with that file's directory as cwd, and the script walks up to find the mod's repo root from there, same as it would from a terminal.

To do every mod in one go, there's also **Run Task** → `Dorn: Sync All Mods` / `Dorn: Check All Mods`. These run `tools/sync-all-dorn-mods.sh`, which auto-discovers every sibling `Dorns_*` folder with a `.mod_id` file (skipping `Dorns_Common` itself and any not-yet-set-up mod) and syncs each in turn — nothing to list or maintain, adding a new mod just means giving it a `.mod_id` and it's automatically included next time. Nothing to bump by hand afterwards either.

These are defined once as **User tasks** (Command Palette → `Tasks: Open User Tasks`), not per-mod `.vscode/tasks.json`. They use a fixed absolute path to this repo's tools (`C:/GAMMA/mods/Dorns_Common/tools/...`) and `${fileDirname}` (the currently open file's folder) for cwd — deliberately **not** `${workspaceFolder}`. In a multi-root workspace `${workspaceFolder}` resolves to whichever folder Cursor considers "current" (not necessarily the mod you're looking at), which silently ran the sync against the wrong folder. `${fileDirname}` + the scripts' own git-root walk-up removes that ambiguity without needing a hardcoded mod list to maintain: open any file in the mod you want, run the task, done.

Windows location: `%APPDATA%\Cursor\User\tasks.json`. Contents:

```json
{
	"version": "2.0.0",
	"tasks": [
		{
			"label": "Dorn: Sync Common",
			"type": "shell",
			"command": "bash",
			"args": ["C:/GAMMA/mods/Dorns_Common/tools/sync-dorn-common.sh"],
			"options": { "cwd": "${fileDirname}" },
			"problemMatcher": [],
			"presentation": { "reveal": "always", "panel": "shared" }
		},
		{
			"label": "Dorn: Check Common",
			"type": "shell",
			"command": "bash",
			"args": ["C:/GAMMA/mods/Dorns_Common/tools/sync-dorn-common.sh", "--check"],
			"options": { "cwd": "${fileDirname}" },
			"problemMatcher": [],
			"presentation": { "reveal": "always", "panel": "shared" }
		},
		{
			"label": "Dorn: Sync All Mods",
			"type": "shell",
			"command": "bash",
			"args": ["C:/GAMMA/mods/Dorns_Common/tools/sync-all-dorn-mods.sh"],
			"problemMatcher": [],
			"presentation": { "reveal": "always", "panel": "shared" }
		},
		{
			"label": "Dorn: Check All Mods",
			"type": "shell",
			"command": "bash",
			"args": ["C:/GAMMA/mods/Dorns_Common/tools/sync-all-dorn-mods.sh", "--check"],
			"problemMatcher": [],
			"presentation": { "reveal": "always", "panel": "shared" }
		}
	]
}
```

Nothing here needs updating when you add a new mod — `${fileDirname}` plus the scripts' own git-root walk-up handles any mod automatically.

**Backup / restore**: a copy of this file is committed at `tools/cursor-user-tasks.json` in this repo, so it survives a reinstall or new machine. To (re)install it:

```bash
cp tools/cursor-user-tasks.json "$APPDATA/Cursor/User/tasks.json"   # Git Bash / WSL
```

or on Windows directly:

```powershell
copy tools\cursor-user-tasks.json %APPDATA%\Cursor\User\tasks.json
```

If you already have other User tasks defined, merge the `tasks`/`inputs` arrays by hand instead of overwriting.

**Running a task**: Command Palette (`Ctrl+Shift+P`) → **Tasks: Run Task** → pick e.g. `Dorn: Sync Common`. To edit the list, Command Palette → **Tasks: Open User Tasks**.

## Feature code

```lua
local MOD_ID = "dorn_prone_fix"
local DORN_COMMON_VERSION = "dorn_common_a9f6380b" -- managed by sync-dorn-common.sh, do not hand-edit

local DORN

function on_game_start()
	DORN = _G[DORN_COMMON_VERSION].load(MOD_ID)   -- wires deps + calls sys.reset_mod/dbg.clear_source(MOD_ID)
	-- ...
end

DORN.mcm.bool(MOD_ID, "main/foo", false)
local ctx, actor = DORN.sys.ready(MOD_ID, db, on_option_change)
```

`_G[DORN_COMMON_VERSION].load(mod_id)` (defined in
`tools/dorn_common.template.script`, synced as `dorn_common_<hash>.script`)
resolves the three sibling globals, calls `sys.set_deps`,
`sys.reset_mod(mod_id)`, and `dbg.clear_source(mod_id)` for you, and returns
`{ mcm = ..., dbg = ..., sys = ... }`.

`DORN_COMMON_VERSION`'s value is rewritten in place by the sync script on
every run — don't hand-edit it, and don't rename the variable, since sync
finds it by that exact name via regex.

Resolve `DORN` inside `on_game_start()`, never at the top level of the
script — by the time `on_game_start()` runs, every `.script` file has
already been auto-loaded by the engine, so `_G[DORN_COMMON_VERSION]` and the
three globals it looks up are all guaranteed to exist. At the top level
(i.e. while the file itself is still being parsed), that's not guaranteed —
other scripts load in whatever order the engine's file scan produces, not
necessarily before yours.

## Hooks

```bash
git config core.hooksPath githooks
```

`pre-commit`: syncs, fails if that produced changes not yet `git add`ed.

## Bump common (per mod, independently)

1. Edit scripts here and commit (committing here *is* publishing — no push/tag/CI step needed for other mods to pick it up, though push it too so the remote-clone fallback stays current)
2. In that mod: run sync (see above) — this rewrites `dorn_{mcm,dbg,sys,common}_<hash>.script` under the new commit hash, and updates that mod's `DORN_COMMON_VERSION` constant to match, automatically
3. `git add gamedata/scripts` and commit
4. Push — that mod's own release CI zips its committed `gamedata/` as-is

Other mods are unaffected until you repeat steps 2–4 in them — each mod updates on its own schedule, at its own pace.
