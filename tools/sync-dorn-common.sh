#!/usr/bin/env bash
# Canonical copy — lives only in Dorns_Common/tools. Feature mods invoke it
# via a relative path; they do NOT keep their own copy.
#
# Run from anywhere inside the TARGET mod's repo — like git, it walks up from
# the current directory to find the repo root:
#   cd /path/to/Dorns_Prone_Fix/gamedata/scripts   # any subdirectory works
#   bash /path/to/Dorns_Common/tools/sync-dorn-common.sh [--check]
#
# Sync = copy Dorns_Common's scripts into the mod's gamedata/scripts as flat
# files suffixed with Dorns_Common's current commit hash. That's it, no
# version numbers, no tags, no CI:
#   gamedata/scripts/dorn_{mcm,dbg,sys}_<commit>.script     # copied verbatim
#   gamedata/scripts/dorn_common_<commit>.script            # tiny loader, only @COMMIT@ substituted
#
# The mod's _main.script references dorn_common_<commit> directly (see
# README "Feature code") and calls its load(mod_id) — no per-mod generated
# entry script, no process_file() call. X-Ray auto-loads every .script file
# in gamedata/scripts at boot regardless of who references it, which is both
# why this works without process_file() AND why process_file() must never be
# called on any of these 4 files: calling it from within a script that is
# itself already being loaded throws "attempt to call global 'process_file'
# (a nil value)" — this is what broke every mod under the previous
# generated-entry-script design.
#
# This naming keeps mods fully independent in MO2's merged VFS:
# dorn_*_<commit>.script only overlaps between mods synced from the exact
# same commit, where the content is byte-identical anyway. (Files must stay
# flat, not nested in a subdirectory — X-Ray's namespace wrapper only
# understands "." as a nesting separator, and a "/" in the namespace name
# produces invalid Lua source.)
#
# Source (no local mirror is ever kept):
#   1. ../Dorns_Common next to the mod, if present — must be a clean git
#      checkout (no uncommitted changes to the files being synced), so the
#      commit hash actually matches what gets copied.
#   2. otherwise a throwaway `git clone --depth 1` of the default branch into
#      a temp directory, deleted when the script exits.
#
# --check verifies gamedata/scripts already has what a real sync would
# produce (same commit, same content) — no changes made. Used by the
# pre-commit hook.
#
# Env:
#   DORN_COMMON_LOCAL  — path to a Dorns_Common checkout (default: ../Dorns_Common, relative to cwd)
#   DORN_COMMON_REPO   — git URL used when local checkout is missing
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" ]]; then
	echo "sync-dorn-common: not inside a git repo — cd into the target mod first" >&2
	exit 1
fi

CHECK_ONLY=0
for arg in "$@"; do
	case "$arg" in
		--check) CHECK_ONLY=1 ;;
		*)
			echo "sync-dorn-common: unknown argument: $arg (only --check is supported)" >&2
			exit 1
			;;
	esac
done

# .mod_id is not used for naming anymore (no generated entry script), but it
# stays required as the "this mod syncs common code" marker — it's what lets
# sync-all-dorn-mods.sh auto-discover which mods to touch.
MOD_ID_FILE="$ROOT/.mod_id"
if [[ ! -f "$MOD_ID_FILE" ]]; then
	echo "sync-dorn-common: missing ${MOD_ID_FILE}" >&2
	echo "  Create it once with this mod's MOD_ID, e.g.:" >&2
	echo "    echo dorn_prone_fix > .mod_id" >&2
	exit 1
fi

SCRIPTS="$ROOT/gamedata/scripts"
LOCAL="${DORN_COMMON_LOCAL:-$ROOT/../Dorns_Common}"
REMOTE="${DORN_COMMON_REPO:-https://github.com/JoshuaCarter/GAMMA-Common.git}"

TMP_CLONE=""
cleanup() {
	if [[ -n "$TMP_CLONE" && -d "$TMP_CLONE" ]]; then
		rm -rf "$TMP_CLONE"
	fi
}
trap cleanup EXIT

SRC=""
if [[ -f "$LOCAL/gamedata/scripts/dorn_mcm.script" ]]; then
	if [[ -d "$LOCAL/.git" ]] && [[ -n "$(git -C "$LOCAL" status --porcelain -- gamedata/scripts 2>/dev/null)" ]]; then
		echo "sync-dorn-common: ${LOCAL} has uncommitted changes — commit them first" >&2
		echo "  (the synced commit hash must match what actually gets copied)" >&2
		exit 1
	fi
	SRC="$LOCAL"
