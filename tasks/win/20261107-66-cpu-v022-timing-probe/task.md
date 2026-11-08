# 卡 66：CPU v0.22（时序第四轮）+ L1 独立时序探针（150 MHz）

## 1. 目标

测量第四轮修改后的 CPU 在 150 MHz 下的布局布线时序，与卡 64（v0.21，138.3 MHz，WNS −0.562 ns）对比。目标是 WNS ≥ +0.3 ns（约 157 MHz），为整片 SoC 的拥塞留余量。本卡只做时序分析，不生成 bitstream，也不上板。

第四轮改动：
- **I$ 填充时预译码**（cpu-spec v0.22、cache-spec v0.13）：预译码在填充时算好，与指令一起存进 I$ 数据 RAM，每路数据 RAM 由 64 位加宽到 108 位。F2 写入 IB 时不再译码。I$ 缺失多 1 拍。
- **前端等价修复**：F2 → IB 写入控制按槽拆分，恢复地址预先选好。
- **后端等价修复**：IB → E 的发射和旁路选择预先寄存成独热码；ALU 环；D$ 数据末级合并。
- R-05 为 1,808,045 周期（+319，来自 I$ 缺失 +1 拍）。

## 2. 输入

| 项 | 内容 |
|---|---|
| RTL 检出 | 本卡所在提交，分支 `zc100116/cpu-n16` |
| 新增源文件 | `rtl/cpu/edrv32_cpu_predecode.v`（已加入 `rtl/filelists/cpu.f`） |
| 探针源文件 | 沿用卡 60 的 `tasks/win/20261105-60-cpu-v018-tournament-probe/src/` 下三个文件，内容不变 |
| 对照数据 | 卡 64：WNS −0.562 ns，138.3 MHz，1625 个违例端点，LUT / FF 为 19712 / 12877，DRM 27 |

## 3. 环境

PDS 2022.2-SP6.1，PG2L200H-6 FBB676，与卡 64 相同。

## 4. 需要的 IP

与卡 64 相同，共 9 个。其中 **`ip_ram_icache_data` 需要重新生成**：数据位宽由 64 改为 108，其余选项不变。按 `fpga/ip/ip_ram_icache_data.md` 操作，模块名不变。

## 5. 操作步骤

1. **Windows Codex（命令行）**：在卡 64 用过的检出 `../EdRV32-Competition-2026-v018` 中，从本卡所在提交拉出分支 `win/20261107-66-cpu-v022-timing-probe` 并检出。
2. **用户（GUI）**：
   1. 打开卡 64 的工程 `EdRV32-FPGA/EdRV32-PROBE-V018`。
   2. 在 IP Compiler 中重新生成 `ip_ram_icache_data`，写端口和读端口位宽都改为 108，深度 2048 和其他选项不变，然后更新工程中的 IP。
   3. 用 Add Design 加入新文件 `<检出>/rtl/cpu/edrv32_cpu_predecode.v`。其他源文件路径不变，不需要重新导入。
   4. 用默认参数重新跑综合、Map、布局布线，关闭 Generate Bitstream 的 Auto Run。
3. **Windows Codex（命令行）**：
   - 确认生成的 `ip_ram_icache_data` 端口为 `wr_data[107:0]`、`rd_data[107:0]`；
   - 导出报告，命令与卡 64 相同：
     ```tcl
     set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
     report_timing -input_db_file {<工程>/place_route/edrv32_cpu_l1_timing_probe_pnr.adf} -delay_type min_max -max_path 5000 -nworst 1 -input_pins TRUE -force_to_run
     ```
   - 按第 6 节整理产物。

## 6. 产物

放在 `artifacts/R1/` 下，文件和格式与卡 64 相同：
- `timing_summary.txt`
- `timing_setup_top200.txt`
- `timing_setup_fail_all.txt`：全部违例端点，每端点一行
- `timing_setup_top20_detail.txt`
- `timing_setup_near_positive.txt`：0 到 +0.3 ns 之间的 200 条 setup 路径（窗口改为 +0.3 ns）
- `timing_hold_top20.txt`
- `high_fanout.txt`
- `resource_summary.txt`
- `resource_hier.txt`
- `settings.txt`
- `native_reports/`（包含 `timing5000.rtr.gz`）

不再按 P1–P10 分组。`timing_group_worst.txt` 改为按起点模块 → 终点模块分类：
- 列出违例条数最多的 8 类；
- 每类给出条数、最差 slack、级数范围，以及最差一条路径的逐级明细和每一级的扇出。

## 7. 通过判据

布局布线完成，产物齐全，`ip_ram_icache_data` 为 108 位。目标是 150 MHz 下 WNS ≥ +0.3 ns。没有达到时，违例路径就是下一轮的输入。

## 8. result.md 模板

```markdown
# 卡 66 结果

| 布局布线参数 | 慢角 WNS / TNS | 违例端点数 | WHS | 估算 Fmax | LUT / FF / DRM / APM / LUTRAM | u_cpu LUT / FF |
|---|---|---|---|---|---|---|
| | | | | | | |

## 分类（起点模块 → 终点模块，最多 8 类）

| 类 | 违例条数 | 最差 slack | 级数范围 | 最差路径 逻辑 / 布线 ns | 起点 → 终点 |
|---|---|---|---|---|---|

## 与卡 64 对比

## ip_ram_icache_data 端口确认

## 原始报告在 Windows 本地的路径

## 未取得的项和原因
```
