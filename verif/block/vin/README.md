# VIN independent verification (V-T1)

本文保留 V-T1 的独立验证交付记录。V-I1 的真实 RTL 联调、故障归因及最终回归结果见
[`2026-10-28-vin-block-integration.md`](../../../docs/debug/2026-10-28-vin-block-integration.md)。

依据 `vin-spec.md` v0.1（含变更记录澄清）、`vin-testplan.md` v0.1、SoC v0.9
4.2/4.3/4.5/7.1/7.3 编写。没有阅读 `rtl/media/vin/`，没有修改 RTL、docs 或
`verif/common/`。起始提交 `7a46a7a29c18d1e4fd7964361b204454d4ebe6da`；DVP 模型提交
`e2c7550`。VIN 测试提交号见本文件所属提交及 V-T1 的 worker_done。

当前结果：DVP 模型自测和 VIN harness/reference 自测通过，功能 testbench 在接口桩下
完成全量 elaboration/lint，0 告警。**尚未运行或宣称真实 VIN 的 VI-01–17 通过**；真实
RTL 文件列表与联调由 V-I1 补齐。

## 环境与文件

- `../../models/dvp_camera_model.sv`：两个独立实例；可设置 `half_period_ns`、`phase_ns`、
  `line_blank`、`frame_blank`、`vsync_width`。`send_frame(width,height,image,dx,dy,odd,stop)`
  接受按实际宽度 `width+dx` 行优先排列的 RGB565 动态数组，按高字节在先发送。
  `dx/dy` 修改实际行长/行数，`odd` 在每行末多发一个字节；`stop >= 0` 在指定行数后
  停止，保持 VSYNC 低，下一次调用先结束旧帧再开始新帧。`frame_blank` 是有效区前后的
  PCLK 空拍；`vsync_width` 是每次调用中 SOF 前的高电平拍数，调用之间空闲保持高电平。
- `edrv32_vin_memory.sv`：字节寻址 AXI256 RAM，独立的 AW/W/B/AR/R 随机等待，写停止、
  读停止、B 保持，指定编号 B/R 事务注入 SLVERR。存储器缺省字节为 `0xA5`，用于检查
  行尾 WSTRB 和 stride 空隙未被改写。复位清除测试 RAM 与事务记录。
- `edrv32_vin_reference_pkg.sv`：只根据输入图像、配置与激励独立整形、分配 frame_id、
  选择环槽；`reference_selftest()` 使用手写的裁剪/补零/环槽期望值自检。
- `edrv32_vin_tb.sv`：APB 驱动、逐像素 Surface 比对、PIX 流数据与 SOF/EOL/EOF 比对、
  两路摄像头、PIX 直通及可反压直通、VI-01–17。PIX 随机反压仅用于可反压的内存源。
  发生输出停顿后，直通级保持 VALID 与负载直到握手。
- `dut_connections.svh`：按规格第 3 节显式连接公开端口；没有 DUT 内部层次引用。
- `support.f`：复用 `edrv32_axi256_if.sv`、`edrv32_axi256_checker.sv`、
  `edrv32_apb_if.sv`。APB 使用媒体槽 1。
- `selftest/edrv32_vin.sv`：所有输出接 0 的接口桩，没有实现 VIN 功能。仅 selftest 文件
  列表引用它；正式 `files.f` 使用预期的 `rtl/media/vin/*.v`，等待 V-I1 替换为完整列表。

`HARNESS_SELFTEST=1` 只运行模型自测；默认 0 才运行 VIN 测试。全量功能任务仍以默认参数
在桩下 lint/elaborate，自测二进制用常量参数去掉无需执行的功能激励以减少编译开销。

## 测试位置与档位

全部功能测试位于 `edrv32_vin_tb.sv` 中同名 task，`run_test()` 串行派发。每项激励用
独立 SV 进程，限制生成的单个 C++ coroutine 大小；同一时刻只执行一个测试。

