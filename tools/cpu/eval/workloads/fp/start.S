/* start.S — C2-F evaluation startup; clock: target CPU. */
.section .text.start,"ax",@progbits
.globl _start
_start:
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop
    la sp, __stack_top
    li t0, 0x6000
    csrs mstatus, t0
#ifdef FP_ENABLED
    csrw fcsr, zero
#endif
    call main
1:  j 1b
.section .text,"ax",@progbits
.globl start_time
start_time:
    ret
.globl stop_time
stop_time:
    ret
