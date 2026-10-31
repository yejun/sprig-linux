# Sprig Linux

A small Linux distribution for PCs with little memory: a current kernel, BusyBox and a few programs that run in
16 MB of RAM. It is made for the emulated PC of [Tab5 PC](https://github.com/yejun/tab5-pc) (tiny386 on the M5Stack
Tab5), and boots in tiny386 elsewhere too.

- Linux 7.3.1, BusyBox 1.37 (static, musl), on an ext4 root file system with a 16 MB swap file
- nano, htop, Lua, tcc (a C compiler), MicroPython, an SSH server and client (dropbear), the console mouse (gpm)
- network over the PC's NE2000 card (DHCP at boot)
- a text console, or a graphics console (800 x 600, 256 colours) with the boot logo

The kernel is booted directly by tiny386's loader (linuxstart), without a BIOS. It needs a Pentium-class CPU (Linux
no longer supports the 486): `gen = 5` in tiny386's settings.

| guest RAM | free after boot |
|---|---|
| 16 MB | 7.2 MB + 16 MB swap |
| 18 MB (the settings here) | 9.1 MB + 16 MB swap |
| 20 MB | 11.4 MB + 16 MB swap |

## Build

On Linux (x86-64), with gcc (with `-m32`), make, flex, bison, bc, libelf, git, curl, fakeroot and e2fsprogs; for the
programs also tic (ncurses), autoconf, automake, libtool and python3. BusyBox and the programs are built for i386 +
musl with [zig](https://ziglang.org)'s `zig cc`; the scripts download it (a pinned version, like every source).

    ./extras.sh           # the programs beyond BusyBox -> work/extras (optional)
    ./build.sh            # kernel, loader, root file system (BusyBox, and the programs if built) -> out/
    FB=1 ./build.sh       # or: the same and the graphics console's kernel and settings

The results in `out/`: `bzImage`, `linuxstart.bin`, `root.img` (128 MB), `tiny386-linux.ini` (and with `FB=1`
`bzImage-fb`, `tiny386-linux-fb.ini`).
Downloads are kept in `work/dl`, each checked against its SHA-256. A patch that doesn't apply stops the build.

A release is built from a clean checkout with every source unpacked anew, and `package.sh` checks that the images are
such a build of the current commit (`BUILDINFO` records what they were built from and with):

    RELEASE=1 ./extras.sh && RELEASE=1 FB=1 ./build.sh && ./package.sh    # -> release/

`release/` then holds the images (`root.img` gzipped), `BUILDINFO`, `THIRD_PARTY_NOTICES.md`, the licences, the
sources archive (this repository and every upstream archive: it builds again without a network) and `SHA256SUMS`.

GitHub builds releases too (`.github/workflows/build.yml`): by hand from the Actions tab (`release/` as an artifact
for 3 days), or for a version tag (`git tag v0.1 && git push origin v0.1`): a draft release to look over and
publish.

## Install on the Tab5 PC

Decompress the release's `root.img.gz` first (`gunzip root.img.gz`, or 7-Zip on Windows): the Tab5 PC needs
`root.img` itself. Copy `bzImage`, `linuxstart.bin` and `root.img` to `/linux` on the card, and `tiny386-linux.ini` (or
`tiny386-linux-fb.ini`, with `bzImage-fb`) as `/tiny386.ini` (keep the DOS one to switch back). The first start
makes BusyBox's links (a few minutes); after that Linux is at the prompt in about 30 s.

`root` has no password. The SSH server is off: `sshd start` starts it, `sshd enable` starts it at every boot
(`sshd disable`, `sshd stop`, `sshd status`). It lets root in once root has a password (`passwd`); on the Tab5 PC
from another computer: `ssh -p 2222 root@<the Tab5's address>`.

## Notes

How it is set up and why (kernel options, the console, memory, speed): [docs/NOTES.md](docs/NOTES.md).

## Licence

The build scripts and configuration here are under the MIT licence (LICENSE). The kernel and the programs keep their
own licences: see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) (the texts are in the image's
`/usr/share/licenses`). `patches/` and `busybox-patches/` are changes to the kernel and BusyBox under their licence
(GPL-2.0). Binary releases come with the exact sources they were built from.
