#!/bin/sh
# Usage: go-licenses.sh <binary> <destination> [<extra>]
#
# Copies the license files of every Go module linked into <binary>, as listed
# by `go version -m`, from the module cache to <destination>/<module path>/,
# and the LICENSE and PATENTS files of the Go distribution that built it to
# <destination>/go-stdlib/. Run it in the build stage, in the main module's
# directory, with the go command and module cache that built the binary.
#
# <extra>/<module path>@<version>/ holds license files that the module itself
# lacks, such as those of the C sources it compiles in, laid out like the
# module: the files for a package go in the package's directory. They are
# copied next to the module's own. Each such directory must match a module
# version in the binary, and each cgo package that the binary links from that
# module needs a file in its directory, so the files are looked at again when
# the dependency changes.
#
# Any other package outside the standard library and the main module that
# compiles C sources stops the script, unless the module's own license files
# cover those sources and <extra>/cgo-covered lists <module path>@<version> on
# a line of its own. Each version listed there must be in the binary too.
set -eu

bin=$1
dest=$2
extra=${3:-}

modcache=$(go env GOMODCACHE)
goroot=$(go env GOROOT)
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

: > "$work/used"
while read -r mod ver; do
  if [ -z "$ver" ]; then
    echo "$mod has no version (a local replacement?)" >&2
    exit 1
  fi
  src="$modcache/$(escape "$mod")@$(escape "$ver")"
  test -d "$src" || { echo "$mod $ver is not in the module cache" >&2; exit 1; }
  out="$dest/$mod"
  mkdir -p "$out"
  for f in "$src"/*; do
    case ${f##*/} in
      [Ll][Ii][Cc][Ee][Nn][CcSs][Ee]* | [Cc][Oo][Pp][Yy][Ii][Nn][Gg]* | \
      [Nn][Oo][Tt][Ii][Cc][Ee]* | [Pp][Aa][Tt][Ee][Nn][Tt][Ss]*)
        if [ -f "$f" ]; then cp "$f" "$out/"; fi
        ;;
    esac
  done
  if [ -n "$extra" ] && [ -d "$extra/$mod@$ver" ]; then
    cp -R "$extra/$mod@$ver/." "$out/"
    echo "$mod@$ver" >> "$work/used"
  fi
  # Only files count: the directory can also hold package directories from
  # <extra>, or the directory of a module whose path starts with this one.
  found=
  for f in "$out"/*; do
    if [ -f "$f" ]; then found=1; fi
  done
  if [ -z "$found" ]; then
    echo "$mod $ver has no license file${extra:+; add it to $extra/$mod@$ver/}" >&2
    exit 1
  fi
done < "$work/modules"

: > "$work/covered"
if [ -n "$extra" ]; then
  find "$extra" -type d -name '*@*' > "$work/extra"
  while read -r dir; do
    key=${dir#"$extra"/}
    if ! grep -Fqx "$key" "$work/used"; then
      echo "$dir: $bin does not link this module version" >&2
      exit 1
    fi
  done < "$work/extra"

  if [ -f "$extra/cgo-covered" ]; then
    sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' "$extra/cgo-covered" > "$work/covered"
    while read -r key; do
      if ! awk -v key="$key" '$1 "@" $2 == key { found = 1 } END { exit !found }' "$work/modules"; then
        echo "$extra/cgo-covered: $bin does not link $key" >&2
        exit 1
      fi
    done < "$work/covered"
  fi
fi

# One line per package with C sources: the module path it is imported under,
# then the path and version of the module that was compiled, which differ when
# go.mod replaces the module, then the package.
main=$(go version -m "$bin" | awk -F '\t' '$2 == "path" { print $3; exit }')
go list -deps -f '{{if .CgoFiles}}{{with .Module}}{{if not .Main}}{{.Path}} {{with .Replace}}{{.Path}} {{.Version}}{{else}}{{.Path}} {{.Version}}{{end}} {{$.ImportPath}}{{end}}{{end}}{{end}}' "$main" \
  > "$work/cgo"
while read -r path mod ver pkg; do
  if [ -z "$pkg" ] || grep -Fqx "$mod@$ver" "$work/covered"; then continue; fi
  dir="${extra:-<extra>}/$mod@$ver${pkg#"$path"}"
  found=
  if grep -Fqx "$mod@$ver" "$work/used"; then
    for f in "$dir"/*; do
      if [ -f "$f" ]; then found=1; fi
    done
  fi
  if [ -z "$found" ]; then
    echo "$pkg compiles C sources; add their license to $dir/, or list $mod@$ver in ${extra:-<extra>}/cgo-covered if the module's license covers them" >&2
    exit 1
  fi
done < "$work/cgo"

mkdir -p "$dest/go-stdlib"
cp "$goroot/LICENSE" "$goroot/PATENTS" "$dest/go-stdlib/"
find "$dest" -type d -exec chmod 0755 {} \;
find "$dest" -type f -exec chmod 0644 {} \;
