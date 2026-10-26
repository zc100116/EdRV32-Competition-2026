# 旧 CoreMark 工程与当前 CPU＋系统子系统对照

## 数据来源与可比范围

- 旧工程：`G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc_coremark`，主报告日期 2026-10-07。
- 当前工程：`G:/codex_project/EdRV32-FPGA/EdRV32`，主报告日期 2026-10-26；本轮设计输入 commit 为 `157afa245359199cfa6bf7c18e2e21d165ae8203`。
- 两者报告中的工具均为 PDS 2022.2-SP6.1 build 138931，器件 PG2L200H-6 FBB676。
- 旧测量报告未记录 Git commit，不能把当前旧仓库 HEAD `6028c445090f3bdb75ae753b0ca7fa0994304156` 认定为当次测量版本。
- 旧工程与当前工程不是相同架构、相同存储配置或相同时钟条件。以下是实测记录对照，不把差异单独归因于某一种 RTL 写法或 IP 参数。
- 主表只使用各阶段根目录的当前报告；原有 logbackup/bak 下的历史日志和报告作为原始资料保留，不混入主表统计。

## 一、Compile 总体数据

| 项 | 旧 CoreMark | 当前工程 |
|---|---:|---:|
| Real time | 1 分 42 秒 | 11 分 0 秒 |
| CPU time | 26 秒 | 1 分 44 秒 |
| Process CPU time | 26 秒 | 1 分 44 秒 |
| 峰值内存 | 657 MB | 2,394 MB |
| 编译数据库大小（本地文件实测，未上传 .adf） | 6,210,072 字节 | 147,420,498 字节 |
| 当前 compile/run.log 的 E: 行 | 0 | 0 |
| 当前 compile/run.log 的 W: 行 | 1411 | 1149 |
| constant probe loop 警告 | 243 | 110 |

按上述数字计算，当前 wall time 约为旧工程的 6.47 倍，CPU time 为 4 倍，数据库大小约为 23.74 倍。
旧工程 loop 警告更多，但编译更快；因此不能仅凭 loop 警告数量解释耗时或数据库膨胀。

最终原始 `.cmr`、完整 `compile/run.log` 均在各自目录中，未删减 warning。

## 二、Compile 分阶段耗时

单位均为秒，wall 和 CPU 均直接取自各自日志的 `Time elapsed` 行。

| 阶段 | 旧 wall | 当前 wall | 旧 CPU | 当前 CPU |
|---|---:|---:|---:|---:|
| rtl-analyze | 1.467 | 1.394 | 0.062 | 0.016 |
| rtl-elaborate | 0.443 | 0.291 | 0.094 | 0.016 |
| rtl-prep | 0.495 | 0.344 | 0.031 | 0.031 |
| rtl-infer | 74.694 | 37.660 | 21.594 | 10.438 |
| rtl-control-opt | 0.569 | 15.984 | 0.094 | 4.156 |
| rtl-data-opt | 1.778 | 74.895 | 0.547 | 19.969 |
| FSM inference | 0.402 | 7.213 | 0.188 | 2.141 |
| sdm2adm | 1.476 | 37.693 | 0.984 | 11.359 |

当前 rtl-infer 反而短于旧工程；显著增加的是 rtl-data-opt 和 sdm2adm。
两者日志都在 sdm2adm 后进入 `Saving design to DB`，保存阶段未给独立耗时统计。
当前保存期间观察到数据库持续增长，不将具体偏慢原因认定为磁盘、杀毒软件或某个 RTL 模块。

## 三、完整流程耗时

以下每格为各阶段日志原文：Real / CPU / Process CPU / Peak memory。

| 阶段 | 旧工程 | 当前工程 |
|---|---|---|
| compile | 0h:1m:42s / 0h:0m:26s / 0h:0m:26s / 657 MB | 0h:11m:0s / 0h:1m:44s / 0h:1m:44s / 2,394 MB |
| synthesize | 0h:2m:34s / 0h:0m:38s / 0h:0m:39s / 1,495 MB | 0h:5m:30s / 0h:1m:19s / 0h:1m:23s / 5,615 MB |
| device_map | 0h:0m:27s / 0h:0m:6s / 0h:0m:6s / 822 MB | 0h:0m:22s / 0h:0m:3s / 0h:0m:3s / 718 MB |
| place_route | 0h:9m:50s / 0h:2m:53s / 0h:3m:47s / 4,031 MB | 0h:26m:3s / 0h:6m:19s / 0h:7m:12s / 3,508 MB |
| report_timing | 0h:0m:36s / 0h:0m:10s / 0h:0m:12s / 2,723 MB | 0h:0m:29s / 0h:0m:6s / 0h:0m:6s / 2,337 MB |

