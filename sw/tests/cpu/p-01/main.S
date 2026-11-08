/* File: p-01/main.S; Spec: cpu-testplan 3.3–3.7, cpu-spec 2–7.
 * Description: v0.15 全类型矩阵：按槽龄配对、互换管线、RAW/WAW及双控制排斥。
 * Clock: clk_sys. */
#include "test.h"
    START
    li t0, 8
    csrw mie, t0
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0000_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0000_0:
    add a0, a2, a3
pair_0000_1:
    add a1, a2, a3
pair_0000_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0001_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0001_0:
    add a0, a2, a3
pair_0001_1:
    add a1, a0, a3
pair_0001_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0002_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0002_0:
    add a0, a2, a3
pair_0002_1:
    add a0, a2, a3
pair_0002_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0003_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0003_0:
    add a0, a2, a3
pair_0003_1:
    lui a1, 1
pair_0003_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0004_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0004_0:
    add a0, a2, a3
pair_0004_1:
    lui a1, 1
pair_0004_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0005_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0005_0:
    add a0, a2, a3
pair_0005_1:
    lui a0, 1
pair_0005_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0006_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0006_0:
    add a0, a2, a3
pair_0006_1:
    auipc a1, 0
pair_0006_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0007_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0007_0:
    add a0, a2, a3
pair_0007_1:
    auipc a1, 0
pair_0007_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0008_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0008_0:
    add a0, a2, a3
pair_0008_1:
    auipc a0, 0
pair_0008_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0009_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0009_0:
    add a0, a2, a3
pair_0009_1:
    lw a1, 0(a4)
pair_0009_end:
    nop
    li a0, 7
    li a1, 9
    la a2, pair_0010_end
    li a3, 0
    la a4, scratch
    la a5, pair_0010_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0010_0:
    add a0, a2, a3
pair_0010_1:
    lw a1, 0(a0)
pair_0010_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0011_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0011_0:
    add a0, a2, a3
pair_0011_1:
    lw a0, 0(a4)
pair_0011_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0012_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0012_0:
    add a0, a2, a3
pair_0012_1:
    sw a2, 0(a4)
pair_0012_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0013_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0013_0:
    add a0, a2, a3
pair_0013_1:
    sw a0, 0(a4)
pair_0013_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0014_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0014_0:
    add a0, a2, a3
pair_0014_1:
    sw a2, 0(a4)
pair_0014_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0015_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0015_0:
    add a0, a2, a3
pair_0015_1:
    mul a1, a2, a3
pair_0015_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0016_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0016_0:
    add a0, a2, a3
pair_0016_1:
    mul a1, a0, a3
pair_0016_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0017_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0017_0:
    add a0, a2, a3
pair_0017_1:
    mul a0, a2, a3
pair_0017_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0018_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0018_0:
    add a0, a2, a3
pair_0018_1:
    div a1, a2, a3
pair_0018_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0019_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0019_0:
    add a0, a2, a3
pair_0019_1:
    div a1, a0, a3
pair_0019_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0020_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0020_0:
    add a0, a2, a3
pair_0020_1:
    div a0, a2, a3
pair_0020_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0021_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0021_0:
    add a0, a2, a3
pair_0021_1:
    beq a2, a3, pair_0021_end
pair_0021_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0022_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0022_0:
    add a0, a2, a3
pair_0022_1:
    beq a0, a3, pair_0022_end
pair_0022_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0023_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0023_0:
    add a0, a2, a3
pair_0023_1:
    beq a2, a3, pair_0023_end
pair_0023_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0024_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0024_0:
    add a0, a2, a3
pair_0024_1:
    jal a1, pair_0024_end
pair_0024_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0025_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0025_0:
    add a0, a2, a3
pair_0025_1:
    jal a1, pair_0025_end
pair_0025_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0026_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0026_0:
    add a0, a2, a3
pair_0026_1:
    jal a0, pair_0026_end
pair_0026_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0027_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0027_0:
    add a0, a2, a3
pair_0027_1:
    jalr a1, 0(a5)
pair_0027_end:
    nop
    li a0, 7
    li a1, 9
    la a2, pair_0028_end
    li a3, 0
    la a4, scratch
    la a5, pair_0028_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0028_0:
    add a0, a2, a3
pair_0028_1:
    jalr a1, 0(a0)
pair_0028_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0029_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0029_0:
    add a0, a2, a3
pair_0029_1:
    jalr a0, 0(a5)
pair_0029_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0030_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0030_0:
    add a0, a2, a3
pair_0030_1:
    csrrw a1, mscratch, a2
pair_0030_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0031_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0031_0:
    add a0, a2, a3
pair_0031_1:
    csrrw a1, mscratch, a0
pair_0031_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0032_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0032_0:
    add a0, a2, a3
pair_0032_1:
    csrrw a0, mscratch, a2
pair_0032_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0033_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0033_0:
    add a0, a2, a3
pair_0033_1:
    fence rw,rw
pair_0033_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0034_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0034_0:
    add a0, a2, a3
pair_0034_1:
    fence rw,rw
pair_0034_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0035_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0035_0:
    add a0, a2, a3
pair_0035_1:
    fence rw,rw
pair_0035_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0036_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0036_0:
    add a0, a2, a3
pair_0036_1:
    fence.i
pair_0036_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0037_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0037_0:
    add a0, a2, a3
pair_0037_1:
    fence.i
pair_0037_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0038_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0038_0:
    add a0, a2, a3
pair_0038_1:
    fence.i
pair_0038_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0039_end
    li t2, 0
    EXPECT 11, t2, pair_0039_1, pair_0039_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0039_0:
    add a0, a2, a3
pair_0039_1:
    ecall
pair_0039_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0040_end
    li t2, 0
    EXPECT 11, t2, pair_0040_1, pair_0040_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0040_0:
    add a0, a2, a3
pair_0040_1:
    ecall
pair_0040_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0041_end
    li t2, 0
    EXPECT 11, t2, pair_0041_1, pair_0041_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0041_0:
    add a0, a2, a3
pair_0041_1:
    ecall
pair_0041_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0042_end
    li t2, 0
    EXPECT 3, t2, pair_0042_1, pair_0042_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0042_0:
    add a0, a2, a3
pair_0042_1:
    ebreak
pair_0042_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0043_end
    li t2, 0
    EXPECT 3, t2, pair_0043_1, pair_0043_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0043_0:
    add a0, a2, a3
pair_0043_1:
    ebreak
pair_0043_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0044_end
    li t2, 0
    EXPECT 3, t2, pair_0044_1, pair_0044_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0044_0:
    add a0, a2, a3
pair_0044_1:
    ebreak
pair_0044_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0045_end
    la t0, pair_0045_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0045_0:
    add a0, a2, a3
pair_0045_1:
    mret
pair_0045_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0046_end
    la t0, pair_0046_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0046_0:
    add a0, a2, a3
pair_0046_1:
    mret
pair_0046_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0047_end
    la t0, pair_0047_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0047_0:
    add a0, a2, a3
pair_0047_1:
    mret
pair_0047_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0048_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0048_0:
    add a0, a2, a3
pair_0048_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0048_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0049_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0049_0:
    add a0, a2, a3
pair_0049_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0049_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0050_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0050_0:
    add a0, a2, a3
pair_0050_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0050_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0051_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0051_0:
    lui a0, 1
pair_0051_1:
    add a1, a2, a3
pair_0051_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0052_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0052_0:
    lui a0, 1
pair_0052_1:
    add a1, a0, a3
pair_0052_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0053_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0053_0:
    lui a0, 1
pair_0053_1:
    add a0, a2, a3
pair_0053_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0054_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0054_0:
    lui a0, 1
pair_0054_1:
    lui a1, 1
pair_0054_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0055_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0055_0:
    lui a0, 1
pair_0055_1:
    lui a1, 1
pair_0055_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0056_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0056_0:
    lui a0, 1
pair_0056_1:
    lui a0, 1
pair_0056_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0057_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0057_0:
    lui a0, 1
pair_0057_1:
    auipc a1, 0
pair_0057_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0058_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0058_0:
    lui a0, 1
pair_0058_1:
    auipc a1, 0
pair_0058_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0059_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0059_0:
    lui a0, 1
pair_0059_1:
    auipc a0, 0
pair_0059_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0060_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0060_0:
    lui a0, 1
pair_0060_1:
    lw a1, 0(a4)
pair_0060_end:
    nop
    li a0, 7
    li a1, 9
    la a2, pair_0061_end
    li a3, 0
    la a4, scratch
    la a5, pair_0061_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0061_0:
    lui a0, %hi(pair_0061_end)
pair_0061_1:
    lw a1, 0(a0)
pair_0061_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0062_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0062_0:
    lui a0, 1
pair_0062_1:
    lw a0, 0(a4)
pair_0062_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0063_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0063_0:
    lui a0, 1
pair_0063_1:
    sw a2, 0(a4)
pair_0063_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0064_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0064_0:
    lui a0, 1
pair_0064_1:
    sw a0, 0(a4)
pair_0064_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0065_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0065_0:
    lui a0, 1
pair_0065_1:
    sw a2, 0(a4)
pair_0065_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0066_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0066_0:
    lui a0, 1
pair_0066_1:
    mul a1, a2, a3
pair_0066_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0067_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0067_0:
    lui a0, 1
pair_0067_1:
    mul a1, a0, a3
pair_0067_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0068_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0068_0:
    lui a0, 1
pair_0068_1:
    mul a0, a2, a3
pair_0068_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0069_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0069_0:
    lui a0, 1
pair_0069_1:
    div a1, a2, a3
pair_0069_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0070_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0070_0:
    lui a0, 1
pair_0070_1:
    div a1, a0, a3
pair_0070_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0071_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0071_0:
    lui a0, 1
pair_0071_1:
    div a0, a2, a3
pair_0071_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0072_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0072_0:
    lui a0, 1
pair_0072_1:
    beq a2, a3, pair_0072_end
pair_0072_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0073_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0073_0:
    lui a0, 1
pair_0073_1:
    beq a0, a3, pair_0073_end
pair_0073_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0074_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0074_0:
    lui a0, 1
pair_0074_1:
    beq a2, a3, pair_0074_end
pair_0074_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0075_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0075_0:
    lui a0, 1
pair_0075_1:
    jal a1, pair_0075_end
pair_0075_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0076_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0076_0:
    lui a0, 1
pair_0076_1:
    jal a1, pair_0076_end
pair_0076_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0077_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0077_0:
    lui a0, 1
pair_0077_1:
    jal a0, pair_0077_end
pair_0077_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0078_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0078_0:
    lui a0, 1
pair_0078_1:
    jalr a1, 0(a5)
pair_0078_end:
    nop
    li a0, 7
    li a1, 9
    la a2, pair_0079_end
    li a3, 0
    la a4, scratch
    la a5, pair_0079_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0079_0:
    lui a0, %hi(pair_0079_end)
pair_0079_1:
    jalr a1, %lo(pair_0079_end)(a0)
pair_0079_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0080_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0080_0:
    lui a0, 1
pair_0080_1:
    jalr a0, 0(a5)
pair_0080_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0081_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0081_0:
    lui a0, 1
pair_0081_1:
    csrrw a1, mscratch, a2
pair_0081_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0082_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0082_0:
    lui a0, 1
pair_0082_1:
    csrrw a1, mscratch, a0
pair_0082_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0083_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0083_0:
    lui a0, 1
pair_0083_1:
    csrrw a0, mscratch, a2
pair_0083_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0084_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0084_0:
    lui a0, 1
pair_0084_1:
    fence rw,rw
pair_0084_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0085_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0085_0:
    lui a0, 1
pair_0085_1:
    fence rw,rw
pair_0085_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0086_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0086_0:
    lui a0, 1
pair_0086_1:
    fence rw,rw
pair_0086_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0087_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0087_0:
    lui a0, 1
pair_0087_1:
    fence.i
pair_0087_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0088_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0088_0:
    lui a0, 1
pair_0088_1:
    fence.i
pair_0088_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0089_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0089_0:
    lui a0, 1
pair_0089_1:
    fence.i
pair_0089_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0090_end
    li t2, 0
    EXPECT 11, t2, pair_0090_1, pair_0090_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0090_0:
    lui a0, 1
pair_0090_1:
    ecall
pair_0090_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0091_end
    li t2, 0
    EXPECT 11, t2, pair_0091_1, pair_0091_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0091_0:
    lui a0, 1
pair_0091_1:
    ecall
pair_0091_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0092_end
    li t2, 0
    EXPECT 11, t2, pair_0092_1, pair_0092_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0092_0:
    lui a0, 1
pair_0092_1:
    ecall
pair_0092_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0093_end
    li t2, 0
    EXPECT 3, t2, pair_0093_1, pair_0093_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0093_0:
    lui a0, 1
pair_0093_1:
    ebreak
pair_0093_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0094_end
    li t2, 0
    EXPECT 3, t2, pair_0094_1, pair_0094_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0094_0:
    lui a0, 1
pair_0094_1:
    ebreak
pair_0094_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0095_end
    li t2, 0
    EXPECT 3, t2, pair_0095_1, pair_0095_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0095_0:
    lui a0, 1
pair_0095_1:
    ebreak
pair_0095_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0096_end
    la t0, pair_0096_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0096_0:
    lui a0, 1
pair_0096_1:
    mret
pair_0096_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0097_end
    la t0, pair_0097_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0097_0:
    lui a0, 1
pair_0097_1:
    mret
pair_0097_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0098_end
    la t0, pair_0098_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0098_0:
    lui a0, 1
pair_0098_1:
    mret
pair_0098_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0099_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0099_0:
    lui a0, 1
pair_0099_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0099_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0100_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0100_0:
    lui a0, 1
pair_0100_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0100_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0101_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0101_0:
    lui a0, 1
pair_0101_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0101_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0102_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0102_0:
    auipc a0, 0
pair_0102_1:
    add a1, a2, a3
pair_0102_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0103_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0103_0:
    auipc a0, 0
pair_0103_1:
    add a1, a0, a3
pair_0103_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0104_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0104_0:
    auipc a0, 0
pair_0104_1:
    add a0, a2, a3
pair_0104_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0105_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0105_0:
    auipc a0, 0
pair_0105_1:
    lui a1, 1
pair_0105_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0106_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0106_0:
    auipc a0, 0
pair_0106_1:
    lui a1, 1
pair_0106_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0107_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0107_0:
    auipc a0, 0
pair_0107_1:
    lui a0, 1
pair_0107_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0108_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0108_0:
    auipc a0, 0
pair_0108_1:
    auipc a1, 0
pair_0108_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0109_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0109_0:
    auipc a0, 0
pair_0109_1:
    auipc a1, 0
pair_0109_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0110_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0110_0:
    auipc a0, 0
pair_0110_1:
    auipc a0, 0
pair_0110_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0111_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0111_0:
    auipc a0, 0
pair_0111_1:
    lw a1, 0(a4)
pair_0111_end:
    nop
    li a0, 7
    li a1, 9
    la a2, pair_0112_end
    li a3, 0
    la a4, scratch
    la a5, pair_0112_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0112_0:
    auipc a0, 0
