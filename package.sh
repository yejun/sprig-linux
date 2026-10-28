#!/usr/bin/env bash
# Package a release into $REL (default ./release), after `./extras.sh && FB=1 ./build.sh`: the two kernels, the
# loader, root.img gzipped, the settings, SHA256SUMS, and the sources: sprig-linux-<version>-sources.tar holds this
# repository and every archive the build downloaded (work/dl), so it builds again without a network. Stops if a path
# of this computer is in the images.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$HERE/work}
OUT=${OUT:-$HERE/out}
REL=${REL:-$HERE/release}
VERSION=${VERSION:-$(git -C "$HERE" describe --tags --always --dirty)}
FILES=(bzImage bzImage-fb linuxstart.bin tiny386-linux.ini tiny386-linux-fb.ini)
for f in "${FILES[@]}" root.img; do
  [[ -f $OUT/$f ]] || { echo "$OUT/$f is missing: run ./extras.sh and FB=1 ./build.sh first" >&2; exit 1; }
done

# no path of this computer in the root file system or the kernel (it happened: the kernel's version string, tcc's
# debug sections)
t=$(mktemp -d)
debugfs -R "rdump / $t" "$OUT/root.img" >/dev/null 2>&1
if grep -rlaF -e "$HOME" -e "$HERE" "$t" "$WORK"/linux-*/vmlinux; then
  echo "these files hold paths of this computer" >&2
  rm -rf "${t:?}"
  exit 1
fi
rm -rf "${t:?}"

rm -rf "${REL:?}" && mkdir -p "$REL"
for f in "${FILES[@]}"; do cp "$OUT/$f" "$REL/"; done
gzip -9 -n -c "$OUT/root.img" > "$REL/root.img.gz"
S=sprig-linux-$VERSION
git -C "$HERE" archive --prefix="$S/" -o "$REL/$S-sources.tar" HEAD
tar -rf "$REL/$S-sources.tar" --owner=0 --group=0 --transform "s|^|$S/work/|" -C "$WORK" dl
(cd "$REL" && sha256sum -- * > SHA256SUMS)
ls -l "$REL"
