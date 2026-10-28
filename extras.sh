#!/usr/bin/env bash
# Programs beyond BusyBox, built static for i386 + musl like BusyBox (zig cc, Pentium instructions) and installed
# into $WORK/extras, which build.sh copies into the root file system: dropbear (SSH server and client, scp), gpm (the
# console mouse), nano, htop, Lua, tcc (a C compiler, with musl's headers and libraries), MicroPython.
# Needs what build.sh needs, plus tic (ncurses), autoconf, automake, libtool (gpm) and python3 on this computer.
# Run before build.sh:  ./extras.sh   (RELEASE=1 as for build.sh: a clean checkout, every source unpacked anew)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${WORK:-$HERE/work}
DROPBEAR=2026.94 GPM=1.20.7 NCURSES=6.6 NANO=9.3 HTOP=3.5.3 LUA=5.5.1 MUSL=1.2.6 TCC=e23dabed154a8495f3ac1ff3cc9d04fa1c207893
MPY=1.29.0
mkdir -p "$WORK/pkgs"
cd "$WORK"
Z=$HERE/tools/zcc
EX=$WORK/extras    # what goes into the guest
SYS=$WORK/sysroot  # what only the build needs (ncurses)
HOST=(--host=i386-linux-musl --build=x86_64-linux-gnu)
rm -rf "$EX" "$SYS" "$WORK/extras.info" && mkdir -p "$EX" "$SYS"

cd pkgs
. "$HERE/tools/fetch.sh"
release_check
use_zig
fetch https://matt.ucc.asn.au/dropbear/releases/dropbear-$DROPBEAR.tar.bz2 dropbear-$DROPBEAR \
  e098034a843699200c8c977a991fff73159735bf795d5f72ef672c41a6b1ae81
fetch https://www.nico.schottelius.org/software/gpm/archives/gpm-$GPM.tar.bz2 gpm-$GPM \
  f011b7dc7afb824e0a017b89b7300514e772853ece7fc4ee640310889411a48d
fetch https://ftp.gnu.org/gnu/ncurses/ncurses-$NCURSES.tar.gz ncurses-$NCURSES \
  355b4cbbed880b0381a04c46617b7656e362585d52e9cf84a67e2009b749ff11
fetch https://ftp.gnu.org/gnu/nano/nano-$NANO.tar.xz nano-$NANO \
  a9affc52c9596ee0682bcdd4ceb3c0b235eb221d83d733dfd9b0dff45897cb0d
fetch https://github.com/htop-dev/htop/releases/download/$HTOP/htop-$HTOP.tar.xz htop-$HTOP \
  a8b164386494cb85bb255a415a3f5f80afe7a0c4491da5d113b3a0f951087e65
fetch https://www.lua.org/ftp/lua-$LUA.tar.gz lua-$LUA \
  1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce
fetch https://musl.libc.org/releases/musl-$MUSL.tar.gz musl-$MUSL \
  d585fd3b613c66151fc3249e8ed44f77020cb5e6c1e635a616d3f9f82460512a
fetch https://micropython.org/resources/source/micropython-$MPY.tar.xz micropython-$MPY \
  d925a7c664e79a2bdf3dfcb285ba5e2237041cc35a0bd4ee573b6c5711efeca0
rm -rf "tinycc-${TCC:?}"   # (unpacked anew: changed below)
fetch https://github.com/TinyCC/tinycc/archive/$TCC.tar.gz tinycc-$TCC \
  d2470fdeed862ddb18f4ec4e6a405fa984580c3d85c38492516749c61931c30e

# musl, for tcc: headers, static libraries and start files (no shared library: tcc links statically, below)
(cd musl-$MUSL && ./configure --target=i386-linux-musl --prefix=/usr --syslibdir=/lib CC="$Z" AR="zig ar" \
   RANLIB="zig ranlib" >/dev/null && make -s -j"$(nproc)" >/dev/null && make -s install DESTDIR="$EX" >/dev/null)
rm -rf "$EX/lib" "$EX/usr/lib/libc.so"

