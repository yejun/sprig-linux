# Downloads for build.sh and extras.sh (sourced): each archive kept in $WORK/dl, where package.sh takes the release's
# sources from, and unpacked into the current directory once. With the archives already there (an unpacked sources
# release) nothing is downloaded.
mkdir -p "$WORK/dl"
fetch() {   # fetch <url> <the directory it unpacks to>
  local f=$WORK/dl/${1##*/}
  [[ -f $f ]] || { curl -sSfL -o "$f.part" "$1" && mv "$f.part" "$f"; }
  [[ -d $2 ]] || tar -xf "$f"
}
fetch_git() {   # fetch_git <repository> <commit> <name>: the commit's files in <name>-<commit>, its archive in $WORK/dl
  local f=$WORK/dl/$3-$2.tar.gz t
  if [[ ! -f $f ]]; then
    t=$(mktemp -d)
    git init -q "$t" && git -C "$t" fetch -q --depth 1 "$1" "$2" &&
      git -C "$t" archive --prefix="$3-$2/" -o "$f" FETCH_HEAD
    rm -rf "${t:?}"
  fi
  [[ -d $3-$2 ]] || tar -xzf "$f"
}
