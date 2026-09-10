; mayhem/ld65-cfg/fixture.s — source of fixture.o, the object every fuzzed linker config is linked
; against (assembled with `ca65 -g`). It carries the five standard segments plus the empty header
; segments and exports every `type = import` symbol the shipped cfg/*.cfg files expect, so 77 of the
; 86 upstream configs link it to completion (the fuzzer reaches memory-area placement + output writing,
; not just the config parser).
.export __AUTOSTART__: absolute = 1
.export __BANKRAMADDR__: absolute = 1
.export __BASHDR__: absolute = 1
.export __BLLHDR__: absolute = 1
.export __BOOTLDR__: absolute = 1
.export __CART_ENTRY__: absolute = 1
.export __CART_HEADER__: absolute = 1
.export __DEFDIR__: absolute = 1
.export __EXEHDR__: absolute = 1
.export __LOADADDR__: absolute = 1
.export __ORIXHDR__: absolute = 1
.export __OVERLAYADDR__: absolute = 1
.export __STARTUP__: absolute = 1
.export __SYSTEM_CHECK__: absolute = 1
.export __TAPEHDR__: absolute = 1
.export __TGIHDR__: absolute = 1
.export __UPLOADER__: absolute = 1
.export _cas_hdr: absolute = 1
.export main
.segment "LOADADDR"
.segment "EXEHDR"
.segment "STARTUP"
.segment "LOWCODE"
.segment "ONCE"
.segment "INIT"
.code
main:   lda #$01
        rts
.rodata
tab:    .byte 1, 2, 3
.data
var:    .word $1234
.bss
buf:    .res 16