## 四、Compile warning 逐项对照

计数为 `W:` 日志行数，不是独立缺陷数。全部原文可在各自 compile/run.log 中查到。

| 类别 | 旧工程 | 当前工程 |
|---|---:|---:|
| ConstantProbeLoop | 243 | 110 |
| Other | 2 | 0 |
| Public-4030 | 124 | 12 |
| Sdm-2000 | 1 | 0 |
| Sdm-2003 | 79 | 79 |
| Sdm-2008 | 72 | 0 |
| Sdm-2010 | 12 | 2 |
| Sdm-2014 | 65 | 0 |
| Verilog-2008 | 189 | 269 |
| Verilog-2017 | 72 | 0 |
| Verilog-2020 | 408 | 408 |
| Verilog-2021 | 3 | 0 |
| Verilog-2023 | 30 | 142 |
| Verilog-2036 | 4 | 4 |
| Verilog-2038 | 88 | 108 |
| Verilog-2039 | 19 | 15 |

- 旧工程 Verilog-2017 和 Sdm-2008 包括自定义 `can`、`map` 属性被工具忽略；原文保留。
- 旧工程 Sdm-2014 为反馈 mux 提示；不因工具建议就给数据寄存器添加复位。
- 两者都有多写 RAM 推断警告，需结合综合后的具体映射分析。
- 当前 110 条 constant probe loop 均未给出实例或信号路径；不能单独当作组合环路定位结论。

## 五、资源消耗

### 同口径的器件映射与布局布线逻辑层次数据

LUT / FF / Distributed RAM / APM / DRM 均保留报告原有单位，DRM 不自行解释成实际字节数。

| 阶段和指标 | 旧工程 | 当前工程 |
|---|---:|---:|
| Device Map LUT | 29245 | 24347 |
| Device Map FF | 15755 | 9099 |
| Device Map Distributed RAM | 411 | 39 |
| Device Map APM | 7 | 4 |
| Device Map DRM | 22 | 74 |
| PnR 逻辑层次顶层 LUT | 29193 | 24441 |
| PnR 逻辑层次顶层 FF | 15782 | 9121 |
| PnR Distributed RAM | 411 | 39 |
| PnR APM | 7 | 4 |
| PnR DRM | 22 | 74 |
| PnR IO | 15 | 9 |
| PnR GPLL / PPLL | 1 / 0 | 0 / 0 |
| PnR USCM | 1 | 1 |

### PnR 物理站点细分（与上面的逻辑层次 LUT 口径不同）

| 指标 | 旧工程 | 当前工程 |
|---|---:|---:|
| CLMA 内 LUT | 23571 | 19334 |
| CLMS 内 LUT | 7485 | 5994 |
| CLMA 内 FF | 12104 | 6985 |
| CLMS 内 FF | 3678 | 2136 |

不能把物理站点 LUT 明细与逻辑层次 LUT 总数混为同一个指标。
完整逻辑层次路径和各级资源见各自 `resource_hier.txt`，原表见 `.snr`、`.dmr`、`.prr`。

### SRAM、ROM、cache 的测量实例资源

| 模块 | 旧工程 DRM | 当前工程 DRM |
|---|---:|---:|
| SRAM 子系统 | 8 | 64 |
| Boot ROM 子系统 | 4 | 4 |
| I-cache | 5 | 3 |
| D-cache | 5 | 3 |

旧乘法单元总 APM=7：主 33×33 乘法 IP 占 4，低位乘法通路另占 3；
该划分可由旧 `.snr` 的 `u_mdu`、`gen_pango_multiplier.u_multiplier` 和
`gen_short_low_multiplier.u_low_multiplier` 行核对。当前乘法单元共 4 个 APM。

## 六、乘法器参数

旧 `mul.idf` 与旧 compile/run.log 的实例参数一致；当前参数以当前 compile/run.log 和 ip_ports.md 为准。

| 参数 | 旧 mul | 当前 ip_mul_s33x33 |
|---|---|---|
| A / B 位宽 | 33 / 33 | 33 / 33 |
| A_SIGNED / B_SIGNED | 1 / 1 | 1 / 1 |
| 输出位宽 | 66 | 66 |
| INREG_EN / OUTREG_EN | 0 / 0 | 0 / 0 |
| PIPEREG_EN_1（XYREG） | 1 | 0 |
| PIPEREG_EN_2（MREG） | 1 | 1 |
| PIPEREG_EN_3（PREG） | 1 | 0 |
| PIPE_STATUS | 3 | 2 |
| CPO_REG（展开后15位） | 000000000000000 | 000000000000010 |
| ASYNC_RST | 1 | 1 |
| ADVANCED_BOOL | 1 | 1 |

