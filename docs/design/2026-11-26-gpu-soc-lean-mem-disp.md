# GPU SoC 的精简 mem_xbar 与 L0 DISP

## 背景和问题

卡 107 第 9 轮全片 LUT 116.2k（73%），布线余量不足。GPU 项目流量不需要视觉
项目的分级流量调控；界面由 GPU 合入 L0，独立 L1 扫描与混合不再使用。
本次依据已确认的 `gpu-soc-spec.md` v0.3（6.2、8.2、8.3）及
`gpu-soc-testplan.md` v0.3（ST-01～ST-07）实施 S-8。

## 约束

只修改 GPU 专用版本；视觉 RTL、规格、测试、软件及共享驱动保持原版本。
W 缓冲、B FIFO、读返回缓冲的 credit 预留与按序释放、违规事务响应保持原行为。
不增加 IP、兜底或额外保护。SoC 顶层端口不变。

## 可选方案

- 原多级调度与双层扫描：保留已有功能和对应资源，但 GPU 项目不使用这些功能。
- 按 v0.3 精简：固定在途数，删除调度参数和统计；DISP 只保留 L0。
  同口径 Yosys 测得两个顶层合计减少 11615 LUT6、4434 FF，见下表。

## 决策

mem_xbar 每次授权依次选择紧急 P0、紧急 P1、CPU P2，然后在 P0/P1/P3/P4
间按事务轮转。只有轮转授权推进轮转指针；被容量或 credit 阻塞的队首不参与。
同端口读写都可授权时选择该端口上次授权的反向，复位后的第一次竞争选择读；
方向交替由协调者确认并写入规格提交 `9a656e2db`，首次竞争读优先在 `f865ed838` 确认。

删除 URG_MAX、饿死计时、DRR deficit/weight、token/rate、DIR_BATCH、等待时间戳、
统计事件、累计计数、快照及其寄存器状态。固定全局上限 8；读上限为
`{4,1,1,4,2}`，写上限为 `{0,0,1,2,2}`。旧参数和统计地址自然落入零读/忽略写。
保留公共寄存器、错误地址/端口/类型、ERROR 中断与 W1C 优先级。

DISP 删除 L1 描述符、Surface 状态、FIFO、读计数 CDC、读空事件 CDC、欠账及
alpha 混合的七个乘法。帧参数 CDC 从 57 位缩为 6 位，仅传 L0 使能、X2 和像素偏移。
L1 寄存器与使能位读零/忽略写，SWITCH1 恒零，ERR_CODE 不产生 3。
L0 的 RGB、同步与 DE 仍保持原十一拍对齐，原尺寸/X2 的 beat 欠账规则不变。

## 影响和资源实测

RTL 提交：`2b89c48b6`（mem）、`d0b6e23e0`、`1caf5592e` 和 `4b78379ce`（RGB 单写点整理，DISP）；
寄存器生成文件：`1445cdb89`；GPU 专用 PC 模型及软件测试：`81e87e3ba`；验证改写：`f432c47b5`、`899b9f405`。
改前为 `4426bf9e5`，改后上述 RTL，公共依赖未改。

Yosys 通用 LUT6 映射，RAM 包装 blackbox，保持模块层次；父模块递归包含子模块，
父子行不能相加。FF 统计映射后的单 bit DFF 单元，LUT6 统计 `$lut`。
APM 列为动态乘法实例代理数：改前 DISP 的七个 8×8 乘法对应第 9 轮的七个 APM；
Yosys 未做 Pango APM 映射，七个乘法在通用映射中计入 LUT，因而 LUT 差值也不能
直接当作 PDS 的 LUT 节省量；实际器件资源仍须 PDS 确认。
RAM 列统计包装实例，未把 blackbox 内部存储展开成 FF/LUT。

| 模块 | LUT6 前→后 | FF 前→后 | APM 代理前→后 | RAM 包装前→后 |
|---|---:|---:|---:|---:|
| mem_xbar_gpu（含子模块） | 14463→5433 | 5375→2366 | 0→0 | 4→4 |
| mem_xbar_regs_gpu | 6299→111 | 2600→54 | 0→0 | 0→0 |
| mem_xbar_sched_gpu | 869→54 | 125→10 | 0→0 | 0→0 |
| mem_xbar_rbuf_gpu | 3729→3729 | 1707→1707 | 0→0 | 1→1 |
| disp_gpu（含子模块） | 6414→3829 | 3690→2265 | 7→0 | 2→1 |
| disp_reader_gpu | 1051→574 | 456→293 | 0→0 | 0→0 |
| disp_regs_gpu | 1295→1070 | 493→374 | 0→0 | 0→0 |
| disp_scan_gpu | 2140→631 | 1254→550 | 7→0 | 0→0 |

