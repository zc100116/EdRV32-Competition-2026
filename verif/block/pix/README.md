# PIX 独立模块验证（V-T3）

依据 `docs/spec/pix-spec.md` v0.1、`docs/testplan/pix-testplan.md` v0.1 和 SoC
4.3、4.5、7.1 实现 PX-01–PX-14。未阅读 `rtl/media/pix/`，未修改归属目录以外的文件。
正式 DUT 为 `edrv32_pix`，仅经 `files.f` 的 `-f ../../../rtl/filelists/pix.f` 引入；
所有检查只使用规格中的公开端口和寄存器。

本阶段参考模型 selftest、完整环境的桩下 lint/编译和 PX-01 环境验证通过。
真实 DUT 文件尚不存在，正式 smoke 会明确编译失败；**没有真实 RTL 的 PX-01–PX-14
通过结论**，通过判定及真实性能测量留给 V-I2。

## 文件和运行方式

- `pix_ref.py`：标准库整数参考模型。按 2.1 展开/截断，按 2.2 执行有符号算术移位和
  饱和，按 2.4 做两次独立补零窗口，按 2.5 顺序执行灰度、二值化和反色。
- `scenarios.py`：全部测试项的配置、尺寸、图案、截断位置和确定性随机种子。
- `environment.svh`：125 MHz 像素源、随机反压接收端、逐像素/标记 scoreboard、APB
  BFM、寄存器和性能计数检查。媒体 APB 使用公共 `edrv32_apb_if.sv` 的槽 2。
- `edrv32_pix_tb.sv`、`dut_connections.svh`：正式顶层和公开端口连接。
- `run.py`：以 `--timing -Wall -j 1 -CFLAGS -O0` 编译一次，串行执行各场景。每个场景
  先以 `+PREPARE=1` 运行 testbench，导出 `inN.hex` 和 `cfgN.txt`；runner 再调用
  Python 模型产生 `outN.hex`，最后重放同一输入并检查输出。不完整帧不生成期望输出。
- `selftest/test.yaml`：独立模型自测，无 RTL 依赖，smoke/full 均会发现。
- `test.yaml`、`full/test.yaml`：正式 smoke 和 full；full runner 包含所有 PX 项。
- `edrv32_pix_passthrough_stub.sv`、`edrv32_pix_stub_tb.sv`、`stub.f`：显式直通桩环境。
  桩只接通流接口和 APB 应答，不实现 PIX 运算或寄存器；仅显式 `--stub` 命令使用。
  该命令只执行 PX-01 的两个帧，跳过桩不存在的寄存器检查，保留数据、数量和标记检查。
  正式 YAML 和正式文件列表均不引用桩，也不自动切换到桩。

图案全部由 SV 像素源生成：随机、六种纯色、RGB 渐变、棋盘格，以及渐变加噪声。
`verif/models/` 没有现成自然图像，PX-07 使用 1280×720 渐变加噪声，不依赖外部文件。
Gamma 两组全表均经 APB 初始化：bank 0 为恒等表，bank 1 为 `255-index`。
SOFT_RST 后不重写表，后续 Gamma 帧检查其保留。

帧计划每行依次为：宽、高、ENABLE、CFG、BC、THRESH、图案、种子、实际发送拍数、
流控模式、场景标志、帧中修改位置及新的 ENABLE/CFG/BC/THRESH。
流控模式 0 连续、1 随机 VALID 间隙及随机 READY、2 连续且检查输入吞吐。
场景标志为 1 冲刷上限、2 不等输出结束即提交下一 SOF、4 帧中 SOFT_RST、8 空闲
SOFT_RST、16 挂起复位后的 SOF 重启。它们只描述激励，不是 DUT 参数。

## 测试项映射

所有逐像素及 SOF/EOL/EOF 检查在 `environment.svh:stream_monitor`；配置计划在
`scenarios.py:cases()` 对应的 `add(编号, ...)` 中。

