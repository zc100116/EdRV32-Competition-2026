# VIN CH2 独立模块级验证（B2-1c）

依据 `vin-spec.md` v0.3 第 2.4、2.6–2.9、4、5.1、6 节和
`vin-testplan.md` v0.4 的 VI-19–23、VI-15 CH2 部分实现。
开发基线为 `729338d`，测试提交为本报告所属提交；未阅读 `rtl/media/vin/` 的实现。
只复用了既有公开端口连接、DVP 模型、AXI RAM、APB 接口和协议检查器。

## 测试项与目录

| 项 | 目录 / 入口 | 档位 | 检查 |
|---|---|---|---|
| VI-15 CH2 | `../edrv32_vin_tb.sv::vi15()`，`../test.yaml`、`../full/test.yaml` | smoke/full | CH2 全寄存器复位、CTRL/SLOT_BUSY 读写、STRIDE/BASE 对齐、RO/保留偏移、SOFT_RST 后复位 |
| VI-19 | `full/`，`edrv32_vin_ch2_tb.sv::vi19()` | full | cam0 同送 CH0/CH2，三帧三槽，两通道逐字节比对和相同 frame_id；CH2_FRAME、DONE_INFO、PERF5、最后 B 后完成 |
| VI-20 | `full/`，`::vi20()` | full | 内存源同送 CH0/CH2，逐字节结果、相同 frame_id、读 DONE、持续 RREADY |
| VI-21 | `full/`，`::vi21()` | full | (a)(c) 摄像头有效数据溢出及恢复；(b) 内存源 CH2 长停顿反压；(d) 上补齐停顿 1500 周期；(e) 内存源 CH0+CH2 全速逐字节比较 |
| VI-22 | `test.yaml`、`full/`，`::vi22()` | smoke/full | 64×8 cam0，CH2 配置错误 8/PERF15，无 CH2 写或完成，同源 CH0 正确 |
| VI-23 | `full/`，`::vi23()` | full | 全槽占用跳帧、帧中改 SLOT_BUSY、下一帧采样；成功槽序列 0/1/2/0、PERF11、源 frame_id 包含跳过帧 |
| 参考模型 / harness 自测 | `selftest/` | smoke/full | 整数参考模型自测、DVP 像素计数、RAM 字节序、CH0/CH2 完整逐字节及行间空隙比对 |

新增三个 `test.yaml` 都显式指定 `group: verif/block/vin`，与既有 VIN 测试串行运行。
正式测试使用真实 `rtl/filelists/vin.f`，只有 `selftest/files.f` 使用既有接口桩。
接口桩不实现 VIN 功能，selftest 不构成真实 CH2 功能通过证据。

VI-21 按 `vin-testplan` v0.4 实现五种公开接口情形，不读取内部 FIFO 或选路状态：

- (a)(c)：摄像头有效行到达时长时间停止 P1 写，继续检查丢帧、计数、排空、
  槽复用与下一帧恢复；摄像头源始终不被反压。
- (b)：只开内存源 CH2，停止写 20000 周期后检查无溢出、MSRC_BUSY；再等待
  4096 周期检查 AR 计数保持，证明源暂停。RREADY 始终为 1；恢复写后逐字节
  比较整帧、检查最后 B 后完成和内存源 DONE。
- (d)：cam0 只开 CH2，用公开 PERF0 观察 SOF，停止写 1500 个 clk_mem 周期，
  该窗口早于第一行有效缩放结果。检查上补齐不因满 FIFO 而溢出，恢复后比较整帧。
- (e)：内存源同送 CH0/CH2，P1 不添加停顿，比较两通道整帧和相同 frame_id，
  检查 CH0/CH2 溢出计数均为 0。

## 参考模型

`reference.py` 只用 Python 标准库，由源图像直接计算输出，不依赖 RTL：

1. R/B 五位展开为 `(v << 3) | (v >> 2)`，G 六位为 `(v << 2) | (v >> 4)`。
2. 每个 2×2 块对展开后的每个通道执行 `(sum + 2) >> 2`。
3. 量化采用整数式 `(254*c + 255) // 510`。
4. 第 0–11、372–383 行填字节 `57,57,57,0`；有效区为 640×360。
5. 按 DDR 地址升序写 `R,G,B,0`，即 32 位字 `{0,B,G,R}`，每行 2560 字节。

