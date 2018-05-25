#include <mips/m32c0.h>
#include <mips/mips.h>
#include <mips/pmap.h>
#include <common.h>
#include <pmap.h>         /* TYPES AND MACROS ONLY */
#include <mips/tlb.h>     /* TYPES AND MACROS ONLY */
#include <vm.h>           /* TYPES AND MACROS ONLY */

#define PTE_KERNEL (ENTRYLO0_G_MASK | ENTRYLO0_V_MASK | ENTRYLO0_D_MASK)
#define TLBWI() asm volatile("tlbwi; ehb" : : : "memory")

extern uint8_t __ebss_phys[];
extern uint8_t _ebase[];
extern uint8_t __kernel_start[];
extern uint8_t __kernel_phys_start[];
extern uint8_t __kpd_phys[];

static inline  uint32_t boot_get_tlb_size(void) {
  uint32_t config1 = mips32_getconfig1();
  return _mips32r2_ext(config1, CFG1_MMUS_SHIFT, CFG1_MMUS_BITS) + 1;
}

static inline int boot_tlb_probe(tlbhi_t hi) {
  mips32_setentryhi(hi);
  asm volatile("tlbp; ehb" : : : "memory");
  return mips32_getindex();
}

static inline char *boot_strcpy(char *dst, char *src) {
  while ((*(dst++) = *(src++))) {}
  return dst;
}

static inline void boot_memcpy(void *dst, void *src, unsigned n) {
  char *cdst = dst, *csrc = src;
  while (n-- != 0)
    *(cdst++) = *(csrc++);
}

/*
 * Initialize the TLB to a known state.
 */
void boot_tlb_init(void) {
  uint32_t tlb_size = boot_get_tlb_size();

  tlbhi_t hi = MIPS_KSEG0_START & C0_ENTRYHI_VPN2_MASK;
  mips32_setpagemask(0);
  mips32_setentrylo0(0);
  mips32_setentrylo1(0);
  for (uint32_t i = 0; i < tlb_size; i++, hi += 2 * PAGESIZE) {
    mips32_setindex(i);
    if (boot_tlb_probe(hi) >= 0)
      continue;
    TLBWI();
  }
}

void boot_exc_init(void) {
  /*
   * Enable Vectored Interrupt Mode as described in „MIPS32® 24KETM Processor
   * Core Family Software User’s Manual”, chapter 6.3.1.2.
   */

  /* The location of exception vectors is set to EBase. */
  mips32_set_c0(C0_EBASE, _ebase);
  mips32_bc_c0(C0_STATUS, SR_BEV);
  /* Use the special interrupt vector at EBase + 0x200. */
  mips32_bs_c0(C0_CAUSE, CR_IV);
  /* Set vector spacing to 0. */
  mips32_set_c0(C0_INTCTL, INTCTL_VS_0);
}

/*
 * The bootloader places kernel arguments in the first megabyte of
 * physical memory, which is where we want to put the KPT. We need
 * to copy the arguments to a new location.
 */
void *boot_copy_args(int argc, char ***argvp, char ***envpp) {
  char **argv = *argvp, **envp = *envpp;
  void *kernel_end = (void *)MIPS_PHYS_TO_KSEG0(__ebss_phys);
  char **new_argv = kernel_end;

  /* Copy the argv array */
  kernel_end += argc * sizeof(void *);
  boot_memcpy(new_argv, argv, argc * sizeof(void *));

  int envp_len = 0;
  while (envp[envp_len] != NULL)
    envp_len++;
  char **new_envp = kernel_end;

  /* Copy the envp array */
  kernel_end += (envp_len + 1) * sizeof(void *);
  boot_memcpy(new_envp, envp, (envp_len + 1) * sizeof(void *));

  /* Copy the strings from the argv array */
  for (int i = 0; i < argc; i++) {
    new_argv[i] = kernel_end;
    kernel_end = boot_strcpy(kernel_end, argv[i]);
  }

  /* Copy the strings from the envp array */
  for (int i = 0; i < envp_len; i++) {
    new_envp[i] = kernel_end;
    kernel_end = boot_strcpy(kernel_end, envp[i]);
  }
  /* The envp array is NULL-terminated */
  new_envp[envp_len] = NULL;
  *argvp = new_argv;
  *envpp = new_envp;
  return align(kernel_end, 4);
}

/*
 * Initialize the KPT and KPD and add a wired mapping for KPD.
 */
void boot_kpt_init(void) {
  pte_t *kpt = (pte_t *)KPT_KSEG0_BASE;
  pte_t *kpd = (pte_t *)MIPS_PHYS_TO_KSEG0(__kpd_phys);

  /* First set all entries to global */
  for (unsigned i = 0; i < PTE_INDEX(KVA_END - MIPS_KSEG2_START); i++) {
    kpt[i] = PTE_GLOBAL;
  }
  for (unsigned i = 0; i < PD_ENTRIES; i++) {
    kpd[i] = PTE_GLOBAL;
  }

  /*
   * Now map the VA range __kernel_start - KVA_END to physical addresses
   * starting at __kernel_phys_start.
   */
  vm_paddr_t pa = (vm_paddr_t)__kernel_phys_start;
  for (vaddr_t va = (vaddr_t)__kernel_start; va < KVA_END;
       va += PAGESIZE, pa += PAGESIZE) {
    kpt[PTE_INDEX(va - MIPS_KSEG2_START)] = PTE_PFN(pa) | PTE_KERNEL;
  }

  /* Now map the KPT itself. */
  pa = (vm_paddr_t)KPT_PHYS_BASE;
  for (vaddr_t va = (vaddr_t)KPT_KSEG2_BASE; va < KVA_END;
       va += (1 << PDE_SHIFT), pa += PAGESIZE) {
    kpd[PDE_INDEX(va)] = PTE_PFN(pa) | PTE_KERNEL;
  }

  /* Wire the mapping for the KPD. */
  mips32_setentryhi(KPD_KSEG2_BASE & C0_ENTRYHI_VPN2_MASK);
  mips32_setentrylo0(PTE_GLOBAL);
  mips32_setentrylo1(PTE_PFN((uintptr_t)__kpd_phys) | PTE_KERNEL);
  mips32_setindex(0);
  TLBWI();
  mips32_setwired(1);

  /* Set the Context register so that it points to the page table (almost). */
  mips32_setcontext(PT_BASE << 1);
}

void *boot_init(int argc, char ***argvp, char ***envpp) {
  void *ret;
  boot_tlb_init();
  ret = boot_copy_args(argc, argvp, envpp);
  boot_kpt_init();
  boot_exc_init();
  return ret;
}
