#!/usr/bin/env bash
# Programs beyond BusyBox, built static for i386 + musl like BusyBox (zig cc, Pentium instructions) and installed
# into $WORK/extras, which build.sh copies into the root file system: dropbear (SSH server and client, scp), gpm (the
# console mouse), nano, htop, Lua, tcc (a C compiler, with musl's headers and libraries), MicroPython.
# Needs what build.sh needs, plus tic (ncurses), autoconf, automake, libtool (gpm) and python3 on this computer.
# Run before build.sh:  ./extras.sh
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
rm -rf "$EX" "$SYS" && mkdir -p "$EX" "$SYS"

cd pkgs
. "$HERE/tools/fetch.sh"
fetch https://matt.ucc.asn.au/dropbear/releases/dropbear-$DROPBEAR.tar.bz2 dropbear-$DROPBEAR
fetch https://www.nico.schottelius.org/software/gpm/archives/gpm-$GPM.tar.bz2 gpm-$GPM
fetch https://ftp.gnu.org/gnu/ncurses/ncurses-$NCURSES.tar.gz ncurses-$NCURSES
fetch https://ftp.gnu.org/gnu/nano/nano-$NANO.tar.xz nano-$NANO
fetch https://github.com/htop-dev/htop/releases/download/$HTOP/htop-$HTOP.tar.xz htop-$HTOP
fetch https://www.lua.org/ftp/lua-$LUA.tar.gz lua-$LUA
fetch https://musl.libc.org/releases/musl-$MUSL.tar.gz musl-$MUSL
fetch https://micropython.org/resources/source/micropython-$MPY.tar.xz micropython-$MPY
rm -rf "tinycc-${TCC:?}"   # (unpacked anew: patched below)
fetch_git https://github.com/TinyCC/tinycc.git $TCC tinycc

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

find "$EX" -type f -perm -u+x -exec sh -c 'file "$1" | grep -q ELF && strip "$1"' _ {} \;
# (debug data out of the libraries too: tcc's own are in .stab sections, with this computer's paths)
find "$EX" -type f \( -name '*.a' -o -name '*.o' \) -exec strip --strip-debug -R .stab -R .stabstr {} \;
du -sh "$EX"
