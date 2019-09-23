#ifndef _SYS_SYSENT_H_
#define _SYS_SYSENT_H_

#include <sys/cdefs.h>
#include <sys/syscall.h>

typedef struct thread thread_t;

#define SYSCALL_ARGS_MAX 4

typedef struct syscall_args {
  register_t code;
  register_t args[SYSCALL_ARGS_MAX];
} syscall_args_t;

typedef int syscall_t(thread_t *, syscall_args_t *);

typedef struct {
  syscall_t *call;
} sysent_t;

extern sysent_t sysent[];

#endif /* !_SYS_SYSENT_H_ */
