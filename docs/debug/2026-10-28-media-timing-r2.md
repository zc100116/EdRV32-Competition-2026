# ETH、GEO、VIN clk_mem 125 MHz 时序流水化（V-R7）

## 1. 现象

V-W3 在 PG2L200H-6 FBB676、PDS 2022.2-SP6.1（build 138931）、8 ns clk_mem
下得到 slow WNS −1.270 ns、542 个违例端点。原始测量 commit 为 `8b3d5df`，
报告为 `docs/reports/2026-10-28-timing-media-top-r2.md`；逐级数据位于
`tasks/win/20261028-05-media-r2/artifacts/`。按 `endpoint_groups.txt` 汇总：

| 分组 | 端点数 | 最差 ns | 终点 |
|---|---:|---:|---|
| ETH RX header | 188 | −1.270 | ARP MAC/IP/pending、RX metadata/address/start、packet FIFO count/pointer/RAM、drop |
| ETH TX frame | 8 | −0.767 | TX 异步 FIFO DRM 写数据 |
| GEO range → PERF | 63 | −0.995 | PERF1（含综合中间节点 N133_29） |
| GEO source RAM → bilinear | 100 | −0.478 | 插值 APM 输入 |
| GEO descriptor → bilinear | 8 | −0.193 | 插值 APM 使能 |
| GEO descriptor → coords | 3 | −0.014 | row_y_r 使能 |
| VIN remaining address → 两通道 | 172 | −0.348 | DMA write_data/strb、通道 count、FIFO fetch/head |

本次没有 Windows PDS 复测结果；Linux 回归验证功能、协议和性能，不能据此宣称
新的 WNS 或 8 ns 时序已闭合。

## 2. 复现