pair_0112_1:
    lw a1, 0(a0)
pair_0112_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0113_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0113_0:
    auipc a0, 0
pair_0113_1:
    lw a0, 0(a4)
pair_0113_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0114_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0114_0:
    auipc a0, 0
pair_0114_1:
    sw a2, 0(a4)
pair_0114_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0115_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0115_0:
    auipc a0, 0
pair_0115_1:
    sw a0, 0(a4)
pair_0115_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0116_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0116_0:
    auipc a0, 0
pair_0116_1:
    sw a2, 0(a4)
pair_0116_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0117_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0117_0:
    auipc a0, 0
pair_0117_1:
    mul a1, a2, a3
pair_0117_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0118_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0118_0:
    auipc a0, 0
pair_0118_1:
    mul a1, a0, a3
pair_0118_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0119_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0119_0:
    auipc a0, 0
pair_0119_1:
    mul a0, a2, a3
pair_0119_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0120_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0120_0:
    auipc a0, 0
pair_0120_1:
    div a1, a2, a3
pair_0120_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0121_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0121_0:
    auipc a0, 0
pair_0121_1:
    div a1, a0, a3
pair_0121_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0122_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0122_0:
    auipc a0, 0
pair_0122_1:
    div a0, a2, a3
pair_0122_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0123_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0123_0:
    auipc a0, 0
pair_0123_1:
    beq a2, a3, pair_0123_end
pair_0123_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0124_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0124_0:
    auipc a0, 0
pair_0124_1:
    beq a0, a3, pair_0124_end
pair_0124_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0125_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0125_0:
    auipc a0, 0
pair_0125_1:
    beq a2, a3, pair_0125_end
pair_0125_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0126_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0126_0:
    auipc a0, 0
pair_0126_1:
    jal a1, pair_0126_end
pair_0126_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0127_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0127_0:
    auipc a0, 0
pair_0127_1:
    jal a1, pair_0127_end
pair_0127_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0128_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0128_0:
    auipc a0, 0
pair_0128_1:
    jal a0, pair_0128_end
pair_0128_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0129_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0129_0:
    auipc a0, 0
pair_0129_1:
    jalr a1, 0(a5)
pair_0129_end:
    nop
    li a0, 7
    li a1, 9
    la a2, pair_0130_end
    li a3, 0
    la a4, scratch
    la a5, pair_0130_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0130_0:
    auipc a0, 0
pair_0130_1:
    jalr a1, 8(a0)
pair_0130_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0131_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0131_0:
    auipc a0, 0
pair_0131_1:
    jalr a0, 0(a5)
pair_0131_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0132_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0132_0:
    auipc a0, 0
pair_0132_1:
    csrrw a1, mscratch, a2
pair_0132_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0133_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0133_0:
    auipc a0, 0
pair_0133_1:
    csrrw a1, mscratch, a0
pair_0133_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0134_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0134_0:
    auipc a0, 0
pair_0134_1:
    csrrw a0, mscratch, a2
pair_0134_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0135_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0135_0:
    auipc a0, 0
pair_0135_1:
    fence rw,rw
pair_0135_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0136_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0136_0:
    auipc a0, 0
pair_0136_1:
    fence rw,rw
pair_0136_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0137_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0137_0:
    auipc a0, 0
pair_0137_1:
    fence rw,rw
pair_0137_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0138_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0138_0:
    auipc a0, 0
pair_0138_1:
    fence.i
pair_0138_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0139_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0139_0:
    auipc a0, 0
pair_0139_1:
    fence.i
pair_0139_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0140_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0140_0:
    auipc a0, 0
pair_0140_1:
    fence.i
pair_0140_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0141_end
    li t2, 0
    EXPECT 11, t2, pair_0141_1, pair_0141_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0141_0:
    auipc a0, 0
pair_0141_1:
    ecall
pair_0141_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0142_end
    li t2, 0
    EXPECT 11, t2, pair_0142_1, pair_0142_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0142_0:
    auipc a0, 0
pair_0142_1:
    ecall
pair_0142_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0143_end
    li t2, 0
    EXPECT 11, t2, pair_0143_1, pair_0143_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0143_0:
    auipc a0, 0
pair_0143_1:
    ecall
pair_0143_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0144_end
    li t2, 0
    EXPECT 3, t2, pair_0144_1, pair_0144_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0144_0:
    auipc a0, 0
pair_0144_1:
    ebreak
pair_0144_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0145_end
    li t2, 0
    EXPECT 3, t2, pair_0145_1, pair_0145_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0145_0:
    auipc a0, 0
pair_0145_1:
    ebreak
pair_0145_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0146_end
    li t2, 0
    EXPECT 3, t2, pair_0146_1, pair_0146_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0146_0:
    auipc a0, 0
pair_0146_1:
    ebreak
pair_0146_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0147_end
    la t0, pair_0147_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0147_0:
    auipc a0, 0
pair_0147_1:
    mret
pair_0147_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0148_end
    la t0, pair_0148_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0148_0:
    auipc a0, 0
pair_0148_1:
    mret
pair_0148_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0149_end
    la t0, pair_0149_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0149_0:
    auipc a0, 0
pair_0149_1:
    mret
pair_0149_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0150_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0150_0:
    auipc a0, 0
pair_0150_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0150_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0151_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0151_0:
    auipc a0, 0
pair_0151_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0151_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0152_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0152_0:
    auipc a0, 0
pair_0152_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0152_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0153_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0153_0:
    lw a0, 0(a4)
pair_0153_1:
    add a1, a2, a3
pair_0153_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0154_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0154_0:
    lw a0, 0(a4)
pair_0154_1:
    add a1, a0, a3
pair_0154_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0155_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0155_0:
    lw a0, 0(a4)
pair_0155_1:
    add a0, a2, a3
pair_0155_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0156_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0156_0:
    lw a0, 0(a4)
pair_0156_1:
    lui a1, 1
pair_0156_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0157_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0157_0:
    lw a0, 0(a4)
pair_0157_1:
    lui a1, 1
pair_0157_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0158_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0158_0:
    lw a0, 0(a4)
pair_0158_1:
    lui a0, 1
pair_0158_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0159_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0159_0:
    lw a0, 0(a4)
pair_0159_1:
    auipc a1, 0
pair_0159_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0160_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0160_0:
    lw a0, 0(a4)
pair_0160_1:
    auipc a1, 0
pair_0160_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0161_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0161_0:
    lw a0, 0(a4)
pair_0161_1:
    auipc a0, 0
pair_0161_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0162_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0162_0:
    lw a0, 0(a4)
pair_0162_1:
    lw a1, 0(a4)
pair_0162_end:
    nop
    li a0, 7
    li a1, 9
    la a2, pair_0163_end
    li a3, 0
    la a4, scratch
    la a5, pair_0163_end
    sw a2, 0(a4)
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0163_0:
    lw a0, 0(a4)
pair_0163_1:
    lw a1, 0(a0)
pair_0163_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0164_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0164_0:
    lw a0, 0(a4)
pair_0164_1:
    lw a0, 0(a4)
pair_0164_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0165_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0165_0:
    lw a0, 0(a4)
pair_0165_1:
    sw a2, 0(a4)
pair_0165_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0166_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0166_0:
    lw a0, 0(a4)
pair_0166_1:
    sw a0, 0(a4)
pair_0166_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0167_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0167_0:
    lw a0, 0(a4)
pair_0167_1:
    sw a2, 0(a4)
pair_0167_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0168_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0168_0:
    lw a0, 0(a4)
pair_0168_1:
    mul a1, a2, a3
pair_0168_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0169_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0169_0:
    lw a0, 0(a4)
pair_0169_1:
    mul a1, a0, a3
pair_0169_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0170_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0170_0:
    lw a0, 0(a4)
pair_0170_1:
    mul a0, a2, a3
pair_0170_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0171_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0171_0:
    lw a0, 0(a4)
pair_0171_1:
    div a1, a2, a3
pair_0171_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0172_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0172_0:
    lw a0, 0(a4)
pair_0172_1:
    div a1, a0, a3
pair_0172_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0173_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0173_0:
    lw a0, 0(a4)
pair_0173_1:
    div a0, a2, a3
pair_0173_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0174_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0174_0:
    lw a0, 0(a4)
pair_0174_1:
    beq a2, a3, pair_0174_end
pair_0174_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0175_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0175_0:
    lw a0, 0(a4)
pair_0175_1:
    beq a0, a3, pair_0175_end
pair_0175_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0176_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0176_0:
    lw a0, 0(a4)
pair_0176_1:
    beq a2, a3, pair_0176_end
pair_0176_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0177_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0177_0:
    lw a0, 0(a4)
pair_0177_1:
    jal a1, pair_0177_end
pair_0177_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0178_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0178_0:
    lw a0, 0(a4)
pair_0178_1:
    jal a1, pair_0178_end
pair_0178_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0179_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0179_0:
    lw a0, 0(a4)
pair_0179_1:
    jal a0, pair_0179_end
pair_0179_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0180_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0180_0:
    lw a0, 0(a4)
pair_0180_1:
    jalr a1, 0(a5)
pair_0180_end:
    nop
    li a0, 7
    li a1, 9
    la a2, pair_0181_end
    li a3, 0
    la a4, scratch
    la a5, pair_0181_end
    sw a2, 0(a4)
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0181_0:
    lw a0, 0(a4)
pair_0181_1:
    jalr a1, 0(a0)
pair_0181_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0182_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0182_0:
    lw a0, 0(a4)
pair_0182_1:
    jalr a0, 0(a5)
pair_0182_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0183_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0183_0:
    lw a0, 0(a4)
pair_0183_1:
    csrrw a1, mscratch, a2
pair_0183_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0184_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0184_0:
    lw a0, 0(a4)
pair_0184_1:
    csrrw a1, mscratch, a0
pair_0184_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0185_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0185_0:
    lw a0, 0(a4)
pair_0185_1:
    csrrw a0, mscratch, a2
pair_0185_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0186_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0186_0:
    lw a0, 0(a4)
pair_0186_1:
    fence rw,rw
pair_0186_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0187_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0187_0:
    lw a0, 0(a4)
pair_0187_1:
    fence rw,rw
pair_0187_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0188_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0188_0:
    lw a0, 0(a4)
pair_0188_1:
    fence rw,rw
pair_0188_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0189_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0189_0:
    lw a0, 0(a4)
pair_0189_1:
    fence.i
pair_0189_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0190_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0190_0:
    lw a0, 0(a4)
pair_0190_1:
    fence.i
pair_0190_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0191_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0191_0:
    lw a0, 0(a4)
pair_0191_1:
    fence.i
pair_0191_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0192_end
    li t2, 0
    EXPECT 11, t2, pair_0192_1, pair_0192_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0192_0:
    lw a0, 0(a4)
pair_0192_1:
    ecall
pair_0192_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0193_end
    li t2, 0
    EXPECT 11, t2, pair_0193_1, pair_0193_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0193_0:
    lw a0, 0(a4)
pair_0193_1:
    ecall
pair_0193_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0194_end
    li t2, 0
    EXPECT 11, t2, pair_0194_1, pair_0194_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0194_0:
    lw a0, 0(a4)
pair_0194_1:
    ecall
pair_0194_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0195_end
    li t2, 0
    EXPECT 3, t2, pair_0195_1, pair_0195_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0195_0:
    lw a0, 0(a4)
pair_0195_1:
    ebreak
pair_0195_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0196_end
    li t2, 0
    EXPECT 3, t2, pair_0196_1, pair_0196_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0196_0:
    lw a0, 0(a4)
pair_0196_1:
    ebreak
pair_0196_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0197_end
    li t2, 0
    EXPECT 3, t2, pair_0197_1, pair_0197_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0197_0:
    lw a0, 0(a4)
pair_0197_1:
    ebreak
pair_0197_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0198_end
    la t0, pair_0198_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0198_0:
    lw a0, 0(a4)
pair_0198_1:
    mret
pair_0198_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0199_end
    la t0, pair_0199_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0199_0:
    lw a0, 0(a4)
pair_0199_1:
    mret
pair_0199_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0200_end
    la t0, pair_0200_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0200_0:
    lw a0, 0(a4)
pair_0200_1:
    mret
pair_0200_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0201_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0201_0:
    lw a0, 0(a4)
pair_0201_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0201_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0202_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0202_0:
    lw a0, 0(a4)
pair_0202_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0202_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0203_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0203_0:
    lw a0, 0(a4)
pair_0203_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0203_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0204_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0204_0:
    sw a2, 0(a4)
pair_0204_1:
    add a1, a2, a3
pair_0204_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0205_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0205_0:
    sw a2, 0(a4)
pair_0205_1:
    add a1, a0, a3
pair_0205_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0206_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0206_0:
    sw a2, 0(a4)
pair_0206_1:
    add a0, a2, a3
pair_0206_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0207_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0207_0:
    sw a2, 0(a4)
pair_0207_1:
    lui a1, 1
pair_0207_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0208_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0208_0:
    sw a2, 0(a4)
pair_0208_1:
    lui a1, 1
pair_0208_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0209_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0209_0:
    sw a2, 0(a4)
pair_0209_1:
    lui a0, 1
pair_0209_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0210_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0210_0:
    sw a2, 0(a4)
pair_0210_1:
    auipc a1, 0
pair_0210_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0211_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0211_0:
    sw a2, 0(a4)
pair_0211_1:
    auipc a1, 0
pair_0211_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0212_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0212_0:
    sw a2, 0(a4)
pair_0212_1:
    auipc a0, 0
pair_0212_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0213_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0213_0:
    sw a2, 0(a4)
pair_0213_1:
    lw a1, 0(a4)
pair_0213_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0214_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0214_0:
    sw a2, 0(a4)
pair_0214_1:
    lw a1, 0(a4)
pair_0214_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0215_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0215_0:
    sw a2, 0(a4)
pair_0215_1:
    lw a0, 0(a4)
pair_0215_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0216_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0216_0:
    sw a2, 0(a4)
pair_0216_1:
    sw a2, 0(a4)
pair_0216_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0217_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0217_0:
    sw a2, 0(a4)
pair_0217_1:
    sw a0, 0(a4)
pair_0217_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0218_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0218_0:
    sw a2, 0(a4)
pair_0218_1:
    sw a2, 0(a4)
pair_0218_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0219_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0219_0:
    sw a2, 0(a4)
pair_0219_1:
    mul a1, a2, a3
pair_0219_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0220_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0220_0:
    sw a2, 0(a4)
pair_0220_1:
    mul a1, a0, a3
pair_0220_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0221_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0221_0:
    sw a2, 0(a4)
pair_0221_1:
    mul a0, a2, a3
pair_0221_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0222_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0222_0:
    sw a2, 0(a4)
pair_0222_1:
    div a1, a2, a3
pair_0222_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0223_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0223_0:
    sw a2, 0(a4)
pair_0223_1:
    div a1, a0, a3
pair_0223_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0224_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0224_0:
    sw a2, 0(a4)
pair_0224_1:
    div a0, a2, a3
pair_0224_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0225_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0225_0:
    sw a2, 0(a4)
