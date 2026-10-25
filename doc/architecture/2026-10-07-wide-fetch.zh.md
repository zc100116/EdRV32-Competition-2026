# 宽取指与 resident B 旁路，2026-10-07

## 本批改造

前一检查点 `2e09af0` 已有双 ALU 与双退休，本批先扩展真正的取指供给，再补齐主消费者读取 resident B 的寄存旁路。参数 `FETCH_WIDE` 在 core/cached_core 中默认 0，SoC 对应 `CPU_FETCH_WIDE`。`FETCH_WIDE=1` 自动选择双窗口前端；目标性能配置同时启用 `DUAL_ISSUE=1`。

ICache 每路原本就从同步 RAM 读取 128 位 line。本批将命中和 refill 的结果按请求偏移选择为两个相邻 32 位 word；位于 line 最后一个 word 时只返回一条，下一请求从新 line 开始。ITCM、非缓存访问和不可执行区域继续使用一条 word。AXI 仍是 64 位，16 字节 line 的 refill 仍是两拍，未改变 DCache 或外部总线。

IF1 在请求接受时保存实际 word 数与四个半字位置的预测元数据，顺序 PC 按 4/8 字节推进。预测器的四个查询共享 BTB/BHT/loop/RAS 状态和同一训练口；IF1 preview 仍只用于已寄存的前两位置快速目标，其余位置通过原 PC 寄存边界启动预测目标请求。

IF2 宽模式具有 12 半字本地 FIFO，一次最多接收四个半字并直接形成两条完整指令。16+16、16+32、32+16、32+32，以及从高半字开始、跨返回块和跨 Cache line 的续接均按真实长度推进。按寄存占用决定接收容量，未组合回收下游当周期释放的空间。最早的完整预测跳转优先；末尾 32 位跳转必须等到续接半字到达后才早重定向。旧 epoch 返回被丢弃，错误不能被第二指令掩盖。

resident B 旁路用每个源独立的 A/B 选择位和共同的生产者包 PC。消费者读取 EX 输出 pipe 中已寄存的 B 结果；背压时捕获并持有，不串联两个组合 ALU。年轻 resident B 遮蔽旧 Load/MDU 时，清除对应旧依赖标记，避免误等旧生产者。B 槽自身对 resident 的依赖仍保守拆分，LSU/分支/MDU 仍单独发射。

## 可复现验收

```sh
python3 sim/script/run_dual_issue.py --suite all
python3 sim/script/run_dual_isa.py --mode all --memory both --jobs 8
python3 sim/script/run_dual_coremark.py --mode all --opt both
```

`wide-frontend` 三种固定种子覆盖长段两条 32 位指令/周期、混合长度、背压、单条消费、跨 line、redirect/epoch 回绕和旧返回；`wide-prediction` 覆盖位置 1/2/3 的预测及最后半字 32 位跳转续接；`wide-cache` 核对两条返回、line 末尾和非缓存单条返回及背压保持；`wide-predictor` 核对新增查询的 BTB/BHT/loop/RAS 一致性；`wide-mdu-irq` 覆盖更早成对 ALU 的精确中断和 MDU 取消/重放。逐条参考模型增加了两个固定 resident B 源选择场景，程序现在为 980 条。

架构入口的 all 表示 scalar32、dual32、dual64，分别运行 direct/cached 两种存储。direct 模型仍按单 word 供应，不伪造 64 位响应；cached 才验证真实双 word 返回。每种配置 riscv-tests 62 项和 ACT 82 项，共 864 次，沿用已公开的 Debug trigger/PMP 排除范围。CoreMark all 表示 scalar、paired、dual、wide 四种配置，共 24 轮；原软件镜像不重新编译。

每批从 Git 导出的独立源码快照运行，保存编译命令、工具版本、源/镜像 SHA256、日志和随机种子。新的性能结果使用软件 CSR 区间；SIM_PROFILE 观察窗含管理指令，不能混为同一窗口。

## 完整快照验收结果

