#ifndef __MIPS_PMAP_H__
#define __MIPS_PMAP_H__

#include <mips/mips.h>

#define PTE_MASK 0xfffff000
#define PTE_SHIFT 12
#define PTE_SIZE 4
#define PTE_SIZE_BITS 2
#define PDE_MASK 0xffc00000
#define PDE_SHIFT 22

#define PTE_INDEX(x) (((x)&PTE_MASK) >> PTE_SHIFT)
#define PDE_INDEX(x) (((x)&PDE_MASK) >> PDE_SHIFT)

#define PD_ENTRIES 1024 /* page directory entries */
#define PD_SIZE (PD_ENTRIES * PTE_SIZE)
#define PTF_ENTRIES 1024 /* page table fragment entries */
#define PTF_SIZE (PTF_ENTRIES * PTE_SIZE)
#define PT_ENTRIES (PD_ENTRIES * PTF_ENTRIES)
#define PT_SIZE (PT_ENTRIES * PTE_SIZE)
#define PT_SIZE_BITS 22

#define PMAP_KERNEL_BEGIN MIPS_KSEG2_START
#define PMAP_KERNEL_END 0xfffff000 /* kseg2 & kseg3 */
#define PMAP_USER_BEGIN 0x00000000
#define PMAP_USER_END MIPS_KSEG0_START /* useg */

/* Physical/kseg0/kseg2 base addresses of Kernel Page Table */
#define KPT_PHYS_BASE 0
#define KPT_KSEG0_BASE MIPS_PHYS_TO_KSEG0(KPT_PHYS_BASE)
#define KPT_KSEG2_BASE (MIPS_KSEG2_START + 0x300000)

/* kseg2 base address of Kernel Page Directory */
#define KPD_KSEG2_BASE (MIPS_KSEG2_START + 0x401000)

/* kseg2 start address of the kernel image */
#define KERNEL_KSEG2_BASE 0xc0402000

/* Start & end addresses of Kernel Virtual Address Space */
#define KVA_START MIPS_KSEG2_START
#define KVA_END   0xe0000000

#define PT_BASE MIPS_KSEG2_START
#define PD_BASE (PT_BASE + PT_SIZE)

#endif /* !__MIPS_PMAP_H__ */
