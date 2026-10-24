# Minimal smoke test for cached core.
# Tests basic ALU, branch, and store-to-memory (D-cache exercise).
# PASS: writes 1 to tohost, loops forever.
# FAIL: writes 3 to tohost.

.equ TOHOST, 0x80001000

.section .text
.globl _start
_start:
    # Test ALU ops
    li   x1, 0x123
    li   x2, 0x456
    add  x3, x1, x2          # x3 = 0x579
    li   x4, 0x579
    bne  x3, x4, fail

    # Test branch
    li   x5, 0
    beq  x5, x0, 1f
    j    fail
1:
    # Test memory store+load through D-cache
    # Store to tohost region as test (write to 0x80001004 as scratch)
    li   x6, 0xCAFEBABE
    li   x7, TOHOST+4
    sw   x6, 0(x7)           # store through D-cache (WT)
    lw   x8, 0(x7)           # load back (should hit D-cache)
    bne  x6, x8, fail

    # Second store to different offset (tests line fill)
    li   x9, 0xDEADBEEF
    li   x10, TOHOST+256
    sw   x9, 0(x10)
    lw   x11, 0(x10)
    bne  x9, x11, fail

    # Test I-cache: jump forward (exercises I-cache fetch)
    j    2f
    nop
    nop
2:  nop

    # PASS
    li   x15, 1
    li   x16, TOHOST
    sw   x15, 0(x16)
    j    pass_loop

fail:
    li   x15, 3
    li   x16, TOHOST
    sw   x15, 0(x16)

pass_loop:
    nop
    j    pass_loop
