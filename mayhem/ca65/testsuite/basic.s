	lda #$01
	sta $0200
	ldx #$00
loop:	inx
	bne loop
	rts
