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

## R-7：clk_mem 的 AUD 与 GPU 读返回缓冲流水（2026-11-27）

背景：卡 107 round10 的 AUD RD→AR 路径为 19 级、−1.73 ns，GPU mem_xbar
读返回 credit/地址选择路径为 10–14 级、−0.36～−1.01 ns。约束是端口、事务顺序、
FIFO 阈值与全局 128 beat 预留/按序归还规则不变；视觉版 mem_xbar 不修改。
本节改前基线为 `2659df37969d7d37ae3c48e2050b85aeafc2fa6c`，改后为包含本节的提交。

### 方案与决策

AUD 原来一拍串接回绕可用量、环尾、页尾、最小值、FIFO 比较及 AR 使能。
选择把地址和两个独立的 19 位 beat 差值先寄存，避免把完整 avail 的环形算式送入
AR 控制。WR 已回绕时，环尾比 avail 更紧；未回绕时，WR−RD 比环尾更紧，
所以这两种情况分别使用 ring_left 与 forward，结果等于原来的边界最小值。
各差值只传低 4 位与“至少 16 beat”标志；大数归约在减法所在级结束。
512 B 对齐的基址使页内低 9 位等于 RD 的低 9 位，页内第八个 512 B 段才需要截短。

AUD 现在依次经过 IDLE（快照）、LIMIT（512 B/4 KiB 限幅）、PLAN（两者取小）、
CHECK（当前 FIFO 空位比较及 AR 负载寄存），然后进入 ADDR。
相对原来每次 AR 准备增加 **3 拍**；协调者已通过本任务 ask 明确同意此延迟，
以逐级预算优先。CHECK 仍比较 `free >= beats × 8`，空数据、禁用、重启或 FIFO
空位不足都返回 IDLE 重新采样；整个准备过程只有一个状态机，没有重复提交入口。
AR 发出后地址和长度保持到握手。RD 的下一 beat 地址和回绕标志也提前保存，
每个 R 握手更新预测值，因此错误排空中连续接收 R beat 也不依赖八拍样本输出间隔。
以每 beat 至少 1 拍接收和 8 拍输出估算，16-beat 突发原最短 146 拍，现为 149 拍，
周期增量约 `3/146 = 2.05%`；实际流量仍为规格的 192 KB/s。

GPU rbuf 将 DDR 返回对当前各口 head 的命中先寄存为 port_return，正常 credit
下一拍才加一；fetch 扣除仍发生在原拍，所以只有保守少算一拍，不会超发。
分配新 head 时清掉属于旧 head 的延迟命中，避免同时有别口 DDR 返回时误加 credit。
每描述符另存“已实际返回/合成的 beat − 已 fetch 的 beat”，随原 DDR/fetch 边沿更新，
错误描述符分配时直接初始化为长度。它提供切换 head 时的完整 credit 快照。

最后一个 beat 被上游接收时，仅寄存下个 head 的二进制与 one-hot 选择；下一拍
加载其地址和 credit，加载拍不参与 fetch。one-hot 使描述符数据经过并行 AND/OR
选择；避免二进制 8 选 1 后再做进位运算。每口描述符计数随 reserve/last_take 更新，
用于判断同拍新事务是否直接成为 head；不再把旧的长优先选择树接到地址/credit CE。
各口还同步维护 credit 非零标志，递增时置位、递减时判断旧值是否大于一；
描述符也保存相同标志供 head 加载。仲裁只读该标志，把 port_available 的归约
与 RAM 地址选择分开，未增加气泡。全局 free_cnt 的预留、释放边沿及 DDR 无反压接口不变。

相比原实现，首次返回的可见 credit 最多晚一拍，同口后续描述符之间多一个加载气泡；
16-beat、单口持续输出且其余条件理想时，计入原有 head 切换空拍，描述符间隔
从 17 拍变为 18 拍（约下降 5.56%），其他端口可使用加载拍。该数字是结构估算，
不是实测带宽。
没有增加端口、参数、错误检查或兜底路径。

### 验证与深度参考

复现命令（在指定仿真环境中逐项执行，单任务 `-j 1`，没有运行 SoC 仿真）：

```sh
python3 tools/regress.py full --path verif/unit/aud_dma -j 1
python3 tools/regress.py full --path verif/unit/aud_fifo -j 1
python3 tools/regress.py full --path verif/unit/aud_control -j 1
python3 tools/regress.py full --path verif/unit/mem_xbar_gpu -j 1
```

风格与 lint：

