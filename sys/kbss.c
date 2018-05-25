#include <kbss.h>
#include <stdc.h>
#include <vm.h>

/* The end of the kernel's .bss section BEFORE boot args are copied
 * (see cboot.c). Provided by the linker. */
extern uint8_t __ebss[];

static struct {
  /* Pointer to free memory used to service allocation requests. */
  void *ptr;
  /* Allocation limit -- initially NULL, can be set only once. */
  void *end;
} kbss = {__ebss, NULL};

void kbss_init(void *new_ebss) {
  extern uint8_t __bss[];
  bzero(__bss, __ebss - __bss);
  kbss.ptr = new_ebss;
}

void *kbss_grow(size_t size) {
  void *ptr = kbss.ptr;
  size = roundup(size, sizeof(uint64_t));
  if (kbss.end != NULL)
    assert(ptr + size <= kbss.end);
  kbss.ptr += size;
  bzero(ptr, size);
  return ptr;
}

void *kbss_fix(void) {
  assert(kbss.end == NULL);
  kbss.end = align(kbss.ptr, PAGESIZE);
  return kbss.end;
}
