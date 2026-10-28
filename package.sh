#!/usr/bin/env bash
# Package a release into $REL (default ./release), after `RELEASE=1 ./extras.sh && RELEASE=1 FB=1 ./build.sh` from
# the same clean checkout: the two kernels, the loader, root.img gzipped, the settings, BUILDINFO (what it was built
# from and with), THIRD_PARTY_NOTICES.md and the licences (sprig-linux-<version>-licenses.tar.gz, as in the image's
# /usr/share/licenses), SHA256SUMS, and the sources: sprig-linux-<version>-sources.tar holds this repository and every
# archive the build used (work/dl, zig's too), so it builds again without a network. Stops if a path of this computer
# is in the images.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$HERE/work}
OUT=${OUT:-$HERE/out}
REL=${REL:-$HERE/release}
VERSION=${VERSION:-$(git -C "$HERE" describe --tags --always)}
FILES=(bzImage bzImage-fb linuxstart.bin tiny386-linux.ini tiny386-linux-fb.ini BUILDINFO)
for f in "${FILES[@]}" root.img; do
  [[ -f $OUT/$f ]] || { echo "$OUT/$f is missing: run RELEASE=1 ./extras.sh and RELEASE=1 FB=1 ./build.sh" >&2; exit 1; }
done

# the images are from this commit, unchanged, with every source unpacked anew (what the sources archive holds)
[[ -z "$(git -C "$HERE" status --porcelain)" ]] || { echo "the checkout has local changes" >&2; exit 1; }
grep -qx "commit: $(git -C "$HERE" rev-parse HEAD)" "$OUT/BUILDINFO" &&
  grep -qx "release: 1   graphics console: 1" "$OUT/BUILDINFO" ||
  { echo "out/ isn't a RELEASE=1 FB=1 build of this commit (BUILDINFO)" >&2; exit 1; }

# no path of this computer in the root file system or the kernel (it happened: the kernel's version string, tcc's
# debug sections)
t=$(mktemp -d)
debugfs -R "rdump / $t" "$OUT/root.img" >/dev/null 2>&1
if grep -rlaF -e "$HOME" -e "$HERE" "$t" "$WORK"/linux-*/vmlinux; then
  echo "these files hold paths of this computer" >&2
  rm -rf "${t:?}"
  exit 1
fi

rm -rf "${REL:?}" && mkdir -p "$REL"
S=sprig-linux-$VERSION
for f in "${FILES[@]}"; do cp "$OUT/$f" "$REL/"; done
cp "$HERE/THIRD_PARTY_NOTICES.md" "$REL/"
gzip -9 -n -c "$OUT/root.img" > "$REL/root.img.gz"
tar -czf "$REL/$S-licenses.tar.gz" --owner=0 --group=0 --sort=name -C "$t/usr/share" --transform "s|^licenses|$S-licenses|" licenses
rm -rf "${t:?}"
git -C "$HERE" archive --prefix="$S/" -o "$REL/$S-sources.tar" HEAD
tar -rf "$REL/$S-sources.tar" --owner=0 --group=0 --sort=name --transform "s|^|$S/work/|" -C "$WORK" dl
(cd "$REL" && sha256sum -- * > SHA256SUMS)
ls -l "$REL"
