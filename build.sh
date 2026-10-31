#!/usr/bin/env bash
# Build Sprig Linux: a kernel (bzImage), tiny386's loader (linuxstart.bin) and an ext4 root file system with BusyBox
# and the programs from extras.sh if it has run (root.img), in $OUT (default ./out):  ./build.sh   (FB=1: the graphics
# console too). Needs: gcc (-m32), make, flex, bison, bc, libelf, git, curl, fakeroot, mke2fs (e2fsprogs); zig is
# downloaded. Sources are downloaded into $WORK/dl (default ./work). See README.md.
# RELEASE=1 (for package.sh): from a clean checkout, every source unpacked anew, after RELEASE=1 ./extras.sh.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$HERE/work}
OUT=${OUT:-$HERE/out}
KVER=7.3.1
BBVER=1.37.0
TINY386=003c2666dfe665e1068917af69a99afed1f0f70f   # tiny386 (github.com/hchunhui/tiny386): its loader
export KBUILD_BUILD_USER=sprig KBUILD_BUILD_HOST=sprig-linux   # (in the kernel's version string, not this computer's)
mkdir -p "$WORK"
cd "$WORK"
command -v bc >/dev/null || { echo "bc is missing (the kernel build needs it)" >&2; exit 1; }
. "$HERE/tools/fetch.sh"
release_check
if [[ "${RELEASE:-}" == 1 ]]; then   # the programs from extras.sh: built the same way, from this commit
  [[ "$(cat extras.info 2>/dev/null)" == "release $(git -C "$HERE" rev-parse HEAD)" ]] ||
    { echo "run RELEASE=1 ./extras.sh first (from this commit)" >&2; exit 1; }
  rm -rf "${OUT:?}"
