VAL = 5
.if VAL > 3
	lda #(VAL*2)
.else
	lda #$00
.endif
.define ADDR $C000
	jmp ADDR