修改前功能/性能基线：`ce08c28c33b1bdde65ed2aabffb202ad2b55b844`。
仿真器：Verilator 5.020（2024-01-01，Debian 5.020-1）；clk_mem 周期 8 ns。
独立模块测试的固定存储延迟和向量保持原样，ETH ET-14、GEO GE-12 均为原有测试。
GE-12 使用 seed 1，GEO/VIN full 随机场景使用原有 seed 1–10；完整 case 名和种子见运行日志。

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/regress.py perf --path verif/block/eth -j 1
python3 tools/regress.py perf --path verif/block/geo -j 1
```

修改前日志副本：`build/media-timing-r2/{eth,geo}-before-detail.log`。
修改后日志：`build/media-timing-r2/` 及标准 `build/regress/`。

## 3. 观察

ETH RX 的 `header_r[144]` 与 ARP IP 字段共享物理寄存器，但逐级路径实际经过
UDP 伪首部求和 `pseudo_w`、折叠 `udp_fold_w`、`udp_good_w`、有序检查 `action_w`，
最后形成 ARP/RX 各终点使能。并非 ARP 字段本身需要长算术。

RX 最后一个 UDP 字节之后还有四个 FCS 字节，帧尾标记再到达；可以利用这段必有
时间完成最终和的三级寄存，仍在原帧尾周期作接收/丢弃决定。TX 的 IPv4 校验和
在头部字节 24、25 才被发送，包长和标识可在更早的头部字节发送时完成求和流水。

GEO 的 `desc_r` 主要通过范围错误 `range_error_w` → `error_w` → `stop_w`，
使能/屏蔽写数据和插值流水。它并非直接作为插值权重输入。RAM 路径则经过
`bank_data_w` 的选组/背景色选择、RGB 展开、`top_delta_w`/`bottom_delta_w`
减法，再进入 APM；原始 DRM tco 约 1.6 ns，APM 输入 setup 也占用周期预算。

VIN 逐级路径可在 `setup_near_positive_top20_detail.txt` 中复现：
`address_left_r` → `burst_beats_w` → `ch_awlen` → 整突发可用比较 →
`u_p1/eligible_w` → 通道选择/AWREADY/WREADY → DMA 的 `write_available_w`，
最终到写数据保持寄存器 CE 或 FIFO 消费逻辑。相同组合仲裁把通道零的路径传播到通道一。

## 4. 根因

本节行号指修改前基线 `ce08c28`。

- `edrv32_eth_rx.v:110,115,142`（eth 2.2、2.4）：帧尾决策同时串接 UDP 头/累计和、两次校验和折叠、
  IP/UDP 长度减法、窗口末地址加法/比较、空间判定。多段进位链和有序条件合并到同一周期。
- `edrv32_eth_tx.v:203,207`（eth 2.6）：`frame_r` 长度 → `ip_length_w` → IPv4 多项求和/折叠 →
  `checksum_w` → `header_w` 字节选择 → TX FIFO DRM。
- `edrv32_geo_range.v:20,24` / `edrv32_geo.v:188,193`（geo 2.4、4.3）：系数取绝对值、乘 31/15、求和和比较全部组合，
  结果通过停止信号继续串接到像素数求和、32 位 PERF 进位链和坐标/插值使能。
- `edrv32_geo_bilinear.v:75,79`（geo 2.2、5.2）：源 RAM 选出的像素直接进入差分乘法，没有独立像素输入级。
- `edrv32_vin_p1_arb.v:57,61,75`（vin 2.9）：`eligible_w` 在当前周期直接决定 `selected_w` 和总线 READY，
  使上游 DMA 的突发长度算术与两个通道的数据/FIFO 控制串接。

## 5. 修复

| 分组 | 实现 | 增加的固定延迟 |
|---|---|---|
| ETH RX 188 端点 | 源/目的 IP 各自成对求和，再寄存地址和、UDP 长度和、伪首部和；最终 UDP 累计和经 pseudo_r、udp_fold_r、udp_good_r 三级。payload_r、words_r、end_r、limit_r 及 IP 长度派生量提前寄存 | 对外接收/ARP/计数事件 +0 拍；最终 UDP 和内部 +3 拍，被四字节 FCS 吸收 |
| ETH TX 8 端点 | IP 成对求和、长度/常量和、长度/标识和、总和、折叠、取反逐级寄存，发送 checksum_r | 对外字节流 +0 拍；标识更新到有效校验和 +4 拍，早于字节 24 |
| GEO PERF/CE/coords 共 74 端点 | 范围检查拆成绝对值、31/15 加权、跨度和、比较四级；描述符增加 S_PREP 等待四拍，S_CHECK 后才使用结果 | 每描述符 +4 拍；计数事件仍在原来的对应握手/忙周期采样 |
| GEO RAM 100 端点 | bilinear 先捕获四像素和 fx/fy，再做原有水平/垂直插值；valid/eol 和 fy 同步延长 | 插值 +1 拍；advance_i 统一停顿，吞吐仍为每拍一个像素 |
| VIN 172 端点 | 整突发资格和轮询选择先写入 grant_r/hold_r，下一周期对外暴露 AW；READY 只由已寄存所有权和握手产生 | 每突发获得资格后增加一拍授予；像素打包仍为每拍一个字，W 连续输出 |

APB 寄存器定义、性能计数规则、外部端口、ARP 优先级、ABORT 排空和 DDR 提交边界均未改变。
特别保留 GEO PERF 事件在实际握手周期的采样；没有通过延迟计数事件来切断时序。
RX 的窗口大小、enable/error、ARP pending 和 metadata ready 仍在帧尾即时参与检查，
只提前寄存包头派生算术量；释放指针也仍即时参与空间比较。
所有新增数据级不复位，只有控制 valid/state/counter 使用复位。

性能对比（相同原测试、相同向量与存储模型）：

| 测试/指标 | 修改前 | 修改后 | 规格上限/下限 |
|---|---:|---:|---:|
| ET-14 RX MB/s | 116.556207 | 116.556207 | ≥ 100 |
| ET-14 TX MB/s | 116.418931 | 116.418931 | ≥ 100 |
| ET-14 ARP ns | 104.010400 | 104.010400 | ≤ 10000 |
| GE-12 s≤1 PERF0 / ns | 1203173 / 9625384 | 1203605 / 9628840 | ≤ 16700000 ns |
| GE-12 s≤2 PERF0 / ns | 2452913 / 19623304 | 2453345 / 19626760 | ≤ 33000000 ns |

两档 GE-12 均增加 432 个周期（3456 ns），仍满足原指标；ET-14 三项数字保持一致。

## 6. 防回归

- ETH RX 单元新增 LEN 0–35 的带 UDP 校验和连续字节帧，覆盖恰好四个 FCS 字节、
  最短帧填充边界和奇偶尾部；另加接收 FIFO valid 间断。
- GEO range 单元按四拍延迟采样，保留正负边界、最小有符号系数及随机精确参考比较。
  bilinear 单元参考流水改为三拍，继续核对精确舍入、fx/fy、EOL 和随机全流水停顿。
- VIN arbiter 单元扩展为两个通道各 16 个突发，遍历 1–16 beat 长度，保留整突发准入、
  AW 反压保持、W 不交织、轮询和 B 按序返回检查。
- 模块级测试未修改。

所有回归使用 `-j 1`，未使用 `--parallel`，每次 `--path` 只指定一个目录。
单元回归的命令为：

```sh
for media_unit in eth_rx eth_tx eth_rx_write geo_math geo_bilinear geo_coords \
    geo_source geo_regs geo_address vin_p1_arb vin_ch; do
    python3 tools/regress.py smoke --path "verif/unit/$media_unit" -j 1
    python3 tools/regress.py full --path "verif/unit/$media_unit" -j 1
