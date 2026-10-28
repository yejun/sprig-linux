# What build.sh and extras.sh share (sourced): downloads, zig, patches, release checks.
#
# Downloads: each archive kept in $WORK/dl, checked against its SHA-256, and unpacked into the current directory
# once (with RELEASE=1 always anew). $WORK/dl is what package.sh puts in the release's sources; with the archives
# already there (an unpacked sources release) nothing is downloaded.
mkdir -p "$WORK/dl"
fetch() {   # fetch <url> <the directory it unpacks to> <sha256>
  local f=$WORK/dl/${1##*/}
  [[ -f $f ]] || { curl -sSfL -o "$f.part" "$1" && mv "$f.part" "$f"; }
  echo "$3  $f" | sha256sum -c --quiet - || { echo "$f is not the archive expected (SHA-256)" >&2; exit 1; }
  [[ "${RELEASE:-}" == 1 ]] && rm -rf "./${2:?}"
  [[ -d $2 ]] || tar -xf "$f"
}
fetch_git() {   # fetch_git <repository> <commit> <name>: the commit's files in <name>-<commit>, its archive in $WORK/dl
  local f=$WORK/dl/$3-$2.tar.gz t
  if [[ ! -f $f ]]; then
    t=$(mktemp -d)
    git init -q "$t" && git -C "$t" fetch -q --depth 1 "$1" "$2" &&
      [[ "$(git -C "$t" rev-parse FETCH_HEAD)" == "$2" ]] &&
      git -C "$t" archive --prefix="$3-$2/" -o "$f" FETCH_HEAD
    rm -rf "${t:?}"
  fi
  [[ "${RELEASE:-}" == 1 ]] && rm -rf "./$3-${2:?}"
  [[ -d $3-$2 ]] || tar -xzf "$f"
}

# zig, pinned: it compiles everything for the guest, and its musl and compiler-rt are linked into every program (so
# its archive is among the sources too)
ZIG=0.17.0
use_zig() {
  (cd "$WORK" && fetch "https://ziglang.org/download/$ZIG/zig-x86_64-linux-$ZIG.tar.xz" zig-x86_64-linux-$ZIG \
    1cbe9df9f27e6b78d14ccbca43b6703a404ef79ef1c463de901d7f088d4e2026)
  export PATH="$WORK/zig-x86_64-linux-$ZIG:$PATH"
}

# A patch is applied, or found already applied (it reverses cleanly); anything else stops the build
apply_patches() {   # apply_patches <tree> <patch files...>
  local d=$1 p; shift
  for p in "$@"; do
    if patch -d "$d" -p1 -s -N --dry-run < "$p" >/dev/null 2>&1; then
      patch -d "$d" -p1 -s -N < "$p"
    elif ! patch -d "$d" -p1 -s -R --dry-run < "$p" >/dev/null 2>&1; then
      echo "$p doesn't apply to $d (and isn't applied already)" >&2
      exit 1
    fi
  done
}

# RELEASE=1: only from a clean checkout (what is built is what the sources archive holds)
release_check() {
  [[ "${RELEASE:-}" == 1 ]] || return 0
  if [[ -n "$(git -C "$HERE" status --porcelain)" ]]; then
    echo "RELEASE=1 needs a clean checkout (commit or stash the changes first)" >&2
    exit 1
  fi
}