pair_0225_1:
    beq a2, a3, pair_0225_end
pair_0225_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0226_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0226_0:
    sw a2, 0(a4)
pair_0226_1:
    beq a0, a3, pair_0226_end
pair_0226_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0227_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0227_0:
    sw a2, 0(a4)
pair_0227_1:
    beq a2, a3, pair_0227_end
pair_0227_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0228_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0228_0:
    sw a2, 0(a4)
pair_0228_1:
    jal a1, pair_0228_end
pair_0228_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0229_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0229_0:
    sw a2, 0(a4)
pair_0229_1:
    jal a1, pair_0229_end
pair_0229_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0230_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0230_0:
    sw a2, 0(a4)
pair_0230_1:
    jal a0, pair_0230_end
pair_0230_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0231_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0231_0:
    sw a2, 0(a4)
pair_0231_1:
    jalr a1, 0(a5)
pair_0231_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0232_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0232_0:
    sw a2, 0(a4)
pair_0232_1:
    jalr a1, 0(a5)
pair_0232_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0233_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0233_0:
    sw a2, 0(a4)
pair_0233_1:
    jalr a0, 0(a5)
pair_0233_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0234_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0234_0:
    sw a2, 0(a4)
pair_0234_1:
    csrrw a1, mscratch, a2
pair_0234_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0235_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0235_0:
    sw a2, 0(a4)
pair_0235_1:
    csrrw a1, mscratch, a0
pair_0235_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0236_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0236_0:
    sw a2, 0(a4)
pair_0236_1:
    csrrw a0, mscratch, a2
pair_0236_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0237_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0237_0:
    sw a2, 0(a4)
pair_0237_1:
    fence rw,rw
pair_0237_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0238_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0238_0:
    sw a2, 0(a4)
pair_0238_1:
    fence rw,rw
pair_0238_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0239_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0239_0:
    sw a2, 0(a4)
pair_0239_1:
    fence rw,rw
pair_0239_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0240_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0240_0:
    sw a2, 0(a4)
pair_0240_1:
    fence.i
pair_0240_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0241_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0241_0:
    sw a2, 0(a4)
pair_0241_1:
    fence.i
pair_0241_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0242_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0242_0:
    sw a2, 0(a4)
pair_0242_1:
    fence.i
pair_0242_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0243_end
    li t2, 0
    EXPECT 11, t2, pair_0243_1, pair_0243_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0243_0:
    sw a2, 0(a4)
pair_0243_1:
    ecall
pair_0243_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0244_end
    li t2, 0
    EXPECT 11, t2, pair_0244_1, pair_0244_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0244_0:
    sw a2, 0(a4)
pair_0244_1:
    ecall
pair_0244_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0245_end
    li t2, 0
    EXPECT 11, t2, pair_0245_1, pair_0245_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0245_0:
    sw a2, 0(a4)
pair_0245_1:
    ecall
pair_0245_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0246_end
    li t2, 0
    EXPECT 3, t2, pair_0246_1, pair_0246_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0246_0:
    sw a2, 0(a4)
pair_0246_1:
    ebreak
pair_0246_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0247_end
    li t2, 0
    EXPECT 3, t2, pair_0247_1, pair_0247_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0247_0:
    sw a2, 0(a4)
pair_0247_1:
    ebreak
pair_0247_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0248_end
    li t2, 0
    EXPECT 3, t2, pair_0248_1, pair_0248_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0248_0:
    sw a2, 0(a4)
pair_0248_1:
    ebreak
pair_0248_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0249_end
    la t0, pair_0249_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0249_0:
    sw a2, 0(a4)
pair_0249_1:
    mret
pair_0249_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0250_end
    la t0, pair_0250_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0250_0:
    sw a2, 0(a4)
pair_0250_1:
    mret
pair_0250_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0251_end
    la t0, pair_0251_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0251_0:
    sw a2, 0(a4)
pair_0251_1:
    mret
pair_0251_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0252_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0252_0:
    sw a2, 0(a4)
pair_0252_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0252_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0253_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0253_0:
    sw a2, 0(a4)
pair_0253_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0253_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0254_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0254_0:
    sw a2, 0(a4)
pair_0254_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0254_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0255_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0255_0:
    mul a0, a2, a3
pair_0255_1:
    add a1, a2, a3
pair_0255_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0256_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0256_0:
    mul a0, a2, a3
pair_0256_1:
    add a1, a0, a3
pair_0256_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0257_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0257_0:
    mul a0, a2, a3
pair_0257_1:
    add a0, a2, a3
pair_0257_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0258_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0258_0:
    mul a0, a2, a3
pair_0258_1:
    lui a1, 1
pair_0258_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0259_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0259_0:
    mul a0, a2, a3
pair_0259_1:
    lui a1, 1
pair_0259_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0260_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0260_0:
    mul a0, a2, a3
pair_0260_1:
    lui a0, 1
pair_0260_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0261_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0261_0:
    mul a0, a2, a3
pair_0261_1:
    auipc a1, 0
pair_0261_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0262_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0262_0:
    mul a0, a2, a3
pair_0262_1:
    auipc a1, 0
pair_0262_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0263_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0263_0:
    mul a0, a2, a3
pair_0263_1:
    auipc a0, 0
pair_0263_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0264_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0264_0:
    mul a0, a2, a3
pair_0264_1:
    lw a1, 0(a4)
pair_0264_end:
    nop
    li a0, 7
    li a1, 9
    la a2, pair_0265_end
    li a3, 1
    la a4, scratch
    la a5, pair_0265_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0265_0:
    mul a0, a2, a3
pair_0265_1:
    lw a1, 0(a0)
pair_0265_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0266_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0266_0:
    mul a0, a2, a3
pair_0266_1:
    lw a0, 0(a4)
pair_0266_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0267_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0267_0:
    mul a0, a2, a3
pair_0267_1:
    sw a2, 0(a4)
pair_0267_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0268_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0268_0:
    mul a0, a2, a3
pair_0268_1:
    sw a0, 0(a4)
pair_0268_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0269_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0269_0:
    mul a0, a2, a3
pair_0269_1:
    sw a2, 0(a4)
pair_0269_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0270_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0270_0:
    mul a0, a2, a3
pair_0270_1:
    mul a1, a2, a3
pair_0270_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0271_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0271_0:
    mul a0, a2, a3
pair_0271_1:
    mul a1, a0, a3
pair_0271_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0272_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0272_0:
    mul a0, a2, a3
pair_0272_1:
    mul a0, a2, a3
pair_0272_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0273_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0273_0:
    mul a0, a2, a3
pair_0273_1:
    div a1, a2, a3
pair_0273_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0274_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0274_0:
    mul a0, a2, a3
pair_0274_1:
    div a1, a0, a3
pair_0274_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0275_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0275_0:
    mul a0, a2, a3
pair_0275_1:
    div a0, a2, a3
pair_0275_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0276_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0276_0:
    mul a0, a2, a3
pair_0276_1:
    beq a2, a3, pair_0276_end
pair_0276_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0277_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0277_0:
    mul a0, a2, a3
pair_0277_1:
    beq a0, a3, pair_0277_end
pair_0277_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0278_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0278_0:
    mul a0, a2, a3
pair_0278_1:
    beq a2, a3, pair_0278_end
pair_0278_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0279_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0279_0:
    mul a0, a2, a3
pair_0279_1:
    jal a1, pair_0279_end
pair_0279_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0280_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0280_0:
    mul a0, a2, a3
pair_0280_1:
    jal a1, pair_0280_end
pair_0280_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0281_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0281_0:
    mul a0, a2, a3
pair_0281_1:
    jal a0, pair_0281_end
pair_0281_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0282_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0282_0:
    mul a0, a2, a3
pair_0282_1:
    jalr a1, 0(a5)
pair_0282_end:
    nop
    li a0, 7
    li a1, 9
    la a2, pair_0283_end
    li a3, 1
    la a4, scratch
    la a5, pair_0283_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0283_0:
    mul a0, a2, a3
pair_0283_1:
    jalr a1, 0(a0)
pair_0283_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0284_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0284_0:
    mul a0, a2, a3
pair_0284_1:
    jalr a0, 0(a5)
pair_0284_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0285_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0285_0:
    mul a0, a2, a3
pair_0285_1:
    csrrw a1, mscratch, a2
pair_0285_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0286_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0286_0:
    mul a0, a2, a3
pair_0286_1:
    csrrw a1, mscratch, a0
pair_0286_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0287_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0287_0:
    mul a0, a2, a3
pair_0287_1:
    csrrw a0, mscratch, a2
pair_0287_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0288_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0288_0:
    mul a0, a2, a3
pair_0288_1:
    fence rw,rw
pair_0288_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0289_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0289_0:
    mul a0, a2, a3
pair_0289_1:
    fence rw,rw
pair_0289_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0290_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0290_0:
    mul a0, a2, a3
pair_0290_1:
    fence rw,rw
pair_0290_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0291_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0291_0:
    mul a0, a2, a3
pair_0291_1:
    fence.i
pair_0291_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0292_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0292_0:
    mul a0, a2, a3
pair_0292_1:
    fence.i
pair_0292_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0293_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0293_0:
    mul a0, a2, a3
pair_0293_1:
    fence.i
pair_0293_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0294_end
    li t2, 0
    EXPECT 11, t2, pair_0294_1, pair_0294_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0294_0:
    mul a0, a2, a3
pair_0294_1:
    ecall
pair_0294_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0295_end
    li t2, 0
    EXPECT 11, t2, pair_0295_1, pair_0295_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0295_0:
    mul a0, a2, a3
pair_0295_1:
    ecall
pair_0295_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0296_end
    li t2, 0
    EXPECT 11, t2, pair_0296_1, pair_0296_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0296_0:
    mul a0, a2, a3
pair_0296_1:
    ecall
pair_0296_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0297_end
    li t2, 0
    EXPECT 3, t2, pair_0297_1, pair_0297_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0297_0:
    mul a0, a2, a3
pair_0297_1:
    ebreak
pair_0297_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0298_end
    li t2, 0
    EXPECT 3, t2, pair_0298_1, pair_0298_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0298_0:
    mul a0, a2, a3
pair_0298_1:
    ebreak
pair_0298_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0299_end
    li t2, 0
    EXPECT 3, t2, pair_0299_1, pair_0299_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0299_0:
    mul a0, a2, a3
pair_0299_1:
    ebreak
pair_0299_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0300_end
    la t0, pair_0300_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0300_0:
    mul a0, a2, a3
pair_0300_1:
    mret
pair_0300_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0301_end
    la t0, pair_0301_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0301_0:
    mul a0, a2, a3
pair_0301_1:
    mret
pair_0301_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0302_end
    la t0, pair_0302_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0302_0:
    mul a0, a2, a3
pair_0302_1:
    mret
pair_0302_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0303_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0303_0:
    mul a0, a2, a3
pair_0303_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0303_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0304_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0304_0:
    mul a0, a2, a3
pair_0304_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0304_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0305_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0305_0:
    mul a0, a2, a3
pair_0305_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0305_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0306_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0306_0:
    div a0, a2, a3
pair_0306_1:
    add a1, a2, a3
pair_0306_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0307_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0307_0:
    div a0, a2, a3
pair_0307_1:
    add a1, a0, a3
pair_0307_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0308_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0308_0:
    div a0, a2, a3
pair_0308_1:
    add a0, a2, a3
pair_0308_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0309_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0309_0:
    div a0, a2, a3
pair_0309_1:
    lui a1, 1
pair_0309_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0310_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0310_0:
    div a0, a2, a3
pair_0310_1:
    lui a1, 1
pair_0310_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0311_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0311_0:
    div a0, a2, a3
pair_0311_1:
    lui a0, 1
pair_0311_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0312_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0312_0:
    div a0, a2, a3
pair_0312_1:
    auipc a1, 0
pair_0312_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0313_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0313_0:
    div a0, a2, a3
pair_0313_1:
    auipc a1, 0
pair_0313_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0314_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0314_0:
    div a0, a2, a3
pair_0314_1:
    auipc a0, 0
pair_0314_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0315_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0315_0:
    div a0, a2, a3
pair_0315_1:
    lw a1, 0(a4)
pair_0315_end:
    nop
    li a0, 7
    li a1, 9
    la a2, pair_0316_end
    li a3, 1
    la a4, scratch
    la a5, pair_0316_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0316_0:
    div a0, a2, a3
pair_0316_1:
    lw a1, 0(a0)
pair_0316_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0317_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0317_0:
    div a0, a2, a3
pair_0317_1:
    lw a0, 0(a4)
pair_0317_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0318_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0318_0:
    div a0, a2, a3
pair_0318_1:
    sw a2, 0(a4)
pair_0318_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0319_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0319_0:
    div a0, a2, a3
pair_0319_1:
    sw a0, 0(a4)
pair_0319_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0320_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0320_0:
    div a0, a2, a3
pair_0320_1:
    sw a2, 0(a4)
pair_0320_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0321_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0321_0:
    div a0, a2, a3
pair_0321_1:
    mul a1, a2, a3
pair_0321_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0322_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0322_0:
    div a0, a2, a3
pair_0322_1:
    mul a1, a0, a3
pair_0322_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0323_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0323_0:
    div a0, a2, a3
pair_0323_1:
    mul a0, a2, a3
pair_0323_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0324_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0324_0:
    div a0, a2, a3
pair_0324_1:
    div a1, a2, a3
pair_0324_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0325_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0325_0:
    div a0, a2, a3
pair_0325_1:
    div a1, a0, a3
pair_0325_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0326_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0326_0:
    div a0, a2, a3
pair_0326_1:
    div a0, a2, a3
pair_0326_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0327_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0327_0:
    div a0, a2, a3
pair_0327_1:
    beq a2, a3, pair_0327_end
pair_0327_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0328_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0328_0:
    div a0, a2, a3
pair_0328_1:
    beq a0, a3, pair_0328_end
pair_0328_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0329_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0329_0:
    div a0, a2, a3
pair_0329_1:
    beq a2, a3, pair_0329_end
pair_0329_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0330_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0330_0:
    div a0, a2, a3
pair_0330_1:
    jal a1, pair_0330_end
pair_0330_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0331_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0331_0:
    div a0, a2, a3
pair_0331_1:
    jal a1, pair_0331_end
pair_0331_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0332_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0332_0:
    div a0, a2, a3
pair_0332_1:
    jal a0, pair_0332_end
pair_0332_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0333_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0333_0:
    div a0, a2, a3
pair_0333_1:
    jalr a1, 0(a5)
pair_0333_end:
    nop
    li a0, 7
    li a1, 9
    la a2, pair_0334_end
    li a3, 1
    la a4, scratch
    la a5, pair_0334_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0334_0:
    div a0, a2, a3
pair_0334_1:
    jalr a1, 0(a0)
pair_0334_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0335_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0335_0:
    div a0, a2, a3
pair_0335_1:
    jalr a0, 0(a5)
pair_0335_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0336_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0336_0:
    div a0, a2, a3
pair_0336_1:
    csrrw a1, mscratch, a2
pair_0336_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0337_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0337_0:
    div a0, a2, a3
