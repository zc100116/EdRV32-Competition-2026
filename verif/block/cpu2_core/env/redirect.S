/* File: redirect.S; Spec: cpu-v2-testplan CV07/CV14; Clock: clk_sys. */
.section .text.init
.globl _start
_start:
    li s0, 4
    li s1, 0
loop:
    addi s1, s1, 1
    bne s1, s0, loop
    jal zero, taken
    .word 0xffffffff
    la t0, tohost
    li t1, 3
    sw t1, 0(t0)
taken:
    bne s1, s0, fail
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
