#ifndef _SYS_CONTEXT_H_
#define _SYS_CONTEXT_H_

#include <sys/cdefs.h>
#include <sys/types.h>

typedef struct thread thread_t;
typedef struct __ucontext ucontext_t;
typedef struct ctx ctx_t;
typedef struct mcontext user_ctx_t;

/*! \brief Prepare ctx to jump into a kernel thread. */
void ctx_init(ctx_t *ctx, void *pc, void *sp);

/*! \brief Set args and return address for context that calls a procedure. */
void ctx_setup_call(ctx_t *ctx, register_t retaddr, register_t arg);

/*! \brief Sets a value that will be returned by ctx_switch. */
void ctx_set_retval(ctx_t *ctx, long value);

/*! \brief Copy user exception ctx. */
void user_ctx_copy(user_ctx_t *to, user_ctx_t *from);

/*! \brief Prepare ctx to jump into a user-space program. */
void user_ctx_init(user_ctx_t *ctx, void *pc, void *sp);

/*! \brief Set a return value within the ctx and advance the program counter.
 *
 * Useful for returning values from syscalls. */
void user_ctx_set_retval(user_ctx_t *ctx, register_t value, register_t error);

/* This function stores the current context to @from, and resumes the
 * context stored in @to. It does not return immediatelly, it returns
 * only when the @from context is resumed.
 *
 * When switching it atomically releases @from thread spin lock (if applicable)
 * and acquires @to thread spin lock (if TDF_NEEDLOCK is set for it).
 *
 * \returns a value set by \a ctx_set_retval or 0 otherwise.
 */
long ctx_switch(thread_t *from, thread_t *to);

/* Implementation of setcontext syscall. */
int do_setcontext(thread_t *td, ucontext_t *uc);

#endif /* !_SYS_CONTEXT_H_ */
