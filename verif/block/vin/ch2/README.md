# VIN CH2 独立模块级验证（B2-1c）

依据 `vin-spec.md` v0.2 第 2.4、2.6–2.9、4、5.1、6 节和
`vin-testplan.md` v0.3 的 VI-19–23、VI-15 CH2 部分实现。
开发基线为 `729338d`，测试提交为本报告所属提交；未阅读 `rtl/media/vin/` 的实现。
只复用了既有公开端口连接、DVP 模型、AXI RAM、APB 接口和协议检查器。

## 测试项与目录

| 项 | 目录 / 入口 | 档位 | 检查 |
|---|---|---|---|
| VI-15 CH2 | `../edrv32_vin_tb.sv::vi15()`，`../test.yaml`、`../full/test.yaml` | smoke/full | CH2 全寄存器复位、CTRL/SLOT_BUSY 读写、STRIDE/BASE 对齐、RO/保留偏移、SOFT_RST 后复位 |
| VI-19 | `full/`，`edrv32_vin_ch2_tb.sv::vi19()` | full | cam0 同送 CH0/CH2，三帧三槽，两通道逐字节比对和相同 frame_id；CH2_FRAME、DONE_INFO、PERF5、最后 B 后完成 |
| VI-20 | `full/`，`::vi20()` | full | 内存源同送 CH0/CH2，逐字节结果、相同 frame_id、读 DONE、持续 RREADY |
| VI-21 | `full/`，`::vi21()` | full | (a) cam0 只开 CH2；(b) 内存源只开 CH2；(c) cam0 同送 CH0/CH2；全程停止 P1 写，检查丢帧、计数、无完成、排空、下帧原槽恢复 |
| VI-22 | `test.yaml`、`full/`，`::vi22()` | smoke/full | 64×8 cam0，CH2 配置错误 8/PERF15，无 CH2 写或完成，同源 CH0 正确 |
| VI-23 | `full/`，`::vi23()` | full | 全槽占用跳帧、帧中改 SLOT_BUSY、下一帧采样；成功槽序列 0/1/2/0、PERF11、源 frame_id 包含跳过帧 |
| 参考模型 / harness 自测 | `selftest/` | smoke/full | 整数参考模型自测、DVP 像素计数、RAM 字节序、CH0/CH2 完整逐字节及行间空隙比对 |

新增三个 `test.yaml` 都显式指定 `group: verif/block/vin`，与既有 VIN 测试串行运行。
正式测试使用真实 `rtl/filelists/vin.f`，只有 `selftest/files.f` 使用既有接口桩。
接口桩不实现 VIN 功能，selftest 不构成真实 CH2 功能通过证据。

VI-21 按协调者问答修改后的方案（`729338d`）实现：共享 P1 无法仅阻止内部
CH2 仲裁授权，采用公共 AWREADY/WREADY 停止的三种场景，不增加 wrapper 或层次引用。
场景 (b) 在写停止期间等待内存源 DONE，同时持续检查 RREADY，验证 CH2 不暂停源。
场景 (c) 检查两个溢出计数；最近错误代码由先后顺序决定，不假定固定的最后错误通道。

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

**当前尚未合入 CH2 RTL，VI-19–23 和修改后的 VI-15 未运行功能回归。**
协调者已明确要求本轮先交付测试，真实 RTL 联调另行安排；届时应执行：

```sh
python3 tools/regress.py smoke -j 1 --path verif/block/vin
python3 tools/regress.py full -j 1 --path verif/block/vin
```

新增 runner 生成数据后以 `-Wall -j 1 -CFLAGS -O0` 编译，不重试或替代失败结果。
full 二进制可用 `+DIR=<绝对 build/vin_ch2/full 路径> +CASE=19`（至 23）定位单项。
`+CASE=smoke` 只跑 VI-22，`+CASE=full` 跑 VI-19–23。

## 修改的文件

`../edrv32_vin_tb.sv` 仅修改 VI-15 的 CH2 寄存器部分；本目录新增
`reference.py`、`crosscheck.py`、`run.py`、`edrv32_vin_ch2_tb.sv`、`support.f`、
`files.f`、`test.yaml`、`full/{files.f,test.yaml}`、`selftest/{files.f,test.yaml}` 和本报告。
