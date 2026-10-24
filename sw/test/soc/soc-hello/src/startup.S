# ============================================================================
# startup.S - EdRV32 bare-metal CRT0 for C test programs (Phase 1).
# Sets the stack pointer, calls main, and reports the return value to the
# tohost location (1 = PASS / 3 = FAIL) before hanging.
# ============================================================================
.section .text.startup,"ax",@progbits
.globl _start
.type _start, @function
_start:
    la   sp, _sp                 # stack top (linker-defined)
    call main
    # main returned: 0 -> tohost=1 (PASS), otherwise tohost=3 (FAIL)
    li   t0, 0x80001000          # TOHOST
    li   t1, 1
    bne  a0, x0, 1f
    sw   t1, 0(t0)
    j    2f
1:
    li   t1, 3
    sw   t1, 0(t0)
2:
    j    2b                      # hang after reporting
.size _start, .-_start