当前模型的两次使能上升沿延迟和 CE 保持曾通过本机 ModelSim 定向检查；
旧 IP 的 3 级配置不能作为当前 2 级配置的等价替代。

## 七、存储器配置与容量

容量由 `.idf` 的地址宽度、数据宽度计算；表中首先列单个 IP 的配置，避免把单 IP 与整个 cache 混淆。

| 存储器 | 旧 CoreMark IP | 当前 IP |
|---|---|---|
| SRAM 类型 | Simple Dual Port RAM | Single Port RAM |
| SRAM 数据宽度 / 地址宽度 | 64 / 12 | 64 / 15 |
| SRAM 字数与容量 | 4096×64，32 KiB | 32768×64，256 KiB |
| SRAM 字节使能 | 开启，BYTE_SIZE=8，8 位使能 | 开启，BYTE_SIZE=8，8 位使能 |
| SRAM 输出寄存器 | 关闭 | 关闭 |
| SRAM 时钟使能 | WR_CLK_EN=0，RD_CLK_EN=0 | CLK_EN=1 |
| SRAM 初始化 | HEX，sram.dat | 不初始化 |
| Boot ROM | 2048×64，16 KiB | 2048×64，16 KiB |
| Boot ROM 时钟使能 | CLK_EN=0 | CLK_EN=1 |
| Boot ROM 输出寄存器 | 关闭 | 关闭 |
| Boot ROM 初始化 | HEX，bootrom.dat | INIT_FILE=NONE，未加载外部镜像 |
| Cache Tag 单 IP | 128×21；地址7位 | 物理512×20；逻辑使用前128项 |
| Cache Tag 字节使能 | 关闭 | 关闭 |
| Cache Data 单 IP | 128×128，2 KiB | 512×64，4 KiB |
| Cache Data 字节使能 | 开启，16 位（每字节8位） | I-cache 关闭；D-cache 开启8位 |
| Cache RAM 读时钟使能 | RD_CLK_EN=0 | RD_CLK_EN=1 |
| Cache RAM 输出寄存器 | 关闭 | 关闭 |

报告层次显示 I-cache、D-cache 各自均有两路 Data RAM：按上述配置计算，每个 cache 的数据容量
旧为 4 KiB，当前为 8 KiB。容量计算不包含 tag、valid、dirty 等元数据。

## 八、时序条件与结果

| 项 | 旧工程 | 当前工程 |
|---|---|---|
| 主时钟 | soc_clk，PLL 从27MHz生成 | clk_sys，直接输入 |
| 目标周期 | 10.0000 ns | 6.6670 ns |
| 目标频率 | 100.0001 MHz（报告原文） | 149.9925 MHz（报告原文） |
| Estimated Frequency | 102.1662 MHz | 69.5652 MHz |
| Setup WNS，slow | +0.212 ns | −7.708 ns |
| Setup TNS，slow | 0.000 ns | −86183.305 ns |
| Hold WHS，fast | +0.102 ns | +0.107 ns |
| Design Summary | All Constraints Met | Some Constraints Violated |

旧展开参数明确 CPU_DUAL_ISSUE=1、CPU_FETCH_WIDE=1；当前 RVC_EN=1。
两套设计、存储容量、宏及流水结构不同，不能把此表当作相同设计的 A/B 性能实验。

## 九、文件位置与快照注意事项

- 本目录保留旧工程全部 15 个 IP 的 `.idf`，所有参数原值见 `ip_configuration.md`。
- `import_sources.tcl` 只导入 6 个 IP：cache_tag、cache_data、sram、boot_rom、mul、pll0。
  目录中另外 9 个 IP 的存在不代表它们消耗了本次 CoreMark 顶层的资源。
- 保存了 `import_sources.tcl`、`impl.tcl`、`edrv32_coremark.pds`、`edrv32_soc.pds`、clock.fdc 和 io.fdc。
- `edrv32_soc.pds` 最后修改于 2026-10-24，晚于 2026-10-07 的测量；它是当前磁盘快照，
  不保证与当次测量配置逐字一致。编译宏、乘法器参数和性能结论优先依据当次日志和报告。
- 原生 `.adf`、报告数据库 `.db`、综合网表、bitstream 和 IP RTL 未复制。
- 当前工程完整原始日志中 `synthesize/run.log`、项目 pds.log 和 project_run.log 超过数 MB。
  用户明确要求完整保存以交给 VPS Claude 定位耗时和 warning，因此保留全文，不作截断。
