# C2-F 可复现浮点负载

设计与模型边界见 [CPU v2 FPU 设计记录](../../../../../docs/design/2026-11-27-cpu-v2-fpu.md)。
本目录只放源代码；所有 ELF、日志和结果进入 `build/c2f/`。不需要 RTL 或板卡。

在仓库根目录串行运行：

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/cpu/eval/fpu_model.py
python3 tools/cpu/eval/fpu_resources.py
python3 tools/cpu/eval/fpu_eval.py run
```

复用已有 Spike 日志重跑模型：

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/cpu/eval/fpu_eval.py measure
```

依赖：xPack `riscv-none-elf-gcc` 15.2.0（含 newlib、libm、libgcc 及 RV32
ilp32/ilp32f/ilp32d multilib）、同前缀的 objdump/nm/size、Spike 1.1.1-dev、Python 3
标准库。本次输入基线为 `f63071ea077abec8eff013b194ec3d27dde2885d`，在包含本目录与
三个 `fpu_*.py` 的交付提交上执行上述命令；汇总会记录执行时的 git commit 和 GCC
版本。`commands.txt` 保存每个 ELF 的原始编译/Spike 命令，不依赖外部下载源码。

每个负载运行三版：`soft`（rv32im/ilp32）、`F`（rv32imf/ilp32f）、`FD`
（rv32imfd/ilp32d），均加 Zicsr/Zifencei。flags 固定为 `-O2 -ffp-contract=fast
-fno-math-errno -ffreestanding`，不开 fast-math。源代码遵从 C11，编译告警视为错误。
`real.h` 为 `_s` 选择 float，其余为 double；sqrt 显式用 GCC builtin，使硬浮点
版生成 FSQRT，soft 版调用 sqrtf/sqrt。其它数学函数照常链接对应 multilib 的 libm。

|程序|规模|计时内操作|
|---|---|---|
|matrix_s、matrix_d|16×16×16|传统三循环矩阵乘，4096 次乘加|
|whetstone_s、whetstone_d|LOOP=1、II=1|改编 Netlib Whetstone；原模块次数保留，移除时间校准与打印|
|vertex_s|64 顶点|4×4 变换、法线归一化、方向光点积；直接覆盖 FSQRT/FDIV|
|physics_s|64 粒子×3 轴×16 步|弹簧/阻尼力、速度及位置积分|

`whetstone.c` 保留原许可全文，来源为
[Rich Painter v1.2 / Netlib](https://www.netlib.org/benchmark/whetstone.c)，下载日期
2026-11-27。用 volatile sink 保存每个模块结果，数学公式和主要循环次数未改变；
模块 1/10 的次数在原程序就是 0。这里比较改编程序的模型周期，不报告标准 MWIPS。
`kernels.c` 的初始化在计时外；所有程序保留结果，禁止优化器删除整个核。

Spike 加载本目录 `start.S` 与上一级 `spike.ld`，在 M 模式 RAM 运行。
计时从 start_time 入口（包含 ret）到 stop_time 入口。无操作系统、缓存 miss 或
真实图形驱动开销，因此 vertex_s 不能代表 GLQuake 整体帧率。

输出目录中每个 `<workload>/<arch>/` 包含：

- `workload.elf`、`numeric.dis`、`size.txt`：软件及体积；size 的 text 含只读数据和库。
- `commands.txt`、`build.log`、`debug.cmd`、`console.log`、`spike.log`：复现和原始 trace。
- `results.json`：实际动态指令分类与各方案的**周期模型估算**。

`build/c2f/results.json` 为汇总，`table.md` 为默认方案的体积/加速比表。
模型比较统一 FMA、ADD 短路、独立 ADD、共享 FP64、Newton、D II=1，还给出
3R FRF 与 4 项提交窗口的敏感度。`fpu_model.py` 自检覆盖相关性、双发射、FMA
读相位、长操作并行、LSU 双 beat、写回/尾端竞争；`fpu_resources.py` 验证 APM
分块完整积并打印资源公式的结果。它们都不替代 SoftFloat/TestFloat 的 RTL 验证。
