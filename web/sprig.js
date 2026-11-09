// Sprig Linux in the browser: tiny386 (github.com/hchunhui/tiny386, BSD-3-Clause) built for WebAssembly, booting
// the release's graphics-console kernel and root file system. Everything is held in memory: what is written to
// the disk is gone when the page is closed or reloaded. No network beyond the emulated card itself.
'use strict';

(() => {
const $ = id => document.getElementById(id);
const screen = $('screen'), cover = $('cover'), startBtn = $('start'), status = $('status'), bar = $('bar');
const W = 800, H = 600;

// the machine (tiny386's ini): the release's tiny386-linux-fb.ini, with no BIOS (the kernel is started directly)
const INI = `[pc]
bios =
vga_bios =
linuxstart = linuxstart.bin
kernel = bzImage-fb
cmdline = console=tty0 root=/dev/sda rw ne.io=0x300 ne.irq=9 pata_legacy.probe_mask=1 vga=0x303 video=vesafb:ypan
hda = root.img
mem_size = 18M
vga_mem_size = 1M
fill_cmos = 1
[cpu]
gen = 5
fpu = 1
[display]
width = ${W}
height = ${H}
`;

// the files tiny386 opens, by name; its C library reads and writes them through these imports
const files = {}, fds = {};
let nextFd = 3, mem8, ex, pc;
const str = p => { let n = 0; while (mem8[p + n]) n++; return new TextDecoder().decode(mem8.subarray(p, p + n)); };
let log = '';
const env = {
  __abort: p => { throw new Error('tiny386: ' + str(p)); },
  exit: s => { throw new Error('tiny386 exit ' + s); },
  __get_mticks: () => Date.now(),
  __console_print: p => { log = (log + str(p)).slice(-4000); },
  __filestore_fetch: () => {},
  __open_get_size: p => (str(p) in files ? files[str(p)].length : -1),
  __open: p => { const f = files[str(p)]; if (!f) return -1; fds[nextFd] = f; return nextFd++; },
  __read: (fd, buf, off, len) => {
    const f = fds[fd]; if (!f || off + len > f.length) return -1;
    mem8.set(f.subarray(off, off + len), buf); return 0;
  },
  __write: (fd, buf, off, len) => {
    const f = fds[fd]; if (!f || off + len > f.length) return -1;
    f.set(mem8.subarray(buf, buf + len), off); return 0;
  },
  __close: fd => { delete fds[fd]; },
  on_packet_cb: () => {},
  sin: Math.sin, cos: Math.cos, tan: Math.tan, atan2: Math.atan2, pow: Math.pow, log2: Math.log2, log10: Math.log10,
  round: Math.round,
};

// a download, with its progress counted into done (of total, for the bar)
let done = 0, total = 0;
async function get(name) {
  const r = await fetch(name);
  if (!r.ok) throw new Error(`${name}: ${r.status}`);
  const parts = [], rd = r.body.getReader();
  for (;;) {
    const { done: end, value } = await rd.read();
    if (end) break;
    parts.push(value); done += value.length;
    bar.style.width = Math.min(100, 100 * done / total) + '%';
  }
  return new Blob(parts);
}
async function gunzip(blob) {
  const head = new Uint8Array(await blob.slice(0, 2).arrayBuffer());
  if (head[0] !== 0x1f || head[1] !== 0x8b) return new Uint8Array(await blob.arrayBuffer());   // (already unpacked)
  const n = new DataView(await blob.slice(blob.size - 4).arrayBuffer()).getUint32(0, true);    // (its size, mod 4 GB)
  const out = new Uint8Array(n), rd = blob.stream().pipeThrough(new DecompressionStream('gzip')).getReader();
  for (let at = 0; ;) { const { done: end, value } = await rd.read(); if (end) break; out.set(value, at); at += value.length; }
  return out;
}

async function start() {
  startBtn.disabled = true;
  cover.classList.add('loading');
  try {
    const sizes = SPRIG.sizes;
    total = Object.values(sizes).reduce((a, b) => a + b, 0);
    status.textContent = `Downloading ${(total / 1e6).toFixed(0)} MB…`;
    const [wasm, ls, kernel, root] = await Promise.all(
      ['tiny386.wasm', 'linuxstart.bin', 'bzImage-fb', 'root.img.gz'].map(get));
    status.textContent = 'Unpacking…';
    files['linuxstart.bin'] = new Uint8Array(await ls.arrayBuffer());
    files['bzImage-fb'] = new Uint8Array(await kernel.arrayBuffer());
    files['root.img'] = await gunzip(root);
    files['sprig.ini'] = new TextEncoder().encode(INI);

    const { instance } = await WebAssembly.instantiate(await wasm.arrayBuffer(), { env });
    ex = instance.exports;
    ex.memory.grow(1024);   // (64 MB: the PC's memory and the screen; its allocator never grows it)
    mem8 = new Uint8Array(ex.memory.buffer);
    const ini = ex.malloc(16);
    mem8.set(new TextEncoder().encode('sprig.ini\0'), ini);
    const conf = ex.wasm_prepare(ini);
    if (!conf) throw new Error('tiny386 rejected its settings');
    pc = ex.wasm_init(conf);
    run();
  } catch (e) {
    cover.classList.remove('loading');
    status.textContent = 'Sprig Linux could not start: ' + e.message;
    startBtn.disabled = false;
    console.error(e, log);
  }
}

function run() {
  cover.hidden = true;
  screen.focus();
  const fb = ex.wasm_getfb(pc), img = new ImageData(W, H), px = new Uint32Array(img.data.buffer);
  const src = new Uint32Array(ex.memory.buffer, fb, W * H), ctx = screen.getContext('2d');
  let on = true;
  const tick = new MessageChannel();   // (the PC runs flat out, between the page's own work)
  tick.port1.onmessage = () => {
    if (!on) return;
    if (!ex.wasm_loop_ex(pc, 2)) { on = false; off(); return; }
    tick.port2.postMessage(0);
  };
  tick.port2.postMessage(0);
  (function draw() {   // tiny386's screen is BGRX; the canvas wants RGBA
    for (let i = 0; i < px.length; i++) {
      const v = src[i];
      px[i] = 0xff000000 | (v & 0xff) << 16 | (v & 0xff00) | (v >>> 16 & 0xff);
    }
    ctx.putImageData(img, 0, 0);
    if (on) requestAnimationFrame(draw);
  })();
  input();
}

function off() {   // poweroff: tiny386 has switched the PC off
  if (document.pointerLockElement) document.exitPointerLock();
  cover.hidden = false;
  cover.classList.remove('loading');
  cover.classList.add('off');
  status.textContent = 'Sprig Linux has switched the PC off.';
  startBtn.textContent = 'Start again';
  startBtn.disabled = false;
  startBtn.onclick = () => location.reload();
}

// keys as PC scan codes (by KeyboardEvent.code); the mouse once the screen is clicked (pointer lock: the guest's
// pointer is relative), until Esc. The scan-code table is tiny386's web page's, which took it from v86
// (github.com/copy/v86): Copyright (c) 2012, The v86 contributors. All rights reserved. Redistribution and use in
// source and binary forms, with or without modification, are permitted provided that the following conditions are
// met: 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the
// following disclaimer. 2. Redistributions in binary form must reproduce the above copyright notice, this list of
// conditions and the following disclaimer in the documentation and/or other materials provided with the
// distribution. THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
// IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
// PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
// INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
// ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
const CODES = {
  Escape: 0x01, Digit1: 0x02, Digit2: 0x03, Digit3: 0x04, Digit4: 0x05, Digit5: 0x06, Digit6: 0x07, Digit7: 0x08,
  Digit8: 0x09, Digit9: 0x0a, Digit0: 0x0b, Minus: 0x0c, Equal: 0x0d, Backspace: 0x0e, Tab: 0x0f, KeyQ: 0x10,
  KeyW: 0x11, KeyE: 0x12, KeyR: 0x13, KeyT: 0x14, KeyY: 0x15, KeyU: 0x16, KeyI: 0x17, KeyO: 0x18, KeyP: 0x19,
  BracketLeft: 0x1a, BracketRight: 0x1b, Enter: 0x1c, ControlLeft: 0x1d, KeyA: 0x1e, KeyS: 0x1f, KeyD: 0x20,
  KeyF: 0x21, KeyG: 0x22, KeyH: 0x23, KeyJ: 0x24, KeyK: 0x25, KeyL: 0x26, Semicolon: 0x27, Quote: 0x28,
  Backquote: 0x29, ShiftLeft: 0x2a, Backslash: 0x2b, KeyZ: 0x2c, KeyX: 0x2d, KeyC: 0x2e, KeyV: 0x2f, KeyB: 0x30,
  KeyN: 0x31, KeyM: 0x32, Comma: 0x33, Period: 0x34, Slash: 0x35, IntlRo: 0x35, ShiftRight: 0x36,
  NumpadMultiply: 0x37, AltLeft: 0x38, Space: 0x39, CapsLock: 0x3a, F1: 0x3b, F2: 0x3c, F3: 0x3d, F4: 0x3e,
  F5: 0x3f, F6: 0x40, F7: 0x41, F8: 0x42, F9: 0x43, F10: 0x44, NumLock: 0x45, ScrollLock: 0x46, Numpad7: 0x47,
  Numpad8: 0x48, Numpad9: 0x49, NumpadSubtract: 0x4a, Numpad4: 0x4b, Numpad5: 0x4c, Numpad6: 0x4d, NumpadAdd: 0x4e,
  Numpad1: 0x4f, Numpad2: 0x50, Numpad3: 0x51, Numpad0: 0x52, NumpadDecimal: 0x53, IntlBackslash: 0x56, F11: 0x57,
  F12: 0x58, NumpadEnter: 0xe01c, ControlRight: 0xe01d, NumpadDivide: 0xe035, AltRight: 0xe038, Home: 0xe047,
  ArrowUp: 0xe048, PageUp: 0xe049, ArrowLeft: 0xe04b, ArrowRight: 0xe04d, End: 0xe04f, ArrowDown: 0xe050,
  PageDown: 0xe051, Insert: 0xe052, Delete: 0xe053, MetaLeft: 0xe05b, MetaRight: 0xe05c, ContextMenu: 0xe05d,
};
function input() {
  const key = down => e => {
    const c = CODES[e.code];
    if (c === undefined) return;
    e.preventDefault();
    ex.wasm_send_kbd(pc, down, c);
  };
  screen.addEventListener('keydown', key(1));
  screen.addEventListener('keyup', key(0));
  screen.addEventListener('blur', () => {   // (no key left held down)
    for (const c of [0x1d, 0x2a, 0x36, 0x38, 0xe01d, 0xe038]) ex.wasm_send_kbd(pc, 0, c);
  });
  const locked = () => document.pointerLockElement === screen;
  screen.addEventListener('mousedown', e => {
    screen.focus();
    if (!locked()) { screen.requestPointerLock(); return; }
    ex.wasm_send_mouse(pc, 0, 0, 0, e.buttons);
  });
  screen.addEventListener('mouseup', e => { if (locked()) ex.wasm_send_mouse(pc, 0, 0, 0, e.buttons); });
  screen.addEventListener('mousemove', e => { if (locked()) ex.wasm_send_mouse(pc, e.movementX, e.movementY, 0, e.buttons); });
  screen.addEventListener('wheel', e => {
    if (!locked()) return;
    e.preventDefault();
    ex.wasm_send_mouse(pc, 0, 0, Math.sign(e.deltaY), e.buttons);
  }, { passive: false });
  screen.addEventListener('contextmenu', e => e.preventDefault());
  document.addEventListener('pointerlockchange', () => document.body.classList.toggle('grabbed', locked()));
}

startBtn.onclick = start;
$('size').textContent = `${(Object.values(SPRIG.sizes).reduce((a, b) => a + b, 0) / 1e6).toFixed(0)} MB`;
document.querySelectorAll('.version').forEach(e => { e.textContent = SPRIG.version; });
})();
