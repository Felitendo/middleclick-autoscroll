#!/usr/bin/env bash
#
# Builds the binary package for Debian, Ubuntu and their derivatives into
# dist/.
#
# Everything the package contains comes out of `make install`. This only wraps
# what that produced, so there is exactly one description of where a file goes
# and it is the Makefile - a packaging script that lists the files again is a
# second description, and the two drift.
#
# Needs: make, dpkg-deb, msgfmt (gettext), scdoc.

set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:-$(make -s -C "$here" version)}"
name=middleclick-autoscroll

# A package without its man page or its translations is not a package this
# should be quietly willing to produce: the Makefile skips both when the tools
# are missing, and the result would look like a successful build.
for tool in msgfmt scdoc dpkg-deb; do
	command -v "$tool" > /dev/null || { echo "$0: $tool is not installed" >&2; exit 1; }
done

root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT

make -C "$here" install \
	DESTDIR="$root" \
	PREFIX=/usr \
	VERSION="$version" \
	USERUNITDIR=/usr/lib/systemd/user

install -d "$root/DEBIAN"
sed "s|@VERSION@|$version|g" "$here/packaging/deb/control" > "$root/DEBIAN/control"
install -Dm644 "$here/packaging/deb/copyright" \
	"$root/usr/share/doc/$name/copyright"

# Relative to the package root, and DEBIAN/ itself is not part of the contents.
# Sorted in the C locale so the file comes out the same whatever the locale of
# the machine that built it.
( cd "$root" && find . -type f ! -path './DEBIAN/*' -printf '%P\0' \
	| LC_ALL=C sort -z | xargs -0 md5sum > DEBIAN/md5sums )

mkdir -p "$here/dist"
out="$here/dist/${name}_${version}_all.deb"
dpkg-deb --root-owner-group --build "$root" "$out" > /dev/null

echo "$out"
