#!/usr/bin/env bash
# Canonical copy — lives only in Dorns_Common/tools.
#
# Runs sync-dorn-common.sh (optionally --check) against every sibling
# Dorns_* mod that has a .mod_id — i.e. every mod actually set up to sync
# common code. Dorns_Common itself and any not-yet-set-up mod are skipped
# automatically; nothing to maintain here when you add a new mod.
#
# Usage:
#   bash <path>/sync-all-dorn-mods.sh              # sync every mod
#   bash <path>/sync-all-dorn-mods.sh --check       # check every mod, no changes
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

FAILED=()
SKIPPED=()
OK=()

for mod in "$MODS_ROOT"/Dorns_*/; do
	mod="${mod%/}"
	name="$(basename "$mod")"
	[[ -f "$mod/.mod_id" ]] || { SKIPPED+=("$name"); continue; }

	echo "=== $name ==="
	if (cd "$mod" && bash "$SCRIPT_DIR/sync-dorn-common.sh" "$@"); then
		OK+=("$name")
	else
		FAILED+=("$name")
	fi
	echo
done

echo "sync-all-dorn-mods: ${#OK[@]} ok, ${#FAILED[@]} failed, ${#SKIPPED[@]} skipped (no .mod_id: ${SKIPPED[*]:-none})"
[[ ${#FAILED[@]} -eq 0 ]] || { echo "sync-all-dorn-mods: failed: ${FAILED[*]}" >&2; exit 1; }
exit 0
