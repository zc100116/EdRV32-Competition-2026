# ============================================================================
# File        : startup.S
# Author      : Edward ZC
# Description : ROM startup for the MES50HP UART-first board image.
# Notes       : No initialized RAM data is required.
# ============================================================================
.section .text.startup,"ax",@progbits
.globl _start
.type _start, @function
_start:
    la   sp, _sp
    call main
1:
    j    1b
.size _start, .-_start
