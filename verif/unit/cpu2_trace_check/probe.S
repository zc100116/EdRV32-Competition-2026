# File: probe.S
# Spec: cpu-v2-testplan 4, V01 converter fixture.
# Description: Produce integer, FP f0, flags, memory, CSR and ecall commit records.
# Clock: architectural instruction order.
.section .text
.global _start
_start:
li t0,0x6000
csrw mstatus,t0
li t1,0x80000100
li t2,0x12345678
sw t2,0(t1)
lb a0,0(t1)
fmv.w.x f0,t2
fmv.w.x f2,zero
fdiv.s f1,f0,f2
csrr a1,fcsr
la t0,stop
csrw mtvec,t0
ecall
stop:
j stop
