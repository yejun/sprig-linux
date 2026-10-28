# What build.sh and extras.sh share (sourced): downloads, patches, zig, release checks.
#
# fetch <url> <the directory it unpacks to> <sha256> [patches...]: the archive is kept in $WORK/dl and checked against
# its SHA-256 (a copy there already that doesn't match is downloaded again), and unpacked into the current directory. A tree is patched only right
# after unpacking, with the whole series, every patch applying cleanly or the build stops; a stamp in it records the
# series, and a tree whose series differs (or that has none: an interrupted run, an older build) is unpacked anew.
# With RELEASE=1 every tree is unpacked anew. $WORK/dl is what package.sh puts in the release's sources; with the
# archives already there (an unpacked sources release) nothing is downloaded. Sources in git are taken as GitHub's
# archive of the pinned commit, pinned like the others.
mkdir -p "$WORK/dl"
fetch() {
  local url=$1 dir=$2 sum=$3 f=$WORK/dl/${1##*/} stamp=none p
  [[ $url == */archive/* ]] && f=$WORK/dl/$dir.tar.gz   # (GitHub's archive of a commit: <commit>.tar.gz)
  shift 3
  if [[ -f $f ]] && ! echo "$sum  $f" | sha256sum -c --quiet - >/dev/null 2>&1; then
    echo "$f isn't the archive expected (SHA-256): downloading it again" >&2   # (an old or damaged copy)
    rm -f "$f"
  fi
  [[ -f $f ]] || { curl -sSfL -o "$f.part" "$url" && mv "$f.part" "$f"; }
  echo "$sum  $f" | sha256sum -c --quiet - || { echo "$f is not the archive expected (SHA-256)" >&2; exit 1; }
  (($#)) && stamp=$(cat "$@" | sha256sum | cut -d' ' -f1)
  if [[ "${RELEASE:-}" == 1 || ! -d $dir || "$(cat "$dir/.sprig-patches" 2>/dev/null)" != "$stamp" ]]; then
    rm -rf "./${dir:?}"
    tar -xf "$f"
    for p in "$@"; do
      patch -d "$dir" -p1 -s -N < "$p" || { echo "$p doesn't apply to $dir" >&2; exit 1; }
    done
    echo "$stamp" > "$dir/.sprig-patches"
  fi
}

# zig, pinned: it compiles everything for the guest, and its musl and compiler-rt are linked into every program (so
# its archive is among the sources too)
ZIG=0.17.0
use_zig() {
  (cd "$WORK" && fetch "https://ziglang.org/download/$ZIG/zig-x86_64-linux-$ZIG.tar.xz" zig-x86_64-linux-$ZIG \
    1cbe9df9f27e6b78d14ccbca43b6703a404ef79ef1c463de901d7f088d4e2026)
  export PATH="$WORK/zig-x86_64-linux-$ZIG:$PATH"
}

# RELEASE=1: only from a clean git checkout (what is built is what the sources archive holds)
release_check() {
  [[ "${RELEASE:-}" == 1 ]] || return 0
  local st
  st=$(git -C "$HERE" status --porcelain) || { echo "RELEASE=1 needs a git checkout of this repository" >&2; exit 1; }
  [[ -z $st ]] || { echo "RELEASE=1 needs a clean checkout (commit or stash the changes first)" >&2; exit 1; }
}
