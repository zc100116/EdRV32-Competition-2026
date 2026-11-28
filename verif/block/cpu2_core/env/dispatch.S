/* File: dispatch.S; Spec: cpu-v2-spec 5.1; Clock: clk_sys.
 * Warm the same straight-line instructions before observing completion-credit capacity.
 */
.section .text.init
.globl _start
_start:
    la ra, warm_done
    la t0, start_time+4
    jr t0
warm_done:
    la ra, done
    j start_time
.balign 32
.globl start_time
start_time:
.rept 8
.irp r,a0,a1,a2,a3,a4,a5,a6,a7
    addi \r, zero, 1
.endr
.endr
.globl stop_time
stop_time:
    ret
done:
    li t1, 1
.irp r,a0,a1,a2,a3,a4,a5,a6,a7
    bne \r, t1, fail
.endr
    la t0, tohost
    li t1, 1
    sw t1, 0(t0)
1:  j 1b
.section .tohost,"aw"
.balign 64
.globl tohost
tohost: .dword 0

.section .text
fail:
    la t0, tohost
    li t1, 3
    sw t1, 0(t0)
    j fail