done
for media_block in eth geo vin; do
    python3 tools/regress.py smoke --path "verif/block/$media_block" -j 1
    python3 tools/regress.py full --path "verif/block/$media_block" -j 1
done
```

ETH TX 的 full 自动包含 `eth_tx/fast`；VIN 的 smoke/full 均自动包含
`verif/block/vin/pix_integration`。性能命令见第 2 节。

风格命令：`python3 tools/check/verilog_style.py rtl/eth rtl/media/geo rtl/media/vin`，
27 文件、0 告警。三个完整子系统顶层分别用 `tools/check/lint.sh --top-module`
指定 `edrv32_eth`、`edrv32_geo`、`edrv32_vin`，定义 `SIM_MODE`，
从对应模块测试 `files.f` 用 `tools.regress.expand_files` 展开、去除测试 `.sv`，
保留全部 RTL/tech 源和 include 参数：均 0 告警；日志为
`build/media-timing-r2/{eth,geo,vin}-lint.log`。

验收合计 **42 PASS、0 FAIL**，其中 smoke 18 项、full 22 项、perf 2 项：

| 范围 | smoke PASS | full PASS | perf PASS |
|---|---:|---:|---:|
| ETH 单元（rx、tx、rx_write） | 3 | 4 | — |
| GEO 单元（math、bilinear、coords、source、regs、address） | 6 | 6 | — |
| VIN 单元（p1_arb、ch） | 2 | 2 | — |
| ETH 模块 | 2 | 3 | 1 |
| GEO 模块 | 2 | 3 | 1 |
| VIN 模块（含 PIX 集成） | 3 | 4 | — |

ETH smoke 22 个功能场景、full 10 个随机场景，另含自测和 ET-14 三个性能场景；
GEO smoke 53、full 33、perf 2 个场景；VIN full 的 VI-01–17 和 seed 1–10 均通过，
VI-18 实际 PIX 集成在 smoke/full 均通过。VIN full 子目录包含构建用时 1432 秒，
日志末尾为 `PASS VIN full`，没有修改或跳过完整尺寸场景。

修改后测量对应以下三个提交的最终 RTL 树（分支 `zc100116/task-media-timing-r2`）：

| 提交 | 修改文件 |
|---|---|
| `c0b5716` | `rtl/eth/edrv32_eth_rx.v`、`rtl/eth/edrv32_eth_tx.v`、`verif/unit/eth_rx/tb.sv` |
| `1d15bb4` | `rtl/media/geo/edrv32_geo.v`、`rtl/media/geo/edrv32_geo_range.v`、`rtl/media/geo/edrv32_geo_bilinear.v`、`verif/unit/geo_math/tb.sv`、`verif/unit/geo_bilinear/tb.sv` |
| `1c8f1c9` | `rtl/media/vin/edrv32_vin_p1_arb.v`、`verif/unit/vin_p1_arb/tb.sv` |

本调试记录为另一个文档提交；没有修改规格、验证方案、模块级测试、tech 包装或文件列表。

VIN 仓库及 vin-testplan 没有 perf 档；协调者已答复接受既有 smoke、full、
pix_integration 验收，不修改独立模块级测试。

## 7. 同类排查

检查 `setup_near_positive_top200.txt`（0–1 ns）及最差 20 条明细：
VIN 的 write_data/write_strb、count、fetch_bin/head_data 均来自同一个组合资格/授予链，
由寄存授予一起截断；GEO 各 RAM bank 到 APM 的近零正裕量路径由像素输入级一起截断；
GEO `desc_r` 到 bilinear 使能及 coords row_y 的正/负裕量路径由范围检查输出寄存一起截断。
ETH TX 在 542 个完整违例端点中另有 8 条（摘要背景未单列），一并修复其校验和链。
其他子系统的正裕量路径不在本次修改范围。

后续需在 Windows 用原 8 ns 约束进行 PDS 布局布线复测，取得 slow setup 与资源数据。
