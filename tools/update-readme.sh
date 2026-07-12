#!/usr/bin/env bash
# Update README.md for a Dorn feature mod.
# Usage: update-readme.sh MOD_ROOT [VER]
#   VER set: sync line-1 title suffix from meta.ini and ensure mod-list footer
#   VER unset: ensure mod-list footer only
#
# Footer is identical in every feature-mod README:
#   ## See my other mods here:
#
#   https://github.com/JoshuaCarter/GAMMA-Mods
# Touches nothing else in README.md.

set -euo pipefail

MOD_ROOT="${1:?MOD_ROOT required}"
VER="${2:-}"
README="${MOD_ROOT}/README.md"
MOD_LIST_URL="https://github.com/JoshuaCarter/GAMMA-Mods"
FOOTER_HEADING="## See my other mods here:"

[ -f "$README" ] || exit 0

if [ -n "$VER" ]; then
  if head -1 "$README" | grep -qE '^# .* v[0-9]+\.[0-9]+\.[0-9]+$'; then
    sed -i '1s/ v[0-9][0-9.]*$/ v'"${VER}"'/' "$README"
  elif head -1 "$README" | grep -qE '^# '; then
    sed -i '1s/$/ v'"${VER}"'/' "$README"
  fi
fi

section_line=$(grep -nE '^(## Other mods|## See my other mods here:)$' "$README" | head -1 | cut -d: -f1 || true)
tmp=$(mktemp)

if [ -n "$section_line" ]; then
  head -n "$((section_line - 1))" "$README" > "$tmp"
else
  cp "$README" "$tmp"
fi

# Trim trailing blank lines from body.
while [ -s "$tmp" ] && [ -z "$(tail -1 "$tmp" | tr -d '[:space:]')" ]; do
  head -n -1 "$tmp" > "${tmp}.trim" && mv "${tmp}.trim" "$tmp"
done

{
  echo ""
  echo "$FOOTER_HEADING"
  echo ""
  echo "$MOD_LIST_URL"
} >> "$tmp"

mv "$tmp" "$README"

NORMALIZE="${DORN_COMMON_LOCAL:-${MODS_ROOT:-C:/GAMMA/mods}/Dorns_Common}/tools/normalize-text-file.sh"
if [[ -x "$NORMALIZE" ]]; then
  bash "$NORMALIZE" "$README"
fi
