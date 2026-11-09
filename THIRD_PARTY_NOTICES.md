# Third-party software

This repository's own files (the build scripts, the configuration, the root file system's files in `rootfs/` and the
documentation) are under the MIT licence in [LICENSE](LICENSE). The patches in `patches/` and `busybox-patches/`
change the Linux kernel and BusyBox and are offered under those programs' licence, GPL-2.0; those in
`lynx-patches/` change lynx, under its licence, GPL-2.0; `frotz-patches/` change Frotz, under its licence,
GPL-2.0-or-later; `dialog-patches/` change dialog, under its licence, LGPL-2.1.

The web page (`web/`, on GitHub Pages) runs tiny386 compiled to WebAssembly: [tiny386](https://github.com/hchunhui/tiny386)
003c266's emulator and its `wasm/` port with its small C library, BSD-3-Clause (parts from QEMU and TinyEMU MIT,
nanoprintf 0BSD), its licence beside it as `tiny386-LICENSE.txt`; without its LGPL sound synthesis (fmopl). The
page's key table comes from tiny386's web page, which took it from [v86](https://github.com/copy/v86) (BSD-2-Clause;
the notice is in `web/sprig.js`). The page runs a release's own files, with that release's notices and sources.

Sprig Linux's images are built from the software below; each keeps its own licence. The full licence texts are in
the image (`/usr/share/licenses`) and, for a release, in `sprig-linux-<version>-licenses.tar.gz` beside it. The
exact sources a release was built from are in its `sprig-linux-<version>-sources.tar` (this repository and every
upstream archive, with their SHA-256 in `BUILDINFO`); `build.sh` and `extras.sh` pin the versions and checksums.

| Software | Version | Licence | Where |
|---|---|---|---|
| [Linux](https://kernel.org) | 7.3.3, with patches/ | GPL-2.0 (with the syscall note) | `bzImage`, `bzImage-fb` |
| [BusyBox](https://busybox.net) | 1.37.0, with busybox-patches/ | GPL-2.0 | the image: `/bin/busybox` |
| linuxstart, from [tiny386](https://github.com/hchunhui/tiny386) | tiny386 003c266 | MIT (linuxstart: Fabrice Bellard); tiny386's build files BSD-3-Clause | `linuxstart.bin` |
| musl, as bundled with [zig](https://ziglang.org) | zig 0.17.0 | MIT | linked into every program in the image |
| compiler-rt, as bundled with zig | zig 0.17.0 | MIT | linked into every program in the image |
| [musl](https://musl.libc.org) | 1.2.6 | MIT | the image: tcc's C library (`/usr/include`, `/usr/lib`) |
| [Dropbear](https://matt.ucc.asn.au/dropbear/dropbear.html) | 2026.94 | MIT, with parts under other permissive licences (see its LICENSE) | the image: SSH server and client |
| [gpm](https://www.nico.schottelius.org/software/gpm/) | 1.20.7 | GPL-2.0-or-later | the image: the console mouse |
| [ncurses](https://invisible-island.net/ncurses/) | 6.6 | MIT-style (X11) | the image: in the full-screen programs (nano, htop, lynx, mc, ncdu, frotz), terminal descriptions |
| [GNU nano](https://www.nano-editor.org) | 9.3 | GPL-3.0-or-later | the image |
| [htop](https://htop.dev) | 3.5.3 | GPL-2.0-or-later | the image |
| [Lua](https://www.lua.org) | 5.5.1 | MIT | the image |
| [Tiny C Compiler](https://repo.or.cz/tinycc.git) | e23dabe | LGPL-2.1-or-later | the image |
| [MicroPython](https://micropython.org) | 1.29.0 | MIT (parts under other permissive licences, see its LICENSE) | the image |
| [Lynx](https://lynx.invisible-island.net) | 2.9.3, with lynx-patches/ | GPL-2.0 (its COPYHEADER permits linking with OpenSSL) | the image: the web browser |
| [OpenSSL](https://openssl-library.org) | 3.6.5 | Apache-2.0 | the image: linked into lynx |
| [zlib](https://zlib.net) | 1.3.2 | Zlib | the image: linked into lynx |
| [Brotli](https://github.com/google/brotli) (its decoder) | 1.2.1 | MIT | the image: linked into lynx |
| [PCRE2](https://github.com/PCRE2Project/pcre2) | 10.49 | BSD-3-Clause (with its exception for binaries) | the image: linked into mc (through GLib) |
| [libffi](https://sourceware.org/libffi/) | 3.8.0 | MIT | build only (GLib's GObject, not linked into mc) |
| [GLib](https://gitlab.gnome.org/GNOME/glib) | 2.88.4 | LGPL-2.1-or-later | the image: linked into mc |
| [GNU Midnight Commander](https://midnight-commander.org) | 4.8.33 | GPL-3.0-or-later | the image: `mc`, `mcedit`, `mcview`, `mcdiff` |
| [ncdu](https://dev.yorhel.nl/ncdu) | 1.22 | MIT | the image |
| [SQLite](https://sqlite.org) | 3.54.1 | public domain | the image: `sqlite3` |
| [Frotz](https://gitlab.com/DavidGriffith/frotz) | 2.55, with frotz-patches/ | GPL-2.0-or-later | the image: the Z-machine player |
| Zork I, II and III ([historicalsource](https://github.com/historicalsource/zork1)) | the compiled stories at 97b7b3d, 3da9661, 3ec9ed4 | MIT (Microsoft, 2025) | the image: `/usr/share/games/zork` |
| [dialog](https://invisible-island.net/dialog/) | 1.3-20260721, with dialog-patches/ | LGPL-2.1 | the image: `menu`'s boxes |
| [Bywater BASIC](https://sourceforge.net/projects/bwbasic/) | 3.40 | GPL-2.0 | the image: `bwbasic`, `basic` |
| [CMatrix](https://github.com/abishekvashok/cmatrix) | 2.0 (5c082c6) | GPL-3.0-or-later | the image: `cmatrix` |
| [Meson](https://mesonbuild.com) | 1.12.1 | Apache-2.0 | build only (GLib's build) |
| Mozilla's CA certificates, as [curl](https://curl.se/docs/caextract.html) publishes them | 2026-10-20 | MPL-2.0 | the image: `/etc/ssl/certs` |
