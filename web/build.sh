#!/usr/bin/env bash
# The web page that runs Sprig Linux in a browser (GitHub Pages: .github/workflows/pages.yml), from a release's
# files: tiny386's WebAssembly build (its wasm/ port, compiled with zig: no browser-side toolchain) beside the
# release's graphics-console kernel, loader and root file system, which the page downloads and runs.
#
#   web/build.sh <directory with bzImage-fb, linuxstart.bin, root.img.gz> <version>   -> web/site/
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
WORK=${WORK:-$HERE/work}
REL=$(cd "$1" && pwd) VER=$2
SITE=$HERE/web/site
mkdir -p "$WORK"
cd "$WORK"
. "$HERE/tools/fetch.sh"
use_zig
fetch_tiny386

# tiny386's wasm/ port, as its Makefile builds it, compiled and linked by zig; without its sound chip's synthesis
# (fmopl.c, LGPL: the page has no sound, and the AdLib card stays silent), so all of it is under
# permissive licences (BSD-3-Clause, MIT)
T=$WORK/tiny386-$TINY386/wasm
mapfile -t SRCS < <(sed -n '/^SRCS/,/^$/p' "$T/Makefile" | tr -d '\\' | tr -s ' \t' '\n' | grep '\.c$' |
  grep -v fmopl)
rm -rf "$WORK/wasm-build" && mkdir -p "$WORK/wasm-build"
pids=()
for s in "${SRCS[@]}"; do
  zig cc --target=wasm32-freestanding -O3 -nostdlib -fno-builtin -ffunction-sections -fdata-sections -I "$T/libc" \
    -DI386_ENABLE_FPU -DI386_ENABLE_MMX -DI386_ENABLE_SSE -DI386_ENABLE_SSE2 -DI386_ENABLE_SSE3 -DI386_ENABLE_SSSE3 \
    -ffile-prefix-map="$WORK/"= -w -c "$T/$s" -o "$WORK/wasm-build/$(basename "$s" .c).o" & pids+=($!)
done
for p in "${pids[@]}"; do wait "$p"; done   # (each, so that a failed compile stops the build)
rm -rf "$SITE" && mkdir -p "$SITE"
zig wasm-ld --gc-sections --export-dynamic --no-entry --strip-all --allow-undefined -o "$SITE/tiny386.wasm" \
  "$WORK"/wasm-build/*.o

# the page, and the release's files it runs
cp "$HERE"/web/{index.html,sprig.js,sprig.svg} "$SITE/"
cp "$REL"/{bzImage-fb,linuxstart.bin,root.img.gz} "$SITE/"
cp "$WORK/tiny386-$TINY386/LICENSE" "$SITE/tiny386-LICENSE.txt"
size() { stat -c %s "$SITE/$1"; }
cat > "$SITE/sprig-files.js" <<EOF
// written by web/build.sh: the version shown, and the downloads' sizes (for the progress bar)
const SPRIG = { version: '${VER#v}', sizes: { 'tiny386.wasm': $(size tiny386.wasm), 'linuxstart.bin': $(size linuxstart.bin),
  'bzImage-fb': $(size bzImage-fb), 'root.img.gz': $(size root.img.gz) } };
EOF
touch "$SITE/.nojekyll"
du -sh "$SITE"
