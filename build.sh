#!/usr/bin/env bash
# Build Sprig Linux: a kernel (bzImage), tiny386's loader (linuxstart.bin) and an ext4 root file system with BusyBox
# and the programs from extras.sh (root.img), in $OUT (default ./out):  ./build.sh   (FB=1: the graphics console too)
# Needs: gcc (-m32), make, flex, bison, bc, libelf, git, zig (BusyBox for i386 with musl), fakeroot, mke2fs
# (e2fsprogs). Sources are downloaded into $WORK (default ./work). See README.md.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$HERE/work}
OUT=${OUT:-$HERE/out}
KVER=${KVER:-7.3}
BBVER=${BBVER:-1.37.0}
TINY386=${TINY386:-003c2666dfe665e1068917af69a99afed1f0f70f}   # tiny386 (github.com/hchunhui/tiny386): its loader
export KBUILD_BUILD_USER=sprig KBUILD_BUILD_HOST=sprig-linux   # (in the kernel's version string, not this computer's)
mkdir -p "$WORK" "$OUT"
cd "$WORK"
command -v bc >/dev/null || { echo "bc is missing (the kernel build needs it)" >&2; exit 1; }
[[ -d linux-$KVER ]] || curl -sL "https://cdn.kernel.org/pub/linux/kernel/v${KVER%%.*}.x/linux-$KVER.tar.xz" | tar -xJ
[[ -d busybox-$BBVER ]] || curl -sL "https://busybox.net/downloads/busybox-$BBVER.tar.bz2" | tar -xj
if [[ "$(git -C tiny386 rev-parse HEAD 2>/dev/null)" != "$TINY386" ]]; then
  rm -rf tiny386 && git init -q tiny386
  git -C tiny386 fetch -q --depth 1 https://github.com/hchunhui/tiny386.git "$TINY386"
  git -C tiny386 checkout -q FETCH_HEAD
fi
for p in "$HERE"/patches/*.patch; do   # (once: a patch already in the tree is left alone)
  patch -d linux-$KVER -p1 -s -N --dry-run < "$p" >/dev/null 2>&1 && patch -d linux-$KVER -p1 -s -N < "$p"
done
for p in "$HERE"/busybox-patches/*.patch; do
  patch -d busybox-$BBVER -p1 -s -N --dry-run < "$p" >/dev/null 2>&1 && patch -d busybox-$BBVER -p1 -s -N < "$p"
done

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
# the machine needs 1 MB of video memory for it (vga_mem_size), and video=vesafb:ypan scrolls by panning
# (patches/0003)
rm -rf ls-build && cp -r tiny386/linuxstart ls-build
make -s -C ls-build linuxstart.bin
cp ls-build/linuxstart.bin "$OUT/"
if [[ "${FB:-}" == 1 ]]; then
  sed -e 's|^kernel = .*|kernel = /sdcard/linux/bzImage-fb|' \
      -e 's|^\(cmdline = .*\)|\1 vga=0x303 video=vesafb:ypan|' -e 's|^vga_mem_size = .*|vga_mem_size = 1M|' \
      "$HERE/tiny386-linux.ini" > "$OUT/tiny386-linux-fb.ini"
fi

# BusyBox, static, i386 + musl (zig cc), Pentium instructions; tc doesn't build with current kernel headers
cat > zcc <<'ZCC'
#!/bin/bash
args=()
for a in "$@"; do
  case "$a" in -Wl,--warn-common|-Wl,-Map,*|-Wl,--sort-common|-Wl,--sort-section,alignment|-Wl,--verbose) ;; *) args+=("$a") ;; esac
done
exec zig cc -target x86-linux-musl -mcpu=pentium "${args[@]}"
ZCC
chmod +x zcc
(cd busybox-$BBVER && make -s defconfig >/dev/null &&
 sed -i -e 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/' -e 's/^CONFIG_TC=y/# CONFIG_TC is not set/' .config &&
 make -s -j"$(nproc)" CC="$WORK/zcc" HOSTCC=gcc AR="zig ar" STRIP=strip >/dev/null)

# root file system, ext4 with a journal (the emulated PC is often reset or switched off while running): BusyBox (its
# applets linked at first boot), rootfs/ from here, a 16 MB swap file (filled, not zeros: the kernel refuses a swap
# file with holes, and mke2fs leaves zeros out); 4 KB blocks for the same reason
rm -rf root && mkdir -p root/{bin,sbin,usr/bin,usr/sbin,usr/share/udhcpc,proc,sys,dev,tmp,root,var/run,var/log,home,mnt}
cp -r "$HERE/rootfs/." root/
[[ -d "$WORK/extras" ]] && cp -a "$WORK/extras/." root/   # from extras.sh, if run
cp busybox-$BBVER/busybox root/bin/ && ln -s busybox root/bin/sh && ln -s ../bin/busybox root/sbin/init
mkdir -p root/etc/rc.d && ln -s ../../etc/init.d/sshd root/usr/sbin/sshd   # (services: sshd start / enable)
install -m 755 busybox-$BBVER/examples/udhcp/simple.script root/usr/share/udhcpc/default.script
head -c 16M /dev/zero | tr '\0' '\125' > root/swapfile && chmod 600 root/swapfile && mkswap root/swapfile >/dev/null
rm -f "$OUT/root.img"
fakeroot sh -c "chown -R 0:0 root && mke2fs -q -t ext4 -b 4096 -L sprig -d root '$OUT/root.img' ${ROOT_MB:-128}M"
cp "$HERE/tiny386-linux.ini" "$OUT/"
ls -l "$OUT"