```sh
. ~/.local/opt/edrv32/env.sh
python3 - <<'PY_LINT'
from pathlib import Path
import subprocess
from verif.soc.gpu_common.run import sources
rtl = sources(Path('rtl/filelists/gpu_soc.f').resolve())
for top in ['edrv32_aud', 'edrv32_mem_xbar_gpu', 'edrv32_gpu_soc_top']:
    subprocess.run(['verilator', '--lint-only', '-Wall', '+define+SIM_MODE',
                    '--top-module', top, *rtl], cwd='rtl/filelists', check=True)
subprocess.run(['python3', 'tools/check/verilog_style.py',
                *[f for f in rtl if f.endswith(('.v', '.vh'))]], check=True)
PY_LINT
```

Yosys 使用 0.70+219（5053d0e26），XC7 LUT6/CARRY4 代理，不等同于 PDS 物理时序。
测量保留被跟踪的公共信号名，不对正式 RTL 增加用于测量的寄存器。
下面两段保存为 `build/r7/synth.py`、`build/r7/depth.py` 后依次执行即可复现；
JSON、综合日志与逐级路径均放在 `build/r7/`，仿真摘要为
`build/r7/remote-tests.log`、`build/r7/final-tests.log` 与 `build/r7/mem-final.log`，
lint 摘要为 `build/r7/lint.log`。

```sh
mkdir -p build/r7
. ~/.local/opt/edrv32/env.sh
python3 build/r7/synth.py > build/r7/synth-run.log 2>&1
python3 build/r7/depth.py > build/r7/depth.txt
```

综合脚本：

```python
from pathlib import Path
import subprocess
out=Path('build/r7')
for stem,source in [('aud','rtl/media/aud/edrv32_aud_dma.v'),('rbuf','rtl/mem/edrv32_mem_xbar_rbuf_gpu.v')]:
    top=Path(source).stem
    old=out/(stem+'-before.v')
    old.write_bytes(subprocess.check_output(['git','show','2659df379:'+source]))
    for version,path in [('before',old),('after',Path(source))]:
        prefix=out/(stem+'-'+version)
        commands=[]
        if stem=='rbuf':
            commands.append('read_verilog -lib -D SIM_MODE -Irtl/include rtl/tech/edrv32_ram_mem_xbar_r.v')
        commands += ['read_verilog '+str(path),'proc','setattr -set keep 1 w:port_* w:sent_r* w:received_r* w:port_return_r w:available_r* w:addr_r w:ring_full_r w:forward_full_r w:ring_last_r w:wrap_r w:ring_left_r w:forward_r w:wrapped_r w:ring_beats_r w:page_beats_r w:beats_r w:next_ptr_r w:rd_ptr_o w:m_axi_araddr_o w:m_axi_arlen_o',f'synth_xilinx -top {top} -family xc7 -flatten -noiopad -noclkbuf',f'write_json {prefix}.json','stat','ltp -noff']
        script=prefix.with_suffix('.ys');script.write_text('\n'.join(commands)+'\n')
        subprocess.run(['yosys','-Q','-T','-l',str(prefix)+'.log','-s',str(script)],stdout=subprocess.DEVNULL,check=True)
        print(prefix,flush=True)
```

路径脚本在 FD/LD 寄存器处停止，分别统计 LUT/INV/MUX 与 CARRY4；进位块数
不能直接当 LUT 级数，也不把一个 CARRY4 内部当四个 LUT。结果包含目标寄存器
D、CE 与同步复位置位输入，不跨寄存器拼接路径。

