/* BootROM entry: print the board banner, clear SRAM BSS, run SRAM program. */
.section .text.boot,"ax",@progbits
.globl _start
.type _start, @function
_start:
    la   sp, _sp
    .option push
    .option norelax
    la   gp, __global_pointer$
    .option pop

    call edrv32_boot_banner

    la   t0, _sbss
    la   t1, _ebss
1:
    bgeu t0, t1, 2f
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    1b
2:
    fence.i
    call main
3:
    j    3b
.size _start, .-_start
