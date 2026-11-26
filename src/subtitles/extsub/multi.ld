/* several external subtitles: a 64 KiB RWX region extsub.sh has the loader stub map at 0x1b90000 (after the Extras
   page's 0x1b80000; unused gap before .text1 0x1c00000); header first. .bss stays inside the region. */
SECTIONS {
  . = 0x1b90000;
  .text : { *(.hdr) *(.text*) *(.rodata*) *(.data*) }
  .bss : { *(.bss*) *(COMMON) }
  /DISCARD/ : { *(.ARM.*) *(.comment) }
}
