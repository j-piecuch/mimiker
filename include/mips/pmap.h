#ifndef __MIPS_PMAP_H__
#define __MIPS_PMAP_H__

#include <mips/mips.h>

#define PTE_MASK 0xfffff000
#define PTE_SHIFT 12
#define PTE_SIZE 4
#define PTE_SIZE_BITS 2
#define PDE_MASK 0xffc00000
#define PDE_SHIFT 22

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

#define KPT_PHYS_BASE 0
#define KPT_KSEG0_BASE MIPS_PHYS_TO_KSEG0(KPT_PHYS_BASE)
#define KPT_KSEG2_BASE (MIPS_KSEG2_START + 0x300000)

#define KPD_PHYS_BASE 0x100000
#define KPD_KSEG0_BASE MIPS_PHYS_TO_KSEG0(KPD_PHYS_BASE)
#define KPD_KSEG2_BASE (MIPS_KSEG2_START + 0x401000)

#define KERNEL_KSEG2_BASE 0xc0402000

#define KVA_START MIPS_KSEG2_START
#define KVA_END   0xe0000000

#define PT_BASE MIPS_KSEG2_START
#define PD_BASE (PT_BASE + PT_SIZE)

#endif /* !__MIPS_PMAP_H__ */
