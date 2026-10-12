/* bdpdrv1 symbols (module loaded at 0x7e8d3000 on RU 65-0131 firmware) and kernel symbols */
vdp_cont = 0x7eaac9a0;
i4VDecH265SPSPsr = 0x7eb22120;
vH265PreParseSPS = 0x7eb207c8;
VDP_SetEnable = 0x7e9a3f40;
jiffies = 0x805760c0;
rd_cont = 0x7e9fa2e0;
printk = 0x803f7df0;
orig_cont = 0x7ea9c7b8;
DOVI_CleanDCacheRange = 0x7eb5bc94;
SECTIONS {
  . = 0x7e98be80;
  .text : { *(.text.entry) *(.text*) *(.rodata*) }
  . = 0x7e98c748;
  .data : { *(.data.st) *(.data*) *(.bss*) }
  /DISCARD/ : { *(.ARM.*) *(.comment) }
}
