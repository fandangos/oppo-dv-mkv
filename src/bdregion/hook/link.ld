/* the jailbreak's free .text1 area 0x1c03a00..0x1c03fff (RWX); header first */
SECTIONS {
  . = 0x1c03a00;
  .text : { *(.hdr) *(.text.gate) *(.text*) *(.rodata*) *(.data*) *(.bss*) *(COMMON) }
  /DISCARD/ : { *(.ARM.*) *(.comment) }
}
