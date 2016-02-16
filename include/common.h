#ifndef __COMMON_H__
#define __COMMON_H__

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <mips/cpu.h>
#include <mips/mips32.h>
#include <mips/m32c0.h>

/* Flag operations */
#define SET(t, f)   ((t) |= (f))
#define CLR(t, f)   ((t) &= ~(f))
#define INV(t, f)   ((t) ^= (f))
#define ISSET(t, f) ((t) & (f))

/* Bit operations */
#define B_SET(n, b)   ((n) |=  (1 << (b)))
#define B_CLR(n, b)   ((n) &= ~(1 << (b)))
#define B_INV(n, b)   ((n) ^=  (1 << (b)))
#define B_ISSET(n, b) ((n) & (1 << (b)))

/* Macros for counting and rounding. */
#define howmany(x, y) (((x) + ((y) - 1)) / (y))

/* Useful macros */
#define STR_NOEXPAND(x) #x     /* This does not expand x. */
#define STR(x) STR_NOEXPAND(x) /* This will expand x. */

/* Target platform properties */
#define NBBY 8 /* Number of Bits per BYte */

/* Aligns the address to given size (must be power of 2) */
#define ALIGN(addr, size) (((uintptr_t)(addr) + (size) - 1) & ~((size) - 1))

#endif // __COMMON_H__