# V-T2 DISP 独立模块验证结果

日期：2026-10-28。RTL/规格基线：`b65fa64`；接收模型提交：`8c08c52`；
模块测试与 Python 参考提交：`820c2d8`。
依据 DISP v0.2、DISP testplan v0.1 及协调者对 VS 行界和停止确认相位扫描的答复。
未打开 DISP RTL 源码文件，未修改 `rtl/`、`docs/` 或 `verif/common/`。

## 命令与结果

先执行 `. ~/.local/opt/edrv32/env.sh`。工具：Verilator 5.020、Python 3.12.3。
每次编译 `-j 1`，本任务的仿真进程串行运行。正常时钟为 clk_mem 125 MHz、
clk_pix 74.25 MHz；DS-13 按 seed 改变频率比和初始相位。

| 命令 | 结果 | 原始日志 |
|---|---|---|
| `make smoke REGRESS_ARGS='-j 1 --path verif/unit/tmds_rx_model'` | 1 PASS，0 FAIL | `build/regress/smoke/unit/tmds_rx_model/verilator/run.log` |
| `make smoke REGRESS_ARGS='-j 1 --path verif/block/disp'` | 12 个仿真实例 PASS，0 FAIL | `build/regress/smoke/block/disp/verilator/run.log` |
| `make full REGRESS_ARGS='-j 1 --path verif/block/disp'` | 29 个仿真实例 PASS，0 FAIL（两个 YAML 测试组通过） | `build/regress/full/block/disp/full/verilator/run.log`、`build/regress/full/block/disp/verilator/run.log` |

smoke 的 12 个实例：DS-01、DS-03 的两种 stride、DS-04/05/06/07/11/12，
以及 DS-12 的三个停止相位。full 新增 17 个实例：DS-02/08/09/10、
DS-10 的三个停止相位、DS-13 的 10 个 seed（1–10）。
统一回归把 smoke 记为一个 YAML 测试组，把 full 记为两个 YAML 测试组。

全部单例的详细输出在 `build/disp/DS-*.log`，编译日志在 `build/disp/compile.log`。
Python 生成的 `build/disp/tmds.hex` 正好有 1,237,500 行，DS-02 逐符号比对整帧，
包含三个通道的运行差异和全部消隐控制符号。

## 测试项实现位置

以下行号对应 `820c2d8`，路径前缀为 `verif/block/disp/`。

| 项 | 实现位置 | 结果 |
|---|---|---|
| DS-01 | `tb.sv:298` 时序/像素监视器；`tb.sv:587` 两帧激励 | PASS |
| DS-02 | `tmds_ref.py:13` 编码、`:45` 整帧生成；`tb.sv:298` 逐符号比较；`:592` 激励 | PASS |
| DS-03 | `tb.sv:214` AR 行地址/顺序检查；`:298` 每像素比对；`:592` 激励，stride 2560/4096 | 两种 stride PASS |
| DS-04 | `tb.sv:610` 帧中/消隐中切换、重复帧、FRAME/SWITCH/REL_BASE/CUR_BASE/计数 | PASS |
| DS-05 | `tb.sv:644` ENABLE、关闭、IDLE；`:298` 使能前后黑色/完整帧 | PASS |
| DS-06 | `tb.sv:195` 随机 AR/R 驱动；`:214` RREADY、行容量界限、outstanding；`:592` 激励 | PASS |
| DS-07 | `tb.sv:661` 跨帧停顿、未扫描帧中还欠账、重新使能；`:298` 黑组/对齐；`:439` PERF | PASS |
| DS-08 | `tb.sv:661` 保持使能的跨帧停顿、请求积压；`:214` 前帧读完才发后帧；PERF4=1 | PASS |
| DS-09 | `tb.sv:693` 强制已知低/高水位；`:214` urgent；`:439` PERF3 精确周期计数 | PASS |
| DS-10 | `tb.sv:708` 帧中 ABORT；`:466` 三相位停止；`:431` IDLE/事务排空 | 普通及三相位 PASS |
| DS-11 | `tb.sv:195` SLVERR 注入；`:592` ERR_CODE/IRQ/RW1C；`:298` 数据照常显示 | PASS |
| DS-12 | `tb.sv:501` 复位值/对齐/PSTRB/RO/保留/START；`:725` SOFT_RST/基线；`:466` 三相位停止 | 普通及三相位 PASS |
| DS-13 | `tb.sv:754` 10 seed、每 seed 六帧随机区间；`:195` AXI 随机；`:298` 输出参考检查 | seed 1–10 全部 PASS |

