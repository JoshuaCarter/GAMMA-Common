#!/usr/bin/env bash
# Canonical copy — lives only in Dorns_Common/tools. Feature mods invoke it
# via a relative path; they do NOT keep their own copy.
#
# Run from anywhere inside the TARGET mod's repo:
#   bash /path/to/Dorns_Common/tools/sync-dorn-common.sh [--check]
#
# Synced assets (commit-suffixed where noted for MO2 VFS independence):
#   gamedata/scripts/dorn_{mcm,dbg,sys,common}_<commit>.script
#   gamedata/textures/dorn_mcm_banner_<commit>.dds
#   githooks/pre-commit
#   README.md mod-list footer (via tools/update-readme.sh)
#   .editorconfig, .gitattributes, .gitignore
#   .github/workflows/release.yml
#   .vscode/settings.json, .vscode/launch.json
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
	exit 1
fi

SCRIPTS="$ROOT/gamedata/scripts"
TEXTURES="$ROOT/gamedata/textures"
TEXT_ENG="$ROOT/gamedata/configs/text/eng"
GITHOOKS="$ROOT/githooks"
VSCODE="$ROOT/.vscode"
GITHUB_WF="$ROOT/.github/workflows"
LOCAL="${DORN_COMMON_LOCAL:-$ROOT/../Dorns_Common}"
REMOTE="${DORN_COMMON_REPO:-https://github.com/JoshuaCarter/GAMMA-Common.git}"

SYNC_PATHS=(
	gamedata/scripts/dorn_mcm.script
	gamedata/scripts/dorn_dbg.script
	gamedata/scripts/dorn_sys.script
	gamedata/textures/dorn_mcm_banner.dds
	tools/dorn_common.template.script
	tools/patch-dorn-mcm-banner.sh
	tools/update-readme.sh
	tools/githooks/pre-commit
	tools/mod/.editorconfig
	tools/mod/.gitattributes
	tools/mod/.gitignore
	tools/mod/.github/workflows/release.yml
	tools/mod/.vscode/settings.json
	tools/mod/.vscode/launch.json
)

# src_rel:dest_rel pairs — copied byte-for-byte into the target mod repo root
UNIVERSAL_PAIRS=(
	tools/mod/.editorconfig:.editorconfig
	tools/mod/.gitattributes:.gitattributes
	tools/mod/.gitignore:.gitignore
	tools/mod/.github/workflows/release.yml:.github/workflows/release.yml
	tools/mod/.vscode/settings.json:.vscode/settings.json
	tools/mod/.vscode/launch.json:.vscode/launch.json
)

TMP_CLONE=""
cleanup() {
	if [[ -n "$TMP_CLONE" && -d "$TMP_CLONE" ]]; then
		rm -rf "$TMP_CLONE"
	fi
}
trap cleanup EXIT

SRC=""
if [[ -f "$LOCAL/gamedata/scripts/dorn_mcm.script" ]]; then
	if [[ -d "$LOCAL/.git" ]]; then
		for rel in "${SYNC_PATHS[@]}"; do
			if [[ -n "$(git -C "$LOCAL" status --porcelain -- "$rel" 2>/dev/null)" ]]; then
				echo "sync-dorn-common: ${LOCAL} has uncommitted changes in ${rel} — commit them first" >&2
				exit 1
			fi
		done
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

dest_script() { echo "$SCRIPTS/${1}_${COMMIT}.script"; }
dest_banner() { echo "$TEXTURES/dorn_mcm_banner_${COMMIT}.dds"; }

expected_loader() {
	sed "s/@COMMIT@/$COMMIT/g" "$TEMPLATE" > "$1"
}

expected_mcm() {
	sed "s/@COMMIT@/$COMMIT/g" "$SRC/gamedata/scripts/dorn_mcm.script" > "$1"
}

VERSION_RE='DORN_COMMON_VERSION[[:space:]]*=[[:space:]]*"dorn_common_[0-9a-f]+"'

verify_readme() {
	local script="$SRC/tools/update-readme.sh"
	[[ -f "$script" && -f "$ROOT/README.md" && -f "$ROOT/meta.ini" ]] || return 0
	local tmpdir ver
	tmpdir="$(mktemp -d)"
	cp "$ROOT/README.md" "$tmpdir/README.md"
	ver="$(grep -E '^version=' "$ROOT/meta.ini" | head -1 | cut -d= -f2 | tr -d '[:space:]')"
	bash "$script" "$tmpdir" "$ver"
	cmp -s "$tmpdir/README.md" "$ROOT/README.md" || { rm -rf "$tmpdir"; return 1; }
	rm -rf "$tmpdir"
	return 0
}

