/* memcpy, memmove, memset and strlen for i386, linked into BusyBox in place of zig's (build.sh). Zig's libc takes
 * them from its compiler-rt, which for a program built for size (-Os, as BusyBox is) copies and fills a byte at a
 * time. On the Tab5's emulated PC a REP MOVSD or REP STOSD is done in bulk, so these use them for 16 bytes or more,
 * and plain loops below that (and for the last 0-3 bytes), which stay in the emulator's translated code.
 * strlen looks at a word at a time once aligned (a word read never crosses a page). */

	.text

	.globl memcpy
	.type memcpy, @function
memcpy:	/* void *memcpy(void *d, const void *s, size_t n) */
	push %esi
	push %edi
	mov 12(%esp), %edi
	mov 16(%esp), %esi
	mov 20(%esp), %ecx
	mov %edi, %eax
	cmp $16, %ecx
	jb 2f
	mov %ecx, %edx
	shr $2, %ecx
	rep movsl
	mov %edx, %ecx
	and $3, %ecx
2:	test %ecx, %ecx
	jz 3f
1:	movb (%esi), %dl
	movb %dl, (%edi)
	inc %esi
	inc %edi
	dec %ecx
	jnz 1b
3:	pop %edi
	pop %esi
	ret
	.size memcpy, .-memcpy

	.globl memmove
	.type memmove, @function
memmove:	/* void *memmove(void *d, const void *s, size_t n): forwards unless d lies within s .. s + n */
	mov 4(%esp), %eax
	sub 8(%esp), %eax
	cmp 12(%esp), %eax
	jae memcpy
	push %esi
	push %edi
	mov 12(%esp), %edi
	mov 16(%esp), %esi
	mov 20(%esp), %ecx
	lea -1(%edi,%ecx), %edi
	lea -1(%esi,%ecx), %esi
	std
	rep movsb
	cld
	mov 12(%esp), %eax
	pop %edi
	pop %esi
	ret
	.size memmove, .-memmove

	.globl memset
	.type memset, @function
memset:	/* void *memset(void *d, int c, size_t n) */
	push %edi
	mov 8(%esp), %edi
	movzbl 12(%esp), %eax
	mov 16(%esp), %ecx
	cmp $16, %ecx
	jb 2f
	imul $0x01010101, %eax, %eax
	mov %ecx, %edx
	shr $2, %ecx
	rep stosl
	mov %edx, %ecx
	and $3, %ecx
2:	test %ecx, %ecx
	jz 3f
1:	movb %al, (%edi)
	inc %edi
	dec %ecx
	jnz 1b
3:	mov 8(%esp), %eax
	pop %edi
	ret
	.size memset, .-memset

	.globl strlen
	.type strlen, @function
strlen:	/* size_t strlen(const char *s) */
	mov 4(%esp), %eax
1:	testb $3, %al		/* bytes up to a word boundary */
	jz 2f
	cmpb $0, (%eax)
	je 5f
	inc %eax
	jmp 1b
2:	push %ebx
3:	mov (%eax), %edx	/* a word: has it a zero byte? */
	lea -0x01010101(%edx), %ebx
	not %edx
	and %edx, %ebx
	and $0x80808080, %ebx
	jnz 4f
	add $4, %eax
	jmp 3b
4:	pop %ebx
6:	cmpb $0, (%eax)		/* which one */
	je 5f
	inc %eax
	jmp 6b
5:	sub 4(%esp), %eax
	ret
	.size strlen, .-strlen

	.section .note.GNU-stack, "", @progbits
