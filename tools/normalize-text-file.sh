#!/usr/bin/env bash
# Normalize a synced text file: LF endings, trim leading/trailing blank lines,
# strip trailing whitespace per line, exactly one trailing newline at EOF.
# Usage: normalize-text-file.sh SRC [DEST]
#   DEST omitted: overwrite SRC in place.
set -euo pipefail

SRC="${1:?normalize-text-file: missing source}"
DEST="${2:-$SRC}"

perl -0777 -e '
	use strict;
	use warnings;
	open my $in, "<:raw", $ARGV[0] or die "normalize-text-file: read $ARGV[0]: $!\n";
	local $/; my $text = <$in>; close $in;
	$text =~ s/\r\n/\n/g;
	$text =~ s/\A[ \t\r\n]+//s;
	$text =~ s/[ \t\r\n]+\z/\n/s;
	$text =~ s/[ \t]+$//gm;
	open my $out, ">:raw", $ARGV[1] or die "normalize-text-file: write $ARGV[1]: $!\n";
	print {$out} $text;
	close $out;
' "$SRC" "$DEST"