else
	TMP_CLONE="$(mktemp -d)"
	git clone --depth 1 "$REMOTE" "$TMP_CLONE"
	echo "sync-dorn-common: cloned ${REMOTE} (temporary, removed on exit)"
	SRC="$TMP_CLONE"
fi
COMMIT="$(git -C "$SRC" rev-parse --short=8 HEAD)"
TEMPLATE="$SRC/tools/dorn_common.template.script"
[[ -f "$TEMPLATE" ]] || { echo "sync-dorn-common: missing ${TEMPLATE}" >&2; exit 1; }

dest_file() { echo "$SCRIPTS/${1}_${COMMIT}.script"; }

expected_loader() {
	sed "s/@COMMIT@/$COMMIT/g" "$TEMPLATE" > "$1"
}

verify_install() {
	local src_scripts="$SRC/gamedata/scripts"
	for name in dorn_mcm dorn_dbg dorn_sys; do
		cmp -s "$src_scripts/${name}.script" "$(dest_file "$name")" || return 1
	done

	local tmp
	tmp="$(mktemp)"
	expected_loader "$tmp"
	if ! cmp -s "$tmp" "$(dest_file dorn_common)"; then
		rm -f "$tmp"
		return 1
	fi
	rm -f "$tmp"
	return 0
}

if [[ "$CHECK_ONLY" == "1" ]]; then
	if verify_install; then
		echo "sync-dorn-common: ok (${COMMIT})"
		exit 0
	fi
	echo "sync-dorn-common: out of date — run: bash <path>/sync-dorn-common.sh" >&2
	echo "  then update the commit suffix in this mod's _main.script" >&2
	exit 1
fi

UPDATED=0

mkdir -p "$SCRIPTS"

# Migration: drop the old common_<hash>/ subdirectory layout and the old
# generated <mod_id>_common.script entry (both broke module loading — see
# notes at the top of this file), plus any stale flat
# dorn_{mcm,dbg,sys,common}_<hash>.script files from a previous commit.
while IFS= read -r old; do
	[[ -n "$old" ]] && { rm -rf "$old"; UPDATED=1; }
done < <(find "$SCRIPTS" -maxdepth 1 -type d -name 'common_*' 2>/dev/null || true)
while IFS= read -r old; do
	# Old generated entry scripts were named "<mod_id>_common.script" (suffix
	# "_common.script"); the new loader is "dorn_common_<hash>.script"
	# (prefix "dorn_common_"), so this glob can't touch it.
	[[ -n "$old" ]] && { rm -f "$old"; UPDATED=1; }
done < <(find "$SCRIPTS" -maxdepth 1 -type f -name '*_common.script' 2>/dev/null || true)
for name in dorn_mcm dorn_dbg dorn_sys dorn_common; do
	while IFS= read -r old; do
		if [[ -n "$old" && "$old" != "$(dest_file "$name")" ]]; then
			rm -f "$old"
			UPDATED=1
		fi
	done < <(find "$SCRIPTS" -maxdepth 1 -type f -name "${name}_*.script" 2>/dev/null || true)
done

for name in dorn_mcm dorn_dbg dorn_sys; do
	src="$SRC/gamedata/scripts/${name}.script"
	dst="$(dest_file "$name")"
	if [[ ! -f "$dst" ]] || ! cmp -s "$src" "$dst"; then
		cp "$src" "$dst"
		UPDATED=1
	fi
done

LOADER_TMP="$(mktemp)"
expected_loader "$LOADER_TMP"
LOADER_DST="$(dest_file dorn_common)"
if [[ ! -f "$LOADER_DST" ]] || ! cmp -s "$LOADER_TMP" "$LOADER_DST"; then
	mv "$LOADER_TMP" "$LOADER_DST"
	UPDATED=1
else
	rm -f "$LOADER_TMP"
fi

echo "sync-dorn-common: ${COMMIT} (source: ${SRC})"
if [[ "$UPDATED" == "1" ]]; then
	echo "sync-dorn-common: updated — git add gamedata/scripts, then set COMMON = \"dorn_common_${COMMIT}\" in this mod's _main.script"
fi
exit 0