三种 full 输入包括逐像素变化的异或图案、RGB565 分量渐变，以及以 2×2 块排列的
黑/白/红/绿/蓝和中间色。期望文件每行一个小端 32 位 C4 字，testbench 仍逐字节比对，
并检查每行额外 32 字节 stride 空隙保持 RAM 初值 `0xA5`。
比较失败打印测试编号、通道、槽、行、行内字节、地址、期望、实际值和仿真时刻。

参考模型自测逐个检查 256 个量化输入（用 `Fraction` 的精确有理数 `round` 交叉核对），
全部 R/B 和 G 展开值、已知颜色/四点平均，以及整张红色图的 384 行数据和补齐边界。
不修改模型以追随离线工具或 RTL 的结果。

## 与 NPU 离线工具交叉核对

命令：

```sh
git submodule update --init third_party/ultralytics
~/.local/opt/edrv32-py/bin/python verif/block/vin/ch2/crosscheck.py
```

输入为 `reference.image(0)` 的完整 1280×720 RGB565 图像，逐点按规格展开为 RGB8，
无损保存 PNG 后交给真实的 `tools/npu/input_pack.py::pack()`。
该函数调用 `quantize.prepare_image()` 的 OpenCV `INTER_LINEAR`、居中补 114，
再用 `torch.round(normalized * 127)` 和 `format.pack_c4()`。

结果：**983,040 字节，逐字节差异 0，最大绝对差 0**，包括上下补齐和第四字节。
没有需列出的差异或舍入边界例外。
Python 3.12.3，OpenCV 5.0.0，NumPy 2.5.2，torch 2.14.1+cpu；
ultralytics 子模块 commit `9d25f80daa5b3af71c16521eba353cb6e7fb66e2`。
原始输入、两份二进制和完整差异位置表在 `build/vin_ch2_crosscheck/`
（`source.png`、`integer.bin`、`npu.bin`、只有标题行的 `differences.tsv`、`run.log`）。
生成物不入库；crosscheck 脚本未引入新依赖。

## 验证命令与状态

Linux，Verilator 5.020，编译和仿真均使用单任务，无 `--parallel`。

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/check/verilog_style.py verif/block/vin
python3 tools/regress.py smoke -j 1 --path verif/block/vin/selftest
python3 tools/regress.py smoke -j 1 --path verif/block/vin/ch2/selftest
```

自测输出 `PASS CH2 reference`、`PASS CH2 harness selftest (no VIN functional result)`。
既有 VIN selftest 和新增 CH2 selftest 各为 `Summary: 1 PASS, 0 FAIL`、退出码 0。
日志在 `build/vin_ch2/selftest/{compile,run}.log` 和
`build/regress/smoke/block/vin/{selftest,ch2/selftest}/verilator/`。
风格工具只扫描 `.v/.vh`，所以 VIN 目录为 0 文件、0 告警；另按第 7 节检查新增
SV/Python 的文件头、非注释行 100 列、四空格缩进、Tab，及 SV 例化的显式端口连接。

完整 testbench 的 lint（默认参数，包含所有功能场景）可复现为：

```sh
python3 - <<'PY'
from pathlib import Path
import subprocess
import sys
sys.path.insert(0, 'tools')
from regress import expand_files
for top, files in [
    ('edrv32_vin_ch2_tb', 'verif/block/vin/ch2/selftest/files.f'),
    ('edrv32_vin_ch2_tb', 'verif/block/vin/ch2/files.f'),
    ('edrv32_vin_tb', 'verif/block/vin/files.f'),
]:
    subprocess.run(['verilator', '--lint-only', '--timing', '-Wall',
                    '+define+SIM_MODE', '--top-module', top,
                    *expand_files(Path(files))], check=True)
