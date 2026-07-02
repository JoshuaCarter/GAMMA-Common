#!/usr/bin/env bash
# Canonical copy — lives only in Dorns_Common/tools. Feature mods invoke it
# via a relative path; they do NOT keep their own copy.
#
# Run from anywhere inside the TARGET mod's repo — like git, it walks up from
# the current directory to find the repo root (and the .mod_id file there):
#   cd /path/to/Dorns_Prone_Fix/gamedata/scripts   # any subdirectory works
#   bash /path/to/Dorns_Common/tools/sync-dorn-common.sh [--check]
#
# Sync = copy Dorns_Common's current commit into gamedata/scripts as flat
# files suffixed with that commit's hash. That's it, no version numbers, no
# tags, no CI:
#   gamedata/scripts/<mod_id>_common.script           # generated entry, records the commit
#   gamedata/scripts/dorn_{mcm,dbg,sys}_<commit>.script
#
# <mod_id> comes from the target mod's .mod_id (one line, set once at the
# repo root): echo dorn_prone_fix > .mod_id
#
# This naming keeps mods fully independent in MO2's merged VFS: the entry
# script name is unique per mod, and dorn_*_<commit>.script only overlaps
# between mods synced from the exact same commit, where the content is
# byte-identical anyway.
#
# IMPORTANT: these must stay flat files, not a subdirectory. X-Ray's
# process_file() uses the same string for both the file path AND the Lua
# namespace it registers the module under, and its namespace wrapper only
# understands "." as a nesting separator — a "/" in that string produces
# invalid Lua source (e.g. `common_x/dorn_mcm= this`) and silently breaks
# every mod that loads it. Flat, underscore-suffixed filenames avoid this
# entirely.
#
# Source (no local mirror is ever kept):
#   1. ../Dorns_Common next to the mod, if present — must be a clean git
#      checkout (no uncommitted changes to the files being synced), so the
#      commit hash actually matches what gets copied.
#   2. otherwise a throwaway `git clone --depth 1` of the default branch into
#      a temp directory, deleted when the script exits.
#
# --check verifies the mod's currently-synced commit is intact — no network,
# no new commit lookup. Used by the pre-commit hook.
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

MOD_ID_FILE="$ROOT/.mod_id"
if [[ ! -f "$MOD_ID_FILE" ]]; then
	echo "sync-dorn-common: missing ${MOD_ID_FILE}" >&2
	echo "  Create it once with this mod's MOD_ID, e.g.:" >&2
	echo "    echo dorn_prone_fix > .mod_id" >&2
	exit 1
fi
MOD_ID="$(tr -d '[:space:]' < "$MOD_ID_FILE")"
if [[ -z "$MOD_ID" ]]; then
	echo "sync-dorn-common: ${MOD_ID_FILE} is empty" >&2
	exit 1
fi

SCRIPTS="$ROOT/gamedata/scripts"
ENTRY="$SCRIPTS/${MOD_ID}_common.script"
LOCAL="${DORN_COMMON_LOCAL:-$ROOT/../Dorns_Common}"
REMOTE="${DORN_COMMON_REPO:-https://github.com/JoshuaCarter/GAMMA-Common.git}"

TMP_CLONE=""
cleanup() {
	if [[ -n "$TMP_CLONE" && -d "$TMP_CLONE" ]]; then
		rm -rf "$TMP_CLONE"
	fi
}
trap cleanup EXIT

read_commit_from_entry() {
	[[ -f "$ENTRY" ]] || return 1
	local line
	line="$(head -n 1 "$ENTRY")"
	if [[ "$line" =~ ^--[[:space:]]*dorn-common-commit:[[:space:]]*([0-9a-f]+)[[:space:]]*$ ]]; then
		echo "${BASH_REMATCH[1]}"
		return 0
	fi
	return 1
}

