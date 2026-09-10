.segment "CODE"
.byte $01, $02, $03
.word $1234, $5678
.asciiz "hello"
label:
	.res 4, $ff