| 测试项 | 实现位置及激励 | 检查点 | 档位 |
|---|---|---|---|
| PX-01 | `add(1)`，64×8 随机图，两种 ENABLE/旁路配置 | RGB565 恒等、左右顺序、像素数、全部标记 | smoke/full |
| PX-02 | `add(2)`，4 个亮度 × 4 个对比度，渐变 | 有符号负数右移、CONTRAST 0/511、两端饱和、逐位参考比对 | smoke/full |
| PX-03 | `add(3)`、`gamma_initialize()`、`midframe_write()` | 全表 APB 写入、bank 帧间/帧中修改、BC 后 Gamma 的次序 | smoke/full |
| PX-04 | `add(4)`，两级分别 OP 1–7，随机和棋盘格 | 单级各运算、OP7 旁路、四边四角补零 | smoke/full |
| PX-05 | `add(5)`，32×6，OP0–6 的 49 对组合 | 第二级使用第一级 RGB888 结果，逐位参考比对 | full |
| PX-06 | `add(6)`，8 种组合 × 3 阈值 × 2 图案 | GRAY/BIN/INV 顺序、阈值 0/128/255、`>=` | smoke/full |
| PX-07 | `add(7)`，3 张 720p 合成图，四级全部启用 | 高斯+Sobel+BIN、腐蚀+膨胀、均值+锐化+Gamma，各级精度 | full |
| PX-08 | `add(8)`，两级高斯+Sobel | smoke 为宽 2/4/6 × 高 1/2/3；full 为 5 宽 × 4 高全部 20 种尺寸，含 1278/1280 和 720 高 | smoke/full |
| PX-09 | `add(9)`，连续三帧，`midframe_write()` | 帧中写 CFG、BC、THRESH、ENABLE、GAMMA_BANK 仅在下一 SOF 生效 | smoke/full |
| PX-10 | `add(10)`、`send_frame()`、`receiver_drive`、`check_counters()` | 随机 VALID/READY 下数据和负载保持；连续输入首尾拍差严格等于拍数；精确 PERF1/2 | smoke/full |
| PX-11 | `add(11)`，1280×6 两帧，两级同时启用 | EOF 输入到输出 ≤ W+32 拍；下一 SOF 持续等待、上一 EOF 前不接收 | full |
| PX-12 | `add(12)`，发送 35/64/230 拍的三个场景，各接完整新帧 | 行中/行末/最后一行中断；旧帧无 EOF；新 SOF 出现即丢弃；新帧正确；PERF3 | smoke/full |
| PX-13 | `add(13)`、`reset_registers()`、`register_writes()`、`soft_reset_finished()` | 复位/RO/保留位/未知偏移/PSTRB、FRAME RW1C 和 IRQ 屏蔽、DONE/PERF0、完整帧中与空闲 SOFT_RST、Gamma 保留；不完整帧挂起复位及新 SOF 保持，复位配置直通且 PERF3 清零 | smoke/full |
| PX-14 | `add(14)`，种子 1–10，各 6 帧 | 偶数宽 2–1280、高 1–64、全部合法配置编码、随机流控/图案/帧间配置、每种子两个不完整帧及恢复 | full |

通用寄存器检查在完整帧排空后运行：DONE_COUNT/PERF0 等于输出 EOF 握手次数，PERF1/2
等于 testbench 逐周期计数，PERF3 等于丢弃次数，STATUS 为 IDLE、ERR_CODE 为 0。
输出 EOF 握手后同周期检查 FRAME 中断电平；计数寄存器经正规 APB 读回检查。
PX-13 对 PERF4–15、非使用的描述符寄存器和私有保留位检查读 0/写忽略。

比较失败立即打印 PX 编号、帧号、坐标、期望值、实际值和仿真时刻，并 `$fatal(1, ...)`。
输入 EOF 缺失的帧只检查输出标记及无 EOF，不对规格未定义的残留像素建立期望图。
接收端在中断重启 SOF 附近暂停，避免把丢弃边界的旧输出握手归到新帧。

## 参考模型自测

`pix_ref.py:selftest()` 使用手算常量：RGB 位复制和截断、三个基色的灰度、亮度饱和两端、
对比度 0/511、负数右移向负无穷取整、两组 Gamma、均值/高斯的单点角落与 2×1 补零、
3×3 白图四边四角、锐化上下饱和、Sobel 普通值及饱和、腐蚀/膨胀、BIN 阈值两端和
等于阈值、完整四级小图手算结果；另穷举 65536 个 RGB565 的展开再截断恒等。
这些断言无需 DUT，也不把模型自身的另一路计算当期望值。

## 复现和本阶段证据

工具为 Verilator 5.020、Python 3，Linux；先执行 `. ~/.local/opt/edrv32/env.sh`。
起始提交 `02586b3`（本次提交号由 `git log -1 -- verif/block/pix` 取得）。
单核构建，始终只有一个仿真进程，无 `--parallel`。

```sh
make smoke REGRESS_ARGS='-j 1 --path verif/block/pix/selftest'
python3 verif/block/pix/run.py smoke --stub
make smoke REGRESS_ARGS='-j 1 --path verif/block/pix'
```