| 编号 | 位置 | 检查重点 | 档位 |
|---|---|---|---|
| VI-01 | `vi01()`、`completion_edge()` | 64×8 / 1280×720，3 帧，槽 0/1/2，完成原子性，等待 B 时接收下一帧 | smoke/full |
| VI-02 | `vi02()` | 首次使能和再次使能各丢 2 帧，PERF 与 frame_id | smoke/full |
| VI-03 | `vi03()` | 字节序、HREF 消隐、奇数字节的半像素丢弃 | smoke/full |
| VI-04 | `vi04()` | 两路各行长 ±2/±64、行数 ±1/±10、中途停止、补齐/截断及恢复 | smoke/full |
| VI-05 | `vi05()` | 两路独立、同源双通道、帧中改 SRC/EN/RING_N/BASE、关闭完成在途帧 | smoke/full |
| VI-06 | `vi06()` | RING_N=2/3/4，每种 BUSY mask、运行中更新、全占用 SKIP | smoke/full |
| VI-07 | `vi07()` | CH0/1 分别溢出、并发另一源保持完整、无完成、槽复用、恢复及排空 | smoke/full |
| VI-08 | `vi08()`、`memory_done_edge()` | 34×9，输入/输出不同 stride，逐行 AR，读完成 DONE | smoke/full |
| VI-09 | `vi09()` | 写端停顿和 PIX 随机反压、内存源暂停、RREADY、无溢出 | full |
| VI-10 | `vi10()` | 忙时 START 忽略、无选择通道仍读完、内存 frame_id | full |
| VI-11 | `vi11()` | 两源并行，AW/W/B 随机等待，连续 W、事务顺序与像素归属 | smoke/full |
| VI-12 | `vi12()` | CH0/1 摄像头 FIFO 过半 urgent、输入数量下界、PERF14、内存源无 urgent | full |
| VI-13 | `vi13()` | 摄像头与内存源半帧 ABORT、无遗留事务、保持 ENABLE、下帧恢复 | full |
| VI-14 | `vi14()` | 错误 6/7/8/9/10 的全部配置类别、IRQ/计数/BUS_ERR 与恢复 | smoke/full |
| VI-15 | `vi15()` | 复位/RO/对齐/RW1C/IRQ mask/保留区/CH2/在途 SOFT_RST 及重新丢帧 | smoke/full |
| VI-16 | `vi16()` | 24/48/84 MHz，与独立相位，双摄像头及全尺寸 VI-01 | full |
| VI-17 | `vi17()` | 10 种子，两路不同尺寸、2/1280 边界、畸形帧、P1 停顿、BUSY、内存源穿插 | full |

通用判定在 `compare_surface()`、`drain_channel()`、`drain()`、`wait_idle()` 和
`expect_error()`，检查失败打印测试编号、期望、实际值和仿真时刻，并 `$fatal(1,...)`。
仿真总超时为 2 秒仿真时间（包含 full 中 24 MHz 的完整 720p 帧）。

## 运行与证据

工具：Verilator 5.020，Linux，`. ~/.local/opt/edrv32/env.sh`，编译 `-j 1`，仿真串行。

```sh
make smoke REGRESS_ARGS='-j 1 --path verif/unit/dvp_camera_model'
make smoke REGRESS_ARGS='-j 1 --path verif/block/vin/selftest'
```

两条均为 `Summary: 1 PASS, 0 FAIL`，退出码 0。DVP 自测检查字节值、行/像素数量、
HREF 与 VSYNC、场/行消隐、行长/行数偏差、奇数字节、停止/下一次关闭旧帧及改变时钟。
Harness 日志输出 `PASS VIN reference selftest` 和
`PASS VIN HARNESS SELFTEST (no VIN functional result)`；参考自检包含正/负整形、
完整内存帧、重使能不重置 ID、ID 回绕、环 2/3/4 的回绕/跳忙/全忙。

日志：`build/regress/smoke/unit/dvp_camera_model/verilator/{compile,run}.log`、
`build/regress/smoke/block/vin/selftest/verilator/{compile,run}.log`。

