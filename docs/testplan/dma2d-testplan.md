# 公共 2D DMA 单元验证方案

| 项 | 内容 |
|---|---|
| 版本 | v0.1 |
| 日期 | 2026-10-27 |
| 对应规格 | `docs/spec/dma2d-spec.md` v0.1；SoC 规格 v0.8 4.2 |

## 1. 验证对象和范围

`edrv32_dma2d_rd`、`edrv32_dma2d_wr` 单元级验证，覆盖规格第 2、5、6 节。引擎内的仲裁、Surface 环形缓冲和与 mem_xbar 的联合行为留给各引擎的模块级测试。

## 2. 验证环境

- 单元级：`verif/unit/dma2d_rd/`、`verif/unit/dma2d_wr/`，各一个自检 testbench（Verilator，`--timing`）。
- 从设备：testbench 内的 AXI256 存储模型，支持随机 `arready/awready/wready/bvalid` 和随机 R 返回间隔；可对指定突发注入 SLVERR/DECERR。复用 `verif/common/edrv32_axi256_checker.sv` 检查协议（握手稳定、`wlast` 位置、地址对齐、4 KiB、LEN ≤ 15）。
- 使用者侧：随机 `data_ready`（读）和随机 `data_valid` 间隔（写）。

## 3. 测试项清单

| 编号 | 规格条款 | 测试内容 | 激励 | 检查 | 档位 |
|---|---|---|---|---|---|
| DM-01 | 2.2 | 拆分：base 取 4 KiB 边界前 0/32/480/512 B；width_bytes 取 1、32、33、512、513、2560、5120；height 1、2、17 | 定向 | 每个 AR/AW 的地址和长度与按 2.2 独立计算的列表逐项相同；不跨 4 KiB；LEN ≤ 15 | smoke |
| DM-02 | 2.3 | 读数据和标记 | 定向 + 随机描述符 | 输出 beat 与存储模型逐字节一致（行末超出部分不比）；sol/eol/eof 位置 | smoke |
| DM-03 | 2.4 | 写数据和字节使能 | 定向 + 随机描述符、随机 strb | 写后存储内容逐字节一致；strb = 0 的字节不变 | smoke |
| DM-04 | 3 OUTSTANDING、5.1、5.2 | 未完成突发上限 | OUTSTANDING = 1、4、8，从设备随机延迟 | 任意时刻未完成突发数 ≤ OUTSTANDING | full |
| DM-05 | 5.4 | 吞吐 | 从设备和使用者都不阻塞，width_bytes = 5120，height = 8 | 读写各自数据流连续，突发之间无空拍（以 beat 有效周期数比对） | smoke |
| DM-06 | 2.5 | 完成时刻 | 定向 | 读：最后一个输出 beat 被接收的下一拍或同拍 `done_o`；写：最后一个 B 之后 `done_o`；完成前 `desc_ready_o` = 0 | smoke |
| DM-07 | 6 | 错误响应 | 在第一个、中间、最后一个突发注入 SLVERR/DECERR | `err_o` 与 `done_o` 同拍为 1；数据流不中断 | smoke |
| DM-08 | 5.3 | ABORT | 在 AR 发出中、R 返回中、AW 已发 W 未发完时中止 | 无未完成事务；`idle_o` = 1；无 `done_o`；写方向补齐的 beat strb = 0 且存储不变 | full |
| DM-09 | 2.2–2.5 | 随机回归 | 1000 个随机描述符（满足 2.1 约束），随机反压 | DM-01–03、06 的检查全部成立 | full |

## 4. 参考模型

testbench 内按规格 2.2 独立计算突发列表（不读 RTL）；存储模型保存期望内容，读数据和写结果逐字节比较。

## 5. 覆盖目标

规格 2.1–2.5、5.1–5.4、6 的每一条至少对应一个测试项；4 KiB 边界前后各种距离、单 beat 行、跨多个 4 KiB 的行、OUTSTANDING 边界都要命中。

## 6. 通过判据和回归档位

全部测试自检 PASS；smoke 档：DM-01、02、03、05、06、07；full 档：全部。lint 和风格检查 0 告警。

## 7. 待定事项与变更记录

无待定事项。

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-10-27 | v0.1 | 初稿 |