```python
import json
from pathlib import Path
from functools import lru_cache
for stem in ['aud','rbuf']:
 for version in ['before','after']:
    m=json.loads(Path(f'build/r7/{stem}-{version}.json').read_text())['modules']['edrv32_aud_dma' if stem=='aud' else 'edrv32_mem_xbar_rbuf_gpu']
    cells=m['cells']; nets=m['netnames']; graph={}; ff=[]
    for name,c in cells.items():
        t=c['type']; con=c['connections']
        if t.startswith(('FD','LD')):
            ff.append((name,c));continue
        if not t.startswith(('LUT','MUXF','CARRY','INV')):continue
        ins=[b for p,bs in con.items() if c['port_directions'][p]=='input' for b in bs if isinstance(b,int)]
        for p,bs in con.items():
            if c['port_directions'][p]=='output':
                for b in bs: graph[b]=(ins,t,name)
    def run(sources,targets):
        src=set(b for n,v in nets.items() if any(n.startswith(x) for x in sources) for b in v['bits'] if isinstance(b,int))
        @lru_cache(None)
        def walk(b):
            if b in src:return (0,0,[])
            if b not in graph:return None
            ins,t,name=graph[b]; paths=[v for i in ins if (v:=walk(i)) is not None]
            if not paths:return None
            best=max(paths,key=lambda v:v[0]+v[1]);return(best[0]+(not t.startswith('CARRY')),best[1]+t.startswith('CARRY'),best[2]+[(t,name)])
        results=[]
        for name,c in ff:
            q=set(c['connections']['Q'])
            dst=[n for n,v in nets.items() if q.intersection(v['bits']) and any(n.startswith(x) for x in targets)]
            if not dst:continue
            for port in ['D','CE','R','S']:
                for b in c['connections'].get(port,[]):
                    if (r:=walk(b)) is not None:results.append((r[0]+r[1],r[0],r[1],dst[0],port,r[2]))
        if targets == ['RAM.rd_addr_i']:
            for b in cells['u_ram']['connections']['rd_addr_i']:
                if (r:=walk(b)) is not None: results.append((r[0]+r[1],r[0],r[1],'u_ram.rd_addr_i','input',r[2]))
        if results:
            r=max(results);print(stem,version,sources,'->',targets,':',r[:5]);print(r[5])
        else:print(stem,version,sources,'->',targets,': no combinational path')
    if stem=='aud':
        run(['rd_ptr_o'],['m_axi_araddr_o','m_axi_arlen_o','state_r'])
        for x,y in [(['rd_ptr_o'],['addr_r','ring_left_r','ring_full_r','forward_r','forward_full_r','wrapped_r','next_ptr_r','wrap_r']),(['ring_left_r','ring_full_r','forward_r','forward_full_r','wrapped_r','addr_r'],['ring_beats_r','page_beats_r']),(['ring_beats_r','page_beats_r'],['beats_r']),(['beats_r'],['state_r','m_axi_arlen_o'])]:run(x,y)
    else:
        run(['sent_r','received_r'],['port_available_r','port_addr_r'])
        run(['port_head_r','port_head_mask_r'],['port_available_r','port_addr_r'])
        run(['available_r','start_r','port_return_r'],['port_available_r','port_addr_r'])
        run(['port_available_r'],['RAM.rd_addr_i'])
        run(['port_ready_r'],['RAM.rd_addr_i'])
```

深度结果（非进位逻辑级 + CARRY4 个数）：

| 路径 | 改前 | 改后 |
|---|---:|---:|
| AUD RD→AR 负载/状态使能 | 14 + 13 | 原组合通路已被寄存器切断 |
| AUD RD→地址快照（32 位加法） | — | 1 + 8（单段 32 位进位链） |
| AUD 边界快照→限幅 | — | 1 + 2 |
| AUD 限幅→最小长度 | — | 3 + 0 |
| AUD 最小长度→ARLEN/状态 | — | 1 + 1 |
| rbuf sent/received→port_available/port_addr | 13 + 2 | 原组合通路已被寄存器切断 |
| rbuf 寄存的 head 选择→port_available/port_addr | 11 + 2 | 3 + 0 |
| rbuf 描述符 available/start、延迟返回脉冲→port_available/port_addr | 4 + 0 | 3 + 2 |
| rbuf port_available→RAM 读地址 | 8 + 0 | 原组合通路已被非零标志寄存器切断 |
| rbuf port_ready→原有读仲裁→RAM 读地址 | — | **7 + 0，仍超过 3 LUT 预算** |

以上针对原最差路径及其新的相邻分段，不能由此宣称模块所有寄存器间路径均满足预算。

协调者在本任务第二次 ask 中明确接受保留返回仲裁策略，把上述 **Yosys 代理 7 级**
余段列为已知限制，交卡 107 第 11 轮 PDS 再判断；本次不继续扩大返回仲裁改造范围。

验证结果：AUD DMA、FIFO、control 各 1 PASS；mem_xbar_gpu full、ST-02、常规单元
三个 Verilator 入口及常规 Icarus 入口共 4 PASS。AUD、mem_xbar_gpu 与 GPU SoC
顶层 Verilator `-Wall` 均 0 告警，完整 GPU SoC 文件列表 154 个 RTL 的风格检查
0 告警。仿真工具为 Verilator 5.051 devel（v5.050-99-gf8fb1d664）及 Icarus；
未运行 SoC 级仿真。指定的独立仿真副本在收集日志后清理。

状态：已实现；本次范围的单元回归和静态检查完成。PDS 物理时序，特别是上述返回仲裁
余段，以及完整系统的上板测试留待后续板级任务。
