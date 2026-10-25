/* File: start.S
 * Spec: CLAUDE.md 9.2; edrv32-soc-spec 5.3, 6.1
 * Description: Initialize the stack, initialized data and zero data before main.
 *              Return main's status using the tohost test convention.
 * Clock domain: clk_sys.
 */
.section .text.start,"ax",@progbits
.globl _start
_start:
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop
    la sp, __stack_top
    la t0, __data_load
    la t1, __data_start
    la t2, __data_end
1:
    bgeu t1, t2, 2f
    lw t3, 0(t0)
    sw t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    j 1b
2:
    la t0, __bss_start
    la t1, __bss_end
3:
    bgeu t0, t1, 4f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 3b
4:
    call main
    call edrv32_exit
