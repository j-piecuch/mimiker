#include <mips/asm.h>
#include <mips/pcpu.h>
#include <mips/regdef.h>
#include <mips/m32c0.h>
#include <mips/mips.h>
#include <mips/pmap.h>
#include "assym.h"

#define PTE_KERNEL (ENTRYLO0_D_MASK | ENTRYLO0_G_MASK | ENTRYLO0_V_MASK)
#define NKPTE ((KVA_END - KVA_START) >> PTE_SHIFT)
#define NKPTF (((NKPTE * PTE_SIZE - 1) >> PTE_SHIFT) + 1)


        # t0 = page frame address
# t1 = index into page table
# t2 = how many pages to map
# base: page table base address
# flags: PTE flags
#define FILL_PTES(base, flags)                    \
        li      t3, base                        ; \
        sll     t1, PTE_SIZE_BITS               ; \
        addu    t1, t3                          ; \
        srl     t0, PTE_SHIFT                   ; \
        sll     t0, ENTRYLO0_PFN_SHIFT          ; \
        ori     t0, flags                       ; \
1:      addiu   t2, -1                          ; \
        sw      t0, 0(t1)                       ; \
        addiu   t0, (1 << ENTRYLO0_PFN_SHIFT)   ; \
        bnez    t2, 1b                          ; \
        addiu   t1, PTE_SIZE


        .set noreorder

# Boot environment is described in MIPS® YAMON™ User's Manual, Chapter 5
# ... and MIPS® YAMON™ Reference Manual, Chapter 8.3
#
# $a0 = argc
# $a1 = argv
# $a2 = envp
# $a3 = memsize
#
# $sp is initialized
# $gp is not initialized
#
# C0_STATUS is same as YAMON™ context, but interrupts are disabled.

        .section .boottext

LEAF(_start)

        # Load global pointer to make data section addressing possible
        LA      gp, _gp

        # Mask out software and hardware interrupts,
        # ensure we're in kernel mode, disable FPU,
        # leave error level & exception level and disable interrupts.
        mfc0    t0, C0_STATUS
        li      t1, ~(SR_IPL_MASK|SR_KSU_MASK|SR_CU1|SR_ERL|SR_EXL|SR_IE)
        and     t0, t1
        mtc0    t0, C0_STATUS

        # Clear pending software and hardware interrupts
        mfc0    t0, C0_CAUSE
        li      t1, ~CR_IP_MASK
        and     t0, t1
        mtc0    t0, C0_CAUSE

        # Get the maximum TLB index
        mfc0    t0, C0_CONFIG1
        ext     t0, CFG1_MMUS_SHIFT, CFG1_MMUS_BITS
        
        # Initialize the TLB
        # Code taken from section 4.9.3 of
        # MIPS® Architecture For Programmers,
        # Volume III: The MIPS32® and microMIPS32™ Privileged Resource Architecture

        # Clear PageMask, EntroLo0 and EntryLo1 so that valid bits are off, PFN values
        # are zero, and the default page size is used.
        mtc0    zero, C0_ENTRYLO0       # Clear out PFN and valid bits
        mtc0    zero, C0_ENTRYLO1

        # Start with the base address of kseg0 for the VPN2
        la      t1, MIPS_KSEG0_START

        # Write the VA candidate to EntryHi and probe the TLB to see if it's
        # already there. If it is, a write to the TLB may cause a machine check,
        # so just increment the VA candidate by 2 pages and try again.
1:
        mtc0    t1, C0_ENTRYHI
        ehb                             # Clear EntryHi hazard
        tlbp
        ehb                             # Clear Index hazard
        mfc0    t2, C0_INDEX            # Read back flag to check for match
        bgez    t2, 1b                  # Branch if about to duplicate entry
        addiu   t1, (1 << C0_ENTRYHI_VPN2_SHIFT) # Add 1 to VPN2

        # A write of the VPN2 candidate will be unique, so write this entry
        # into the next index, decrement the index, and continue until the
        # index goes negative (thereby writing all TLB entries)
        mtc0    t0, C0_INDEX
        ehb                             # Clear Index hazard
        tlbwi
        bnez    t0, 1b                  # Loop if more TLB entries to do
        addiu   t0, -1                  # (delay slot) Decrement the TLB index

        # The TLB has been initialized.

        # Fill the KPT.
        # The virtual base address of the kernel (start of .text)
        # is KERNEL_BASE. The physical load address of the start
        # of .text is KERNEL_LOAD.

        la      t0, __kernel_phys_start
        li      t1, ((KERNEL_KSEG2_BASE - MIPS_KSEG2_START) >> PTE_SHIFT)
        li      t2, NKPTE
        FILL_PTES(KPT_KSEG0_BASE, PTE_KERNEL)
        # Fill the KPD
        move    t0, zero                # t0 = page frame address
        li      t1, (MIPS_KSEG2_START >> PDE_SHIFT) # t1 = index into page table
        li      t2, NKPTF               # t2 = how many pages to map
        FILL_PTES(KPD_KSEG0_BASE, PTE_KERNEL)

        # kseg2 has been mapped.
        # Now it should be safe to jump to the remainder of kernel code,
        # which is linked to execute in kseg2.

        # Initialize the platform
        la      t0, platform_init
        jalr    t0
        nop

        # Switch to kernel main thread
        LOAD_PCPU(t0)
        move    a0, zero
        PTR_L   a1, PCPU_CURTHREAD(t0)
        j       ctx_switch
        nop
END(_start)

# vim: sw=8 ts=8 et
