#!/usr/bin/env bash
# Patches feature-mod on_mcm_load scripts to use dorn_mcm.with_header().
# Invoked from sync-dorn-common.sh after common assets are synced.
set -euo pipefail

ROOT="${1:?patch-dorn-mcm-banner: missing target mod root}"
COMMIT="${2:?patch-dorn-mcm-banner: missing common commit}"

SCRIPTS="$ROOT/gamedata/scripts"
[[ -d "$SCRIPTS" ]] || exit 0

PREAMBLE_BEGIN='-- dorn_mcm_banner:begin (managed by sync-dorn-common.sh)'
PREAMBLE_END='-- dorn_mcm_banner:end'

patch_file() {
	local file="$1"
	local before
	before="$(mktemp)"
	cp "$file" "$before"
	perl -0777 -i -pe "
		s/\r\n/\n/g;
		my \$commit = '$COMMIT';
		my \$begin = quotemeta('$PREAMBLE_BEGIN');
		my \$end = quotemeta('$PREAMBLE_END');
		my \$block = \"$PREAMBLE_BEGIN\\n\"
			. \"local DORN_COMMON_VERSION = \\\"dorn_common_\$commit\\\"\\n\"
			. \"local function dorn_mcm()\\n\"
			. \"\\tlocal hash = DORN_COMMON_VERSION:match(\\\"dorn_common_(.+)\\\$\\\")\\n\"
			. \"\\treturn _G[\\\"dorn_mcm_\\\" .. hash]\\n\"
			. \"end\\n\"
			. \"$PREAMBLE_END\";

		if (/\$begin.*?\$end/s) {
			s/\$begin.*?\$end/\$block/s;
		} else {
			while (s/\\n?local DORN_COMMON_VERSION = \"dorn_common_[0-9a-f]+\"[^\n]*\n+local function dorn_mcm\(\)\n\tlocal hash = DORN_COMMON_VERSION:match\([^\n]+\)\n\treturn _G\[[^\n]+\]\nend\n+/\n/) {}
			s/\\A\\n+//;
			if (/\A((?:--[^\n]*\n)+)(?!local |function )/s) {
				my \$comments = \$1;
				s/\A\Q\$comments\E/\$comments\$block\n\n/;
			} else {
				s/\A/\$block\n\n/;
			}
		}

		s/\n{3,}/\n\n/g;

		unless (/local MCM = dorn_mcm\(\)/) {
			s/function on_mcm_load\(\)\n/function on_mcm_load()\n\tlocal MCM = dorn_mcm()\n/;
		}

		unless (/MCM\\.with_header\\(/) {
			s/(\\n\\t\\t\\t\\tsh = true,\\n(?:\\t\\t\\t\\ttext = [^\\n]+,\\n)?\\t\\t\\t\\t)gr = \\{/\$1gr = MCM.with_header({/g;
		}
		while (s/(gr = MCM\\.with_header\\(\\{[\\s\\S]*?)\\n\\t\\t\\t\\t\\},\\n(\\t\\t\\t\\},)/\$1\\n\\t\\t\\t\\t\\}),\\n\$2/) {}
	" "$file"
	if cmp -s "$before" "$file"; then
		rm -f "$before"
		return 1
	fi
	rm -f "$before"
	return 0
}

CHANGED=0
while IFS= read -r -d '' file; do
	base="$(basename "$file")"
	case "$base" in
		dorn_mcm_*.script|dorn_common_*.script|dorn_dbg_*.script|dorn_sys_*.script) continue ;;
	esac
	grep -q 'function on_mcm_load' "$file" || continue
	if patch_file "$file"; then
		CHANGED=1
		echo "patch-dorn-mcm-banner: ${file#"$ROOT"/}"
	fi
done < <(find "$SCRIPTS" -maxdepth 1 -type f -name '*.script' -print0)

exit $CHANGED
