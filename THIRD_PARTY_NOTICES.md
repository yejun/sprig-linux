# Third-party software

Sprig Linux's images are built from the software below; each keeps its own licence. The full licence texts are in
the image (`/usr/share/licenses`) and, for a release, in `sprig-linux-<version>-licenses.tar.gz` beside it. The
exact sources a release was built from are in its `sprig-linux-<version>-sources.tar` (this repository and every
upstream archive, with their SHA-256 in `BUILDINFO`); `build.sh` and `extras.sh` pin the versions and checksums.

| Software | Version | Licence | Where |
|---|---|---|---|
| [Linux](https://kernel.org) | 7.3, with patches/ | GPL-2.0 (with the syscall note) | `bzImage`, `bzImage-fb` |
| [BusyBox](https://busybox.net) | 1.37.0, with busybox-patches/ | GPL-2.0 | the image: `/bin/busybox` |
| linuxstart, from [tiny386](https://github.com/hchunhui/tiny386) | tiny386 003c266 | MIT (linuxstart: Fabrice Bellard); tiny386's build files BSD-3-Clause | `linuxstart.bin` |
| musl, as bundled with [zig](https://ziglang.org) | zig 0.17.0 | MIT | linked into every program in the image |
| compiler-rt, as bundled with zig | zig 0.17.0 | MIT | linked into every program in the image |
| [musl](https://musl.libc.org) | 1.2.6 | MIT | the image: tcc's C library (`/usr/include`, `/usr/lib`) |
| [Dropbear](https://matt.ucc.asn.au/dropbear/dropbear.html) | 2026.94 | MIT, with parts under other permissive licences (see its LICENSE) | the image: SSH server and client |
| [gpm](https://www.nico.schottelius.org/software/gpm/) | 1.20.7 | GPL-2.0 | the image: the console mouse |
| [ncurses](https://invisible-island.net/ncurses/) | 6.6 | MIT-style (X11) | the image: in nano and htop, terminal descriptions |
| [GNU nano](https://www.nano-editor.org) | 9.3 | GPL-3.0-or-later | the image |
| [htop](https://htop.dev) | 3.5.3 | GPL-2.0-or-later | the image |
| [Lua](https://www.lua.org) | 5.5.1 | MIT | the image |
| [Tiny C Compiler](https://repo.or.cz/tinycc.git) | e23dabe | LGPL-2.1-or-later | the image |
| [MicroPython](https://micropython.org) | 1.29.0 | MIT (parts under other permissive licences, see its LICENSE) | the image |

The patches in `patches/` and `busybox-patches/` are offered under GPL-2.0, the licence of what they change.
