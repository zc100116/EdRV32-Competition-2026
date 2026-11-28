/* File: trap.S; Spec: cpu-v2-testplan CV10/CV14; Clock: clk_sys.
 * A younger illegal word must be canceled before registered trap recovery.
 */
.section .text.init
.globl _start
_start:
    la t0, handler
    csrw mtvec, t0
    li s2, 0
    li s0, 11
    li s1, 0
    ecall
    .word 0xffffffff
    li s0, 3
    la s1, breakpoint
breakpoint:
    ebreak
    .word 0xffffffff
    li s0, 4
    la s1, scratch
    addi s1, s1, 1
    lw t2, 0(s1)
    .word 0xffffffff
    li s0, 6
    li t2, 0x1234
    sw t2, 0(s1)
    .word 0xffffffff
    li t0, 4
    bne s2, t0, fail
    la t0, tohost
    li t1, 1
    sw t1, 0(t0)
1:  j 1b
handler:
    csrr t0, mcause
    bne t0, s0, fail
    csrr t0, mtval
    bne t0, s1, fail
    addi s2, s2, 1
    csrr t0, mepc
    addi t0, t0, 8
    csrw mepc, t0
    mret
fail:
    la t0, tohost
    li t1, 3
    sw t1, 0(t0)
    j fail
.section .tohost,"aw"
.balign 64
.globl tohost
tohost: .dword 0

.data
.balign 4
scratch: .word 0
