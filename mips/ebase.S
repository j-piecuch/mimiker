#include <mips/ctx.h>
#include <mips/m32c0.h>
#include <mips/regdef.h>
#include <mips/tlb.h>
#include "assym.h"

#define PDE_SHIFT 22
#define PT_SIZE (1 << 22)
#define PD_BASE (PT_BASE + (PT_BASE >> 12) * 4)
#define PT_BASE_UPPER (PT_BASE >> 16)
#define PD_BASE_UPPER (PD_BASE >> 16)

        # Don't allow the assembler to reorder instructions.
        .set	noreorder
        # Forbid the assembler from using $at register.
        .set	noat

        .global _ebase
        .type   tlb_refill,@function

        .section .ebase

_ebase:

        .org    0x0
        .local  tlb_refill

tlb_refill:
        # We don't want to generate TLB misses during tlb_refill.

        mfc0    k0, C0_CONTEXT
        sra     k0, 1
        lui     k1, 0x0020
        addu    k0, k0, k1                              # k0 = address of PTE of even page from the pair

        # Check if it's safe to access the PT (is there a valid entry in the TLB?)
        mfc0    k1, C0_ENTRYHI                          # Save original EntryHi for later.
        ins     k0, k1, 0, C0_ENTRYHI_VPN2_SHIFT        # Copy current ASID.
        mtc0    k0, C0_ENTRYHI
        ehb
        tlbp
        ehb
        mfc0    k0, C0_INDEX
        # Index < 0 means there was no entry with matching VPN2.
        bltz    k0, miss
        mtc0    k1, C0_ENTRYHI                          # (delay slot) Restore original EntryHi.
hit:
        # We found an entry with matching VPN2.
        # Normally this wouldn't mean that that the access is safe because
        # TLB entries map pairs of pages, which means one could be valid while
        # the other is invalid. However, the system allocates PTFs in pairs,
        # so in the case of accesses to the Page Table both entries are valid.

        mfc0    k0, C0_CONTEXT
        sra     k0, 1
        lui     k1, 0x0020
        addu    k0, k0, k1

        # Simply grab the PTEs and load them into the TLB.
        lw      k1, 0(k0)
        mtc0    k1, C0_ENTRYLO0
        lw      k1, 4(k0)
        mtc0    k1, C0_ENTRYLO1
        ehb
        tlbwr
        eret
miss:
        # Find PDE mapping the Page Table Fragment we want to access.
        mfc0    k1, C0_BADVADDR
        srl     k1, PDE_SHIFT                   # k1 = PDE index
        sll     k1, 2                           # k1 = PDE offset = PDE index * 4
        lui     k0, PT_BASE_UPPER
        addu    k0, k0, k1
        lw      k1, PD_BASE-PT_BASE(k0)         # Load PDE.
        andi    k1, ENTRYLO0_V_MASK             # Is it valid?
        beqz    k1, invalid
        # Note: no nop inside delay slot -- executing the ins instruction
        # won't hurt us if we jump to invalid.

valid:
        # Load the PDE into the TLB.
        ins     k0, zero, 2, 1                          # Clear bit 2.
        lw      k1, PD_BASE-PT_BASE(k0)
        mtc0    k1, C0_ENTRYLO0
        lw      k1, PD_BASE-PT_BASE+4(k0)
        mtc0    k1, C0_ENTRYLO1

        mfc0    k1, C0_CONTEXT
        sra     k1, 1
        lui     k0, 0x0020
        addu    k0, k0, k1
        mfc0    k1, C0_ENTRYHI                          # Save original EntryHi for later.
        ins     k0, k1, 0, C0_ENTRYHI_VPN2_SHIFT        # Copy ASID from original EntryHi.
        mtc0    k0, C0_ENTRYHI
        ehb
        tlbwr
        ehb
        j       hit
        mtc0    k1, C0_ENTRYHI                          # (delay slot) Restore original EntryHi.
invalid:
        # The access is invalid, so write invalid entries into the TLB.
        # Retrying the instruction that missed in the TLB is going to generate
        # a TLB invalid exception (but not another TLB miss).
        mtc0    zero, C0_ENTRYLO0
        mtc0    zero, C0_ENTRYLO1
        ehb
        tlbwr
        eret

        .org    0x100
        .local  cache_error

cache_error:
1:      j       1b
        nop

        .org    0x180
        .local  general_exception

general_exception:
        la      k1, mips_exc_handler
        j       exc_enter
        mfc0    k0, C0_STATUS           # (delay slot) load status register

        .org    0x200
        .local  irq

irq:
        la      k1, mips_intr_handler
        j       exc_enter
        mfc0    k0, C0_STATUS           # (delay slot) load status register


# vim: sw=8 ts=8 et