独立接收模型是 `verif/models/tmds_rx_model.sv`，其自测在
`verif/unit/tmds_rx_model/tb.sv`：穷举字节序列、四种控制符号、B/G/R 通道顺序、
跨消隐的数据序列和 1024/12 像素帧收集均通过。

## 关键观测与边界

- DS-07：读了 3 帧，黑组 47,520 个，读空帧 1 个；PERF1/2 与这些观测逐项一致。
  停顿跨越帧边界，迟到数据在未扫描帧内偿还欠账，之后被扫描的一整帧无新黑组。
- DS-08：读了 4 帧，黑组 65,087 个，读空帧 2 个，PERF4 恰为 1；恢复后位置正确。
- DS-10 和 DS-12 的相位为相对可见 VBlank 开始的 -8、-2、+4 个像素周期。
  两项都分别观测到 0、1、1 个临界请求；首次 IDLE 后再观察完整一帧，ARVALID 始终为 0。
  SOFT_RST 寄存器和全部 PERF 保持复位值，未发生回弹。
- 精确内部 FIFO 水位不从 RTL 层次读取。按协调者许可，行预留用外部占用量下界检查，
  保留 8 beat 的 CDC/编码延迟边界；urgent 在 64/96 beat 的明确区域检查。
  已出现黑组后的偿还窗口由黑组和首个恢复的非黑组界定，期间持续检查所有非黑像素的
  原始位置及完整 16 像素黑组；下一扫描帧完整正确。内部精确阈值由已有 RTL 单元测试承担。

## Lint 与风格

单元模型和模块环境的 `verilator --lint-only --timing -Wall` 都退出 0，日志均为空：
`build/disp/unit-lint.log`、`build/disp/lint.log`。编译也启用 `-Wall`，告警按错误处理。
行为环境采用的告警分类豁免与理由见 `README.md`：`BLKSEQ`、`UNUSEDSIGNAL`、
`SYNCASYNCNET`；未豁免位宽、锁存器或连接错误。默认 timescale 用 `--timescale 1ns/1ps`。

模型 lint 可复现为：

```sh
verilator --lint-only --timing -Wall --top-module tb \
    -Wno-BLKSEQ -Wno-UNUSEDSIGNAL \
    verif/models/tmds_rx_model.sv verif/unit/tmds_rx_model/tb.sv
```

模块环境 lint 可复现为：

```sh
python3 - <<'PY'
import subprocess
import sys
from pathlib import Path
sys.dont_write_bytecode = True
sys.path.insert(0, 'tools')
from regress import expand_files
subprocess.run([
    'verilator', '--lint-only', '--timing', '-Wall', '--timescale', '1ns/1ps',
    '-Wno-BLKSEQ', '-Wno-UNUSEDSIGNAL', '-Wno-SYNCASYNCNET', '--top-module', 'tb',
    *expand_files(Path('verif/block/disp/files.f')),
], check=True)
PY
```

`tools/check/verilog_style.py` 对归属目录退出 0（该脚本只处理 `.v/.vh`，本任务均为 `.sv`）。
另检查三个新增 SV 文件的 100 列、无 Tab、四空格缩进，0 告警，记录在
`build/disp/sv-format.log`；已人工检查文件头、逐信号声明和命名端口连接。

## 失败归因与 ask

最终失败项：无；未解决的 RTL 错误或规格歧义：无。开发中的测试失败已修正：plusarg 读取写法、
HS 定义的垂直行界、TMDS 编码流水线下 PERF 快照的采样时刻，以及已存在欠账时的
FIFO 可用数据界限；均未通过修改 RTL 处理。

三次 ask 均已答复，无待回复问题：

1. 黑盒下不能直接读 FIFO 精确水位/empty；协调者同意用返回 AXI beat、图案/黑组推导
   欠账与对齐，水位检查明确上下界，PERF3 每 mem 周期精确统计，并允许现在串行运行本任务仿真。
2. 规格 2.1 的 VS 行内相位未写明；协调者确认 VS 与 HS 前沿对齐，以首个 DE 像素为原点时，
   VS 在 (1390,724) 上升并持续五行；已据此检查全部时序和 Python 符号。
3. 验证方案 v0.1 未明确覆盖规格 v0.2 第 2.8；协调者批准在 DS-12 内增加停止相位扫描，
   并要求 DS-10 同样覆盖，允许 0/1 个临界请求、完整排空、IDLE 后无 AR 和寄存器不回弹。
