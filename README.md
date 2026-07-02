# GAMMA-Common (Dorns_Common)

Source for Dorn shared scripts. Feature mods sync the three common scripts locally, generate a small per-mod entry script, and commit the result — no submodules, no separate MO2 mod, and no mirrored copy of this repo left lying around.

This repo is **not** an installable MO2 mod itself — it has no `meta.ini`, and nothing here ever gets zipped or installed directly. It only exists to be synced *from*, via git, into feature mods' own `gamedata/`.

There's no version number, no tags, no release CI. "Version" is just this repo's current git commit — sync copies its current commit into a subdirectory named after that commit's short hash. Committing here *is* publishing.

## Source scripts (`gamedata/scripts/`)

| File | Role |
|------|------|
| `dorn_mcm.script` | MCM getters (namespace module) |
| `dorn_dbg.script` | Debug HUD (namespace module) |
| `dorn_sys.script` | `ready()` gate (`set_deps` from `<mod_id>_common`) |

## Why mods never step on each other

MO2 merges every enabled mod's `gamedata/` into one VFS. A file only collides
if two mods ship the exact same relative path with different content.

- **Entry script is unique per mod**: sync generates `<mod_id>_common.script`,
  named from that mod's own `.mod_id`. Two mods can never produce the
  same entry filename, so one mod's synced commit can never leak into
  another — whether they're on the same or different commits.
- **`dorn_mcm.script` / `dorn_dbg.script` / `dorn_sys.script` live under a
  folder named after the commit they came from**: `common_<hash>/`.
  Different commits ⇒ different folder, zero overlap. Same commit ⇒ same
  folder path **and** byte-identical content, so a VFS "collision" there is
  harmless — it doesn't matter which mod's copy MO2 picks.

Net effect: any mix of mods, any mix of commits, no cross-mod interference.

## Mod ID

Each mod has a `.mod_id` file — one line, committed once, e.g.:

```
dorn_prone_fix
```

This is **not** stored in `meta.ini`. MO2 owns `meta.ini` and rewrites it
(and its existing `modid=` field is the Nexus mod ID, unrelated to this — 
repurposing it would be fragile and confusing). A dedicated file is explicit,
never touched by MO2, and never changes once set.

## No local mirror

Older versions of this setup cloned the whole `Dorns_Common` repo into each
mod's `.dorn-common/` folder just to read 4 files. That's gone. The sync
script now reads directly from:

1. `../Dorns_Common` next to the mod, if present (typical dev setup) — it
   must be a clean checkout (no uncommitted changes to the synced files), so
   the commit hash it reports actually matches what gets copied, or
2. a throwaway `git clone --depth 1` into a temp directory, deleted the
   moment the script exits, if there's no local checkout.

Nothing persists in the mod's repo folder beyond what actually gets
committed (`gamedata/scripts/...`). Nothing to gitignore for it.

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
  dorn_prone_fix_common.script    # generated entry + commit pin + loader
  common_a9f6380b/                 # copied from Dorns_Common — committed
    dorn_mcm.script
    dorn_dbg.script
    dorn_sys.script
```

The synced commit is recorded on the first line of `<mod_id>_common.script` (used by `--check`, and to name the `common_<hash>/` folder):

```lua
-- dorn-common-commit: a9f6380b
```

The entry script also `printf`s a one-line startup log (`[DORN] <mod_id>: common loaded (common_<hash>, commit <hash>)`) so you can confirm which commit is actually loaded in-game, e.g. via the log console or `Dorns_FPS_Counter`'s log file.

## Setup (once per mod)

```bash
echo dorn_prone_fix > .mod_id   # match the mod's MOD_ID constant
git config core.hooksPath githooks
```

Copy `githooks/pre-commit` from another Dorn mod as a starting point. Set up the User task once (see Sync, below) — it then works for every mod.

## Sync

It's just two commands. Run sync, get Dorns_Common's current commit copied into a subdirectory named after it, done.

```bash
cd /path/to/the/mod   # or any subdirectory of it
bash /path/to/Dorns_Common/tools/sync-dorn-common.sh              # get latest commit, done
bash /path/to/Dorns_Common/tools/sync-dorn-common.sh --check      # verify only, no network
```

There's no version number to look up or pass — sync always takes whatever commit `../Dorns_Common` (or the remote, if there's no local checkout) is currently on. If the local checkout has uncommitted changes to the synced files, sync refuses to run — commit them there first so the hash actually matches what gets copied.

Or from the editor: **Run Task** → `Dorn: Sync Common` / `Dorn: Check Common`. Have a file from the target mod open and focused first — the task runs with that file's directory as cwd, and the script walks up to find the mod's repo root (and its `.mod_id`) from there, same as it would from a terminal.

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
process_file("dorn_prone_fix_common")
local DORN = dorn_prone_fix_common.get()

function on_game_start()
  dorn_prone_fix_common.init(MOD_ID)  -- resets only this mod's state
  -- ...
end

DORN.mcm.bool(MOD_ID, "main/foo", false)
local ctx, actor = DORN.sys.ready(MOD_ID, db, on_option_change)
```

`process_file`/`get`/`init` always reference `<mod_id>_common` — the mod's own `.mod_id` value. This is stable across syncs; it only ever changes if you rename the mod.

## Hooks

```bash
git config core.hooksPath githooks
```

`pre-commit`: syncs, fails if that produced changes not yet `git add`ed.

## Bump common (per mod, independently)

1. Edit scripts here and commit (committing here *is* publishing — no push/tag/CI step needed for other mods to pick it up, though push it too so the remote-clone fallback stays current)
2. In that mod: run sync (see above)
3. `git add gamedata/scripts` and commit
4. Push — that mod's own release CI zips its committed `gamedata/` as-is

Other mods are unaffected until you repeat step 2–4 in them — each mod updates on its own schedule, at its own pace.