if [[ "$CHECK_ONLY" == "1" ]]; then
	COMMIT="$(read_commit_from_entry)" || {
		echo "sync-dorn-common: missing commit pin in ${ENTRY} — run: bash <path>/sync-dorn-common.sh" >&2
		exit 1
	}
	SRC=""
	[[ -f "$LOCAL/gamedata/scripts/dorn_mcm.script" ]] && SRC="$LOCAL"
else
	SRC=""
	if [[ -f "$LOCAL/gamedata/scripts/dorn_mcm.script" ]]; then
		if [[ -d "$LOCAL/.git" ]] && [[ -n "$(git -C "$LOCAL" status --porcelain -- gamedata/scripts tools/dorn_common.template.script 2>/dev/null)" ]]; then
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
fi

dest_file() { echo "$SCRIPTS/${1}_${COMMIT}.script"; }
TEMPLATE=""
[[ -n "$SRC" ]] && TEMPLATE="$SRC/tools/dorn_common.template.script"

expected_entry() {
	local tmp="$1"
	[[ -f "$TEMPLATE" ]] || return 1
	sed -e "s/@COMMIT@/$COMMIT/g" -e "s/@MOD_ID@/$MOD_ID/g" "$TEMPLATE" > "$tmp"
}

verify_install() {
	[[ -f "$(dest_file dorn_mcm)" ]] || return 1
	[[ -f "$(dest_file dorn_dbg)" ]] || return 1
	[[ -f "$(dest_file dorn_sys)" ]] || return 1
	[[ -f "$ENTRY" ]] || return 1

	if [[ -z "$SRC" || ! -f "$TEMPLATE" ]]; then
		return 0 # no source available (offline, no local checkout) — structural check only
	fi

	local entry_tmp
	entry_tmp="$(mktemp)"
	expected_entry "$entry_tmp" || { rm -f "$entry_tmp"; return 1; }
	cmp -s "$entry_tmp" "$ENTRY" || { rm -f "$entry_tmp"; return 1; }
	rm -f "$entry_tmp"

	local src_scripts="$SRC/gamedata/scripts"
	cmp -s "$src_scripts/dorn_mcm.script" "$(dest_file dorn_mcm)" || return 1
	cmp -s "$src_scripts/dorn_dbg.script" "$(dest_file dorn_dbg)" || return 1
	cmp -s "$src_scripts/dorn_sys.script" "$(dest_file dorn_sys)" || return 1
	return 0
}

if [[ "$CHECK_ONLY" == "1" ]]; then
	if verify_install; then
		echo "sync-dorn-common: ok (${MOD_ID}: ${COMMIT})"
		exit 0
	fi
	echo "sync-dorn-common: out of date — run: bash <path>/sync-dorn-common.sh" >&2
	exit 1
fi

[[ -f "$TEMPLATE" ]] || { echo "sync-dorn-common: missing ${TEMPLATE}" >&2; exit 1; }

UPDATED=0

mkdir -p "$SCRIPTS"

# Migration: drop the old common_<hash>/ subdirectory layout (broke module
# loading — see note at the top of this file) and any stale flat
# dorn_*_<hash>.script files from a previous commit.
while IFS= read -r old; do
	[[ -n "$old" ]] && { rm -rf "$old"; UPDATED=1; }
done < <(find "$SCRIPTS" -maxdepth 1 -type d -name 'common_*' 2>/dev/null || true)
for name in dorn_mcm dorn_dbg dorn_sys; do
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

ENTRY_TMP="$(mktemp)"
expected_entry "$ENTRY_TMP"
if [[ ! -f "$ENTRY" ]] || ! cmp -s "$ENTRY_TMP" "$ENTRY"; then
	mv "$ENTRY_TMP" "$ENTRY"
	UPDATED=1
else
	rm -f "$ENTRY_TMP"
fi

echo "sync-dorn-common: ${MOD_ID}: ${COMMIT} (source: ${SRC})"
if [[ "$UPDATED" == "1" ]]; then
	echo "sync-dorn-common: updated — git add gamedata/scripts"
fi
exit 0
