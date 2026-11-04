/* start.S — cpu-spec 4.1–4.4 evaluation; host Spike, no SoC peripherals.
 * ELF loader initializes data/BSS; establish the C stack and global pointer.
 */
.section .text.start,"ax",@progbits
.globl _start
_start:
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop
    la sp, __stack_top
    call main
1:  j 1b

.section .text,"ax",@progbits
.globl start_time
start_time:
    ret
.globl stop_time
stop_time:
    ret
