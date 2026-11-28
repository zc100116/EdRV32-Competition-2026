/* File: smoke.S; Spec: cpu-v2-testplan CV01; Clock: clk_sys. */
.section .text.init
.globl _start
_start:
    li t0, 17
    li t1, 3
    add t2, t0, t1
    li t3, 20
    bne t2, t3, fail
    la t0, tohost
    li t1, 1
    sw t1, 0(t0)
1:  j 1b
fail:
    la t0, tohost
    li t1, 3
    sw t1, 0(t0)
    j fail
.section .tohost,"aw"
.balign 64
.globl tohost
tohost: .dword 0
