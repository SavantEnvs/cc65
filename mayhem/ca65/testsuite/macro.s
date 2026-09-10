.macro add8 arg
	clc
	adc #arg
.endmacro
.repeat 3, i
	add8 i
.endrepeat
.proc foo
	rts
.endproc
