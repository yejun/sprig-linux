# Notes

How Sprig Linux is set up for a small emulated PC, and what was found on the way. Times are from the Tab5 PC
(tiny386 on an ESP32-P4), where every emulated instruction is costly: the choices below mostly save guest
instructions, memory, or both.

## Kernel

`make ARCH=i386 tinyconfig` plus `tiny386.config` (and `fb.config` for the graphics console):

- **Pentium-class CPU** (`M586TSC`): Linux 7.3 no longer supports the 486.
- **Loaded at 1 MB**: linuxstart jumps to 1 MB, so it gets the bzImage (in a raw vmlinux.bin of a 7.x kernel the
  entry point isn't at its start), and `PHYSICAL_START` is 1 MB (tinyconfig's 16 MB is past the end of a small
  guest).
- **32-bit time system calls** (`COMPAT_32BIT_TIME`): musl on i386 makes them; without them BusyBox's init loops on
  `sigtimedwait` and takes half the CPU.
- **100 Hz, no ticks when idle**: every timer interrupt is costly to emulate. The clock is the PIT: the kernel can't
  calibrate tiny386's TSC (the host's nanoseconds); making the TSC the clock made starting programs 50% slower
  (RDTSC is a slow instruction for the emulator).
- **No old-style ptys** (`LEGACY_PTYS`): 512 devices made at boot took 10 s.
- **Compiled for speed** (`-O2`), not size: most of a program's start is kernel code. 60 starts of `/bin/true` took
  6.0 s instead of 8.1 s; the price is memory (the kernel's code 5.0 MB instead of 3.6).
- **ext4 with a journal**, for ext2 too: the emulated PC is often reset or switched off while it runs, and ext2
  without fsck got corrupted.
- The kernel command line has `pata_legacy.probe_mask=1`: looking for disks at the other five legacy ports took 3 s.

## Root file system

- BusyBox, static against musl, built with `zig cc -target x86-linux-musl -mcpu=pentium` (BusyBox's `tc` doesn't
  build with current kernel headers). Its applets are linked into `/bin` and `/sbin` at the first start.
- The swap file is filled (not zeros) and the file system has 4 KB blocks: mke2fs leaves zero blocks out of files,
  and the kernel refuses a swap file with holes.
- `rcS` uses shell built-ins where it can (starting a program costs the guest ~170 ms), doesn't wait for the DHCP
  address (9 s), prints a line per step, and sets the console to warnings only before the prompt.
- Services are off unless turned on: `sshd enable` puts a link to `/etc/init.d/sshd` in `/etc/rc.d`, which `rcS`
  starts at boot. The SSH server isn't needed by most sessions, and root has no password at first.
- tcc links programs statically by default: a tcc linked to musl's shared library crashed on every compile, and a
  static tcc can't load it (so no `tcc -run` with shared libraries).

## Console

- **Text** (`tiny386-linux.ini`): VGA text mode, the fastest.
- **Graphics** (`FB=1`, `tiny386-linux-fb.ini`): linuxstart sets VBE 800 x 600 with 256 colours (`vga=0x303`),
  maps the linear frame buffer and describes it to the kernel as a VESA frame buffer for vesafb; 100 x 37
  characters and the boot logo. It needs 1 MB of video memory (`vga_mem_size`). `quiet` would hide the logo.
- Scrolling pans instead of redrawing every character: fbcon's legacy acceleration code and vesafb moving the display
  start with the Bochs VBE interface's Y offset (`video=vesafb:ypan`, patches/0003). patches/0001 fixes a kernel bug
  this needs (`bit_putcs` drew nothing below `yres`; also seen in QEMU).
- patches/0004: vesafb has tiny386's 2D engine (where the emulator has one, port 0xf1e0) fill, copy and draw the
  console's glyphs instead of the kernel drawing them pixel by pixel; elsewhere nothing changes.
- The cursor doesn't blink (`rcS`): blinking runs kernel code 5 times a second, enough to push programs being started
  out of the emulator's translated code (starting several programs in turn took 60% longer).
- BusyBox's `top` redraws in place (busybox-patches/0001) instead of clearing the screen at each refresh.
- At the prompt `rcS` resets the scroll region: while the logo is up, the console keeps its rows out of scrolling.

## Network

eth0 is the PC's ISA NE2000 (0x300, IRQ 9), configured by DHCP in the background. On the Tab5 PC the guest gets
192.168.77.2 from the Tab5, reaches the internet through it, and the Tab5's ports 2222, 2323 and 8080 lead to the
guest's 22, 23 and 80. BusyBox's `wget` does https but doesn't check certificates.