源码快照 `baff831a35c1d5ef9f0b85d73ebaf299be80e46e`，从 Git 索引独立导出后运行。89/89 模块及定向运行、864/864 ISA/ACT、24/24 CoreMark 均通过；三轮 CRC 和退休数一致，单发射 O2/O3 热态周期仍精确匹配原基线。修改范围保留 17 个原有格式诊断，零新增诊断。

三种随机种子的 `wide-frontend` 首段均为 32 位指令，连续双输出最长为 56 至 57 周期；原双 ALU 128 条压缩指令 / 64 周期保持通过。固定 resident B 场景同时覆盖两种源选择，逐条参考模型和最终寄存器值一致。

热态第二轮软件 CSR 区间：

| 镜像 | 单发射周期 | 相同新后端、32 位取指 | 64 位取指加 resident B 旁路 | 相对单发射降低 | 宽取指相对同后端 32 位降低 | 新 CPI |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| O2 | 3,487,221 | 3,375,287 | 3,202,529 | 8.16% | 5.12% | 1.104683 |
| O3 | 3,523,737 | 3,349,950 | 3,191,155 | 9.44% | 4.74% | 1.083899 |

O2 缺 B 的 A 接收次数从前一检查点 488,986 降到 94,395；O3 从 414,207 降到 99,728。该计数含推测路径，是接收次数，不是可逐项相加的停顿周期。B 实际退休 O2=291,223、O3=301,375，O3 配对次数甚至少于前一版，但周期仍下降，说明有效供给和等待节拍比单看配对率更重要。

只打开宽取指、尚未加入 resident B 旁路的探索版本，O2/O3 热态周期为 3,279,572 / 3,258,451；最终组合版本为 3,202,529 / 3,191,155。变化有交互作用，不能把不同版本的节省周期独立相加。

完整输入哈希与结果见 [基线记录](../../sim/regressions/wide-fetch-baseline.json)；原始命令与日志归档在 `out/audit/2026-10-07-wide-fetch/verified-results.tar.gz`。SIM_PROFILE 多出管理指令，O2 最终观察周期比软件 CSR 区间多 26 周期，O3 多 24 周期，性能对照始终采用上表 CSR 数字。

以原板上 O2 2.805315668 CoreMark/MHz 和相同收益比例条件估计，新值约 3.055；固定 10 次迭代镜像与板上 4000 次迭代镜像不同，这只是条件估算，尚无新的板上评分或布线频率证据。

## 后续上板的参数与 IP

板顶层 `fpga/pango_200h/edrv32_soc_coremark/source/edrv32_pango_200h_coremark_top.v` 的两个参数现已默认设为 1，直接重新导入即可选择本批配置；如 PDS 设置过顶层参数覆盖，也应确认它们为：

```verilog
CPU_DUAL_ISSUE = 1
CPU_FETCH_WIDE = 1
```

重新导入 `import_sources.tcl` 后需重新综合、布局布线和生成 bitstream。复测单发射时在板顶层将两个参数同时设为 0。其余时钟、ROM/SRAM 镜像和板级宏保持原测试口径。此次没有新增 RTL 文件或新的 FPGA IP；已有 source import 列表仍包含全部改动模块。

| IP | 当前配置及本批要求 |
| --- | --- |
| cache_data | 读/写均为 128 bit，深度 128，地址 7 bit，16 个 8 bit byte-enable；同步读，OUTPUT_REG=0、FAB_REG=0。保持现有配置，不改成 64 bit |
| cache_tag | 读/写均为 21 bit，深度 128，地址 7 bit；保持原同步读配置 |
| mul、pll0、BootROM、SRAM | 本批不改变接口或配置 |

Cache line 宽度和 CPU 每次取指字节数是不同接口：128 位 RAM 读出后选相邻 64 位返回前端即可。无需增加 RAM 读端口或复制 ICache。四查询预测与更宽 FIFO 可能增加 LUT/FF；物理资源和 100 MHz 时序需下一次 PDS 综合布线确认。

本检查点最初没有板上分数；后续实测已补充在文末。用 10 次迭代仿真周期对比推算板上 4000 次迭代收益只是条件估计，不能当作新的 CoreMark/MHz 实测值。

