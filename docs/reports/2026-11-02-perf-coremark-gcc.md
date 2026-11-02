# CoreMark 编译器与编译选项对比（卡 40）

| 项 | 内容 |
|---|---|
| 程序 | b3 `5aeb2c1a`（源码 `23cc1643`），`tasks/win/20261102-40-coremark-gcc/src/variants.md` |
| 硬件 | 卡 34 B1-ILA bitstream，PG2L200H-6 FBB676，CLK_SYS_HZ = 100000000 |
| 方法 | BIOS 串口下载 SRAM monitor，CoreMark 5000 次，两轮 HPM；8 组各一次 |
| 原始数据 | win `874bbf53`：`tasks/win/20261102-40-coremark-gcc/result.md`、`artifacts/uart/<变体>.log` |
| 编译器 | xPack GCC 15.2.0；GNU GCC 16.1.0 源码构建（binutils 2.45，`docs/guides/env-setup.md` 2.1） |

选项：o2 = `-O2`；tuned = `-O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4`；peer = `-O2 -funroll-all-loops -mtune=sifive-7-series -mstrict-align -mbranch-cost=3 -fno-if-conversion -fno-if-conversion2`；combo = tuned + peer 除 `-O2` 外的选项。ISA 均为 `rv32im_zicsr_zifencei/ilp32`。

| 变体 | Iterations/Sec | CoreMark/MHz | 相对同编译器 o2 | 第 1 轮 cycles | 第 1 轮 instructions | IPC |
|---|---:|---:|---:|---:|---:|---:|
| g15-o2 | 360.326 | 3.603 | — | 1387629662 | 1441025033 | 1.038 |
| g15-tuned | 435.438 | 4.354 | +20.8% | 1148269092 | 1239834691 | 1.080 |
| g15-peer | 390.162 | 3.901 | +8.3% | 1281515693 | 1367429982 | 1.067 |
| g15-combo | 424.627 | 4.246 | +17.8% | 1177502301 | 1237199692 | 1.051 |
| g16-o2 | 357.562 | 3.575 | — | 1398357428 | 1424251847 | 1.019 |
| g16-tuned | 422.505 | 4.225 | +18.2% | 1183415430 | 1244278640 | 1.051 |
| g16-peer | 388.339 | 3.883 | +8.6% | 1287533338 | 1351024982 | 1.049 |
| g16-combo | 427.193 | 4.271 | +19.5% | 1170429108 | 1238266827 | 1.058 |

- 16/16 轮 CRC PASS，8 组均 ≥ 10 s。同一程序两轮 cycles 相差 < 2400（< 0.0002%）。
- GCC 16.1 相对 15.2（同选项）：o2 −0.8%，tuned −3.0%，peer −0.5%，combo +0.6%。
- peer 条件（GCC 16.1）：3.883 CoreMark/MHz；最高为 g15-tuned 4.354，高 12.1%。
- IPC 由串口 HPM 计算（instructions / cycles）。分数直接取自串口；单次测量，无重复。
