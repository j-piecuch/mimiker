/* Linker scripts are documented here:
 * https://sourceware.org/binutils/docs/ld/Scripts.html */
OUTPUT_ARCH(mips)
ENTRY(_start)
PHDRS
{
  /* The lowmem segment is for things like boot code,
   * exception handlers and debug data/routines that all
   * must be in kseg0. It has all permission bits set
   * because it contains code as well as writable data. */
  lowmem PT_LOAD FLAGS(7);      /* read-write, executable */
  text   PT_LOAD FLAGS(5);      /* read-only, executable */
  rodata PT_LOAD FLAGS(4);      /* read-only */
  data   PT_LOAD FLAGS(6);      /* read-write */
}
PROVIDE(__tlb_stride_length = 1);
SECTIONS
{
  /* RAM is mapped in kseg0 (cacheable) and kseg1 (non-cacheable) */
  _ram = 0x80000000;

  . = _ram;
  . += 1M;      /* kernel page table */
  __ebase_phys_start = . - _ram;
  .ebase 0x80100000: AT(__ebase_phys_start)
  {
    /* Exception entry points. */
    *(.ebase)
  } : lowmem

  .boot : ALIGN(4)
  {
    *(.boot)
    *cboot.o(.text)
  } : lowmem

  .text.kseg0 : ALIGN(4)
  {
    *(.text.kseg0)
  } : lowmem

  .data.kseg0 : ALIGN(4)
  {
    *(.data.kseg0)
  } : lowmem

  .pcpu : ALIGN(4)
  {
    *(.pcpu)
  } : lowmem

  .text.wired : ALIGN(4)
  {
    *exc.o(.text)
    *(.text.wired)
  } : lowmem

  . += 4K; /* Boot stack */
  . = ALIGN(4096);
  __boot_stack = .;

  . = 0xc0401000;
  __kpd = .;
  __kpd_phys = LOADADDR(.text.wired) + (__boot_stack - ADDR(.text.wired));
  . += 4096;
  __kernel_phys_start = __kpd_phys + 4096;
  .text : AT(__kernel_phys_start)
  {
    __kernel_start = ABSOLUTE(.);
    __text = ABSOLUTE(.);
    EXCLUDE_FILE (*exc.o *cboot.o) *(.text .text.*)
    . = ALIGN(4096);
    __etext = ABSOLUTE(.);
  } : text

  /* The kernel expects the ramdisk start & end addresses
   * to be page-aligned. */
  .initrd :
  {
    __rd_start = ABSOLUTE(.);
    *(.initrd)
    . = ALIGN(4096);
    __rd_end = ABSOLUTE(.);
  } : rodata /* The ramdisk is read-only, so place it in read-only segment. */

  /* In order to be addressable using a 16-bit signed offset from _gp,
   * this section must be placed close to the .data section, as
   * _gp is defined here as the start of the .data section.  */
  .rodata : ALIGN(4)
  {
     *(.rodata .rodata.*)
     . = ALIGN(4096);
  } : rodata

  .data :
  {
    __data = ABSOLUTE(.);
    _gp = .;
    . += 4096;

    *(.data .data.*)
    *(.sdata .sdata.*)
    *(.eh_frame .eh_frame.*)
    . = ALIGN (4096);
    __edata = ABSOLUTE(.);
  } : data
  __data_phys = LOADADDR(.data);

  .bss :
  {
    __bss = ABSOLUTE(.);
    *(.sbss .scommon)
    *(.bss .bss.*)
    *(COMMON)
    . = ALIGN (4096);
    __ebss = ABSOLUTE(.);
  }
  __bss_phys = LOADADDR(.bss);
  __ebss_phys = LOADADDR(.bss) + SIZEOF(.bss);

  /* Sections to be discarded */
  /DISCARD/ :
  {
    *(.comment)
    *(.note)
    *(.options)
    *(.pdr)
    *(.reginfo)
    *(.gnu.attributes)
    *(.MIPS.abiflags)
    *(.MIPS.options)
  }
}
