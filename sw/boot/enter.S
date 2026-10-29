/* File: enter.S
 * Spec: edrv32-soc-spec 7.5; cache-spec 5.4
 * Description: Complete stores and instruction synchronization before application entry.
 * Clock domain: clk_sys.
 */
.section .text.boot_enter,"ax",@progbits
.globl boot_enter
.type boot_enter,@function
boot_enter:
    fence rw, rw
    fence.i
    csrci mstatus, 8
    csrw mie, zero
    jr a0
.size boot_enter, .-boot_enter
