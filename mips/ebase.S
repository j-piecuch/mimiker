#include <mips/ctx.h>
#include <mips/m32c0.h>
#include <mips/regdef.h>
#include <mips/tlb.h>
#include "assym.h"

#define PDE_SHIFT 22
#define PT_SIZE (1 << 22)
#define PD_BASE (PT_BASE + PT_SIZE)
#define PT_BASE_UPPER (PT_BASE >> 16)
#define PD_BASE_UPPER (PD_BASE >> 16)
#define KSEG2_FIRST_PDE_IDX (MIPS_KSEG2_START >> PDE_SHIFT)


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

        # Special case: an access was made to the PT from outside tlb_refill.
        # This needs to be checked and handled separately.

        mfc0    k0, C0_BADVADDR
        srl     k1, k0, 22
        addi    k1, k1, -(PT_BASE >> 22)
        beqz    k1, pt_access
        nop

        mfc0    k0, C0_CONTEXT
        sra     k0, 1                           # k0 = address of PTE of even page from the pair

        # Check if it's safe to access the PT (is the mapping in the TLB?)
        ins     k0, zero, 0, PAGE_SHIFT + 1     # Clear 13 least significant bits.
        mfc0    k1, C0_ENTRYHI                  # Save original EntryHi for later.
        mtc0    k0, C0_ENTRYHI
        ehb
        tlbp
        ehb
        mtc0    k1, C0_ENTRYHI                  # Restore original EntryHi.
        mfc0    k1, C0_INDEX
        bltz    k1, miss                        # Index < 0 means the mapping isn't in the TLB.
        nop
hit:
        # If the mapping is there, access the PT and write the entry mapping BadVAddr into the TLB.
        # It might be invalid, but that's not our problem.
        mfc0    k0, C0_CONTEXT
        sra     k0, 1
        lw      k1, 0(k0)
        mtc0    k1, C0_ENTRYLO0
        lw      k1, 4(k0)
        mtc0    k1, C0_ENTRYLO1
        ehb
        tlbwr
        eret
miss:
        # Find PDE mapping the Page Table Fragment we want to access.
        # If BadVAddr is in kuseg, look in user PD. If it's in kseg2, look in kernel PD.
        mfc0    k1, C0_BADVADDR
        srl     k1, PDE_SHIFT                   # k1 = PDE index
        sll     k1, 2                           # k1 = PDE offset = PDE index * 4
        slti    k0, k1, KSEG2_FIRST_PDE_IDX * 4
        xori    k0, k0, 1
        sll     k0, PAGE_SHIFT                  # k0 = <BadVAddr in kuseg> ? 0 : PAGESIZE
        addu    k0, k0, k1
        li      k1, PD_BASE
        addu    k0, k0, k1                      # k0 = address of PDE
        lw      k1, 0(k0)                       # Load PDE.
        andi    k1, ENTRYLO0_V_MASK             # Is it valid?
        beqz    k1, invalid
        # Note: no nop inside delay slot -- executing the ins instruction
        # won't hurt us if we jump to invalid.

valid:
        # Load the PDE into the TLB.
        ins     k0, zero, 2, 1                  # Clear bit 2.
        lw      k1, 0(k0)
        mtc0    k1, C0_ENTRYLO0
        lw      k1, 4(k0)
        mtc0    k1, C0_ENTRYLO1

        # Check if we accessed user or kernel PD.
        li      k1, PD_BASE + PAGESIZE
        sub     k1, k0, k1                      # k1 < 0 if we accessed user PD.
        sra     k1, 31                          # k1 = <accessed user PD> ? 0xffffffff : 0
        mfc0    k0, C0_ENTRYHI
        and     k0, k0, k1
        mfc0    k1, C0_CONTEXT
        sra     k1, 1

        # If we accessed the user PD, the ASID of the TLB entry should be
        # the ASID of the thread that caused the exception.
        # Otherwise, the ASID should be 0 (ASID reserved for the kernel).
        ins     k1, k0, 0, PAGE_SHIFT + 1

        mfc0    k0, C0_ENTRYHI                  # Save original EntryHi.
        mtc0    k1, C0_ENTRYHI
        ehb
        tlbwr
        ehb
        j       hit
        mtc0    k0, C0_ENTRYHI                  # restore EntryHi (delay slot)
invalid:
        # The access is invalid, so write invalid entries into the TLB.
        # Retrying the instruction that missed in the TLB is going to generate
        # a protection fault (but not another TLB miss).
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

pt_access:
        # If we're accessing the user part of the PT, take PDE from UPD.
        # Otherwise lookup in KPD.
        lui     k1, PT_BASE_UPPER
        subu    k1, k0, k1              # k1 = offset into PT (22 bits)
        srl     k0, k1, 21              # k0 = if <accessing user part> then 0 else 1
        sll     k0, PAGE_SHIFT          # k0 = if <accessing user part> then 0 else PAGESIZE
        srl     k1, PAGE_SHIFT + 1      # k1 = index of even PDE in pair / 2
        sll     k1, 3                   # k1 = offset into PD
        addu    k0, k1, k0
        lui     k1, PD_BASE_UPPER
        addu    k0, k1, k0
        lw      k1, 0(k0)               # load even PDE
        mtc0    k1, C0_ENTRYLO0
        lw      k1, 4(k0)               # load odd PDE
        mtc0    k1, C0_ENTRYLO1
        ehb
        tlbwr
        eret
# vim: sw=8 ts=8 et