第一条：`Summary: 1 PASS, 0 FAIL`，模型自测通过。
第二条：`PASS PX-01 frames=2 environment_stub=1`，两个 64×8 帧，共 1024 像素，
数据及标记正确，仿真结束时刻 4,424,000 ps。
第三条：参考自测 PASS，正式 DUT 项因缺少 `rtl/media/pix/edrv32_pix.v` 编译失败，
`Summary: 1 PASS, 1 FAIL`；没有跳过或把桩计入正式结果。
全部 smoke 场景还完成了 SV 导出输入/配置和 Python 期望文件生成；这只是环境文件流程检查。

日志分别位于 `build/regress/smoke/block/pix/selftest/verilator/run.log`、
`build/pix/stub/{compile.log,PX-01/{prepare.log,run.log}}`、
`build/regress/smoke/block/pix/verilator/run.log`；源/模型导出检查放在
`build/pix/export-check/`。所有生成物均在 `build/`。

SV 桩本身通过仓库检查器：

```sh
python3 tools/check/verilog_style.py verif/block/pix/edrv32_pix_passthrough_stub.sv
```

结果 `Style: 1 files, 0 warnings`。仓库目录扫描只发现 `.v/.vh`，因此另按该检查器相同的
文件头、100 列、4 空格缩进和 Tab 规则检查全部 5 个 SV/SVH 文件，0 告警；SV 语言特性
按第 9 节允许，例化均采用命名连接、一行一端口。SV 风格检查复现：

```sh
python3 - <<'PY'
from pathlib import Path
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, 'tools/check')
from verilog_style import without_comments
errors = []
paths = sorted(p for p in Path('verif/block/pix').rglob('*') if p.suffix in ('.sv', '.svh'))
for path in paths:
    text = path.read_text()
    header = '\n'.join(text.splitlines()[:12])
    for label in ('File', 'Spec', 'Description', 'Clock'):
        if label.lower() not in header.lower():
            errors.append(f'{path}: missing {label}')
    for line_number, (raw, clean) in enumerate(
            zip(text.splitlines(), without_comments(text).splitlines()), 1):
        if '\t' in raw or (clean.strip() and
                (len(raw.rstrip()) > 100 or (len(clean) - len(clean.lstrip())) % 4)):
            errors.append(f'{path}:{line_number}: style')
print('\n'.join(errors))
print(f'SV style: {len(paths)} files, {len(errors)} warnings')
sys.exit(bool(errors))
PY
```

复现完整环境 lint：

```sh
python3 - <<'PY'
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, 'tools')
from regress import expand_files
subprocess.run(['verilator', '--lint-only', '--timing', '-Wall',
                '--timescale', '1ns/1ps', '--top-module', 'edrv32_pix_stub_tb'] +
               expand_files(Path('verif/block/pix/stub.f')), check=True)
PY
```

结果退出码 0、0 告警，所有功能激励/检查 task 均完成 elaboration。
`lint.vlt` 仅豁免行为环境的阻塞更新、Verilator 5.020 对 class 字段的未使用误报、整数
切片、共享 APB 未用槽、桩未用输入、复位采样的同步/异步混用，以及 include 文件中的
class 文件名。真实 RTL 的位宽、组合环、连接、锁存器等告警保持启用。

V-I2 合入真实 RTL 后运行正式 smoke/full，确认编译及 smoke 总时长不超过约 60 秒：

```sh
make smoke REGRESS_ARGS='-j 1 --path verif/block/pix'
make full REGRESS_ARGS='-j 1 --path verif/block/pix'
```

可用 `build/pix/dut/obj/sim +CASE=N +DIR=...` 重放对应 `build/pix/dut/PX-NN` 场景。
输入、配置和期望图均已由 runner 生成，不在仿真期间调用外部模型。

## 协调澄清

经 ask 确认并已纳入：

1. APB 端口与 VIN 相同：`apb_paddr_i/psel_i/penable_i/pwrite_i/pwdata_i/pstrb_i`、
   `apb_prdata_o/pready_o/pslverr_o`；`pready` 恒 1，`pslverr` 恒 0。
2. PX-08 smoke/full 尺寸分别为 9 种和 20 种完整组合。
3. 不完整帧在 `valid && sof` 出现时丢弃，不要求该 SOF 已握手；丢弃/复位期间 READY=0。
   如果挂起 SOFT_RST，丢弃后先复位，再接收持续保持的 SOF。
4. PX-13 增加上述不完整帧挂起复位子场景；新帧按复位配置直通，PERF3 和 CFG 等清零。
   此场景通过持续正规 APB CFG 读和外部 READY 观察复位先于新 SOF 握手，不观察内部状态。