pair_0337_1:
    csrrw a1, mscratch, a0
pair_0337_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0338_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0338_0:
    div a0, a2, a3
pair_0338_1:
    csrrw a0, mscratch, a2
pair_0338_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0339_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0339_0:
    div a0, a2, a3
pair_0339_1:
    fence rw,rw
pair_0339_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0340_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0340_0:
    div a0, a2, a3
pair_0340_1:
    fence rw,rw
pair_0340_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0341_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0341_0:
    div a0, a2, a3
pair_0341_1:
    fence rw,rw
pair_0341_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0342_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0342_0:
    div a0, a2, a3
pair_0342_1:
    fence.i
pair_0342_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0343_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0343_0:
    div a0, a2, a3
pair_0343_1:
    fence.i
pair_0343_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0344_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0344_0:
    div a0, a2, a3
pair_0344_1:
    fence.i
pair_0344_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0345_end
    li t2, 0
    EXPECT 11, t2, pair_0345_1, pair_0345_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0345_0:
    div a0, a2, a3
pair_0345_1:
    ecall
pair_0345_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0346_end
    li t2, 0
    EXPECT 11, t2, pair_0346_1, pair_0346_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0346_0:
    div a0, a2, a3
pair_0346_1:
    ecall
pair_0346_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0347_end
    li t2, 0
    EXPECT 11, t2, pair_0347_1, pair_0347_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0347_0:
    div a0, a2, a3
pair_0347_1:
    ecall
pair_0347_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0348_end
    li t2, 0
    EXPECT 3, t2, pair_0348_1, pair_0348_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0348_0:
    div a0, a2, a3
pair_0348_1:
    ebreak
pair_0348_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0349_end
    li t2, 0
    EXPECT 3, t2, pair_0349_1, pair_0349_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0349_0:
    div a0, a2, a3
pair_0349_1:
    ebreak
pair_0349_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0350_end
    li t2, 0
    EXPECT 3, t2, pair_0350_1, pair_0350_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0350_0:
    div a0, a2, a3
pair_0350_1:
    ebreak
pair_0350_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0351_end
    la t0, pair_0351_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0351_0:
    div a0, a2, a3
pair_0351_1:
    mret
pair_0351_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0352_end
    la t0, pair_0352_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0352_0:
    div a0, a2, a3
pair_0352_1:
    mret
pair_0352_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0353_end
    la t0, pair_0353_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0353_0:
    div a0, a2, a3
pair_0353_1:
    mret
pair_0353_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0354_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0354_0:
    div a0, a2, a3
pair_0354_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0354_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0355_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0355_0:
    div a0, a2, a3
pair_0355_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0355_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0356_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0356_0:
    div a0, a2, a3
pair_0356_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0356_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0357_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0357_0:
    beq a2, a3, pair_0357_1
pair_0357_1:
    add a1, a2, a3
pair_0357_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0358_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0358_0:
    beq a2, a3, pair_0358_1
pair_0358_1:
    add a1, a0, a3
pair_0358_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0359_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0359_0:
    beq a2, a3, pair_0359_1
pair_0359_1:
    add a0, a2, a3
pair_0359_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0360_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0360_0:
    beq a2, a3, pair_0360_1
pair_0360_1:
    lui a1, 1
pair_0360_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0361_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0361_0:
    beq a2, a3, pair_0361_1
pair_0361_1:
    lui a1, 1
pair_0361_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0362_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0362_0:
    beq a2, a3, pair_0362_1
pair_0362_1:
    lui a0, 1
pair_0362_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0363_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0363_0:
    beq a2, a3, pair_0363_1
pair_0363_1:
    auipc a1, 0
pair_0363_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0364_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0364_0:
    beq a2, a3, pair_0364_1
pair_0364_1:
    auipc a1, 0
pair_0364_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0365_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0365_0:
    beq a2, a3, pair_0365_1
pair_0365_1:
    auipc a0, 0
pair_0365_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0366_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0366_0:
    beq a2, a3, pair_0366_1
pair_0366_1:
    lw a1, 0(a4)
pair_0366_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0367_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0367_0:
    beq a2, a3, pair_0367_1
pair_0367_1:
    lw a1, 0(a4)
pair_0367_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0368_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0368_0:
    beq a2, a3, pair_0368_1
pair_0368_1:
    lw a0, 0(a4)
pair_0368_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0369_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0369_0:
    beq a2, a3, pair_0369_1
pair_0369_1:
    sw a2, 0(a4)
pair_0369_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0370_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0370_0:
    beq a2, a3, pair_0370_1
pair_0370_1:
    sw a0, 0(a4)
pair_0370_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0371_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0371_0:
    beq a2, a3, pair_0371_1
pair_0371_1:
    sw a2, 0(a4)
pair_0371_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0372_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0372_0:
    beq a2, a3, pair_0372_1
pair_0372_1:
    mul a1, a2, a3
pair_0372_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0373_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0373_0:
    beq a2, a3, pair_0373_1
pair_0373_1:
    mul a1, a0, a3
pair_0373_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0374_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0374_0:
    beq a2, a3, pair_0374_1
pair_0374_1:
    mul a0, a2, a3
pair_0374_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0375_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0375_0:
    beq a2, a3, pair_0375_1
pair_0375_1:
    div a1, a2, a3
pair_0375_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0376_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0376_0:
    beq a2, a3, pair_0376_1
pair_0376_1:
    div a1, a0, a3
pair_0376_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0377_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0377_0:
    beq a2, a3, pair_0377_1
pair_0377_1:
    div a0, a2, a3
pair_0377_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0378_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0378_0:
    beq a2, a3, pair_0378_1
pair_0378_1:
    beq a2, a3, pair_0378_end
pair_0378_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0379_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0379_0:
    beq a2, a3, pair_0379_1
pair_0379_1:
    beq a0, a3, pair_0379_end
pair_0379_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0380_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0380_0:
    beq a2, a3, pair_0380_1
pair_0380_1:
    beq a2, a3, pair_0380_end
pair_0380_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0381_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0381_0:
    beq a2, a3, pair_0381_1
pair_0381_1:
    jal a1, pair_0381_end
pair_0381_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0382_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0382_0:
    beq a2, a3, pair_0382_1
pair_0382_1:
    jal a1, pair_0382_end
pair_0382_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0383_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0383_0:
    beq a2, a3, pair_0383_1
pair_0383_1:
    jal a0, pair_0383_end
pair_0383_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0384_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0384_0:
    beq a2, a3, pair_0384_1
pair_0384_1:
    jalr a1, 0(a5)
pair_0384_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0385_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0385_0:
    beq a2, a3, pair_0385_1
pair_0385_1:
    jalr a1, 0(a5)
pair_0385_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0386_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0386_0:
    beq a2, a3, pair_0386_1
pair_0386_1:
    jalr a0, 0(a5)
pair_0386_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0387_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0387_0:
    beq a2, a3, pair_0387_1
pair_0387_1:
    csrrw a1, mscratch, a2
pair_0387_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0388_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0388_0:
    beq a2, a3, pair_0388_1
pair_0388_1:
    csrrw a1, mscratch, a0
pair_0388_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0389_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0389_0:
    beq a2, a3, pair_0389_1
pair_0389_1:
    csrrw a0, mscratch, a2
pair_0389_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0390_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0390_0:
    beq a2, a3, pair_0390_1
pair_0390_1:
    fence rw,rw
pair_0390_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0391_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0391_0:
    beq a2, a3, pair_0391_1
pair_0391_1:
    fence rw,rw
pair_0391_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0392_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0392_0:
    beq a2, a3, pair_0392_1
pair_0392_1:
    fence rw,rw
pair_0392_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0393_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0393_0:
    beq a2, a3, pair_0393_1
pair_0393_1:
    fence.i
pair_0393_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0394_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0394_0:
    beq a2, a3, pair_0394_1
pair_0394_1:
    fence.i
pair_0394_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0395_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0395_0:
    beq a2, a3, pair_0395_1
pair_0395_1:
    fence.i
pair_0395_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0396_end
    li t2, 0
    EXPECT 11, t2, pair_0396_1, pair_0396_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0396_0:
    beq a2, a3, pair_0396_1
pair_0396_1:
    ecall
pair_0396_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0397_end
    li t2, 0
    EXPECT 11, t2, pair_0397_1, pair_0397_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0397_0:
    beq a2, a3, pair_0397_1
pair_0397_1:
    ecall
pair_0397_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0398_end
    li t2, 0
    EXPECT 11, t2, pair_0398_1, pair_0398_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0398_0:
    beq a2, a3, pair_0398_1
pair_0398_1:
    ecall
pair_0398_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0399_end
    li t2, 0
    EXPECT 3, t2, pair_0399_1, pair_0399_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0399_0:
    beq a2, a3, pair_0399_1
pair_0399_1:
    ebreak
pair_0399_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0400_end
    li t2, 0
    EXPECT 3, t2, pair_0400_1, pair_0400_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0400_0:
    beq a2, a3, pair_0400_1
pair_0400_1:
    ebreak
pair_0400_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0401_end
    li t2, 0
    EXPECT 3, t2, pair_0401_1, pair_0401_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0401_0:
    beq a2, a3, pair_0401_1
pair_0401_1:
    ebreak
pair_0401_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0402_end
    la t0, pair_0402_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0402_0:
    beq a2, a3, pair_0402_1
pair_0402_1:
    mret
pair_0402_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0403_end
    la t0, pair_0403_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0403_0:
    beq a2, a3, pair_0403_1
pair_0403_1:
    mret
pair_0403_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0404_end
    la t0, pair_0404_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0404_0:
    beq a2, a3, pair_0404_1
pair_0404_1:
    mret
pair_0404_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0405_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0405_0:
    beq a2, a3, pair_0405_1
pair_0405_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0405_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0406_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0406_0:
    beq a2, a3, pair_0406_1
pair_0406_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0406_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0407_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0407_0:
    beq a2, a3, pair_0407_1
pair_0407_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0407_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0408_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0408_0:
    jal a0, pair_0408_1
pair_0408_1:
    add a1, a2, a3
pair_0408_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0409_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0409_0:
    jal a0, pair_0409_1
pair_0409_1:
    add a1, a0, a3
pair_0409_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0410_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0410_0:
    jal a0, pair_0410_1
pair_0410_1:
    add a0, a2, a3
pair_0410_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0411_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0411_0:
    jal a0, pair_0411_1
pair_0411_1:
    lui a1, 1
pair_0411_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0412_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0412_0:
    jal a0, pair_0412_1
pair_0412_1:
    lui a1, 1
pair_0412_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0413_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0413_0:
    jal a0, pair_0413_1
pair_0413_1:
    lui a0, 1
pair_0413_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0414_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0414_0:
    jal a0, pair_0414_1
pair_0414_1:
    auipc a1, 0
pair_0414_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0415_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0415_0:
    jal a0, pair_0415_1
pair_0415_1:
    auipc a1, 0
pair_0415_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0416_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0416_0:
    jal a0, pair_0416_1
pair_0416_1:
    auipc a0, 0
pair_0416_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0417_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0417_0:
    jal a0, pair_0417_1
pair_0417_1:
    lw a1, 0(a4)
pair_0417_end:
    nop
    li a0, 7
    li a1, 9
    la a2, pair_0418_end
    li a3, 0
    la a4, scratch
    la a5, pair_0418_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0418_0:
    jal a0, pair_0418_1
pair_0418_1:
    lw a1, 0(a0)
pair_0418_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0419_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0419_0:
    jal a0, pair_0419_1
pair_0419_1:
    lw a0, 0(a4)
pair_0419_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0420_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0420_0:
    jal a0, pair_0420_1
pair_0420_1:
    sw a2, 0(a4)
pair_0420_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0421_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0421_0:
    jal a0, pair_0421_1
pair_0421_1:
    sw a0, 0(a4)
pair_0421_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0422_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0422_0:
    jal a0, pair_0422_1
pair_0422_1:
    sw a2, 0(a4)
pair_0422_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0423_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0423_0:
    jal a0, pair_0423_1
pair_0423_1:
    mul a1, a2, a3
pair_0423_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0424_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0424_0:
    jal a0, pair_0424_1
pair_0424_1:
    mul a1, a0, a3
pair_0424_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0425_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0425_0:
    jal a0, pair_0425_1
pair_0425_1:
    mul a0, a2, a3
pair_0425_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0426_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0426_0:
    jal a0, pair_0426_1
pair_0426_1:
    div a1, a2, a3
pair_0426_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0427_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0427_0:
    jal a0, pair_0427_1
pair_0427_1:
    div a1, a0, a3
pair_0427_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0428_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0428_0:
    jal a0, pair_0428_1
pair_0428_1:
    div a0, a2, a3
pair_0428_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0429_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0429_0:
    jal a0, pair_0429_1
pair_0429_1:
    beq a2, a3, pair_0429_end
pair_0429_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0430_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0430_0:
    jal a0, pair_0430_1
pair_0430_1:
    beq a0, a3, pair_0430_end
pair_0430_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0431_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0431_0:
    jal a0, pair_0431_1
pair_0431_1:
    beq a2, a3, pair_0431_end
pair_0431_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0432_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0432_0:
    jal a0, pair_0432_1
pair_0432_1:
    jal a1, pair_0432_end
pair_0432_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0433_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0433_0:
    jal a0, pair_0433_1
pair_0433_1:
    jal a1, pair_0433_end
pair_0433_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0434_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0434_0:
    jal a0, pair_0434_1
pair_0434_1:
    jal a0, pair_0434_end
pair_0434_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0435_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0435_0:
    jal a0, pair_0435_1
pair_0435_1:
    jalr a1, 0(a5)
pair_0435_end:
    nop
    li a0, 7
    li a1, 9
    la a2, pair_0436_end
    li a3, 0
    la a4, scratch
    la a5, pair_0436_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0436_0:
    jal a0, pair_0436_1
pair_0436_1:
    jalr a1, 4(a0)
pair_0436_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0437_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0437_0:
    jal a0, pair_0437_1
pair_0437_1:
    jalr a0, 0(a5)
pair_0437_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0438_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0438_0:
    jal a0, pair_0438_1
pair_0438_1:
    csrrw a1, mscratch, a2
pair_0438_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0439_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0439_0:
    jal a0, pair_0439_1
pair_0439_1:
    csrrw a1, mscratch, a0
pair_0439_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0440_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0440_0:
    jal a0, pair_0440_1
pair_0440_1:
    csrrw a0, mscratch, a2
pair_0440_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0441_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0441_0:
    jal a0, pair_0441_1
pair_0441_1:
    fence rw,rw
pair_0441_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0442_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0442_0:
    jal a0, pair_0442_1
pair_0442_1:
    fence rw,rw
pair_0442_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0443_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0443_0:
    jal a0, pair_0443_1
pair_0443_1:
    fence rw,rw
pair_0443_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0444_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0444_0:
    jal a0, pair_0444_1
pair_0444_1:
    fence.i
pair_0444_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0445_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0445_0:
    jal a0, pair_0445_1
pair_0445_1:
    fence.i
pair_0445_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0446_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0446_0:
    jal a0, pair_0446_1
