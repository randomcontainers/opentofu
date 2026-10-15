#!/bin/sh
# Usage: mpl-sources.sh <binary> <destination>
#
# Copies the source of every Go module linked into <binary> that is licensed
# under the Mozilla Public License 2.0 to <destination>/<module path>@<version>.zip
# and prints each of those file names, relative to <destination>, on a line of
# its own. A module counts when a license file at its root contains the MPL 2.0
# text. The zip is the one the go command downloaded from the module proxy
# into the module cache, so run the script in the build stage after
# `go mod verify`, which checks the cache against go.sum.
#
# MPL 2.0 section 3.2 asks that whoever distributes a binary built from MPL
# files also makes their source available; these zips carry it in the image.
set -eu

bin=$1
dest=$2

modcache=$(go env GOMODCACHE)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Module paths and versions are stored in the cache with each capital letter
# written as ! and the lower-case letter.
upper=ABCDEFGHIJKLMNOPQRSTUVWXYZ
lower=abcdefghijklmnopqrstuvwxyz
escape() {
  printf '%s\n' "$1" | sed "s/[$upper]/!&/g" | tr "$upper" "$lower"
}

# A replaced module is listed as a dep line followed by its => line, and the
# replacement is what was compiled.
go version -m "$bin" | awk -F '\t' '
  $2 == "dep" { if (m != "") print m, v; m = $3; v = $4; next }
  $2 == "=>" { m = $3; v = $4; next }
  END { if (m != "") print m, v }
' > "$work/modules"
test -s "$work/modules" || { echo "$bin lists no modules" >&2; exit 1; }

while read -r mod ver; do
  src="$modcache/$(escape "$mod")@$(escape "$ver")"
  test -d "$src" || { echo "$mod $ver is not in the module cache" >&2; exit 1; }
  mpl=
  for f in "$src"/*; do
    case ${f##*/} in
      [Ll][Ii][Cc][Ee][Nn][CcSs][Ee]* | [Cc][Oo][Pp][Yy][Ii][Nn][Gg]*)
        if [ -f "$f" ] && grep -Eq 'Mozilla Public License,? [Vv]ersion 2\.0' "$f"; then mpl=1; fi
        ;;
    esac
  done
  if [ -z "$mpl" ]; then continue; fi
  zip="$modcache/cache/download/$(escape "$mod")/@v/$(escape "$ver").zip"
  test -f "$zip" || { echo "$mod $ver: $zip is missing" >&2; exit 1; }
  mkdir -p "$dest/${mod%/*}"
  cp "$zip" "$dest/$mod@$ver.zip"
  echo "$mod@$ver.zip"
done < "$work/modules"

if [ -d "$dest" ]; then
  find "$dest" -type d -exec chmod 0755 {} \;
  find "$dest" -type f -exec chmod 0644 {} \;
fi
