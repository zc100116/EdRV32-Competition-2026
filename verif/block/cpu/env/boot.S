# File: boot.S; cpu-spec 3.4; SoC spec 6.1; B1 reset jump; clock: host.
.section .boot,"ax",@progbits
.globl edrv32_reset
edrv32_reset:
    .option norvc
    la t0, TEST_ENTRY
    jr t0