pair_0446_1:
    fence.i
pair_0446_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0447_end
    li t2, 0
    EXPECT 11, t2, pair_0447_1, pair_0447_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0447_0:
    jal a0, pair_0447_1
pair_0447_1:
    ecall
pair_0447_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0448_end
    li t2, 0
    EXPECT 11, t2, pair_0448_1, pair_0448_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0448_0:
    jal a0, pair_0448_1
pair_0448_1:
    ecall
pair_0448_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0449_end
    li t2, 0
    EXPECT 11, t2, pair_0449_1, pair_0449_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0449_0:
    jal a0, pair_0449_1
pair_0449_1:
    ecall
pair_0449_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0450_end
    li t2, 0
    EXPECT 3, t2, pair_0450_1, pair_0450_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0450_0:
    jal a0, pair_0450_1
pair_0450_1:
    ebreak
pair_0450_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0451_end
    li t2, 0
    EXPECT 3, t2, pair_0451_1, pair_0451_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0451_0:
    jal a0, pair_0451_1
pair_0451_1:
    ebreak
pair_0451_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0452_end
    li t2, 0
    EXPECT 3, t2, pair_0452_1, pair_0452_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0452_0:
    jal a0, pair_0452_1
pair_0452_1:
    ebreak
pair_0452_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0453_end
    la t0, pair_0453_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0453_0:
    jal a0, pair_0453_1
pair_0453_1:
    mret
pair_0453_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0454_end
    la t0, pair_0454_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0454_0:
    jal a0, pair_0454_1
pair_0454_1:
    mret
pair_0454_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0455_end
    la t0, pair_0455_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0455_0:
    jal a0, pair_0455_1
pair_0455_1:
    mret
pair_0455_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0456_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0456_0:
    jal a0, pair_0456_1
pair_0456_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0456_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0457_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0457_0:
    jal a0, pair_0457_1
pair_0457_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0457_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0458_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0458_0:
    jal a0, pair_0458_1
pair_0458_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0458_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0459_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0459_0:
    jalr a0, 0(a5)
pair_0459_1:
    add a1, a2, a3
pair_0459_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0460_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0460_0:
    jalr a0, 0(a5)
pair_0460_1:
    add a1, a0, a3
pair_0460_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0461_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0461_0:
    jalr a0, 0(a5)
pair_0461_1:
    add a0, a2, a3
pair_0461_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0462_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0462_0:
    jalr a0, 0(a5)
pair_0462_1:
    lui a1, 1
pair_0462_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0463_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0463_0:
    jalr a0, 0(a5)
pair_0463_1:
    lui a1, 1
pair_0463_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0464_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0464_0:
    jalr a0, 0(a5)
pair_0464_1:
    lui a0, 1
pair_0464_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0465_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0465_0:
    jalr a0, 0(a5)
pair_0465_1:
    auipc a1, 0
pair_0465_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0466_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0466_0:
    jalr a0, 0(a5)
pair_0466_1:
    auipc a1, 0
pair_0466_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0467_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0467_0:
    jalr a0, 0(a5)
pair_0467_1:
    auipc a0, 0
pair_0467_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0468_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0468_0:
    jalr a0, 0(a5)
pair_0468_1:
    lw a1, 0(a4)
pair_0468_end:
    nop
    li a0, 7
    li a1, 9
    la a2, pair_0469_end
    li a3, 0
    la a4, scratch
    la a5, pair_0469_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0469_0:
    jalr a0, 0(a5)
pair_0469_1:
    lw a1, 0(a0)
pair_0469_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0470_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0470_0:
    jalr a0, 0(a5)
pair_0470_1:
    lw a0, 0(a4)
pair_0470_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0471_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0471_0:
    jalr a0, 0(a5)
pair_0471_1:
    sw a2, 0(a4)
pair_0471_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0472_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0472_0:
    jalr a0, 0(a5)
pair_0472_1:
    sw a0, 0(a4)
pair_0472_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0473_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0473_0:
    jalr a0, 0(a5)
pair_0473_1:
    sw a2, 0(a4)
pair_0473_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0474_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0474_0:
    jalr a0, 0(a5)
pair_0474_1:
    mul a1, a2, a3
pair_0474_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0475_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0475_0:
    jalr a0, 0(a5)
pair_0475_1:
    mul a1, a0, a3
pair_0475_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0476_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0476_0:
    jalr a0, 0(a5)
pair_0476_1:
    mul a0, a2, a3
pair_0476_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0477_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0477_0:
    jalr a0, 0(a5)
pair_0477_1:
    div a1, a2, a3
pair_0477_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0478_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0478_0:
    jalr a0, 0(a5)
pair_0478_1:
    div a1, a0, a3
pair_0478_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0479_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0479_0:
    jalr a0, 0(a5)
pair_0479_1:
    div a0, a2, a3
pair_0479_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0480_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0480_0:
    jalr a0, 0(a5)
pair_0480_1:
    beq a2, a3, pair_0480_end
pair_0480_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0481_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0481_0:
    jalr a0, 0(a5)
pair_0481_1:
    beq a0, a3, pair_0481_end
pair_0481_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0482_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0482_0:
    jalr a0, 0(a5)
pair_0482_1:
    beq a2, a3, pair_0482_end
pair_0482_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0483_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0483_0:
    jalr a0, 0(a5)
pair_0483_1:
    jal a1, pair_0483_end
pair_0483_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0484_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0484_0:
    jalr a0, 0(a5)
pair_0484_1:
    jal a1, pair_0484_end
pair_0484_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0485_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0485_0:
    jalr a0, 0(a5)
pair_0485_1:
    jal a0, pair_0485_end
pair_0485_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0486_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0486_0:
    jalr a0, 0(a5)
pair_0486_1:
    jalr a1, 0(a5)
pair_0486_end:
    nop
    li a0, 7
    li a1, 9
    la a2, pair_0487_end
    li a3, 0
    la a4, scratch
    la a5, pair_0487_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0487_0:
    jalr a0, 0(a5)
pair_0487_1:
    jalr a1, 0(a0)
pair_0487_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0488_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0488_0:
    jalr a0, 0(a5)
pair_0488_1:
    jalr a0, 0(a5)
pair_0488_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0489_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0489_0:
    jalr a0, 0(a5)
pair_0489_1:
    csrrw a1, mscratch, a2
pair_0489_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0490_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0490_0:
    jalr a0, 0(a5)
pair_0490_1:
    csrrw a1, mscratch, a0
pair_0490_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0491_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0491_0:
    jalr a0, 0(a5)
pair_0491_1:
    csrrw a0, mscratch, a2
pair_0491_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0492_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0492_0:
    jalr a0, 0(a5)
pair_0492_1:
    fence rw,rw
pair_0492_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0493_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0493_0:
    jalr a0, 0(a5)
pair_0493_1:
    fence rw,rw
pair_0493_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0494_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0494_0:
    jalr a0, 0(a5)
pair_0494_1:
    fence rw,rw
pair_0494_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0495_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0495_0:
    jalr a0, 0(a5)
pair_0495_1:
    fence.i
pair_0495_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0496_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0496_0:
    jalr a0, 0(a5)
pair_0496_1:
    fence.i
pair_0496_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0497_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0497_0:
    jalr a0, 0(a5)
pair_0497_1:
    fence.i
pair_0497_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0498_end
    li t2, 0
    EXPECT 11, t2, pair_0498_1, pair_0498_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0498_0:
    jalr a0, 0(a5)
pair_0498_1:
    ecall
pair_0498_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0499_end
    li t2, 0
    EXPECT 11, t2, pair_0499_1, pair_0499_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0499_0:
    jalr a0, 0(a5)
pair_0499_1:
    ecall
pair_0499_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0500_end
    li t2, 0
    EXPECT 11, t2, pair_0500_1, pair_0500_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0500_0:
    jalr a0, 0(a5)
pair_0500_1:
    ecall
pair_0500_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0501_end
    li t2, 0
    EXPECT 3, t2, pair_0501_1, pair_0501_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0501_0:
    jalr a0, 0(a5)
pair_0501_1:
    ebreak
pair_0501_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0502_end
    li t2, 0
    EXPECT 3, t2, pair_0502_1, pair_0502_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0502_0:
    jalr a0, 0(a5)
pair_0502_1:
    ebreak
pair_0502_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0503_end
    li t2, 0
    EXPECT 3, t2, pair_0503_1, pair_0503_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0503_0:
    jalr a0, 0(a5)
pair_0503_1:
    ebreak
pair_0503_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0504_end
    la t0, pair_0504_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0504_0:
    jalr a0, 0(a5)
pair_0504_1:
    mret
pair_0504_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0505_end
    la t0, pair_0505_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0505_0:
    jalr a0, 0(a5)
pair_0505_1:
    mret
pair_0505_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0506_end
    la t0, pair_0506_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0506_0:
    jalr a0, 0(a5)
pair_0506_1:
    mret
pair_0506_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0507_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0507_0:
    jalr a0, 0(a5)
pair_0507_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0507_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0508_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0508_0:
    jalr a0, 0(a5)
pair_0508_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0508_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0509_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0509_0:
    jalr a0, 0(a5)
pair_0509_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0509_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0510_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0510_0:
    csrrw a0, mscratch, a2
pair_0510_1:
    add a1, a2, a3
pair_0510_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0511_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0511_0:
    csrrw a0, mscratch, a2
pair_0511_1:
    add a1, a0, a3
pair_0511_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0512_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0512_0:
    csrrw a0, mscratch, a2
pair_0512_1:
    add a0, a2, a3
pair_0512_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0513_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0513_0:
    csrrw a0, mscratch, a2
pair_0513_1:
    lui a1, 1
pair_0513_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0514_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0514_0:
    csrrw a0, mscratch, a2
pair_0514_1:
    lui a1, 1
pair_0514_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0515_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0515_0:
    csrrw a0, mscratch, a2
pair_0515_1:
    lui a0, 1
pair_0515_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0516_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0516_0:
    csrrw a0, mscratch, a2
pair_0516_1:
    auipc a1, 0
pair_0516_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0517_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0517_0:
    csrrw a0, mscratch, a2
pair_0517_1:
    auipc a1, 0
pair_0517_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0518_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0518_0:
    csrrw a0, mscratch, a2
pair_0518_1:
    auipc a0, 0
pair_0518_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0519_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0519_0:
    csrrw a0, mscratch, a2
pair_0519_1:
    lw a1, 0(a4)
pair_0519_end:
    nop
    li a0, 7
    li a1, 9
    la a2, pair_0520_end
    li a3, 0
    la a4, scratch
    la a5, pair_0520_end
    csrw mscratch, a2
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0520_0:
    csrrw a0, mscratch, a2
pair_0520_1:
    lw a1, 0(a0)
pair_0520_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0521_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0521_0:
    csrrw a0, mscratch, a2
pair_0521_1:
    lw a0, 0(a4)
pair_0521_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0522_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0522_0:
    csrrw a0, mscratch, a2
pair_0522_1:
    sw a2, 0(a4)
pair_0522_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0523_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0523_0:
    csrrw a0, mscratch, a2
pair_0523_1:
    sw a0, 0(a4)
pair_0523_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0524_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0524_0:
    csrrw a0, mscratch, a2
pair_0524_1:
    sw a2, 0(a4)
pair_0524_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0525_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0525_0:
    csrrw a0, mscratch, a2
pair_0525_1:
    mul a1, a2, a3
pair_0525_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0526_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0526_0:
    csrrw a0, mscratch, a2
pair_0526_1:
    mul a1, a0, a3
pair_0526_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0527_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0527_0:
    csrrw a0, mscratch, a2
pair_0527_1:
    mul a0, a2, a3
pair_0527_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0528_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0528_0:
    csrrw a0, mscratch, a2
pair_0528_1:
    div a1, a2, a3
pair_0528_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0529_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0529_0:
    csrrw a0, mscratch, a2
pair_0529_1:
    div a1, a0, a3
pair_0529_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0530_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0530_0:
    csrrw a0, mscratch, a2
pair_0530_1:
    div a0, a2, a3
pair_0530_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0531_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0531_0:
    csrrw a0, mscratch, a2
pair_0531_1:
    beq a2, a3, pair_0531_end
pair_0531_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0532_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0532_0:
    csrrw a0, mscratch, a2
pair_0532_1:
    beq a0, a3, pair_0532_end
pair_0532_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0533_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0533_0:
    csrrw a0, mscratch, a2
pair_0533_1:
    beq a2, a3, pair_0533_end
pair_0533_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0534_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0534_0:
    csrrw a0, mscratch, a2
pair_0534_1:
    jal a1, pair_0534_end
pair_0534_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0535_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0535_0:
    csrrw a0, mscratch, a2
pair_0535_1:
    jal a1, pair_0535_end
pair_0535_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0536_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0536_0:
    csrrw a0, mscratch, a2
pair_0536_1:
    jal a0, pair_0536_end
pair_0536_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0537_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0537_0:
    csrrw a0, mscratch, a2
pair_0537_1:
    jalr a1, 0(a5)
pair_0537_end:
    nop
    li a0, 7
    li a1, 9
    la a2, pair_0538_end
    li a3, 0
    la a4, scratch
    la a5, pair_0538_end
    csrw mscratch, a2
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0538_0:
    csrrw a0, mscratch, a2
pair_0538_1:
    jalr a1, 0(a0)
pair_0538_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0539_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0539_0:
    csrrw a0, mscratch, a2
pair_0539_1:
    jalr a0, 0(a5)
pair_0539_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0540_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0540_0:
    csrrw a0, mscratch, a2
pair_0540_1:
    csrrw a1, mscratch, a2
pair_0540_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0541_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0541_0:
    csrrw a0, mscratch, a2
pair_0541_1:
    csrrw a1, mscratch, a0
pair_0541_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0542_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0542_0:
    csrrw a0, mscratch, a2
pair_0542_1:
    csrrw a0, mscratch, a2
pair_0542_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0543_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0543_0:
    csrrw a0, mscratch, a2
pair_0543_1:
    fence rw,rw
pair_0543_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0544_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0544_0:
    csrrw a0, mscratch, a2
pair_0544_1:
    fence rw,rw
pair_0544_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0545_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0545_0:
    csrrw a0, mscratch, a2
pair_0545_1:
    fence rw,rw
pair_0545_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0546_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0546_0:
    csrrw a0, mscratch, a2
pair_0546_1:
    fence.i
pair_0546_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0547_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0547_0:
    csrrw a0, mscratch, a2
pair_0547_1:
    fence.i
pair_0547_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0548_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0548_0:
    csrrw a0, mscratch, a2
pair_0548_1:
    fence.i
pair_0548_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0549_end
    li t2, 0
    EXPECT 11, t2, pair_0549_1, pair_0549_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0549_0:
    csrrw a0, mscratch, a2
pair_0549_1:
    ecall
pair_0549_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0550_end
    li t2, 0
    EXPECT 11, t2, pair_0550_1, pair_0550_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0550_0:
    csrrw a0, mscratch, a2
pair_0550_1:
    ecall
pair_0550_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0551_end
    li t2, 0
    EXPECT 11, t2, pair_0551_1, pair_0551_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0551_0:
    csrrw a0, mscratch, a2
