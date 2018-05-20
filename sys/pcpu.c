#include <thread.h>
#include <pcpu.h>
#include <common.h>

pcpu_t __section(".pcpu") _pcpu_data[1] = {{}};

static thread_t *dummy =
  &(thread_t){.td_name = "dummy thread", .td_tid = 0, .td_idnest = 1};

void pcpu_init(void) {
  PCPU_SET(curthread, dummy);
}
