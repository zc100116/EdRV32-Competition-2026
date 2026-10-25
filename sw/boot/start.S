/* File: start.S
 * Spec: sys-subsys-spec 2.2; edrv32-soc-spec 7.5
 * Description: ROM startup leaves the preloaded SRAM application intact.
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
    call main