pair_0551_1:
    ecall
pair_0551_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0552_end
    li t2, 0
    EXPECT 3, t2, pair_0552_1, pair_0552_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0552_0:
    csrrw a0, mscratch, a2
pair_0552_1:
    ebreak
pair_0552_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0553_end
    li t2, 0
    EXPECT 3, t2, pair_0553_1, pair_0553_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0553_0:
    csrrw a0, mscratch, a2
pair_0553_1:
    ebreak
pair_0553_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0554_end
    li t2, 0
    EXPECT 3, t2, pair_0554_1, pair_0554_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0554_0:
    csrrw a0, mscratch, a2
pair_0554_1:
    ebreak
pair_0554_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0555_end
    la t0, pair_0555_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0555_0:
    csrrw a0, mscratch, a2
pair_0555_1:
    mret
pair_0555_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0556_end
    la t0, pair_0556_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0556_0:
    csrrw a0, mscratch, a2
pair_0556_1:
    mret
pair_0556_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0557_end
    la t0, pair_0557_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0557_0:
    csrrw a0, mscratch, a2
pair_0557_1:
    mret
pair_0557_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0558_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0558_0:
    csrrw a0, mscratch, a2
pair_0558_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0558_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0559_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0559_0:
    csrrw a0, mscratch, a2
pair_0559_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0559_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0560_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0560_0:
    csrrw a0, mscratch, a2
pair_0560_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0560_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0561_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0561_0:
    fence rw,rw
pair_0561_1:
    add a1, a2, a3
pair_0561_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0562_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0562_0:
    fence rw,rw
pair_0562_1:
    add a1, a0, a3
pair_0562_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0563_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0563_0:
    fence rw,rw
pair_0563_1:
    add a0, a2, a3
pair_0563_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0564_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0564_0:
    fence rw,rw
pair_0564_1:
    lui a1, 1
pair_0564_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0565_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0565_0:
    fence rw,rw
pair_0565_1:
    lui a1, 1
pair_0565_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0566_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0566_0:
    fence rw,rw
pair_0566_1:
    lui a0, 1
pair_0566_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0567_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0567_0:
    fence rw,rw
pair_0567_1:
    auipc a1, 0
pair_0567_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0568_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0568_0:
    fence rw,rw
pair_0568_1:
    auipc a1, 0
pair_0568_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0569_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0569_0:
    fence rw,rw
pair_0569_1:
    auipc a0, 0
pair_0569_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0570_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0570_0:
    fence rw,rw
pair_0570_1:
    lw a1, 0(a4)
pair_0570_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0571_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0571_0:
    fence rw,rw
pair_0571_1:
    lw a1, 0(a4)
pair_0571_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0572_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0572_0:
    fence rw,rw
pair_0572_1:
    lw a0, 0(a4)
pair_0572_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0573_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0573_0:
    fence rw,rw
pair_0573_1:
    sw a2, 0(a4)
pair_0573_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0574_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0574_0:
    fence rw,rw
pair_0574_1:
    sw a0, 0(a4)
pair_0574_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0575_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0575_0:
    fence rw,rw
pair_0575_1:
    sw a2, 0(a4)
pair_0575_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0576_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0576_0:
    fence rw,rw
pair_0576_1:
    mul a1, a2, a3
pair_0576_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0577_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0577_0:
    fence rw,rw
pair_0577_1:
    mul a1, a0, a3
pair_0577_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0578_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0578_0:
    fence rw,rw
pair_0578_1:
    mul a0, a2, a3
pair_0578_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0579_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0579_0:
    fence rw,rw
pair_0579_1:
    div a1, a2, a3
pair_0579_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0580_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0580_0:
    fence rw,rw
pair_0580_1:
    div a1, a0, a3
pair_0580_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0581_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0581_0:
    fence rw,rw
pair_0581_1:
    div a0, a2, a3
pair_0581_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0582_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0582_0:
    fence rw,rw
pair_0582_1:
    beq a2, a3, pair_0582_end
pair_0582_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0583_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0583_0:
    fence rw,rw
pair_0583_1:
    beq a0, a3, pair_0583_end
pair_0583_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0584_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0584_0:
    fence rw,rw
pair_0584_1:
    beq a2, a3, pair_0584_end
pair_0584_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0585_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0585_0:
    fence rw,rw
pair_0585_1:
    jal a1, pair_0585_end
pair_0585_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0586_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0586_0:
    fence rw,rw
pair_0586_1:
    jal a1, pair_0586_end
pair_0586_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0587_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0587_0:
    fence rw,rw
pair_0587_1:
    jal a0, pair_0587_end
pair_0587_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0588_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0588_0:
    fence rw,rw
pair_0588_1:
    jalr a1, 0(a5)
pair_0588_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0589_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0589_0:
    fence rw,rw
pair_0589_1:
    jalr a1, 0(a5)
pair_0589_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0590_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0590_0:
    fence rw,rw
pair_0590_1:
    jalr a0, 0(a5)
pair_0590_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0591_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0591_0:
    fence rw,rw
pair_0591_1:
    csrrw a1, mscratch, a2
pair_0591_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0592_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0592_0:
    fence rw,rw
pair_0592_1:
    csrrw a1, mscratch, a0
pair_0592_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0593_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0593_0:
    fence rw,rw
pair_0593_1:
    csrrw a0, mscratch, a2
pair_0593_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0594_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0594_0:
    fence rw,rw
pair_0594_1:
    fence rw,rw
pair_0594_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0595_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0595_0:
    fence rw,rw
pair_0595_1:
    fence rw,rw
pair_0595_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0596_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0596_0:
    fence rw,rw
pair_0596_1:
    fence rw,rw
pair_0596_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0597_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0597_0:
    fence rw,rw
pair_0597_1:
    fence.i
pair_0597_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0598_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0598_0:
    fence rw,rw
pair_0598_1:
    fence.i
pair_0598_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0599_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0599_0:
    fence rw,rw
pair_0599_1:
    fence.i
pair_0599_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0600_end
    li t2, 0
    EXPECT 11, t2, pair_0600_1, pair_0600_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0600_0:
    fence rw,rw
pair_0600_1:
    ecall
pair_0600_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0601_end
    li t2, 0
    EXPECT 11, t2, pair_0601_1, pair_0601_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0601_0:
    fence rw,rw
pair_0601_1:
    ecall
pair_0601_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0602_end
    li t2, 0
    EXPECT 11, t2, pair_0602_1, pair_0602_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0602_0:
    fence rw,rw
pair_0602_1:
    ecall
pair_0602_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0603_end
    li t2, 0
    EXPECT 3, t2, pair_0603_1, pair_0603_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0603_0:
    fence rw,rw
pair_0603_1:
    ebreak
pair_0603_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0604_end
    li t2, 0
    EXPECT 3, t2, pair_0604_1, pair_0604_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0604_0:
    fence rw,rw
pair_0604_1:
    ebreak
pair_0604_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0605_end
    li t2, 0
    EXPECT 3, t2, pair_0605_1, pair_0605_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0605_0:
    fence rw,rw
pair_0605_1:
    ebreak
pair_0605_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0606_end
    la t0, pair_0606_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0606_0:
    fence rw,rw
pair_0606_1:
    mret
pair_0606_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0607_end
    la t0, pair_0607_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0607_0:
    fence rw,rw
pair_0607_1:
    mret
pair_0607_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0608_end
    la t0, pair_0608_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0608_0:
    fence rw,rw
pair_0608_1:
    mret
pair_0608_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0609_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0609_0:
    fence rw,rw
pair_0609_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0609_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0610_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0610_0:
    fence rw,rw
pair_0610_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0610_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0611_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0611_0:
    fence rw,rw
pair_0611_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0611_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0612_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0612_0:
    fence.i
pair_0612_1:
    add a1, a2, a3
pair_0612_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0613_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0613_0:
    fence.i
pair_0613_1:
    add a1, a0, a3
pair_0613_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0614_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0614_0:
    fence.i
pair_0614_1:
    add a0, a2, a3
pair_0614_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0615_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0615_0:
    fence.i
pair_0615_1:
    lui a1, 1
pair_0615_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0616_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0616_0:
    fence.i
pair_0616_1:
    lui a1, 1
pair_0616_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0617_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0617_0:
    fence.i
pair_0617_1:
    lui a0, 1
pair_0617_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0618_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0618_0:
    fence.i
pair_0618_1:
    auipc a1, 0
pair_0618_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0619_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0619_0:
    fence.i
pair_0619_1:
    auipc a1, 0
pair_0619_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0620_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0620_0:
    fence.i
pair_0620_1:
    auipc a0, 0
pair_0620_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0621_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0621_0:
    fence.i
pair_0621_1:
    lw a1, 0(a4)
pair_0621_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0622_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0622_0:
    fence.i
pair_0622_1:
    lw a1, 0(a4)
pair_0622_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0623_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0623_0:
    fence.i
pair_0623_1:
    lw a0, 0(a4)
pair_0623_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0624_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0624_0:
    fence.i
pair_0624_1:
    sw a2, 0(a4)
pair_0624_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0625_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0625_0:
    fence.i
pair_0625_1:
    sw a0, 0(a4)
pair_0625_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0626_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0626_0:
    fence.i
pair_0626_1:
    sw a2, 0(a4)
pair_0626_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0627_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0627_0:
    fence.i
pair_0627_1:
    mul a1, a2, a3
pair_0627_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0628_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0628_0:
    fence.i
pair_0628_1:
    mul a1, a0, a3
pair_0628_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0629_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0629_0:
    fence.i
pair_0629_1:
    mul a0, a2, a3
pair_0629_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0630_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0630_0:
    fence.i
pair_0630_1:
    div a1, a2, a3
pair_0630_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0631_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0631_0:
    fence.i
pair_0631_1:
    div a1, a0, a3
pair_0631_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0632_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0632_0:
    fence.i
pair_0632_1:
    div a0, a2, a3
pair_0632_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0633_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0633_0:
    fence.i
pair_0633_1:
    beq a2, a3, pair_0633_end
pair_0633_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0634_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0634_0:
    fence.i
pair_0634_1:
    beq a0, a3, pair_0634_end
pair_0634_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0635_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0635_0:
    fence.i
pair_0635_1:
    beq a2, a3, pair_0635_end
pair_0635_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0636_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0636_0:
    fence.i
pair_0636_1:
    jal a1, pair_0636_end
pair_0636_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0637_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0637_0:
    fence.i
pair_0637_1:
    jal a1, pair_0637_end
pair_0637_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0638_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0638_0:
    fence.i
pair_0638_1:
    jal a0, pair_0638_end
pair_0638_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0639_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0639_0:
    fence.i
pair_0639_1:
    jalr a1, 0(a5)
pair_0639_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0640_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0640_0:
    fence.i
pair_0640_1:
    jalr a1, 0(a5)
pair_0640_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0641_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0641_0:
    fence.i
pair_0641_1:
    jalr a0, 0(a5)
pair_0641_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0642_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0642_0:
    fence.i
pair_0642_1:
    csrrw a1, mscratch, a2
pair_0642_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0643_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0643_0:
    fence.i
pair_0643_1:
    csrrw a1, mscratch, a0
pair_0643_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0644_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0644_0:
    fence.i
pair_0644_1:
    csrrw a0, mscratch, a2
pair_0644_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0645_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0645_0:
    fence.i
pair_0645_1:
    fence rw,rw
pair_0645_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0646_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0646_0:
    fence.i
pair_0646_1:
    fence rw,rw
pair_0646_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0647_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0647_0:
    fence.i
pair_0647_1:
    fence rw,rw
pair_0647_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0648_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0648_0:
    fence.i
pair_0648_1:
    fence.i
pair_0648_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0649_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0649_0:
    fence.i
pair_0649_1:
    fence.i
pair_0649_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0650_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0650_0:
    fence.i
pair_0650_1:
    fence.i
pair_0650_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0651_end
    li t2, 0
    EXPECT 11, t2, pair_0651_1, pair_0651_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0651_0:
    fence.i
pair_0651_1:
    ecall
pair_0651_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0652_end
    li t2, 0
    EXPECT 11, t2, pair_0652_1, pair_0652_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0652_0:
    fence.i
pair_0652_1:
    ecall
pair_0652_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0653_end
    li t2, 0
    EXPECT 11, t2, pair_0653_1, pair_0653_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0653_0:
    fence.i
pair_0653_1:
    ecall
pair_0653_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0654_end
    li t2, 0
    EXPECT 3, t2, pair_0654_1, pair_0654_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0654_0:
    fence.i
pair_0654_1:
    ebreak
pair_0654_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0655_end
    li t2, 0
    EXPECT 3, t2, pair_0655_1, pair_0655_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0655_0:
    fence.i
pair_0655_1:
    ebreak
pair_0655_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0656_end
    li t2, 0
    EXPECT 3, t2, pair_0656_1, pair_0656_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0656_0:
    fence.i
pair_0656_1:
    ebreak
pair_0656_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0657_end
    la t0, pair_0657_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0657_0:
    fence.i
pair_0657_1:
    mret
pair_0657_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0658_end
    la t0, pair_0658_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0658_0:
    fence.i
pair_0658_1:
    mret
pair_0658_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0659_end
    la t0, pair_0659_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0659_0:
    fence.i
pair_0659_1:
    mret
pair_0659_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0660_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0660_0:
    fence.i
pair_0660_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0660_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0661_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0661_0:
    fence.i
pair_0661_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0661_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0662_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0662_0:
    fence.i
pair_0662_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0662_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0663_end
    li t2, 0
    EXPECT 11, t2, pair_0663_0, pair_0663_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0663_0:
    ecall
pair_0663_1:
    add a1, a2, a3
pair_0663_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0664_end
    li t2, 0
    EXPECT 11, t2, pair_0664_0, pair_0664_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0664_0:
    ecall
pair_0664_1:
    add a1, a0, a3
pair_0664_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0665_end
    li t2, 0
    EXPECT 11, t2, pair_0665_0, pair_0665_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0665_0:
    ecall
pair_0665_1:
    add a0, a2, a3
pair_0665_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0666_end
    li t2, 0
    EXPECT 11, t2, pair_0666_0, pair_0666_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0666_0:
    ecall
pair_0666_1:
    lui a1, 1
pair_0666_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0667_end
    li t2, 0
    EXPECT 11, t2, pair_0667_0, pair_0667_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0667_0:
    ecall
pair_0667_1:
    lui a1, 1
pair_0667_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0668_end
    li t2, 0
    EXPECT 11, t2, pair_0668_0, pair_0668_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0668_0:
    ecall
pair_0668_1:
    lui a0, 1
pair_0668_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0669_end
    li t2, 0
    EXPECT 11, t2, pair_0669_0, pair_0669_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0669_0:
    ecall
pair_0669_1:
    auipc a1, 0
pair_0669_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0670_end
    li t2, 0
    EXPECT 11, t2, pair_0670_0, pair_0670_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0670_0:
    ecall
pair_0670_1:
    auipc a1, 0
pair_0670_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0671_end
    li t2, 0
    EXPECT 11, t2, pair_0671_0, pair_0671_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0671_0:
    ecall
