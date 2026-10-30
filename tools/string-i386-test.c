/* A test of tools/string-i386.S against plain byte loops: every length to 300 at every alignment, overlapping moves
 * both ways, the bytes around each untouched. Static i386, runs on an x86-64 Linux PC:
 *   PATH=work/zig-x86_64-linux-<ver>:$PATH tools/zcc -c -o /tmp/s.o tools/string-i386.S &&
 *   tools/zcc -Os -fno-builtin -static -o /tmp/t tools/string-i386-test.c /tmp/s.o && /tmp/t */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
static unsigned char a[1024], b[1024], r[1024];
static unsigned rnd = 1;
static unsigned next(void) { rnd = rnd * 1103515245 + 12345; return rnd >> 16; }
static void fill(unsigned char *p, int n) { for (int i = 0; i < n; i++) p[i] = next(); }
int main(void) {
	int bad = 0;
	for (int n = 0; n <= 300; n++)
		for (int da = 0; da < 4; da++)
			for (int sa = 0; sa < 4; sa++) {
				fill(a, sizeof a); fill(b, sizeof b); memcpy(r, b, sizeof r);   /* (memcpy: tested against r) */
				void *ret = memcpy(b + 64 + da, a + 64 + sa, n);
				for (int i = 0; i < n; i++) r[64 + da + i] = a[64 + sa + i];
				if (ret != b + 64 + da || memcmp(b, r, sizeof r)) { printf("memcpy n %d da %d sa %d\n", n, da, sa); bad++; }
				fill(b, sizeof b); for (int i = 0; i < 1024; i++) r[i] = b[i];
				int c = next();
				ret = memset(b + 64 + da, c, n);
				for (int i = 0; i < n; i++) r[64 + da + i] = (unsigned char) c;
				if (ret != b + 64 + da || memcmp(b, r, sizeof r)) { printf("memset n %d da %d\n", n, da); bad++; }
				for (int off = -40; off <= 40; off += 7) {   /* overlapping both ways */
					fill(b, sizeof b); for (int i = 0; i < 1024; i++) r[i] = b[i];
					unsigned char tmp[400];
					int s = 300 + sa, d = 300 + sa + off + da;
					for (int i = 0; i < n; i++) tmp[i] = r[s + i];
					for (int i = 0; i < n; i++) r[d + i] = tmp[i];
					ret = memmove(b + d, b + s, n);
					if (ret != b + d || memcmp(b, r, sizeof r)) { printf("memmove n %d off %d da %d sa %d\n", n, off, da, sa); bad++; }
				}
				fill(a, sizeof a);
				for (int i = 0; i < 1024; i++) if (!a[i]) a[i] = 1;
				a[64 + sa + n] = 0;
				size_t l = strlen((char *) a + 64 + sa);
				if (l != (size_t) n) { printf("strlen n %d sa %d got %zu\n", n, sa, l); bad++; }
			}
	printf("%s (%d bad)\n", bad ? "FAIL" : "ok", bad);
	return bad != 0;
}