### 12:18 上板结果的配置核查

2026-10-07 12:18 串口三轮周期为 1425864774 / 1425864492 / 1425864482，退休指令均为 1159743496，CoreMark/MHz x1000 均为 2805；与同日 10:05 的单发射结果逐轮完全一致。12:05 综合网表保留 `gen_scalar_frontend.u_align_stage`，证明这一轮仍选择单发射前端。

当时工作副本只把 `edrv32_cached_core` 的 `DUAL_ISSUE`、`FETCH_WIDE` 默认值改为 1，板顶层的 `CPU_DUAL_ISSUE`、`CPU_FETCH_WIDE` 却仍为 0。板顶层经过 `edrv32_soc_top` 显式传入 0，覆盖了底层默认值。本次修正板顶层默认值，不更改用户对 cached_core 的修改。现有布线报告的 100 MHz、WNS +0.050 ns、TNS 0 仅属于上述单发射配置；启用双发射和宽取指后需重新确认时序。

## 100 MHz 时序修复及复现

12:42 的真正双发射/宽取指版本在 100 MHz 下 WNS -1.605 ns、TNS -151.600 ns、506 个 setup 违例端点，hold 检查通过；上板没有新的串口输出。实际板上 BootROM/SRAM 镜像在 RTL 仿真中可打印启动信息并进入 CoreMark 第一轮。时序违例是已经确认的硬件问题；启动仿真没有包含器件和布线延迟，不能代替板上复测。

本次修改如下，保持原来的流水边界和周期行为：

1. ALU 和重定向目标采用独立的操作选择与数据合并，消除综合网表中比较/移位结果进入加法进位链的串联。
2. 宽取指 IF2 采用固定位置写入，直接消费的指令通过 head 指针前移处理；自由槽位的写入不依赖同拍预测截断与双指令消费数量。只允许写入注册空闲槽，实际接受的前缀才更新 count/tail，不能覆盖旧有效指令。非宽取指配置保持原有行为。
3. ALIGN 四项队列改为固定槽位循环队列，出队只更新 head/count/有效位，消除 DCache 完成→Decode 依赖判断→整组 ALIGN payload 搬移的路径。pipe 仍只保存 valid/payload，四路 payload 写使能由 stage 产生。
4. 单周期 MUL 的晚到 MDU 源直接接已有捕获寄存器 `late_mdu_value_r`。MDU 消费者原本就等待捕获完成；修改只去掉未发射时 DIV 实时结果到 MUL 数据引脚的连接，不增加请求等待或乘法流水级。

各轮独立 PDS 工程保存在 `out/audit/2026-10-07-dual-timing/`，没有覆盖用户的板级工程：

| 配置/目录 | 100 MHz setup WNS/ns | TNS/ns | 违例端点 |
| --- | ---: | ---: | ---: |
| 原上板报告 `before.rtr` | -1.605 | -151.600 | 506 |
| ALU/重定向选择 `pds` | -1.176 | -1212.482 | 2730 |
| 加入 IF2 固定入队 `pds-v2` | -0.161 | -0.233 | 2 |
| 加入 ALIGN 循环队列 `pds-v3` | +0.203 | 0 | 0 |
| 最终 MUL 输入连接修正 `pds-v4` | **+0.152** | **0** | **0** |

最终报告为 `pds-v4/report_timing/edrv32_pango_200h_coremark_top.rtr`，生成时间 2026-10-07 14:03:58。slow hold +0.150 ns、fast hold +0.101 ns，全部时序约束满足；估计频率 101.5437 MHz，仅作为 STA 结果。最终综合资源为 LUT 29193、FF 15685、APM 7、DRM 22。最后两行输入连接修改会改变映射/布局，不能拿上一轮 +0.203 ns 当作最终版本的裕量。

最终源码已通过 89 项模块/定向运行、864 项冻结 ISA/ACT 运行和 24 轮 CoreMark；四种配置 O2/O3 的所有周期数、退休数和 CRC 与修复前一致。宽取指 O2 热态仍为 3202529，O3 为 3191155。实际板上镜像的最终版本启动仿真运行到 200 万周期并正常进入第一轮；没有完成 4000 次迭代的完整 RTL 板镜像跑分。