pair_0671_1:
    auipc a0, 0
pair_0671_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0672_end
    li t2, 0
    EXPECT 11, t2, pair_0672_0, pair_0672_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0672_0:
    ecall
pair_0672_1:
    lw a1, 0(a4)
pair_0672_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0673_end
    li t2, 0
    EXPECT 11, t2, pair_0673_0, pair_0673_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0673_0:
    ecall
pair_0673_1:
    lw a1, 0(a4)
pair_0673_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0674_end
    li t2, 0
    EXPECT 11, t2, pair_0674_0, pair_0674_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0674_0:
    ecall
pair_0674_1:
    lw a0, 0(a4)
pair_0674_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0675_end
    li t2, 0
    EXPECT 11, t2, pair_0675_0, pair_0675_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0675_0:
    ecall
pair_0675_1:
    sw a2, 0(a4)
pair_0675_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0676_end
    li t2, 0
    EXPECT 11, t2, pair_0676_0, pair_0676_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0676_0:
    ecall
pair_0676_1:
    sw a0, 0(a4)
pair_0676_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0677_end
    li t2, 0
    EXPECT 11, t2, pair_0677_0, pair_0677_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0677_0:
    ecall
pair_0677_1:
    sw a2, 0(a4)
pair_0677_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0678_end
    li t2, 0
    EXPECT 11, t2, pair_0678_0, pair_0678_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0678_0:
    ecall
pair_0678_1:
    mul a1, a2, a3
pair_0678_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0679_end
    li t2, 0
    EXPECT 11, t2, pair_0679_0, pair_0679_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0679_0:
    ecall
pair_0679_1:
    mul a1, a0, a3
pair_0679_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0680_end
    li t2, 0
    EXPECT 11, t2, pair_0680_0, pair_0680_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0680_0:
    ecall
pair_0680_1:
    mul a0, a2, a3
pair_0680_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0681_end
    li t2, 0
    EXPECT 11, t2, pair_0681_0, pair_0681_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0681_0:
    ecall
pair_0681_1:
    div a1, a2, a3
pair_0681_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0682_end
    li t2, 0
    EXPECT 11, t2, pair_0682_0, pair_0682_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0682_0:
    ecall
pair_0682_1:
    div a1, a0, a3
pair_0682_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0683_end
    li t2, 0
    EXPECT 11, t2, pair_0683_0, pair_0683_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0683_0:
    ecall
pair_0683_1:
    div a0, a2, a3
pair_0683_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0684_end
    li t2, 0
    EXPECT 11, t2, pair_0684_0, pair_0684_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0684_0:
    ecall
pair_0684_1:
    beq a2, a3, pair_0684_end
pair_0684_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0685_end
    li t2, 0
    EXPECT 11, t2, pair_0685_0, pair_0685_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0685_0:
    ecall
pair_0685_1:
    beq a0, a3, pair_0685_end
pair_0685_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0686_end
    li t2, 0
    EXPECT 11, t2, pair_0686_0, pair_0686_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0686_0:
    ecall
pair_0686_1:
    beq a2, a3, pair_0686_end
pair_0686_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0687_end
    li t2, 0
    EXPECT 11, t2, pair_0687_0, pair_0687_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0687_0:
    ecall
pair_0687_1:
    jal a1, pair_0687_end
pair_0687_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0688_end
    li t2, 0
    EXPECT 11, t2, pair_0688_0, pair_0688_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0688_0:
    ecall
pair_0688_1:
    jal a1, pair_0688_end
pair_0688_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0689_end
    li t2, 0
    EXPECT 11, t2, pair_0689_0, pair_0689_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0689_0:
    ecall
pair_0689_1:
    jal a0, pair_0689_end
pair_0689_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0690_end
    li t2, 0
    EXPECT 11, t2, pair_0690_0, pair_0690_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0690_0:
    ecall
pair_0690_1:
    jalr a1, 0(a5)
pair_0690_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0691_end
    li t2, 0
    EXPECT 11, t2, pair_0691_0, pair_0691_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0691_0:
    ecall
pair_0691_1:
    jalr a1, 0(a5)
pair_0691_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0692_end
    li t2, 0
    EXPECT 11, t2, pair_0692_0, pair_0692_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0692_0:
    ecall
pair_0692_1:
    jalr a0, 0(a5)
pair_0692_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0693_end
    li t2, 0
    EXPECT 11, t2, pair_0693_0, pair_0693_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0693_0:
    ecall
pair_0693_1:
    csrrw a1, mscratch, a2
pair_0693_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0694_end
    li t2, 0
    EXPECT 11, t2, pair_0694_0, pair_0694_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0694_0:
    ecall
pair_0694_1:
    csrrw a1, mscratch, a0
pair_0694_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0695_end
    li t2, 0
    EXPECT 11, t2, pair_0695_0, pair_0695_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0695_0:
    ecall
pair_0695_1:
    csrrw a0, mscratch, a2
pair_0695_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0696_end
    li t2, 0
    EXPECT 11, t2, pair_0696_0, pair_0696_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0696_0:
    ecall
pair_0696_1:
    fence rw,rw
pair_0696_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0697_end
    li t2, 0
    EXPECT 11, t2, pair_0697_0, pair_0697_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0697_0:
    ecall
pair_0697_1:
    fence rw,rw
pair_0697_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0698_end
    li t2, 0
    EXPECT 11, t2, pair_0698_0, pair_0698_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0698_0:
    ecall
pair_0698_1:
    fence rw,rw
pair_0698_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0699_end
    li t2, 0
    EXPECT 11, t2, pair_0699_0, pair_0699_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0699_0:
    ecall
pair_0699_1:
    fence.i
pair_0699_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0700_end
    li t2, 0
    EXPECT 11, t2, pair_0700_0, pair_0700_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0700_0:
    ecall
pair_0700_1:
    fence.i
pair_0700_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0701_end
    li t2, 0
    EXPECT 11, t2, pair_0701_0, pair_0701_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0701_0:
    ecall
pair_0701_1:
    fence.i
pair_0701_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0702_end
    li t2, 0
    EXPECT 11, t2, pair_0702_0, pair_0702_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0702_0:
    ecall
pair_0702_1:
    ecall
pair_0702_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0703_end
    li t2, 0
    EXPECT 11, t2, pair_0703_0, pair_0703_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0703_0:
    ecall
pair_0703_1:
    ecall
pair_0703_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0704_end
    li t2, 0
    EXPECT 11, t2, pair_0704_0, pair_0704_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0704_0:
    ecall
pair_0704_1:
    ecall
pair_0704_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0705_end
    li t2, 0
    EXPECT 11, t2, pair_0705_0, pair_0705_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0705_0:
    ecall
pair_0705_1:
    ebreak
pair_0705_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0706_end
    li t2, 0
    EXPECT 11, t2, pair_0706_0, pair_0706_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0706_0:
    ecall
pair_0706_1:
    ebreak
pair_0706_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0707_end
    li t2, 0
    EXPECT 11, t2, pair_0707_0, pair_0707_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0707_0:
    ecall
pair_0707_1:
    ebreak
pair_0707_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0708_end
    li t2, 0
    EXPECT 11, t2, pair_0708_0, pair_0708_end
    la t0, pair_0708_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0708_0:
    ecall
pair_0708_1:
    mret
pair_0708_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0709_end
    li t2, 0
    EXPECT 11, t2, pair_0709_0, pair_0709_end
    la t0, pair_0709_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0709_0:
    ecall
pair_0709_1:
    mret
pair_0709_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0710_end
    li t2, 0
    EXPECT 11, t2, pair_0710_0, pair_0710_end
    la t0, pair_0710_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0710_0:
    ecall
pair_0710_1:
    mret
pair_0710_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0711_end
    li t2, 0
    EXPECT 11, t2, pair_0711_0, pair_0711_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0711_0:
    ecall
pair_0711_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0711_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0712_end
    li t2, 0
    EXPECT 11, t2, pair_0712_0, pair_0712_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0712_0:
    ecall
pair_0712_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0712_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0713_end
    li t2, 0
    EXPECT 11, t2, pair_0713_0, pair_0713_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0713_0:
    ecall
pair_0713_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0713_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0714_end
    li t2, 0
    EXPECT 3, t2, pair_0714_0, pair_0714_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0714_0:
    ebreak
pair_0714_1:
    add a1, a2, a3
pair_0714_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0715_end
    li t2, 0
    EXPECT 3, t2, pair_0715_0, pair_0715_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0715_0:
    ebreak
pair_0715_1:
    add a1, a0, a3
pair_0715_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0716_end
    li t2, 0
    EXPECT 3, t2, pair_0716_0, pair_0716_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0716_0:
    ebreak
pair_0716_1:
    add a0, a2, a3
pair_0716_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0717_end
    li t2, 0
    EXPECT 3, t2, pair_0717_0, pair_0717_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0717_0:
    ebreak
pair_0717_1:
    lui a1, 1
pair_0717_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0718_end
    li t2, 0
    EXPECT 3, t2, pair_0718_0, pair_0718_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0718_0:
    ebreak
pair_0718_1:
    lui a1, 1
pair_0718_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0719_end
    li t2, 0
    EXPECT 3, t2, pair_0719_0, pair_0719_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0719_0:
    ebreak
pair_0719_1:
    lui a0, 1
pair_0719_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0720_end
    li t2, 0
    EXPECT 3, t2, pair_0720_0, pair_0720_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0720_0:
    ebreak
pair_0720_1:
    auipc a1, 0
pair_0720_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0721_end
    li t2, 0
    EXPECT 3, t2, pair_0721_0, pair_0721_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0721_0:
    ebreak
pair_0721_1:
    auipc a1, 0
pair_0721_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0722_end
    li t2, 0
    EXPECT 3, t2, pair_0722_0, pair_0722_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0722_0:
    ebreak
pair_0722_1:
    auipc a0, 0
pair_0722_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0723_end
    li t2, 0
    EXPECT 3, t2, pair_0723_0, pair_0723_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0723_0:
    ebreak
pair_0723_1:
    lw a1, 0(a4)
pair_0723_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0724_end
    li t2, 0
    EXPECT 3, t2, pair_0724_0, pair_0724_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0724_0:
    ebreak
pair_0724_1:
    lw a1, 0(a4)
pair_0724_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0725_end
    li t2, 0
    EXPECT 3, t2, pair_0725_0, pair_0725_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0725_0:
    ebreak
pair_0725_1:
    lw a0, 0(a4)
pair_0725_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0726_end
    li t2, 0
    EXPECT 3, t2, pair_0726_0, pair_0726_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0726_0:
    ebreak
pair_0726_1:
    sw a2, 0(a4)
pair_0726_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0727_end
    li t2, 0
    EXPECT 3, t2, pair_0727_0, pair_0727_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0727_0:
    ebreak
pair_0727_1:
    sw a0, 0(a4)
pair_0727_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0728_end
    li t2, 0
    EXPECT 3, t2, pair_0728_0, pair_0728_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0728_0:
    ebreak
pair_0728_1:
    sw a2, 0(a4)
pair_0728_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0729_end
    li t2, 0
    EXPECT 3, t2, pair_0729_0, pair_0729_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0729_0:
    ebreak
pair_0729_1:
    mul a1, a2, a3
pair_0729_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0730_end
    li t2, 0
    EXPECT 3, t2, pair_0730_0, pair_0730_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0730_0:
    ebreak
pair_0730_1:
    mul a1, a0, a3
pair_0730_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0731_end
    li t2, 0
    EXPECT 3, t2, pair_0731_0, pair_0731_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0731_0:
    ebreak
pair_0731_1:
    mul a0, a2, a3
pair_0731_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0732_end
    li t2, 0
    EXPECT 3, t2, pair_0732_0, pair_0732_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0732_0:
    ebreak
pair_0732_1:
    div a1, a2, a3
pair_0732_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0733_end
    li t2, 0
    EXPECT 3, t2, pair_0733_0, pair_0733_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0733_0:
    ebreak
pair_0733_1:
    div a1, a0, a3
pair_0733_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0734_end
    li t2, 0
    EXPECT 3, t2, pair_0734_0, pair_0734_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0734_0:
    ebreak
pair_0734_1:
    div a0, a2, a3
pair_0734_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0735_end
    li t2, 0
    EXPECT 3, t2, pair_0735_0, pair_0735_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0735_0:
    ebreak
pair_0735_1:
    beq a2, a3, pair_0735_end
pair_0735_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0736_end
    li t2, 0
    EXPECT 3, t2, pair_0736_0, pair_0736_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0736_0:
    ebreak
pair_0736_1:
    beq a0, a3, pair_0736_end
pair_0736_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0737_end
    li t2, 0
    EXPECT 3, t2, pair_0737_0, pair_0737_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0737_0:
    ebreak
pair_0737_1:
    beq a2, a3, pair_0737_end
pair_0737_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0738_end
    li t2, 0
    EXPECT 3, t2, pair_0738_0, pair_0738_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0738_0:
    ebreak
pair_0738_1:
    jal a1, pair_0738_end
pair_0738_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0739_end
    li t2, 0
    EXPECT 3, t2, pair_0739_0, pair_0739_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0739_0:
    ebreak
pair_0739_1:
    jal a1, pair_0739_end
pair_0739_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0740_end
    li t2, 0
    EXPECT 3, t2, pair_0740_0, pair_0740_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0740_0:
    ebreak
pair_0740_1:
    jal a0, pair_0740_end
pair_0740_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0741_end
    li t2, 0
    EXPECT 3, t2, pair_0741_0, pair_0741_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0741_0:
    ebreak
pair_0741_1:
    jalr a1, 0(a5)
pair_0741_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0742_end
    li t2, 0
    EXPECT 3, t2, pair_0742_0, pair_0742_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0742_0:
    ebreak
pair_0742_1:
    jalr a1, 0(a5)
pair_0742_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0743_end
    li t2, 0
    EXPECT 3, t2, pair_0743_0, pair_0743_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0743_0:
    ebreak
pair_0743_1:
    jalr a0, 0(a5)
pair_0743_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0744_end
    li t2, 0
    EXPECT 3, t2, pair_0744_0, pair_0744_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0744_0:
    ebreak
pair_0744_1:
    csrrw a1, mscratch, a2
pair_0744_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0745_end
    li t2, 0
    EXPECT 3, t2, pair_0745_0, pair_0745_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0745_0:
    ebreak
pair_0745_1:
    csrrw a1, mscratch, a0
pair_0745_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0746_end
    li t2, 0
    EXPECT 3, t2, pair_0746_0, pair_0746_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0746_0:
    ebreak
pair_0746_1:
    csrrw a0, mscratch, a2
pair_0746_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0747_end
    li t2, 0
    EXPECT 3, t2, pair_0747_0, pair_0747_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0747_0:
    ebreak
pair_0747_1:
    fence rw,rw
pair_0747_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0748_end
    li t2, 0
    EXPECT 3, t2, pair_0748_0, pair_0748_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0748_0:
    ebreak
pair_0748_1:
    fence rw,rw