mem 的四份 RAM 是三份 W 包装和一份 R 包装；DISP 是 `edrv32_ram_disp_scan`。
L1 删除后该包装仍由 L0 使用，所以没有从 `disp_gpu.f` 移除文件，也没有废弃包装。
少一份 512×256 扫描 RAM 对应原来 L1 的四个 DRM；这里的包装数不等于 DRM 块数。

原始脚本、网表和日志：`build/s8/{before,after}/edrv32_{mem_xbar,disp}_gpu/`。
复现时逐模块运行，先检查可用内存至少 2 GiB：

```sh
mkdir -p build/s8/baseline
# 基线源只读展开，不改变当前检出或分支。
git archive 4426bf9e5 rtl | tar -x -C build/s8/baseline
# 展开 mem_subsys_gpu.f 或 disp_gpu.f，去重并收集 +incdir+；
# baseline 使用上面目录中的源，after 使用当前源。
```

生成与测量相同的四份脚本（只生成脚本，不启动综合）：

```python
from pathlib import Path
for label, source in [('before', Path('build/s8/baseline')), ('after', Path('.'))]:
    for short, filelist in [('mem_xbar', 'mem_subsys_gpu.f'), ('disp', 'disp_gpu.f')]:
        files, includes = [], set()
        def expand(path):
            for raw in path.read_text().splitlines():
                line = raw.split('//')[0].strip()
                if line.startswith('-f '):
                    expand(path.parent / line[3:])
                elif line.startswith('+incdir+'):
                    includes.add(str((path.parent / line[8:]).resolve()))
                elif line:
                    files.append(str((path.parent / line).resolve()))
        expand(source / 'rtl/filelists' / filelist)
        top = 'edrv32_' + short + '_gpu'
        out = (Path('build/s8') / label / top).resolve()
        out.mkdir(parents=True, exist_ok=True)
        commands = [
            'read_verilog -D FPGA_MODE ' +
            ' '.join('-I' + item for item in sorted(includes)) + ' ' +
            ' '.join(dict.fromkeys(files)),
            'blackbox edrv32_ram_*', 'hierarchy -top ' + top,
            'proc', 'opt', 'wreduce', 'write_json ' + str(out / 'coarse.json'),
            'synth -top ' + top + ' -noabc',
            'abc -lut 6 -script +strash;if,-K,6', 'opt_clean',
            'write_json ' + str(out / 'netlist.json'), 'stat']
        (out / 'run.ys').write_text('\n'.join(commands) + '\n')
```

逐个执行（每次前用 `free -m` 确认可用内存 ≥ 2 GiB）：

```sh
yosys -Q -T -l build/s8/before/edrv32_mem_xbar_gpu/run.log -s build/s8/before/edrv32_mem_xbar_gpu/run.ys
yosys -Q -T -l build/s8/after/edrv32_mem_xbar_gpu/run.log -s build/s8/after/edrv32_mem_xbar_gpu/run.ys
yosys -Q -T -l build/s8/before/edrv32_disp_gpu/run.log -s build/s8/before/edrv32_disp_gpu/run.ys
yosys -Q -T -l build/s8/after/edrv32_disp_gpu/run.log -s build/s8/after/edrv32_disp_gpu/run.ys
```

动态乘法代理从 `coarse.json` 的 `$mul` 递归统计，两输入均须含信号位；
常数地址乘法不计 APM。资源统计使用 Yosys 0.70+219（5053d0e26）。

## 回归摘要

工具：Verilator 5.051 devel（v5.050-99-gf8fb1d664）、Icarus（mem_xbar 四态补充）、
Yosys 0.70+219。软件采用 C11、`-Wall -Wextra -Werror`。

