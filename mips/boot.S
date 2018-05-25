#define _BOOTCODE /* Put code in .boot section */
#include <mips/asm.h>
#include <mips/pcpu.h>
#include <mips/regdef.h>
#include <mips/m32c0.h>

#include "assym.h"

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

        la      sp, __boot_stack

        # Put boot arguments on the stack so that we can pass a pointer
        # to argv and envp to boot_init.
        addi    sp, -16
        sw      a0, 0(sp)       # argc
        sw      a1, 4(sp)       # argv
        sw      a2, 8(sp)       # envp
        sw      a3, 12(sp)      # memsize

        # The first argument to boot_init is argc, so we don't change a0
        addi    a1, sp, 4       # 2nd argument = pointer to argv
        jal     boot_init
        addi    a2, sp, 8       # (delay slot) 3rd argument = pointer to envp

        # The return value of boot_init is a kseg0 pointer to the new end of
        # kernel .bss section. We'd like to pass it to platform_init, but
        # we can't do it using registers because up to 4 arguments can be passed
        # via registers. Therefore, we put all arguments on the stack and pass
        # a pointer to the stack frame.

        addi    sp, -4
        sw      v0, 0(sp)       # Store the return value of boot_init on the stack

        move    a0, sp          # Pass a pointer to the frame

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
        la      t0, ctx_switch
        jr      t0
        nop
END(_start)

# vim: sw=8 ts=8 et
