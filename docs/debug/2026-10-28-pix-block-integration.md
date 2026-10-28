# PIX 模块联调与 VIN + PIX VI-18

## 1. 现象

起点为 `9e56d4e`（已包含 PIX RTL、独立模块验证及 VIN 验证方案 v0.2）。
初轮 PIX smoke：1 PASS、1 FAIL；full：1 PASS、2 FAIL。
三个失败条目均在 PX-13 仿真退出码 −11 处终止，无像素或寄存器比较失败：
smoke 为 `block/pix`，full 为 `block/pix/full` 和再次运行 smoke 内容的 `block/pix`。
PX-01–04、06、08 小尺寸、09、10、12 在失败之前通过。

## 2. 复现

环境：Linux，Verilator 5.020，Python 3，先执行
`. ~/.local/opt/edrv32/env.sh`。所有回归使用 `-j 1`，同一时刻只运行一个仿真。

```sh
make smoke REGRESS_ARGS='-j 1 --path verif/block/pix'
make full REGRESS_ARGS='-j 1 --path verif/block/pix'
build/pix/dut/obj/sim +CASE=13 +DIR="$PWD/build/pix/dut/PX-13"
```

初轮汇总：`build/pix/integration/smoke-initial.log`、
`build/pix/integration/full-initial.log`。
`build/pix/dut/PX-13/run.log` 崩溃时为空，后被通过的复测覆盖。
诊断构建使用相同文件列表，另外添加 `--assert`、
`-CFLAGS '-O0 -g -fsanitize=address' -LDFLAGS -fsanitize=address`，
`--Mdir "$PWD/build/pix/asan"`。原始诊断为
`build/pix/asan-compile.log`、`build/pix/asan-run.log`。

## 3. 观察

AddressSanitizer 报告 `heap-use-after-free`：
`VlForkSync::done` 内联恢复父协程；父协程再次调用同一 `VlForkSync::init`，
释放仍在使用的父协程后访问它。生成代码位置为
`Vedrv32_pix_tb_edrv32_pix_tb__DepSet_hf9b076f9__0.cpp:12753–12754`。
PX-13 的不完整帧与挂起复位后的新 SOF 相邻，旧 fork 完成到新 fork 启动之间没有时序等待。

## 4. 根因和定性

此问题定性为**测试错误（验证环境/仿真器兼容）**，不是 RTL 违反规格，也不是规格歧义。
`environment.svh` 的逐帧循环重用同一个 fork/join；Verilator 5.020 在 join 完成时
立即恢复父协程，同一调用栈内重新初始化同步对象导致释放后使用。

VI-18 开发时的首轮 lint 定性为**测试错误**：Verilator 5.020 不支持将
`$readmemh` 的加载目标直接写成多维数组切片 `image[f]`；改为先加载一维局部数组再复制。
共享 APB 未使用槽显式驱动为 0，相机 1 未刺激导致的模型 `transmitting` 未使用告警
只在 VI-18 本地 lint 配置中按行为环境豁免；最终三个正式顶层 lint 均为 0 告警。

额外对未修改的三个 PIX 单元 harness 直接使用 `-Wall`，会报告行为测试的 BLKSEQ、
同步采样异步复位的 SYNCASYNCNET、局部形参重名和未使用整数高位；定性为既有测试
lint 配置问题，不是 DUT 错误。本任务指定的零告警 lint 对象为 edrv32_pix、PIX block、
VI-18，三者均通过；未扩展修改既有单元测试，按原 YAML 完成两档验收。

## 5. 修复

- `environment.svh` 的 join 后添加 `#1`，让当前 fork 完成回退后再进入下一轮；
  只改变测试进程调度，不改变时钟边沿上的输入握手和性能判据。
- 在 PX-10、PX-11 通过原有检查时打印实测周期和上限，保留原判据。
- 真实 RTL smoke 通过后删除无 YAML 引用的 `stub.f`、
  `edrv32_pix_passthrough_stub.sv`、`edrv32_pix_stub_tb.sv`；
  runner、环境和 README 同步移除桩路径。
- VI-18 在 `verif/block/vin/pix_integration/` 独立增加，既有 VI-01–17 文件和行为不变。
  文件列表以 `-f` 引入 VIN、PIX 真实 RTL，复用 VIN AXI RAM、APB 接口、协议检查器、DVP 模型。
  64×16 摄像头帧和内存源帧均经过高斯、Sobel、二值化和反色；Python
  `verif/block/pix/pix_ref.py:process` 逐帧生成期望值，DDR 逐像素比较。
  摄像头帧接收至少 96 字、PIX BUSY 时写 VIN ABORT，检查无完成报告、事务排空；
  随后的正确帧复用被中止的槽，PIX PERF3 增加 1。

## 6. 防回归与验收

PX-13 保留完整六帧场景（含不完整帧中挂起 SOFT_RST 后保持下一 SOF），
未删减任何寄存器、像素或时序检查。
测试修复及桩清理提交 `6d9ec39`，VI-18 提交 `97d3c72`；
最终回归基于 `97d3c72`，后续提交仅补本文档。

PX-10：256 个输入字在连续 256 个周期握手，满足每拍 2 像素；
随机流控下像素、负载保持及精确 PERF1/2 检查均通过。
PX-11：两帧均为 1288 周期，上限 `2 × 1280/2 + 32 = 1312`，
提前 24 周期完成冲刷；上一帧输出 EOF 之前不接收下一 SOF。
原始数据为 `build/pix/dut/PX-10/run.log`、`build/pix/dut/PX-11/run.log`。

