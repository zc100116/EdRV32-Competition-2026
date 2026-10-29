/* File: reset_entry.S
 * Spec: CLAUDE.md 9.2; edrv32-soc-spec 5.3.
 * Description: Begin at the Boot ROM reset vector and transfer to the SRAM image.
 * Clock domain: clk_sys.
 */
.section .text.start,"ax",@progbits
.globl _start
_start:
    j boot_entry