sync_readme() {
	local script="$SRC/tools/update-readme.sh"
	[[ -f "$script" && -f "$ROOT/README.md" && -f "$ROOT/meta.ini" ]] || return 0
	local before ver
	before="$(mktemp)"
	cp "$ROOT/README.md" "$before"
	ver="$(grep -E '^version=' "$ROOT/meta.ini" | head -1 | cut -d= -f2 | tr -d '[:space:]')"
	bash "$script" "$ROOT" "$ver"
	if ! cmp -s "$before" "$ROOT/README.md"; then
		rm -f "$before"
		return 1
	fi
	rm -f "$before"
	return 0
}

sync_universal() {
	local pair src_rel dest_rel src_path dest_path
	for pair in "${UNIVERSAL_PAIRS[@]}"; do
		src_rel="${pair%%:*}"
		dest_rel="${pair#*:}"
		src_path="$SRC/$src_rel"
		dest_path="$ROOT/$dest_rel"
		[[ -f "$src_path" ]] || { echo "sync-dorn-common: missing ${src_path}" >&2; return 1; }
		mkdir -p "$(dirname "$dest_path")"
		if [[ ! -f "$dest_path" ]] || ! cmp -s "$src_path" "$dest_path"; then
			cp "$src_path" "$dest_path"
			return 2
		fi
	done
	return 0
}

verify_universal() {
	local pair src_rel dest_rel src_path dest_path
	for pair in "${UNIVERSAL_PAIRS[@]}"; do
		src_rel="${pair%%:*}"
		dest_rel="${pair#*:}"
		src_path="$SRC/$src_rel"
		dest_path="$ROOT/$dest_rel"
		cmp -s "$src_path" "$dest_path" || return 1
	done
	return 0
}

verify_install() {
	local src_scripts="$SRC/gamedata/scripts"
	local tmp

	tmp="$(mktemp)"
	expected_mcm "$tmp"
	cmp -s "$tmp" "$(dest_script dorn_mcm)" || { rm -f "$tmp"; return 1; }
	rm -f "$tmp"

	for name in dorn_dbg dorn_sys; do
		cmp -s "$src_scripts/${name}.script" "$(dest_script "$name")" || return 1
	done

	tmp="$(mktemp)"
	expected_loader "$tmp"
	cmp -s "$tmp" "$(dest_script dorn_common)" || { rm -f "$tmp"; return 1; }
	rm -f "$tmp"

	cmp -s "$SRC/gamedata/textures/dorn_mcm_banner.dds" "$(dest_banner)" || return 1
	cmp -s "$SRC/tools/githooks/pre-commit" "$GITHOOKS/pre-commit" || return 1
	verify_universal || return 1
	verify_readme || return 1

	while IFS= read -r -d '' f; do
		grep -Eq "$VERSION_RE" "$f" || continue
		grep -Eq "\"dorn_common_${COMMIT}\"" "$f" || return 1
	done < <(find "$SCRIPTS" -type f -name '*.script' -print0)
	return 0
}

if [[ "$CHECK_ONLY" == "1" ]]; then
	if verify_install; then
		echo "sync-dorn-common: ok (${COMMIT})"
		exit 0
	fi
	echo "sync-dorn-common: out of date — run: bash <path>/sync-dorn-common.sh" >&2
	exit 1
fi

UPDATED=0

mkdir -p "$SCRIPTS" "$TEXTURES" "$TEXT_ENG" "$GITHOOKS" "$VSCODE" "$GITHUB_WF"

while IFS= read -r old; do
	[[ -n "$old" ]] && { rm -rf "$old"; UPDATED=1; }
done < <(find "$SCRIPTS" -maxdepth 1 -type d -name 'common_*' 2>/dev/null || true)
while IFS= read -r old; do
	[[ -n "$old" ]] && { rm -f "$old"; UPDATED=1; }
done < <(find "$SCRIPTS" -maxdepth 1 -type f -name '*_common.script' 2>/dev/null || true)
for name in dorn_mcm dorn_dbg dorn_sys dorn_common; do
	while IFS= read -r old; do
		if [[ -n "$old" && "$old" != "$(dest_script "$name")" ]]; then
			rm -f "$old"
			UPDATED=1
		fi
	done < <(find "$SCRIPTS" -maxdepth 1 -type f -name "${name}_*.script" 2>/dev/null || true)
done
while IFS= read -r old; do
	if [[ -n "$old" && "$old" != "$(dest_banner)" ]]; then
		rm -f "$old"
		UPDATED=1
	fi