PY
```

三份 lint 均通过，0 告警，日志 `build/{ch2-stub,ch2-rtl,vin-rtl}-lint.log`。
复用既有 `../lint.vlt` 的验证环境豁免，未新增告警屏蔽。
完整 CH2 功能 testbench（`HARNESS_SELFTEST=0`）也以真实 VIN 基线的文件列表完成
`--binary --timing -Wall -j 1 -CFLAGS -O0` 编译和链接，退出码 0、0 告警，未运行。
编译日志为 `build/vin_ch2/elaborate/compile.log`。

原 B2-1c 的 v0.2 联调已完成，见
`docs/debug/2026-10-29-vin-ch2-integration.md`；v0.3 的追加验证记录见文末。
完整目录的回归入口仍为：

```sh
python3 tools/regress.py smoke -j 1 --path verif/block/vin
python3 tools/regress.py full -j 1 --path verif/block/vin
```

runner 生成数据后以 `-Wall -j 1` 编译，full 使用 `-CFLAGS -O1`，
smoke/selftest 使用 `-O0`，不重试或替代失败结果。
full 二进制可用 `+DIR=<绝对 build/vin_ch2/full 路径> +CASE=19`（至 23）定位单项。
`+CASE=smoke` 只跑 VI-22，`+CASE=full` 跑 VI-19–23；
`+CASE=21a` 至 `21e` 分别定位五个子场景，`+CASE=21` 运行全部五项。
runner 的第二个参数也可选择子场景，例如 `python3 verif/block/vin/ch2/run.py full 21b`。

## 修改的文件

`../edrv32_vin_tb.sv` 仅修改 VI-15 的 CH2 寄存器部分；本目录新增
`reference.py`、`crosscheck.py`、`run.py`、`edrv32_vin_ch2_tb.sv`、`support.f`、
`files.f`、`test.yaml`、`full/{files.f,test.yaml}`、`selftest/{files.f,test.yaml}` 和本报告。


## v0.3 反压追加验证（B2-1d）

用户通过协调者确认 VIN v0.3（规格提交 `6537bc8`），追加测试提交 `48b3cb9`。
测试在独立验证分支编写，未读取被测 RTL。旧 RTL 的失败证据和修复后结果将分别
记录；旧 RTL 结果不能作为 v0.3 通过证据。

### 修复前：v0.2 RTL

测试源码提交 `48b3cb9`，Verilator 5.020，`-Wall -j 1 -CFLAGS -O1`。
先用 runner 生成参考数据、构建并运行 (b)，再复用同一二进制逐项运行 (d)(e)：

```sh
. ~/.local/opt/edrv32/env.sh
python3 verif/block/vin/ch2/run.py full 21b
build/vin_ch2/full/obj/sim +DIR=$PWD/build/vin_ch2/full +CASE=21d
build/vin_ch2/full/obj/sim +DIR=$PWD/build/vin_ch2/full +CASE=21e
```

| 子场景 | v0.2 实测 | 现象 |
|---|---|---|
| VI-21b | FAIL | 仿真 160.760 µs，PERF8（0x060）期望 0、实际 1 |
| VI-21d | FAIL | 仿真 77.291568 ms，PERF8（0x060）期望 0、实际 1；已丢弃前两帧并在第三帧 SOF 后停写 1500 周期 |
| VI-21e | PASS | 两通道整帧、frame_id、溢出计数检查均通过；单次仿真墙钟 16.92 s |

(b)(d) 的进程退出码非零，均直接在无溢出断言处失败；没有删除或放宽该断言。
(e) 的实测与“旧 RTL 预期失败”的预估不同：现有 `edrv32_vin_memory` 在无停顿时
可独立并行接收写拍和返回读拍，不模拟 SoC DDR 的共享数据线和命令延迟。
该模型下 (e) 不复现 SC-05 默认 DDR 时序模型下的溢出；保留原判据和无停顿激励，
不为制造失败而添加停顿。SC-05 的实际失败见
`docs/debug/2026-10-29-soc-sc05-ch2-overflow.md`。

原始证据：`build/vin_ch2/flow/old-21{b,d,e}.log`，(b) runner 日志
`build/vin_ch2/flow/old-21b-runner.log`。`old-sim` 是该次修复前二进制的保留副本；
生成物不入库。提交 `4ac07cd` 随后把五个子场景分到独立定时进程，避免把全部
大型逐字节记分板展开到同一个 C++ 协程；不改变激励或判据，lint 为 0 告警。
