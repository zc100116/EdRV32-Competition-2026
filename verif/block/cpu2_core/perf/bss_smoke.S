/* BE1 ELF loading: initialized prefix survives; every declared BSS word is zero. */
    .option norelax
    .section .text.init
    .globl _start
_start:
    call start_time
    la t0, sentinel
    lw t1, 0(t0)
    li t2, 0x13579bdf
    bne t1, t2, fail
    la t0, zeros
    li t2, 32
1:
    lw t1, 0(t0)
    bnez t1, fail
    addi t0, t0, 4
    addi t2, t2, -1
    bnez t2, 1b
    call stop_time
2:
    j 2b
fail:
    ecall
    j fail
    .globl start_time
start_time:
    ret
    .globl stop_time
stop_time:
    ret
    .section .data
    .balign 4
sentinel:
    .word 0x13579bdf
    .section .bss
    .balign 4
zeros:
    .space 128
