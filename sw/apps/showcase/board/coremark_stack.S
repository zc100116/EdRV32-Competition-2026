/* coremark_stack.S — showcase CoreMark uses SRAM code, data and execution stack.
 * Preserve the calling DDR stack and callee-saved frame pointer; clk_sys. */
.section .text.coremark_stack,"ax",@progbits
.globl board_coremark_stack
.type board_coremark_stack,@function
board_coremark_stack:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw s0, 8(sp)
    mv s0, sp
    mv sp, a1
    jalr ra, a0, 0
    mv sp, s0
    lw s0, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16
    ret
.size board_coremark_stack, .-board_coremark_stack