全量 testbench（`HARNESS_SELFTEST=0`，所有 VI task）的 lint 命令：

```sh
python3 - <<'PY'
from pathlib import Path
import subprocess
import sys
sys.path.insert(0, 'tools')
from regress import expand_files
for top, files in [
    ('edrv32_vin_tb', 'verif/block/vin/selftest/files.f'),
    ('edrv32_dvp_camera_model_tb', 'verif/unit/dvp_camera_model/files.f'),
]:
    subprocess.run(['verilator', '--lint-only', '--timing', '-Wall',
                    '--top-module', top] + expand_files(Path(files).resolve()), check=True)
PY
```

两项退出码 0，0 告警；日志 `build/vin-lint.log`、`build/dvp-lint.log`。
`lint.vlt` 仅豁免验证环境的阻塞式队列更新、接口桩未用输入、公共接口未用槽、公共检查器
整型索引、工具对 class 成员使用和包内多个 class 的告警；不屏蔽真实 RTL 告警或位宽告警。
完整功能 testbench 另以默认 `HARNESS_SELFTEST=0` 在接口桩下生成、编译并链接二进制，
退出码 0、0 告警（没有运行 VIN 功能判定），日志 `build/vin-compile-all.log`。复现：

```sh
python3 - <<'PYCODE'
from pathlib import Path
import subprocess
import sys
sys.path.insert(0, 'tools')
from regress import expand_files
subprocess.run(['verilator', '--binary', '--timing', '-Wall', '-CFLAGS', '-O0',
                '-j', '1', '--top-module', 'edrv32_vin_tb', '--Mdir',
                str(Path('build/vin_compile_all').resolve()), '-o', 'sim']
               + expand_files(Path('verif/block/vin/selftest/files.f').resolve()), check=True)
PYCODE
```

仓库 `tools/check/verilog_style.py` 只发现 `.v/.vh`，对这些 SV 文件报告 0 files；另外对
新增 SV/SVH 的头注释、100 列、缩进与 Tab 逐项检查，0 告警，例化均显式命名并一行一端口。

V-I1 补齐 `files.f` 后运行：

```sh
make smoke REGRESS_ARGS='-j 1 --path verif/block/vin'
make full REGRESS_ARGS='-j 1 --path verif/block/vin'
```

正式二进制可用 `+CASE=1` … `+CASE=17` 单独定位，`+CASE=smoke/full` 按方案选择；full
由 `full/test.yaml` 启用 720p 与十种子。功能二进制的 C++ 编译使用 `-O0` 减少单核编译成本。

## 提出的 ask 与边界

1. 首个 frame_id：协调者确认每个源（包括 SOFT_RST 后）首个输出帧为 0，随后 32 位自增；
   PERF0–2 独立计数。已按此实现。
2. SRC=3 的错误检查时机：协调者确认全局/通道使能时，任一源 SOF 都触发一次错误 8 和
   PERF15；VI-14 只运行 cam0，避免多源计数。其余非法通道配置在所选源 SOF 检查。
3. 最后 B 与完成更新：协调者确认允许固定小延迟；VI-01 检查 IRQ 上升在最后 B 的后
   1–4 个 clk_mem 周期，且该拍预置的 APB DONE_INFO 或 DONE_FRAME_ID 已更新；另一字段
   随后正规读取。两个字段分别用两帧检查。
4. 内部 FIFO 可观测性（`msg_70b682f58fc3`）：询问用连续 W、顺序/数据及停止 AW 后的
   输入数量下界验证公开行为；等待 10 分钟未获答复，按 Task 的超时规则依建议推进。
   精确内部 FIFO 水位与授权条件仍需 RTL 单元测试确认；没有声称已直接观测内部水位。

未引入 DUT 功能替代或通过兜底：真实 RTL 缺失时正式列表会明确编译失败；只有明确指定的
selftest 列表使用接口桩。V-I1 需要核对最终公开端口拼写和完整依赖列表，再运行真实功能
回归；本阶段没有真实 RTL 的通过证据。