# tcc, static, and making static programs by default (a tcc linked to musl's shared library crashed, and a static
# one can't load it for tcc -run); its runtime library is compiled by itself, with musl's headers
(cd tinycc-$TCC &&
 sed -i 's|^    s->nocommon = 1;$|&\n    s->static_link = 1; /* tiny386 guest: no shared C library */|' libtcc.c &&
 ./configure --prefix=/usr --cc="$Z" --ar="zig ar" --cpu=i386 --targetos=Linux --config-musl --enable-static \
   --extra-ldflags=-static --crtprefix=/usr/lib >/dev/null && make -s clean >/dev/null &&
 make -s -j"$(nproc)" XTCC="$PWD/tcc -I$EX/usr/include" XAR="$PWD/tcc -ar" >/dev/null &&
 make -s install DESTDIR="$EX" >/dev/null)

# Lua
(cd lua-$LUA && make -s -C src clean >/dev/null &&
 make -s -C src CC="$Z -std=gnu99" AR="zig ar rcu" RANLIB="zig ranlib" SYSCFLAGS=-DLUA_USE_LINUX SYSLIBS= \
   MYLDFLAGS=-static lua luac >/dev/null 2>&1 && install -D -m755 -t "$EX/usr/bin" src/lua src/luac)

# gpm, the console's mouse (started by rcS), and its library for ncurses. (Old code: today's compilers want the
# headers it leaves out, and its variables defined in several files merged.)
(cd gpm-$GPM && { [[ -x configure ]] || ./autogen.sh >/dev/null 2>&1; } &&
 ./configure -q "${HOST[@]}" CC="$Z" AR="zig ar" RANLIB="zig ranlib" --prefix=/usr --sysconfdir=/etc --without-curses \
   CFLAGS="-Os -fcommon -include string.h -include strings.h -include sys/sysmacros.h -include stdlib.h \
   -Wno-implicit-function-declaration -Wno-int-conversion -Wno-incompatible-pointer-types" >/dev/null 2>&1 &&
 make -s -C src gpm lib/libgpm.a LDFLAGS=-static >/dev/null 2>&1 && install -D -m755 -t "$EX/usr/sbin" src/gpm &&
 install -D -m644 -t "$SYS/usr/include" src/headers/gpm.h && install -D -m644 -t "$SYS/usr/lib" src/lib/libgpm.a)

# ncurses (static, wide characters) for nano and htop, with gpm's mouse (linked in: a static program can't load
# libgpm); terminal descriptions for the console and SSH clients
(cd ncurses-$NCURSES && ./configure -q "${HOST[@]}" CC="$Z" AR="zig ar" RANLIB="zig ranlib" --prefix=/usr \
   --without-cxx-binding --without-ada --without-manpages --without-tests --without-progs --without-shared \
   --without-debug --enable-widec --disable-db-install --with-default-terminfo-dir=/usr/share/terminfo \
   --disable-stripping --with-gpm --without-dlsym CPPFLAGS="-I$SYS/usr/include" LDFLAGS="-L$SYS/usr/lib" \
   >/dev/null && make -s -j"$(nproc)" libs >/dev/null 2>&1 &&
 make -s install.libs install.includes DESTDIR="$SYS" >/dev/null 2>&1)
mkdir -p "$EX/usr/share/terminfo"
tic -x -o "$EX/usr/share/terminfo" -e linux,vt100,vt102,vt220,xterm,xterm-256color,xterm-color,screen,screen-256color,tmux,tmux-256color,ansi,dumb \
  ncurses-$NCURSES/misc/terminfo.src
NC=(CPPFLAGS="-I$SYS/usr/include" LDFLAGS="-L$SYS/usr/lib -static" PKG_CONFIG=false)