done < <(find "$TEXTURES" -maxdepth 1 -type f -name 'dorn_mcm_banner_*.dds' 2>/dev/null || true)
while IFS= read -r old; do
	if [[ -n "$old" ]]; then
		rm -f "$old"
		UPDATED=1
	fi
done < <(find "$TEXTURES" -maxdepth 1 -type f -name 'dorn_mcm_banner.dds' 2>/dev/null || true)
while IFS= read -r old; do
	if [[ -n "$old" ]]; then
		rm -f "$old"
		UPDATED=1
	fi
done < <(find "$TEXT_ENG" -maxdepth 1 -type f -name 'ui_mcm_dorn_common_*.xml' 2>/dev/null || true)
while IFS= read -r old; do
	if [[ -n "$old" ]]; then
		rm -f "$old"
		UPDATED=1
	fi
done < <(find "$TEXT_ENG" -maxdepth 1 -type f -name 'ui_mcm_dorn_common.xml' 2>/dev/null || true)

MCM_TMP="$(mktemp)"
expected_mcm "$MCM_TMP"
MCM_DST="$(dest_script dorn_mcm)"
if [[ ! -f "$MCM_DST" ]] || ! cmp -s "$MCM_TMP" "$MCM_DST"; then
	mv "$MCM_TMP" "$MCM_DST"
	UPDATED=1
else
	rm -f "$MCM_TMP"
fi

for name in dorn_dbg dorn_sys; do
	src="$SRC/gamedata/scripts/${name}.script"
	dst="$(dest_script "$name")"
	if [[ ! -f "$dst" ]] || ! cmp -s "$src" "$dst"; then
		cp "$src" "$dst"
		UPDATED=1
	fi
done

LOADER_TMP="$(mktemp)"
expected_loader "$LOADER_TMP"
LOADER_DST="$(dest_script dorn_common)"
if [[ ! -f "$LOADER_DST" ]] || ! cmp -s "$LOADER_TMP" "$LOADER_DST"; then
	mv "$LOADER_TMP" "$LOADER_DST"
	UPDATED=1
else
	rm -f "$LOADER_TMP"
fi

BANNER_SRC="$SRC/gamedata/textures/dorn_mcm_banner.dds"
BANNER_DST="$(dest_banner)"
if [[ ! -f "$BANNER_DST" ]] || ! cmp -s "$BANNER_SRC" "$BANNER_DST"; then
	cp "$BANNER_SRC" "$BANNER_DST"
	UPDATED=1
fi

HOOK_SRC="$SRC/tools/githooks/pre-commit"
HOOK_DST="$GITHOOKS/pre-commit"
if [[ ! -f "$HOOK_DST" ]] || ! cmp -s "$HOOK_SRC" "$HOOK_DST"; then
	cp "$HOOK_SRC" "$HOOK_DST"
	chmod +x "$HOOK_DST"
	UPDATED=1
fi

sync_rc=0
sync_universal || sync_rc=$?
if [[ "$sync_rc" == "2" ]]; then
	UPDATED=1
elif [[ "$sync_rc" != "0" ]]; then
	exit "$sync_rc"
fi

while IFS= read -r -d '' f; do
	grep -Eq "$VERSION_RE" "$f" || continue
	grep -Eq "\"dorn_common_${COMMIT}\"" "$f" && continue
	sed -i -E "s/${VERSION_RE}/DORN_COMMON_VERSION = \"dorn_common_${COMMIT}\"/" "$f"
	UPDATED=1
	echo "sync-dorn-common: bumped DORN_COMMON_VERSION -> dorn_common_${COMMIT} in ${f#"$ROOT"/}"
done < <(find "$SCRIPTS" -type f -name '*.script' -print0)

PATCH_SCRIPT="$SRC/tools/patch-dorn-mcm-banner.sh"
if [[ -x "$PATCH_SCRIPT" ]]; then
	if "$PATCH_SCRIPT" "$ROOT" "$COMMIT"; then
		UPDATED=1
	fi
fi

if ! sync_readme; then
	UPDATED=1
	echo "sync-dorn-common: updated README mod-list footer"
fi

echo "sync-dorn-common: ${COMMIT} (source: ${SRC})"
if [[ "$UPDATED" == "1" ]]; then
	echo "sync-dorn-common: updated — git add .editorconfig .gitattributes .gitignore .github/workflows/release.yml .vscode README.md gamedata/scripts gamedata/textures githooks/pre-commit"
fi
exit 0
