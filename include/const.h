#ifndef _SYS_CONST_H_
#define _SYS_CONST_H_

/*
 * Some constant macros are used in both assembler and
 * C code. Therefore we cannot annotate them always with
 * 'UL' and other type specifiers unilaterally. We use
 * the following macros to deal with this.
 *
 * Similarly, _AT() will cast an expression with a type
 * in C, but leave it unchanged in asm.
 *
 * Stolen from the Linux kernel: include/uapi/linux/const.h
 */

#ifdef __ASSEMBLER__
#define _AC(X,Y) X
#define _AT(T,X) X
#else
#define __AC(X,Y) (X##Y)
#define _AC(X,Y) __AC(X,Y)
#define _AT(T,X) ((T)(X))
#endif

#endif /* !_SYS_CONST_H */