| 命令（先加载环境） | 结果 |
|---|---|
| `make smoke REGRESS_ARGS='-j 1 --path verif/block/pix'` | 2 PASS、0 FAIL；最终冷构建 30 秒（首次修复后 31 秒） |
| `make full REGRESS_ARGS='-j 1 --path verif/block/pix'` | 3 PASS、0 FAIL；full 25 个场景 226 秒，重跑 smoke 2 秒 |
| `make smoke REGRESS_ARGS='-j 1 --path verif/block/vin/pix_integration'` | 1 PASS、0 FAIL；最终冷构建 26 秒，已编译时 1 秒 |
| `make smoke REGRESS_ARGS='-j 1 --path verif/block/vin'` | 3 PASS、0 FAIL；含 VI-18 和原有 11 个 VI smoke 项 |
| `make smoke REGRESS_ARGS='-j 1 --path verif/unit/pix_control'` | 1 PASS、0 FAIL；57 秒 |
| `make full REGRESS_ARGS='-j 1 --path verif/unit/pix_control'` | 1 PASS、0 FAIL；58 秒 |
| `make smoke REGRESS_ARGS='-j 1 --path verif/unit/pix_filter'` | 1 PASS、0 FAIL；13 秒 |
| `make full REGRESS_ARGS='-j 1 --path verif/unit/pix_filter'` | 1 PASS、0 FAIL；14 秒 |
| `make smoke REGRESS_ARGS='-j 1 --path verif/unit/pix_point'` | 1 PASS、0 FAIL；24 秒 |
| `make full REGRESS_ARGS='-j 1 --path verif/unit/pix_point'` | 1 PASS、0 FAIL；22 秒 |

VI-18：摄像头 src0/slot0、内存源 src2/slot1、ABORT 后 src0/slot2 恢复帧全部通过，
终止时刻 254,488 ns。中止帧没有 PIX EOF 或 VIN FRAME，保留的完成状态不变，
下一帧复用 slot2，PIX PERF3 从 0 增为 1，完整帧计数为 3。
记录为 `build/vin_pix/run.log`。

既有 VIN 正式目录实测含构建 216 秒：从 compile.log 创建到关闭约 138.6 秒，
从 run.log 创建到关闭约 77.8 秒（分别为 10:31:26.634916–10:33:45.191206 UTC、
10:33:45.230207–10:35:02.986519 UTC）；selftest 含构建 12 秒。
经 Orca ask，协调者明确确认：60 秒含构建要求仅针对本任务新增或修改的目录，
既有 VIN 的 test.yaml/档位保持原样，冷编译和执行时间如实单列，档位由里程碑回归决定。
因此未移动任何既有 VIN 测试。原始汇总为 `build/pix/integration/vin-smoke.log`。

最终删除 `build/pix/dut/obj` 和 `build/vin_pix/obj` 后串行重跑 smoke，
PIX 为 30 秒，VI-18 为 26 秒，模型自测为 0 秒，均满足约 60 秒含构建要求。
对应汇总为 `build/pix/integration/pix-smoke-cold-final.log`、
`build/pix/integration/vi18-smoke-cold-final.log`。本任务无移至 full 的测试目录。
没有超过半小时才定位的问题；本记录集中记录全部联调结论。

PIX 最终 smoke/full 汇总为 `build/pix/integration/pix-smoke-final.log`、
`build/pix/integration/pix-full-final.log`。
六次单元回归汇总为 `build/pix/integration/pix_{control,filter,point}-{smoke,full}.log`，
详细编译和运行日志为 `build/regress/{smoke,full}/unit/pix_*/verilator/`。

风格和 lint：`python3 tools/check/verilog_style.py rtl/media/pix`
为 6 文件、0 告警；修改目录的 4 个 SV/SVH 按同工具的头注释、100 列、4 空格和
Tab 规则检查为 0 告警。三个正式顶层的 lint 复现如下（不关闭 DUT 告警）：

```sh
python3 - <<'PYCODE'
from pathlib import Path
import subprocess
import sys
sys.path.insert(0, 'tools')
from regress import expand_files
for top, file in [('edrv32_pix', 'rtl/filelists/pix.f'),
                  ('edrv32_pix_tb', 'verif/block/pix/files.f'),
                  ('edrv32_vin_pix_tb', 'verif/block/vin/pix_integration/files.f')]:
    subprocess.run(['verilator', '--lint-only', '--timing', '-Wall',
                    '--timescale', '1ns/1ps', '--top-module', top,
                    '+define+SIM_MODE', *expand_files(Path(file))], check=True)
PYCODE
```

三者退出码均为 0，0 告警。SV 风格检查复现：

```sh
python3 - <<'PYCODE'
from pathlib import Path
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, 'tools/check')
from verilog_style import without_comments
paths = [p for root in ('verif/block/pix', 'verif/block/vin/pix_integration')
         for p in Path(root).rglob('*') if p.suffix in ('.sv', '.svh')]
errors = []
for path in paths:
    text = path.read_text()
    header = '\n'.join(text.splitlines()[:12]).lower()
    for label in ('file', 'spec', 'description', 'clock'):
        if label not in header:
            errors.append(f'{path}: missing {label}')
    for n, (raw, clean) in enumerate(
            zip(text.splitlines(), without_comments(text).splitlines()), 1):
        if '\t' in raw or (clean.strip() and
                (len(raw.rstrip()) > 100 or (len(clean)-len(clean.lstrip())) % 4)):
            errors.append(f'{path}:{n}: style')
print('\n'.join(errors))
print(f'SV style: {len(paths)} files, {len(errors)} warnings')
sys.exit(bool(errors))
PYCODE
```

## 7. 同类排查

PX-12 的三种不完整位置及 PX-14 随机不完整帧使用同一逐帧执行路径，
因此都覆盖 join 后再次进入下一帧的调度。RTL 未增加任何防御逻辑、兜底或特殊处理。