pair_0748_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0749_end
    li t2, 0
    EXPECT 3, t2, pair_0749_0, pair_0749_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0749_0:
    ebreak
pair_0749_1:
    fence rw,rw
pair_0749_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0750_end
    li t2, 0
    EXPECT 3, t2, pair_0750_0, pair_0750_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0750_0:
    ebreak
pair_0750_1:
    fence.i
pair_0750_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0751_end
    li t2, 0
    EXPECT 3, t2, pair_0751_0, pair_0751_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0751_0:
    ebreak
pair_0751_1:
    fence.i
pair_0751_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0752_end
    li t2, 0
    EXPECT 3, t2, pair_0752_0, pair_0752_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0752_0:
    ebreak
pair_0752_1:
    fence.i
pair_0752_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0753_end
    li t2, 0
    EXPECT 3, t2, pair_0753_0, pair_0753_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0753_0:
    ebreak
pair_0753_1:
    ecall
pair_0753_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0754_end
    li t2, 0
    EXPECT 3, t2, pair_0754_0, pair_0754_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0754_0:
    ebreak
pair_0754_1:
    ecall
pair_0754_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0755_end
    li t2, 0
    EXPECT 3, t2, pair_0755_0, pair_0755_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0755_0:
    ebreak
pair_0755_1:
    ecall
pair_0755_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0756_end
    li t2, 0
    EXPECT 3, t2, pair_0756_0, pair_0756_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0756_0:
    ebreak
pair_0756_1:
    ebreak
pair_0756_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0757_end
    li t2, 0
    EXPECT 3, t2, pair_0757_0, pair_0757_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0757_0:
    ebreak
pair_0757_1:
    ebreak
pair_0757_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0758_end
    li t2, 0
    EXPECT 3, t2, pair_0758_0, pair_0758_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0758_0:
    ebreak
pair_0758_1:
    ebreak
pair_0758_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0759_end
    li t2, 0
    EXPECT 3, t2, pair_0759_0, pair_0759_end
    la t0, pair_0759_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0759_0:
    ebreak
pair_0759_1:
    mret
pair_0759_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0760_end
    li t2, 0
    EXPECT 3, t2, pair_0760_0, pair_0760_end
    la t0, pair_0760_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0760_0:
    ebreak
pair_0760_1:
    mret
pair_0760_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0761_end
    li t2, 0
    EXPECT 3, t2, pair_0761_0, pair_0761_end
    la t0, pair_0761_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0761_0:
    ebreak
pair_0761_1:
    mret
pair_0761_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0762_end
    li t2, 0
    EXPECT 3, t2, pair_0762_0, pair_0762_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0762_0:
    ebreak
pair_0762_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0762_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0763_end
    li t2, 0
    EXPECT 3, t2, pair_0763_0, pair_0763_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0763_0:
    ebreak
pair_0763_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0763_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0764_end
    li t2, 0
    EXPECT 3, t2, pair_0764_0, pair_0764_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0764_0:
    ebreak
pair_0764_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0764_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0765_end
    la t0, pair_0765_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0765_0:
    mret
pair_0765_1:
    add a1, a2, a3
pair_0765_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0766_end
    la t0, pair_0766_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0766_0:
    mret
pair_0766_1:
    add a1, a0, a3
pair_0766_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0767_end
    la t0, pair_0767_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0767_0:
    mret
pair_0767_1:
    add a0, a2, a3
pair_0767_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0768_end
    la t0, pair_0768_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0768_0:
    mret
pair_0768_1:
    lui a1, 1
pair_0768_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0769_end
    la t0, pair_0769_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0769_0:
    mret
pair_0769_1:
    lui a1, 1
pair_0769_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0770_end
    la t0, pair_0770_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0770_0:
    mret
pair_0770_1:
    lui a0, 1
pair_0770_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0771_end
    la t0, pair_0771_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0771_0:
    mret
pair_0771_1:
    auipc a1, 0
pair_0771_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0772_end
    la t0, pair_0772_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0772_0:
    mret
pair_0772_1:
    auipc a1, 0
pair_0772_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0773_end
    la t0, pair_0773_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0773_0:
    mret
pair_0773_1:
    auipc a0, 0
pair_0773_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0774_end
    la t0, pair_0774_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0774_0:
    mret
pair_0774_1:
    lw a1, 0(a4)
pair_0774_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0775_end
    la t0, pair_0775_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0775_0:
    mret
pair_0775_1:
    lw a1, 0(a4)
pair_0775_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0776_end
    la t0, pair_0776_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0776_0:
    mret
pair_0776_1:
    lw a0, 0(a4)
pair_0776_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0777_end
    la t0, pair_0777_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0777_0:
    mret
pair_0777_1:
    sw a2, 0(a4)
pair_0777_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0778_end
    la t0, pair_0778_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0778_0:
    mret
pair_0778_1:
    sw a0, 0(a4)
pair_0778_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0779_end
    la t0, pair_0779_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0779_0:
    mret
pair_0779_1:
    sw a2, 0(a4)
pair_0779_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0780_end
    la t0, pair_0780_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0780_0:
    mret
pair_0780_1:
    mul a1, a2, a3
pair_0780_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0781_end
    la t0, pair_0781_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0781_0:
    mret
pair_0781_1:
    mul a1, a0, a3
pair_0781_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0782_end
    la t0, pair_0782_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0782_0:
    mret
pair_0782_1:
    mul a0, a2, a3
pair_0782_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0783_end
    la t0, pair_0783_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0783_0:
    mret
pair_0783_1:
    div a1, a2, a3
pair_0783_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0784_end
    la t0, pair_0784_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0784_0:
    mret
pair_0784_1:
    div a1, a0, a3
pair_0784_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0785_end
    la t0, pair_0785_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0785_0:
    mret
pair_0785_1:
    div a0, a2, a3
pair_0785_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0786_end
    la t0, pair_0786_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0786_0:
    mret
pair_0786_1:
    beq a2, a3, pair_0786_end
pair_0786_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0787_end
    la t0, pair_0787_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0787_0:
    mret
pair_0787_1:
    beq a0, a3, pair_0787_end
pair_0787_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0788_end
    la t0, pair_0788_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0788_0:
    mret
pair_0788_1:
    beq a2, a3, pair_0788_end
pair_0788_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0789_end
    la t0, pair_0789_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0789_0:
    mret
pair_0789_1:
    jal a1, pair_0789_end
pair_0789_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0790_end
    la t0, pair_0790_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0790_0:
    mret
pair_0790_1:
    jal a1, pair_0790_end
pair_0790_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0791_end
    la t0, pair_0791_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0791_0:
    mret
pair_0791_1:
    jal a0, pair_0791_end
pair_0791_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0792_end
    la t0, pair_0792_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0792_0:
    mret
pair_0792_1:
    jalr a1, 0(a5)
pair_0792_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0793_end
    la t0, pair_0793_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0793_0:
    mret
pair_0793_1:
    jalr a1, 0(a5)
pair_0793_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0794_end
    la t0, pair_0794_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0794_0:
    mret
pair_0794_1:
    jalr a0, 0(a5)
pair_0794_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0795_end
    la t0, pair_0795_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0795_0:
    mret
pair_0795_1:
    csrrw a1, mscratch, a2
pair_0795_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0796_end
    la t0, pair_0796_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0796_0:
    mret
pair_0796_1:
    csrrw a1, mscratch, a0
pair_0796_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0797_end
    la t0, pair_0797_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0797_0:
    mret
pair_0797_1:
    csrrw a0, mscratch, a2
pair_0797_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0798_end
    la t0, pair_0798_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0798_0:
    mret
pair_0798_1:
    fence rw,rw
pair_0798_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0799_end
    la t0, pair_0799_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0799_0:
    mret
pair_0799_1:
    fence rw,rw
pair_0799_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0800_end
    la t0, pair_0800_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0800_0:
    mret
pair_0800_1:
    fence rw,rw
pair_0800_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0801_end
    la t0, pair_0801_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0801_0:
    mret
pair_0801_1:
    fence.i
pair_0801_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0802_end
    la t0, pair_0802_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0802_0:
    mret
pair_0802_1:
    fence.i
pair_0802_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0803_end
    la t0, pair_0803_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0803_0:
    mret
pair_0803_1:
    fence.i
pair_0803_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0804_end
    li t2, 0
    EXPECT 11, t2, pair_0804_1, pair_0804_end
    la t0, pair_0804_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0804_0:
    mret
pair_0804_1:
    ecall
pair_0804_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0805_end
    li t2, 0
    EXPECT 11, t2, pair_0805_1, pair_0805_end
    la t0, pair_0805_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0805_0:
    mret
pair_0805_1:
    ecall
pair_0805_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0806_end
    li t2, 0
    EXPECT 11, t2, pair_0806_1, pair_0806_end
    la t0, pair_0806_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0806_0:
    mret
pair_0806_1:
    ecall
pair_0806_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0807_end
    li t2, 0
    EXPECT 3, t2, pair_0807_1, pair_0807_end
    la t0, pair_0807_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0807_0:
    mret
pair_0807_1:
    ebreak
pair_0807_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0808_end
    li t2, 0
    EXPECT 3, t2, pair_0808_1, pair_0808_end
    la t0, pair_0808_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0808_0:
    mret
pair_0808_1:
    ebreak
pair_0808_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0809_end
    li t2, 0
    EXPECT 3, t2, pair_0809_1, pair_0809_end
    la t0, pair_0809_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0809_0:
    mret
pair_0809_1:
    ebreak
pair_0809_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0810_end
    la t0, pair_0810_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0810_0:
    mret
pair_0810_1:
    mret
pair_0810_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0811_end
    la t0, pair_0811_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0811_0:
    mret
pair_0811_1:
    mret
pair_0811_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0812_end
    la t0, pair_0812_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0812_0:
    mret
pair_0812_1:
    mret
pair_0812_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0813_end
    la t0, pair_0813_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0813_0:
    mret
pair_0813_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0813_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0814_end
    la t0, pair_0814_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0814_0:
    mret
pair_0814_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0814_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0815_end
    la t0, pair_0815_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0815_0:
    mret
pair_0815_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0815_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0816_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0816_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0816_1:
    add a1, a2, a3
pair_0816_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0817_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0817_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0817_1:
    add a1, a0, a3
pair_0817_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0818_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0818_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0818_1:
    add a0, a2, a3
pair_0818_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0819_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0819_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0819_1:
    lui a1, 1
pair_0819_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0820_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0820_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0820_1:
    lui a1, 1
pair_0820_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0821_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0821_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0821_1:
    lui a0, 1
pair_0821_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0822_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0822_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0822_1:
    auipc a1, 0
pair_0822_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0823_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0823_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0823_1:
    auipc a1, 0
pair_0823_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0824_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0824_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0824_1:
    auipc a0, 0
pair_0824_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0825_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0825_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0825_1:
    lw a1, 0(a4)
pair_0825_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0826_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0826_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0826_1:
    lw a1, 0(a4)
pair_0826_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0827_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0827_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0827_1:
    lw a0, 0(a4)
pair_0827_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0828_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0828_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0828_1:
    sw a2, 0(a4)
pair_0828_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0829_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0829_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0829_1:
    sw a0, 0(a4)
pair_0829_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0830_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0830_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0830_1:
    sw a2, 0(a4)
pair_0830_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0831_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0831_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0831_1:
    mul a1, a2, a3
pair_0831_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0832_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0832_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0832_1:
    mul a1, a0, a3
pair_0832_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0833_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0833_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0833_1:
    mul a0, a2, a3
pair_0833_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0834_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0834_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0834_1:
    div a1, a2, a3
pair_0834_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0835_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0835_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0835_1:
    div a1, a0, a3
pair_0835_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0836_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0836_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0836_1:
    div a0, a2, a3
pair_0836_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0837_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0837_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0837_1:
    beq a2, a3, pair_0837_end
pair_0837_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0838_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0838_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0838_1:
    beq a0, a3, pair_0838_end
pair_0838_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0839_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0839_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0839_1:
    beq a2, a3, pair_0839_end
pair_0839_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0840_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0840_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0840_1:
    jal a1, pair_0840_end
pair_0840_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0841_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0841_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0841_1:
    jal a1, pair_0841_end
pair_0841_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0842_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0842_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0842_1:
    jal a0, pair_0842_end
pair_0842_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0843_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0843_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0843_1:
    jalr a1, 0(a5)
pair_0843_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0844_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0844_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0844_1:
    jalr a1, 0(a5)
pair_0844_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0845_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0845_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0845_1:
    jalr a0, 0(a5)
pair_0845_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0846_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0846_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0846_1:
    csrrw a1, mscratch, a2
pair_0846_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0847_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0847_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0847_1:
    csrrw a1, mscratch, a0
pair_0847_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0848_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0848_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0848_1:
    csrrw a0, mscratch, a2
pair_0848_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0849_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0849_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0849_1:
    fence rw,rw
pair_0849_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0850_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0850_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0850_1:
    fence rw,rw
pair_0850_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0851_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0851_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0851_1:
    fence rw,rw
pair_0851_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0852_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0852_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0852_1:
    fence.i
pair_0852_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0853_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0853_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0853_1:
    fence.i
pair_0853_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0854_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0854_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0854_1:
    fence.i
pair_0854_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0855_end
    li t2, 0
    EXPECT 11, t2, pair_0855_1, pair_0855_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0855_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0855_1:
    ecall
pair_0855_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0856_end
    li t2, 0
    EXPECT 11, t2, pair_0856_1, pair_0856_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0856_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0856_1:
    ecall
pair_0856_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0857_end
    li t2, 0
    EXPECT 11, t2, pair_0857_1, pair_0857_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0857_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0857_1:
    ecall
pair_0857_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0858_end
    li t2, 0
    EXPECT 3, t2, pair_0858_1, pair_0858_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0858_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0858_1:
    ebreak
pair_0858_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0859_end
    li t2, 0
    EXPECT 3, t2, pair_0859_1, pair_0859_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0859_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0859_1:
    ebreak
pair_0859_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0860_end
    li t2, 0
    EXPECT 3, t2, pair_0860_1, pair_0860_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0860_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0860_1:
    ebreak
pair_0860_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0861_end
    la t0, pair_0861_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0861_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0861_1:
    mret
pair_0861_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0862_end
    la t0, pair_0862_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0862_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0862_1:
    mret
pair_0862_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0863_end
    la t0, pair_0863_end
    csrw mepc, t0
    csrw mstatus, zero
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0863_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0863_1:
    mret
pair_0863_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0864_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0864_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0864_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0864_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0865_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0865_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0865_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0865_end:
    nop
    li a0, 7
    li a1, 9
    li a2, 3
    li a3, 2
    la a4, scratch
    la a5, pair_0866_end
.balign 8
    csrr zero, mscratch
    csrr zero, mscratch
pair_0866_0:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0866_1:
#ifdef SPIKE_SMOKE
    nop
#else
    wfi
#endif
pair_0866_end:
    nop
    j pair_single_entry
    .balign 8
    nop
pair_single_entry:
    addi a0, zero, 1
pair_single_next_block:
    addi a1, zero, 2
    CHECK a0, 1
    CHECK a1, 2
    FINISH