# nano, with its syntax colouring
(cd nano-$NANO && ./configure -q "${HOST[@]}" CC="$Z" --prefix=/usr --sysconfdir=/etc --disable-nls \
   --disable-libmagic --disable-speller "${NC[@]}" NCURSESW_CFLAGS="-I$SYS/usr/include" NCURSESW_LIBS="-lncursesw -lgpm" \
   >/dev/null && make -s -j"$(nproc)" >/dev/null 2>&1 && install -D -m755 -t "$EX/usr/bin" src/nano &&
 install -D -m644 -t "$EX/usr/share/nano" syntax/*.nanorc)
mkdir -p "$EX/etc" && printf 'include "/usr/share/nano/*.nanorc"\nset constantshow\nset mouse\n' > "$EX/etc/nanorc"

# htop
(cd htop-$HTOP && ./configure -q "${HOST[@]}" CC="$Z" --prefix=/usr --enable-static --disable-sensors \
   --disable-capabilities --disable-delayacct --disable-affinity --disable-hwloc "${NC[@]}" \
   HTOP_NCURSESW_CONFIG_SCRIPT=false LIBS=-lgpm >/dev/null && make -s -j"$(nproc)" >/dev/null 2>&1 &&
 install -D -m755 -t "$EX/usr/bin" htop)

# dropbear: one program for the server, the client (ssh), scp and key generation
(cd dropbear-$DROPBEAR && ./configure -q "${HOST[@]}" CC="$Z" AR="zig ar" RANLIB="zig ranlib" --prefix=/usr \
   --disable-zlib --enable-static --disable-lastlog --disable-utmp --disable-utmpx --disable-wtmp --disable-wtmpx \
   --disable-pututline --disable-pututxline --disable-pam >/dev/null 2>&1 &&
 make -s -j"$(nproc)" PROGRAMS="dropbear dbclient dropbearkey scp" MULTI=1 STATIC=1 >/dev/null 2>&1 &&
 install -D -m755 dropbearmulti "$EX/usr/bin/dropbearmulti")
for p in dbclient dropbearkey scp; do ln -sf dropbearmulti "$EX/usr/bin/$p"; done
ln -sf dbclient "$EX/usr/bin/ssh"
mkdir -p "$EX/usr/sbin" "$EX/etc/dropbear" && ln -sf ../bin/dropbearmulti "$EX/usr/sbin/dropbear"

# MicroPython (the Unix port, without ffi, btree and ssl); its preprocessor tools/zcpp
(cd micropython-$MPY && make -s -C mpy-cross >/dev/null 2>&1 && cd ports/unix && make -s clean >/dev/null 2>&1 &&
 make -s -j"$(nproc)" VARIANT=standard CC="$Z" CPP="$HERE/tools/zcpp" STRIP=strip SIZE=size MICROPY_PY_FFI=0 \
   MICROPY_PY_BTREE=0 MICROPY_PY_SSL=0 MICROPY_SSL_MBEDTLS=0 CFLAGS_EXTRA=-DMICROPY_GCREGS_SETJMP=1 \
   LDFLAGS_EXTRA=-static LDFLAGS_ARCH=-Wl,--gc-sections >/dev/null 2>&1 &&
 install -D -m755 build-standard/micropython "$EX/usr/bin/micropython")

# their licences (build.sh adds the kernel's, BusyBox's, the C library's and the loader's)
L=$EX/usr/share/licenses
install -D -m644 -t "$L/dropbear" dropbear-$DROPBEAR/LICENSE
install -D -m644 -t "$L/gpm" gpm-$GPM/COPYING
install -D -m644 -t "$L/ncurses" ncurses-$NCURSES/COPYING
install -D -m644 -t "$L/nano" nano-$NANO/COPYING
install -D -m644 -t "$L/htop" htop-$HTOP/COPYING
mkdir -p "$L/lua" && sed -n '/^\* Copyright (C) 1994/,/^\*\*\*\*/p' lua-$LUA/src/lua.h | grep -v '^\*\*\*\*' |
  sed 's/^\* \{0,1\}//' > "$L/lua/LICENSE"
install -D -m644 -t "$L/musl" musl-$MUSL/COPYRIGHT   # (tcc's C library)
install -D -m644 -t "$L/tcc" tinycc-$TCC/COPYING tinycc-$TCC/RELICENSING
install -D -m644 -t "$L/micropython" micropython-$MPY/LICENSE

find "$EX" -type f -perm -u+x -exec sh -c 'file "$1" | grep -q ELF && strip "$1"' _ {} \;
# (debug data out of the libraries too: tcc's own are in .stab sections, with this computer's paths)
find "$EX" -type f \( -name '*.a' -o -name '*.o' \) -exec strip --strip-debug -R .stab -R .stabstr {} \;
du -sh "$EX"
# how they were built (build.sh with RELEASE=1 takes only extras built with RELEASE=1 from its commit)
if [[ "${RELEASE:-}" == 1 ]]; then echo "release $(git -C "$HERE" rev-parse HEAD)" > "$WORK/extras.info"
else echo dev > "$WORK/extras.info"; fi
