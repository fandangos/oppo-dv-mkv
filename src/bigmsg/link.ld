/* after xtload (0x1c07b00..0x1c07b9c) in the jailbreak's free .text1 tail (RWX); header first */
SECTIONS {
  . = 0x1c07c00;
  .text : { *(.hdr) *(.text*) *(.rodata*) *(.data*) *(.bss*) *(COMMON) }
  /DISCARD/ : { *(.ARM.*) *(.comment) }
}
