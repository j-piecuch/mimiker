/* Linker scripts are documented here:
 * https://sourceware.org/binutils/docs/ld/Scripts.html */
OUTPUT_ARCH(mips)
ENTRY(_start)
PHDRS
{
  lowmem PT_LOAD FLAGS(5);
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
  . += 4K;      /* kernel page directory */
  __exc_phys_start = . - _ram;
  .exc 0x80101000: AT(__exc_phys_start)
  {
    /* Exception handlers. */
    *(.exc)
    . = ALIGN(4096);
  } : lowmem

  __boottext_phys_start = __exc_phys_start + SIZEOF(.exc);
  .boottext : AT(__boottext_phys_start)
  {
    *(.boottext)
    . = ALIGN(4096);
  } : lowmem

  __kernel_phys_start = __boottext_phys_start + SIZEOF(.boottext);
  .text 0xc0402000:
    AT(__kernel_phys_start) ALIGN(4096)
  {
    __kernel_start = .;
    __text = ABSOLUTE(.);
    *(.text .text.*)
    . = ALIGN(4096);
    __etext = ABSOLUTE(.);
  } : text

  /* The kernel expects the ramdisk start & end addresses
   * to be page-aligned. */
  __rd_phys_start = __kernel_phys_start + SIZEOF(.text);
  .initrd : AT(__rd_phys_start) ALIGN(4096)
  {
    __rd_start = ABSOLUTE(.);
    *(.initrd)
    . = ALIGN(4096);
    __rd_end = ABSOLUTE(.);
  } : rodata /* The ramdisk is read-only, so place it in read-only segment. */

  /* In order to be addressable using a 16-bit signed offset from _gp,
   * this section must be placed close to the .data section, as
   * _gp is defined here as the start of the .data section.  */
  __rodata_phys_start = __rd_phys_start + SIZEOF(.initrd);
  .rodata : AT(__rodata_phys_start) ALIGN(4)
  {
     *(.rodata .rodata.*)
     . = ALIGN(4096);
  } : rodata

  __data_phys_start = __rodata_phys_start + SIZEOF(.rodata);
  .data : AT(__data_phys_start) ALIGN(4096)
  {
    __data = ABSOLUTE(.);
    _gp = .;
    *(.data .data.*)
    *(.sdata .sdata.*)
    *(.eh_frame .eh_frame.*)
    . = ALIGN (4);
    __edata = ABSOLUTE(.);
  } : data

  __bss_phys_start = __data_phys_start + SIZEOF(.data);
  .bss : AT(__bss_phys_start) ALIGN(4)
  {
    __bss = ABSOLUTE(.);
    *(.sbss .scommon)
    *(.bss .bss.*)
    *(COMMON)
    . = ALIGN (4096);
    __ebss = ABSOLUTE(.);
  }
  __ebss_phys = __bss_phys_start + SIZEOF(.bss);

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
