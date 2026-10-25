.section .text.startup,"ax",@progbits
.globl _start
.type _start, @function
_start:
    la   sp, _sp

    la   t0, _sidata
    la   t1, _sdata
    la   t2, _edata
1:
    bgeu t1, t2, 2f
    lw   t3, 0(t0)
    sw   t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    j    1b
2:
    la   t1, _sbss
    la   t2, _ebss
3:
    bgeu t1, t2, 4f
    sw   zero, 0(t1)
    addi t1, t1, 4
    j    3b
4:
    call main
5:
    j    5b
.size _start, .-_start
