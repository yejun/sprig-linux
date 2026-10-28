# Sprig Linux

A small Linux distribution for PCs with little memory: a current kernel, BusyBox and a few programs that run in
16 MB of RAM. It is made for the emulated PC of [Tab5 PC](https://github.com/yejun/tab5-pc) (tiny386 on the M5Stack
Tab5), and boots in tiny386 elsewhere too.

- Linux 7.3, BusyBox 1.37 (static, musl), on an ext4 root file system with a 16 MB swap file
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

On Linux (x86-64), with gcc (with `-m32`), make, flex, bison, bc, libelf, git, curl, [zig](https://ziglang.org)
(BusyBox and the programs are built for i386 + musl with `zig cc`), fakeroot and e2fsprogs; for the programs also
tic (ncurses), autoconf, automake, libtool and python3.

    ./build.sh            # kernel, loader, root file system (BusyBox) -> out/
    ./extras.sh           # the programs beyond BusyBox -> work/extras
    ./build.sh            # again: now with them
    FB=1 ./build.sh       # also the graphics console's kernel and settings

Sources are downloaded into `work/`. The results in `out/`: `bzImage`, `linuxstart.bin`, `root.img` (128 MB),
`tiny386-linux.ini` (and with `FB=1` `bzImage-fb`, `tiny386-linux-fb.ini`).

## Install on the Tab5 PC

Copy `bzImage`, `linuxstart.bin` and `root.img` to `/linux` on the card, and `tiny386-linux.ini` (or
`tiny386-linux-fb.ini`, with `bzImage-fb`) as `/tiny386.ini` (keep the DOS one to switch back). The first start
makes BusyBox's links (a few minutes); after that Linux is at the prompt in about 30 s.

`root` has no password. The SSH server is off: `sshd start` starts it, `sshd enable` starts it at every boot
(`sshd disable`, `sshd stop`, `sshd status`). It lets root in once root has a password (`passwd`); on the Tab5 PC
from another computer: `ssh -p 2222 root@<the Tab5's address>`.

## Notes

How it is set up and why (kernel options, the console, memory, speed): [docs/NOTES.md](docs/NOTES.md).

## Licence

The build scripts and configuration here are under the MIT licence (LICENSE). The kernel and the programs keep their
own licences (Linux and BusyBox: GPL-2.0; the others as their sources say); `patches/` and `busybox-patches/` are
changes to the kernel and BusyBox under their licences. Binary releases come with the exact sources they were built
from.
