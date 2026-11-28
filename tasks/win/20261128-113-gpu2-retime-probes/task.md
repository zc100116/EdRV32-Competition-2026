# 卡 113：GPU v2 切拍后的算术探针（3 个工程）复测

## 1. 目标

卡 112 实测 fp32 116 MHz、sfu 138 MHz、setup 114.5 MHz，远低于 220 MHz。RTL 已按 PDS 校准预算重新切拍（提交 84083a20e，设计说明 `docs/design/2026-11-28-gpu-v2-probes.md` 末尾"GP-C"一节）。本卡在同样的 220 MHz（4.545 ns）约束下重跑这三个工程，量出切拍后的裕量和资源，供 G-P05 定延迟。只做时序和资源分析，不生成比特流，不上板。

## 2. 输入

| 项 | 内容 |
|---|---|
| 代码 | 用 `git log -1 --format=%H origin/zc100116/gpu-dev -- tasks/win/20261128-113-gpu2-retime-probes` 找到本卡提交，从它拉出 `win/20261128-113-gpu2-retime-probes`，记录 HEAD |

| 工程 | 顶层 | 导入脚本 | 约束 | 需要的 IP |
|---|---|---|---|---|
| A · fp32 | `edrv32_fpga_probe_gpu2_fp32_top` | `fpga/scripts/import_probe_gpu2_fp32_top.tcl` | `fpga/constraints/edrv32_fpga_probe_gpu2_fp32_top.fdc` | `ip_ram_gpu2_queue` |
| B · sfu | `edrv32_fpga_probe_gpu2_sfu_top` | `import_probe_gpu2_sfu_top.tcl` | 同名 .fdc | `ip_rom_gpu2_sfu`、`ip_ram_gpu2_sfu_scratch`、`ip_lutram_gpu2_sfu_word16`、`ip_lutram_gpu2_sfu_word5` |
| C · setup | `edrv32_fpga_probe_gpu2_setup_top` | `import_probe_gpu2_setup_top.tcl` | 同名 .fdc | 无（APM 原语） |

文件清单、约束和 IP 与卡 112 相同，只有 RTL 内容变了。

## 3. 环境

PDS 2022.2-SP6.1，PG2L200H-6 FBB676，与卡 112 相同。

## 4. 需要的 IP

沿用卡 112 工程里已生成的 IP，不需要重新生成。SFU ROM 内容没有变化。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | C | 按第 2 节拉分支，记录 HEAD |
| 1 | U | 打开卡 112 的 A、B、C 三个工程（`gpu2_probe_fp32/sfu/setup`）。仓库已切到本卡分支，源文件路径不变，直接重新综合即可；如果 PDS 提示源文件已改动，选择重新加载 |
| 2 | U | 默认参数跑综合、Device Map、布局布线，Generate Bitstream 不自动运行 |
| 3 | C | 各工程导出报告（命令同卡 112），按第 6 节整理 |
| 4 | C | 填写 result.md，提交推送 |

三个工程互不依赖，可以同时跑。某一步报错，把报错原文写进 result.md 后停下，不要改 RTL 或约束。

## 6. 产物

放在 `artifacts/<fp32|sfu|setup>/` 下，每个工程一套，格式同卡 112：
- `timing_summary.txt`、`setup_top200.txt`、`setup_top20_detail.txt`、`hold_top20.txt`；
- `segments.txt`：按终点寄存器所在流水级分组，每组最差 3 条。重点单列：fp32 的 FMA 高位移位加法段（设计说明估计最紧，约 4.2 ns）和 DP 加法段；sfu 的 DRM 捕获后选择/前导零段；setup 的 N48 各拍；另列 APM 内部/级联最差路径；
- `resource_summary.txt`（含 CLMA、CLMS、control set 数量）、`resource_hier.txt`；
- `high_fanout.txt`：扇出最大的 50 个网络，以及所有扇出超过 16 的使能网络；
- `settings.txt`。

## 7. 通过判据

三个工程都完成布局布线并交齐第 6 节产物（时序不满足也要完整回传，不判失败）。所有数字取自报告原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 卡 113 结果

| 项 | 内容 |
|---|---|
| 分支 HEAD | |
| PDS 版本 | |

## 汇总
| 工程 | WNS | WHS | 估算 Fmax | LUT | FF | DRM | APM | 分布式 RAM | CLMA | CLMS | control set |
|---|---|---|---|---|---|---|---|---|---|---|---|
| fp32 | | | | | | | | | | | |
| sfu | | | | | | | | | | | |
| setup | | | | | | | | | | | |

## 各工程最差路径与重点段
（每工程：最差路径起点→终点、级数、逻辑/布线延迟；第 6 节点名的重点段裕量）

## 问题与偏离
```