- 风格：8 个 GPU 专用 RTL 与 2 个生成 `.vh`，0 告警；完整 GPU SoC 顶层 lint 0 告警。
- mem_xbar 单元：4 PASS（含完整协议/容量检查、ST-02 定向顺序和 Icarus 四态检查）。
- DISP 单元：扫描 2 PASS、reader 1 PASS、寄存器 1 PASS、参数锁存/滚动 1 PASS。
- mem_subsys_gpu：37 PASS；20 个随机种子；覆盖 86/86 项、9/9 在途上限。
- ST-03：720 行、768 个音频样本帧、116814 次授权；显示 FIFO 最低 80 beat、
  音频 FIFO 最低 128 个样本，无读空/欠载；实测仿真 887.914 s。
  完整帧模型超过旧的 600 s 限额，因此该 full 项时限改为 1800 s。
- DISP 模块：full 18 个场景与独立 ST-07 全部通过，smoke 的 ST-05 通过，两个入口
  2 PASS/0 FAIL；包括原尺寸、X2、帧切换、读空欠账、停止/软复位及 L1 零读/写忽略。
- RGB 单写点整理后另跑扫描/滚动单元及 ST-05 HDMI 逐像素，全部通过，资源数字不变。
- GPU 专用 PC 模型：`soc_test` 与 `platform_input_test` 均 PASS。
- SoC ST-08～ST-12：用户经协调者取消该项验收，完整系统改为上板测试。

取消指令读取时，已启动的 SoC 作业均已结束且通过；其结果仅作为补充，不作为本次验收。
ST-08 只验证 BIOS/CHIP_ID/菜单启动，按协调者此前明确批准使用现有
`--gpu-placeholder` 模式；不以该场景验证 GPU 功能。占位夹具从 `455383e37` 恢复到
隔离验证副本，未重新加入正式 RTL 或文件列表。ST-09～ST-12 使用完整 GPU；
GPU 源从 `1caf5592e` 归档固定，S8 RTL 使用上述提交，避免混入 S-7 的未提交修改。
ST-10 补充结果为 921600 像素一致，ST-12 为 27 次 I2C 写及 256 帧 I2S 立体声。
原始日志归集在 `build/s8/remote-logs/`，本次验收以以上单元、模块回归和 lint 为准。

执行命令（单个构建使用 `-j 1`；按目录并发，SoC 使用相互独立的构建副本）：

```sh
python3 tools/regress.py full --path verif/unit/mem_xbar_gpu -j 1
python3 tools/regress.py full --path verif/unit/disp_scan_gpu -j 1
python3 tools/regress.py full --path verif/unit/disp_layers_gpu -j 1
python3 tools/regress.py full --path verif/unit/disp_reader_gpu -j 1
python3 tools/regress.py full --path verif/unit/disp_regs_gpu -j 1
python3 tools/regress.py full --path verif/block/mem_subsys_gpu -j 1
python3 verif/block/mem_subsys_gpu/coverage.py build/regress/full/block/mem_subsys_gpu
python3 tools/regress.py full --path verif/block/disp_gpu -j 1
make -f sw/bsp/pc/Makefile test
# 以下占位文件只恢复到隔离验证副本，不修改正式 GPU。
git show 455383e37:verif/soc/gpu_common/edrv32_gpu.v > verif/soc/gpu_common/edrv32_gpu.v
python3 verif/soc/gpu_boot/run.py --gpu-placeholder
python3 tools/regress.py full --path verif/soc/gpu_regs -j 1
python3 tools/regress.py full --path verif/soc/gpu_render -j 1
python3 tools/regress.py full --path verif/soc/gpu_irq -j 1
python3 tools/regress.py full --path verif/soc/gpu_audio -j 1
```

并发配置：普通目录 3 路；DISP 的独立场景至多 6 路；SoC 隔离副本至多 3 路。
所有仿真均在指定主机执行，留出约一半核数与内存供并行任务使用。
隔离副本包含 `fpga/` 的静态 ROM 数据，不能只复制 RTL/测试源。

顶层 lint 在 `rtl/filelists/` 下运行，使用现有 GPU SoC 测试工具递归展开并去重
`gpu_soc.f`（直接传嵌套 `-f` 会重复声明公共模块）：

```python
from pathlib import Path
import subprocess
from verif.soc.gpu_common.run import sources
rtl = sources(Path('rtl/filelists/gpu_soc.f').resolve())
subprocess.run(['verilator', '--lint-only', '-Wall', '+define+SIM_MODE',
                '--top-module', 'edrv32_gpu_soc_top', *rtl],
               cwd='rtl/filelists', check=True)
```

## 状态

已实现并完成本次范围的回归；独立仿真目录和本任务进程已清理。
完整系统上板测试、PDS 物理资源和布线结果留给后续板级任务确认。