fi
mkdir -p "$OUT"
use_zig
fetch "https://cdn.kernel.org/pub/linux/kernel/v${KVER%%.*}.x/linux-$KVER.tar.xz" linux-$KVER \
  fa595aad93734f829c963c2a90ef7c3673224fd7fdae7b49406e397cde2de231 "$HERE"/patches/*.patch
fetch "https://busybox.net/downloads/busybox-$BBVER.tar.bz2" busybox-$BBVER \
  3311dff32e746499f4df0d5df04d7eb396382d7e108bb9250e7b519b837043a4 "$HERE"/busybox-patches/*.patch
fetch https://github.com/hchunhui/tiny386/archive/$TINY386.tar.gz tiny386-$TINY386 \
  43c890663beffb39de2d6ee3950e03e9ce92c5f74ae503f17656728532236532

# kernel: tinyconfig + what tiny386 has (tiny386.config); with FB=1 also a variant with a graphics console and the boot
# logo (fb.config: bzImage-fb + tiny386-linux-fb.ini), built first in the same tree
kernel() {   # kernel <output name> <config fragments...>
  local name=$1; shift
  make -C linux-$KVER ARCH=i386 tinyconfig >/dev/null
  (cd linux-$KVER && scripts/kconfig/merge_config.sh -m .config "$@" >/dev/null)
  make -C linux-$KVER ARCH=i386 olddefconfig >/dev/null
  make -C linux-$KVER ARCH=i386 -j"$(nproc)" bzImage >/dev/null
  cp linux-$KVER/arch/x86/boot/bzImage "$OUT/$name"
}
[[ "${FB:-}" == 1 ]] && kernel bzImage-fb "$HERE/tiny386.config" "$HERE/fb.config"
kernel bzImage "$HERE/tiny386.config"

# tiny386's loader (linuxstart). The graphics variant asks it for a VBE mode with vga=0x303 (800x600 with 256
# colours; tiny386 since 003c266): it sets the mode and describes the linear frame buffer to the kernel for vesafb;
# the machine needs 1 MB of video memory for it (vga_mem_size), a display that large ([display]: tiny386 on a
# computer shows 720x480 otherwise and the loader keeps the text console; the Tab5 PC sizes its own), and
# video=vesafb:ypan scrolls by panning (patches/0003)
rm -rf ls-build && cp -r tiny386-$TINY386/linuxstart ls-build
make -s -C ls-build linuxstart.bin
cp ls-build/linuxstart.bin "$OUT/"
if [[ "${FB:-}" == 1 ]]; then
  { sed -e 's|^kernel = .*|kernel = /sdcard/linux/bzImage-fb|' \
        -e 's|^\(cmdline = .*\)|\1 vga=0x303 video=vesafb:ypan|' -e 's|^vga_mem_size = .*|vga_mem_size = 1M|' \
        "$HERE/tiny386-linux.ini"
    printf '\n[display]\nwidth = 800\nheight = 600\n'; } > "$OUT/tiny386-linux-fb.ini"
fi

# BusyBox, static, i386 + musl (tools/zcc: zig cc), Pentium instructions; tc doesn't build with current kernel headers.
# Zig's libc, built for size with a program built for size (as BusyBox is), copies, fills and measures strings a byte
# at a time: the link at -O2 instead (ZCC_LINK_O2: tools/zcc; BusyBox's own code stays -Os), and memcpy, memmove,
# memset and strlen from tools/string-i386.S (REP MOVSD and STOSD, which the Tab5's emulator does in bulk). Its
# object goes into the final link alone (CONFIG_EXTRA_LDLIBS; an archive would not be searched: zig's compiler-rt
# defines them already, weak). The Sprig workload on the Tab5 (3x ls -lR /, nano, htop, tcc): 81.7 -> 77.8 s.
"$HERE/tools/zcc" -c -o string-i386.o "$HERE/tools/string-i386.S"
(cd busybox-$BBVER && make -s defconfig >/dev/null &&
 sed -i -e 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/' -e 's/^CONFIG_TC=y/# CONFIG_TC is not set/' \
        -e "s|^CONFIG_EXTRA_LDLIBS=.*|CONFIG_EXTRA_LDLIBS=\"-Wl,$WORK/string-i386.o\"|" .config &&
 ZCC_LINK_O2=1 make -s -j"$(nproc)" CC="$HERE/tools/zcc" HOSTCC=gcc AR="zig ar" STRIP=strip >/dev/null)

# root file system, ext4 with a journal (the emulated PC is often reset or switched off while running): BusyBox (its
# applets linked at first boot), rootfs/ from here, a 16 MB swap file (filled, not zeros: the kernel refuses a swap
# file with holes, and mke2fs leaves zeros out); 4 KB blocks for the same reason
rm -rf root && mkdir -p root/{bin,sbin,usr/bin,usr/sbin,usr/share/udhcpc,proc,sys,dev,tmp,root,var/run,var/log,home,mnt}
cp -r "$HERE/rootfs/." root/
[[ -d "$WORK/extras" ]] && cp -a "$WORK/extras/." root/   # from extras.sh, if run
cp busybox-$BBVER/busybox root/bin/ && ln -s busybox root/bin/sh && ln -s ../bin/busybox root/sbin/init
mkdir -p root/etc/rc.d && ln -s ../../etc/init.d/sshd root/usr/sbin/sshd   # (services: sshd start / enable)
install -m 755 busybox-$BBVER/examples/udhcp/simple.script root/usr/share/udhcpc/default.script

# the licences of what is in the image (extras.sh adds its programs'), and of the loader beside it: in
# /usr/share/licenses, and package.sh puts them beside the release's files too
L=root/usr/share/licenses
install -D -m644 -t $L/linux linux-$KVER/COPYING linux-$KVER/LICENSES/preferred/GPL-2.0 \
  linux-$KVER/LICENSES/exceptions/Linux-syscall-note
install -D -m644 -t $L/busybox busybox-$BBVER/LICENSE
install -D -m644 -T zig-x86_64-linux-$ZIG/lib/libc/musl/COPYRIGHT $L/zig/musl-COPYRIGHT   # (linked into every
install -D -m644 -T zig-x86_64-linux-$ZIG/LICENSE $L/zig/LICENSE   # program: zig's musl and compiler-rt)
mkdir -p $L/linuxstart && sed -n '1,/\*\//p' tiny386-$TINY386/linuxstart/linuxstart.c > $L/linuxstart/LICENSE
install -D -m644 -T tiny386-$TINY386/LICENSE $L/tiny386/LICENSE

head -c 16M /dev/zero | tr '\0' '\125' > root/swapfile && chmod 600 root/swapfile && mkswap root/swapfile >/dev/null
rm -f "$OUT/root.img"
fakeroot sh -c "chown -R 0:0 root && mke2fs -q -t ext4 -b 4096 -L sprig -d root '$OUT/root.img' ${ROOT_MB:-128}M"
cp "$HERE/tiny386-linux.ini" "$OUT/"

# what it was built from and with (package.sh checks it, and it goes into the release)
{
  echo "Sprig Linux build"
  echo "commit: $(git -C "$HERE" rev-parse HEAD 2>/dev/null || echo unknown)$([[ -n "$(git -C "$HERE" status --porcelain 2>/dev/null)" ]] && echo ' (with local changes)')"
  echo "release: ${RELEASE:-0}   graphics console: ${FB:-0}"
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)   host: $(uname -srm)"
  echo "gcc: $(gcc --version | head -1)"
  echo "zig: $(zig version)"
  echo "make: $(make --version | head -1)   mke2fs: $(mke2fs -V 2>&1 | head -1)"
  echo "sources (SHA-256 of the archives in work/dl):"
  (cd "$WORK/dl" && sha256sum -- *)
} > "$OUT/BUILDINFO"
ls -l "$OUT"
