#!/usr/bin/env bash
# Merge GAMMA-common gamedata into a feature mod tree (CI release step).
# Usage: vendor-gamedata.sh [dest_gamedata_dir] [common_root]
set -euo pipefail

DEST="${1:-gamedata}"
COMMON="${2:-GAMMA-common}"
SRC="${COMMON}/gamedata"

if [[ ! -d "$SRC" ]]; then
	echo "vendor-gamedata: missing directory: $SRC" >&2
	exit 1
fi

mkdir -p "$DEST"
cp -a "$SRC/." "$DEST/"
echo "vendor-gamedata: merged $SRC -> $DEST"