新增维护的边界覆盖位于：

- `sim/cases/cpu/wide-prediction/tb_wide_prediction.sv`：FIFO 只有一个空位时接受一个半字的预测前缀，检查被截断的其余数据不覆盖旧指令。
- `sim/cases/cpu/ex-mul-stable/tb_ex_mul_stable.sv`：MDU 完成先经寄存器再进入 MUL 引脚，捕获后的两操作数在背压/实时结果总线改变时保持。新版 31 项检查通过；回放旧 EX 连接时，在捕获前输入引脚检查明确失败，日志保存在 VM 的 `negative-mdu/results`。

完整复现命令仍为：

```sh
python3 sim/script/run_dual_issue.py --suite all
python3 sim/script/run_dual_isa.py --mode all --memory both --jobs 8
python3 sim/script/run_dual_coremark.py --mode all --opt both --jobs 8
```

最终 VM 源码/结果目录为 `/home/edward/File/edrv32-dual-timing-20261007/v4`。结构化记录 `sim/regressions/dual-timing-baseline.json` 包含工具版本、命令、源码/输入/日志哈希和 STA 报告哈希，已逐项对照当前工作副本；继承的 CRLF 差异经规范化内容对比确认。上板使用两个顶层参数 1、原 100 MHz、原固件和原 IP；板上复测结果见下一节。

同一冻结源码另在 `out/audit/2026-10-07-dual-timing/pds-ready` 完整重建，并在同一次 PDS 进程中完成时序检查与 bitstream 生成，2026-10-07 14:37:39 成功结束。该下载工程同样 WNS +0.152 ns、TNS 0；下载文件为 `generate_bitstream/edrv32_pango_200h_coremark_top.sbit`（9188552 bytes）。结构化记录引用这次下载工程的报告和 bitstream 哈希。原 `pds-v4` 的报告仍保留作对照，后续仅使用 `pds-ready` 的完整工程与下载文件。

归档 `out/audit/2026-10-07-dual-timing/board-ready-checkpoint.zip` 保存 Git 基础 bundle、当前工作补丁、修改的源码与测试、结构化结果、完整仿真源码/日志包、时序/综合报告和下载文件；无需依赖后来覆盖的临时仿真构建目录来复盘。

## 14:56 上板复测结果

2026-10-07 14:56:17 启动，14:56:56 输出 `ALL_ROUNDS_COMPLETE`。串口工具 COM7/115200 的只读 API 记录确认：100 MHz、GCC 15.2.0、`-O2`、4000 次迭代，三轮均显示 CoreMark/MHz x1000 = 3115；seed/list/matrix/state/final CRC 为 18f2/e3c1/0747/8d84/5249，均通过软件自检。

| 轮次 | cycles | instret |
| --- | ---: | ---: |
| 1 | 1284001106 | 1159743496 |
| 2 | 1284000785 | 1159743496 |
| 3 | 1284000781 | 1159743496 |

采用第二轮热态对照：单发射 1425864492 → 本版 1284000785，节省 141863707 周期，周期下降 9.9493%；退休指令数相同。CPI 1.229465392 → 1.107142044，CoreMark/MHz 2.805315668 → 3.115262893，成绩提升 11.0486%。第三轮与第二轮仅相差 4 周期。

精确耗时为 12.84000785 秒，约 311.5263 iterations/sec。串口的 `Total time (secs): 12`、`Iterations/Sec: 333` 为整数计算显示，不能用 333/100 计算标准化成绩；应采用 cycles 或 `CoreMark/MHz x1000`。板上 4000 次迭代与固定 10 次迭代镜像不同，实测 9.95% 的周期收益比此前 8.16% 的仿真比例更高，原 3.055 条件估算不作为实测结果。

原始输出与时间戳保存在 `out/audit/2026-10-07-dual-timing/board-uart-20261007-1456.log` 和同名 JSON；结构化结果已更新 `board_validation`。当前仅确认 O2 上板成绩，尚未上板测 O3。
