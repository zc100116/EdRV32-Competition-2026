# RV32C front-end smoke test.
# Covers two compressed instructions per fetch word, a 32-bit instruction
# crossing a fetch-word boundary, compressed control flow, and compressed
# load/store operations. PASS writes 1 to TOHOST; FAIL writes 3.

.equ TOHOST, 0x80001000
.equ SCRATCH, TOHOST + 0x100

.section .text
.globl _start
.option rvc
_start:
    # Two compressed instructions in one aligned fetch word.
    c.li    a0, 5
    c.addi  a0, 3
    c.li    a1, 8
    bne     a0, a1, fail

    # A 32-bit instruction starts at PC[1]=1 and spans two fetch words.
    .balign 4
    c.nop
    .option push
    .option norvc
    addi    t0, zero, 0x123
    .option pop
    li      t1, 0x123
    bne     t0, t1, fail

    # RV32 C.JAL must link to PC+2; C.JR consumes that exact return address.
    c.li    s0, 0
    c.jal   subroutine
return_from_subroutine:
    c.li    s1, 7
    bne     s0, s1, fail

    # Compressed word store/load through the D-cache hit/miss pipeline.
    li      a3, SCRATCH
    li      a4, 29
    c.sw    a4, 0(a3)
    c.lw    a5, 0(a3)
    bne     a4, a5, fail

    # Taken compressed branch and jump must redirect on halfword boundaries.
    c.li    a2, 0
    c.beqz  a2, branch_taken
    c.j     fail
branch_taken:
    c.j     pass

subroutine:
    c.li    s0, 7
    c.jr    ra

pass:
    li      a5, 1
    li      a6, TOHOST
    sw      a5, 0(a6)
pass_loop:
    c.j     pass_loop

fail:
    li      a5, 3
    li      a6, TOHOST
    sw      a5, 0(a6)
fail_loop:
    c.j     fail_loop
