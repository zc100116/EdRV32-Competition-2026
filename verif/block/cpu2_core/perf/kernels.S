# File: kernels.S
# Spec: cpu-v2-spec 2.3/5.2-5.4; Clock: clk_sys.
# Description: A00 isolated streams; execute the identical kernel once before timing.
.option norvc
.option norelax
.section .text.init,"ax",@progbits
.globl _start, start_time, stop_time
_start:
    la s0, data
    li s4, 0x12345678
    li s5, 7
    li s6, 1
    # Warm marker and tail lines that may be fetched speculatively.
    jal t3, warm_tail_line
    jal t3, warm_marker_line
    jal ra, kernel
    mv s1, s0
    li a0, 1
    .balign 8
start_time:
    jal ra, kernel
stop_time:
    nop
#if CASE == 5 || CASE == 6 || CASE == 24
    lw t4, 8(s0)
    bne t4, s4, fail
#if CASE == 5
    lw t4, 12(s0)
    bne t4, s4, fail
#endif
#endif
    la t0, tohost
    li t1, 1
    sw t1, 0(t0)
1:  j 1b
warm_marker_line:
    mv s1, s0
    li a0, 1
    jalr zero, t3, 0
.balign 32
kernel:
    .rept 64
#if CASE == 0
    addi a0, s4, 1
    addi a1, s4, 2
    addi a2, s4, 3
    addi a3, s4, 4
#elif CASE == 1
    addi a0, a0, 1
    addi a0, a0, 1
    addi a0, a0, 1
    addi a0, a0, 1
#elif CASE == 2
    lw a0, 0(s0)
    lw a1, 4(s0)
#elif CASE == 3
    lw s1, 0(s1)
#elif CASE == 4
    lw a0, 4(s0)
    add a1, a0, s4
#elif CASE == 5
    sw s4, 8(s0)
    sw s4, 12(s0)
#elif CASE == 6
    lw a0, 4(s0)
    sw s4, 8(s0)
#elif CASE == 7
    mul a0, s4, s5
    mul a1, s4, s5
#elif CASE == 8
    mul a0, a0, s6
#elif CASE == 9
    divu a0, s4, s5
#elif CASE == 10
    beq zero, zero, 2f
    nop
2:
#elif CASE == 11
    bne zero, zero, 2f
2:
#elif CASE == 12
    xori s6, s6, 1
    bne s6, zero, 2f
    nop
2:
#elif CASE == 13
    jal zero, 2f
    nop
2:
#elif CASE == 14
    la t0, 2f
    jalr zero, t0, 0
    nop
2:
#elif CASE == 15
    jal t0, leaf
#elif CASE == 16
    addi a0, s4, 1
    lw a1, 4(s0)
#elif CASE == 17
    lw a0, 4(s0)
    addi a1, s4, 1
#elif CASE == 18
    addi a0, s4, 1
    bne zero, zero, 2f
2:
#elif CASE == 19
    addi a0, s4, 1
    add a1, a0, s5
#elif CASE == 20
    addi s1, s0, 0
    lw a0, 4(s1)
#elif CASE == 21
    csrr a0, mscratch
#elif CASE == 22
    slli a0, a0, 1
#elif CASE == 23
    addi a0, s4, 1
    mul a1, s4, s5
#elif CASE == 24
    addi a0, s4, 1
    sw s4, 8(s0)
#elif CASE == 25
    addi a0, s4, 1
    bne a0, zero, 2f
    nop
2:
#elif CASE == 26
    bne zero, zero, 2f
2:  addi a0, s4, 1
#elif CASE == 27
    mul a0, s4, s5
    addi a1, s4, 1
#elif CASE == 28
    divu a0, s4, s5
    addi a1, s4, 1
#elif CASE == 29
    addi a0, s4, 1
    divu a1, s4, s5
#elif CASE == 30
    bne zero, zero, 2f
2:  mul a0, s4, s5
#elif CASE == 31
    mul a0, s4, s5
    bne zero, zero, 2f
2:
#elif CASE == 32
    bne zero, zero, 2f
2:  lw a0, 4(s0)
#elif CASE == 33
    lw a0, 4(s0)
    bne zero, zero, 2f
2:
#elif CASE == 34
    lw a0, 4(s0)
    mul a1, s4, s5
#elif CASE == 35
    mul a0, s4, s5
    lw a1, 4(s0)
#elif CASE == 36
    addi s1, s0, 0
    lw a0, 4(s1)
    add a1, a0, s4
#elif CASE == 37
    divu a0, s4, zero
#endif
    .endr
    ret
leaf:
    jalr zero, t0, 0
warm_tail_line:
    # Warm all tail padding used by the speculative fetch window.
    .rept 32
    nop
    .endr
    jalr zero, t3, 0
    .rept 16
    nop
    .endr
#if CASE == 5 || CASE == 6 || CASE == 24
fail:
    la t0, tohost
    li t1, 3
    sw t1, 0(t0)
    j fail
#endif
.section .tohost,"aw",@progbits
.balign 64
.globl tohost, fromhost
tohost: .dword 0
fromhost: .dword 0
.section .data,"aw",@progbits
.balign 32
data: .word data, 7, 0, 0
