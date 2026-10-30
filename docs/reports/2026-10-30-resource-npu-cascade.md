# NPU APM SIMD 级联累加资源与验证（T-NPU2）

| 项 | 条件 |
|---|---|
| 日期 | 2026-10-30 |
| 状态 | 已合并 T-NPU1；用户精简范围全部 PASS |
| 改前 commit | `25f9347e329764377d88087e05af018593309ceb` |
| 级联 RTL 提交 | `819c256d`（`d0c09235` 重基到 b3 后；资源目标源码一致） |
| 合并验收输入 | `413d229c`；T-NPU1 原提交 `f9ac4983` / `f45715c5`，本分支为 `8797f403` / `413d229c` |
| 规格 | npu-spec v0.5 2、4.3、5.2–5.4、7；npu-testplan 3.8 EQ-01 |
| 目标 | PG2L200H-6/FBB676，clk_npu 150 MHz；本轮不运行 PDS |
| 补充 EQ-01 环境 | 用户提供的仿真主机（环境不记录） |
| RTL 回归及资源 | 本机；Verilator 5.020、Icarus Verilog 12.0、Yosys 0.70+219（5053d0e26） |
| 原始数据 | 本 worktree 的 `build/npu-cascade/`、`build/regress/smoke/`；补充主机的临时目录与进程已清理 |

数据通路 LUT6 代理资源 **40454→29206（−11248）**，fabric FF **31505→24817（−6688）**；
MAC APM 保持 256，数据通路合计保持 288。APM→逻辑的有效结果位数 **8192→1216**。

## 实现与延迟

256 个 APM 保持 32 物理输出通道 × 8 输入项，每个 APM 仍处理两个像素。
新增固定包装 `edrv32_mac_npu_int8_chain`，SIMD 两路 24 位后加，CPI/CPO 串接；
全部 X/Y、MULT、P/CPO 寄存器开启。第 0 级 CPI 接 0，其他级使用相同固定配置。
删除 LUT R1–R3，加法留在 APM 内；最后一级 CPO 等于 P，两路分别取低 19 位。
R4 的 D2 半通道合并及后续数值行为保持。

权重采用推荐的按输入项 k 分 bank 方案；bank k 的读地址和读使能晚 k 沿。
原 DDR 行的八个 32 B beat 在现有 2048 位写数据寄存器内转置，每 beat 向每个 bank
填四个输出通道的权重；接收第七号 beat 后一沿，八个 bank 同时整字写入 RAM。
不增加写缓冲数据 FF，RAM 端口及 DDR 格式不变。取消清除待写使能；已经待写的完整行
仍在该沿提交，与原先待写 beat 的处理一致；取消期间的新 beat 不产生有效提交。
W3 仍在整块装载完毕后开始使用该块。

激活在 A5 后按输入项错拍。四份本地激活副本分别服务八个输出通道；高通道副本先用
该 term 的 `tag[48]` 选择 D2 C8，再把选出的两个像素字节一起延迟 k 沿，选择不会
跨 term 错配；这与将选择位及两组 C8 同时错拍后选择逐拍等价。
所需错拍数据位为 4 × 16 × Σ(k=0..7)k = **1792 FF**（映射前位数），
比将全部低/高 C8 都错拍的 3584 位少 1792；没有使用权重数据错拍（该方案需 7168 FF）。
权重请求错拍为 12 × 28 = **336 位**（映射前：11 位地址 + 1 位使能）。
窗口 A4/A5 权重寄存器每拍推进，以便在 item 0 的无效拍中传递其他项的有效数据。
valid/first/last/tag 从 5 沿延长至 10 沿，valid 保持本地控制，未引入全局 CE。

| 指标 | 改前 | 改后 |
|---|---:|---:|
| A5 到归约结果（寄存边界数） | 5 | 10 |
| 最后归约项 A1 到结果 RAM（双平面） | 29 拍 | 34 拍 |
| 最后归约项 A1 到结果 RAM（单平面） | 27 拍 | 32 拍 |
| MAC 吞吐 | 512 MAC/拍 | 512 MAC/拍 |
| APM→逻辑算术结果连线 | 8192 位（256×2×16） | 1216 位（32×2×19） |
| 专用 APM→APM 级联 | 0 | 10752 位（32×7×48） |

APM→逻辑减少 **6976 位（85.16%）**；级联连线不计作逻辑阵列布线。
链的延迟由 EQ-01 独立整数和验证；结果缓冲延迟由 datapath 单元测试逐 pair 检查。

## PDS 起点及 Yosys 口径

公共起点为 `origin/win/20261030-10-b3-timing-rerun` 的四套 `synthesis_paths.tsv`
和 `synthesis_path_detail.txt`（PDS 2022.2-SP6.1，综合估算）。B3V/B3VN/B3R/B3F
提供的路径样本中均没有 MAC 阵列 APM→R1 路径；B3VN 的 clk_npu 最差顺序路径是
`u_npu/u_conv/residual_pairs_r[0]` → `residual_addr_r[31]`，+0.006 ns、15 级，
属于 T-NPU1 范围。级联实现没有直接编辑 `edrv32_npu_conv.v`；
本分支按协调者指示引入了 T-NPU1 对该文件的修改。

实际 MAC 起点参考已布线的 N-W2（`tasks/win/20261028-02-npu-pnr-r2/result.md`
及 `docs/reports/2026-10-28-timing-npu.md`）：
`g_channel[3].g_lane[5].u_multiply/u_apm` → `g_channel[3].g_pixel[1].r1_data_r`，
+0.214 ns、2 级，布线占 83.9%。改后该 R1 终点已删除；新边界为末级 CPO →
`u_accum/g_channel[*].g_pixel[*].r4_data_r`。改后物理裕量及专用级联可布性尚未取得，
需 PDS 测量，不能由 Yosys LUT6 级数推断。

## Yosys 资源及组合路径

采用下方复现脚本的同一 LUT6 流程，RAM/APM 黑盒，FF 不包含硬块内部寄存器。
基线为 `25f9347e`；改后为 `d0c09235`，与重基后的 `819c256d` 在本节目标源码上无差异。
T-NPU1 的 `edrv32_npu.v`、`edrv32_npu_conv.v` 不在数据通路综合目标内。

| 独立综合目标 | LUT6 改前 | 改后 | Δ | fabric FF 改前 | 改后 | Δ | APM 改前→改后 |
|---|---:|---:|---:|---:|---:|---:|---|
| `edrv32_npu_mac_array` | 12678 | 268 | −12410 | 8132 | 2312 | −5820 | 256→256 |
| `edrv32_npu_weight_store` | 2121 | 2082 | −39 | 2148 | 2176 | +28 | 0→0 |
| `edrv32_npu_window` | 926 | 921 | −5 | 5270 | 5270 | 0 | 0→0 |
| `edrv32_npu_datapath` 合计 | 40454 | 29206 | −11248 | 31505 | 24817 | −6688 | 288→288 |

各目标分别综合，子模块行不能与 datapath 合计行相加。权重写转置使用八个固定的
32 位使能片，保持原有 2048 位写数据寄存；同源读请求前缀、写地址及使能在代理网表
中共享，权重存储最终只增加 28 FF。两版本的显式量化乘法 IP 均为 32，剩余 `$mul` 均为 0。
这些数字是通用单输出 LUT6 代理值，不能作为 PG2L200H 的 PDS LUT/FF 实测值。

| 组合路径 | 改前 LUT6 级数 | 改后 LUT6 级数 | 说明 |
|---|---:|---:|---|
| APM 乘积 → R1 数据寄存器 | 8 | 无 | R1–R3 归约已删除 |
| R4 D2 合并输入 → R4 数据寄存器 | 12 | 12 | 输入由 R3 FF 改为末级 APM CPO；原 20 位加法保留 |

末级 APM CPO→R4 的 12 级包含通用 LUT6 对 20 位加法及 D2 选择的映射，
不代表 PDS 的专用进位链级数；本任务没有修改 R4。T-NPU1 的控制/地址剩余路径见
[控制路径报告](2026-10-30-timing-npu.md)，均留给 B3N PDS 判断。
原始数据为 `build/npu-cascade/{before,after}/<目标>/{resources.json,netlist.json,map.log}`；
路径结果为 datapath 目录下的 `apm_to_r1.json`、`r3_to_r4.json`、`chain_to_r4.json`。
最终资源汇总为 `build/npu-cascade/resources.log`；综合过程日志为
`measure-final2.log` 的 before 部分及 `measure-slices.log` 的固定写片版本。

## 验收（用户精简范围）

用户 2026-10-30 调整为合并 T-NPU1 后一次验收，以 B3N 上板结果为准，不追求高覆盖仿真。
本轮只运行以下五个单元 smoke、八个模块用例和 board_npu 连线 smoke；各 full 档、
NET-01、NET-02、性能及未改动模块单元测试不再运行。整网逐字节一致和帧率由
board_npu 上板 C、D 项验证。此前已停掉的完整回归不恢复。

```sh
# EDRV32_PANGO_SIM_DIR 由用户设置为厂商模型目录。
for unit in npu_mac_chain npu_mac_array npu_weight_store npu_window npu_datapath; do
    flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path "verif/unit/$unit" -j 1
done
for item in op_01 op_02 op_04 op_06 op_07 op_08 op_11 er_05; do
    flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path "verif/block/npu/$item" -j 1
done
flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/soc/board_npu -j 1
```

EQ-01 使用 Icarus 四态执行；包装单级及八级链在每个时钟沿后比对厂商 P/CPO，
包含启动 X 状态，独立整数和验证十沿延迟。单级另用随机 CPI 和 24 位边界检查
两路回绕。实际 1012 拍、1003 个完整点积，种子 `326ace01`。
未设置 EDRV32_PANGO_SIM_DIR 的运行实测退出码 1，明确打印缺少变量错误；
厂商模型只从外部目录读取，未入库。

MAC 检查 1305 个 term 的全部 64 路结果，权重存储检查 1152 行全容量及分段边界，
窗口逐项比较 A5+k 的权重，datapath 含 12 个独立参考用例，并检查每个 pair 的
34/32 拍延迟。模块用例分别覆盖 1×1、3×3 S1 补边、C4+HALF_TAIL、
量化/累加极值及 T-NPU1 停止寄存器的 ABORT 行为；另补 OP-06 的两种 RES_SEL、
OP-07 的 Cout=16/80 半块和 OP-11 的基址、偏移、跨距及 512 B 请求边界。

### 合并验收结果

验收代码输入为 `413d229c`。批次在本机持有共享 flock 串行执行，Verilator 构建 `-j 1`；
启动时工具主机尚未就绪，沿用已经运行的本机批次完成，没有重复执行此批次。
补充主机的环境按要求不记录。

| 检查 | 结果 | 说明 / 用例数量 |
|---|---|---|
| `npu_mac_chain` | PASS | EQ-01，Icarus 四态，逐沿比较 P/CPO |
| `npu_mac_array` | PASS | 1305 个 term，64 路点积和控制标签 |
| `npu_weight_store` | PASS ×2 | Verilator / Icarus，77100 个 bank 检查 |
| `npu_window` | PASS | 22079 个 term，权重按项错拍 |
| `npu_datapath` | PASS | 12 个独立参考用例，34/32 拍 |
| OP-01 | PASS | 9 个变体 |
| OP-02 | PASS | 3 个变体 |
| OP-04 | PASS | 8 个变体 |
| OP-06 | PASS | 2 个变体 |
| OP-07 | PASS | 2 个变体 |
| OP-08 | PASS | 12 个变体 |
| OP-11 | PASS | 5 个变体 |
| ER-05 | PASS | 3 个 ABORT 阶段，包含正常重启 |
| `board_npu` | PASS | BIOS / NPU ID / removed VIN SLVERR / PLIC13 DONE / 64 B 输出比较 |

合计 6 次单元仿真（权重含两种模拟器）、44 个模块变体和一次板级连线仿真，全部 PASS。
板级仿真实际运行 7.43 s。精简验收在本轮没有发现 T-NPU1 或级联累加的功能失败。
原始汇总 `build/npu-cascade/combined-smoke.log`；各项日志在
`build/regress/smoke/{unit,block/npu,soc/board_npu}/`，板级详细日志为
`build/board_npu/simulation.log`。没有运行 full、整网或性能档；整网正确性及帧率交 B3N 上板 C/D 项。

### 风格及 lint

```sh
python3 tools/check/verilog_style.py rtl/npu rtl/tech
python3 - <<'PY'
from pathlib import Path
import subprocess
from tools.regress import expand_files
for name, top in [('npu', 'edrv32_npu'), ('npu_datapath', 'edrv32_npu_datapath')]:
    subprocess.run(['verilator', '--lint-only', '-Wall', '-DSIM_MODE', '--top-module', top]
                   + expand_files(Path('rtl/filelists') / (name + '.f')), check=True)
PY
```

风格 48 个 RTL 文件、0 warnings；两套 filelist lint 均为 0 warnings。
board_vnpu 的完整 testbench 另经 `--lint-only --timing -Wall` 检查，0 warnings。

## Yosys 测量复现脚本

测量使用 FPGA_MODE、LUT6，APM 和 RAM 为端口黑盒，不计硬块内部寄存器。
剩余 `$mul` 在 `wreduce` 后按 T-RND1 口径逐个记录输入/输出位宽及符号参数，
转换为端口黑盒后再映射；本轮 NPU 数据通路没有剩余 `$mul`。
JSON 中自动生成的内部标识在重新映射前归一化，避免此工具版本 JSON 往返后的标识冲突。
两版本均使用同一流程。以下脚本存为 `build/npu-cascade/measure.py` 后运行：

```sh
mkdir -p build/npu-cascade
# 将下方 Python 保存到 build/npu-cascade/measure.py；EDRV32_PANGO_SIM_DIR 指向厂商模型目录。
flock /tmp/edrv32-sim.lock python3 build/npu-cascade/measure.py before after
```

```python
from pathlib import Path
import collections
import json
import os
import re
import subprocess
import sys
sys.path.insert(0, str(Path.cwd()))
from tools.synth.yosys_synth import read_filelist
from tools.synth.netlist_paths import analyze
root=Path.cwd()
base=root/'build/npu-cascade'
commit='25f9347e329764377d88087e05af018593309ceb'
files=[]
includes=set()
read_filelist(root/'rtl/filelists/npu_datapath.f',files,includes)
stubs=[]
for name,width,addr in [('line',256,10),('weight',256,9),('quant',64,9),
                        ('lut',8,12),('residual',256,9),('result',512,9),('scratch',256,9)]:
    stubs.append(f'''(* blackbox *) module ip_ram_npu_{name} (
input wr_clk, wr_rst, wr_en, input [{addr-1}:0] wr_addr,
input [{width-1}:0] wr_data, input rd_clk, rd_rst, rd_clk_en,
input [{addr-1}:0] rd_addr, output [{width-1}:0] rd_data); endmodule''')
for name,a,b,p in [('low',18,16,34),('high',16,16,32)]:
    stubs.append(f'''(* blackbox *) module ip_mul_npu_quant_{name} (
input clk, ce, rst, input [{a-1}:0] a, input [{b-1}:0] b,
output [{p-1}:0] p); endmodule''')
vendor=(Path(os.environ['EDRV32_PANGO_SIM_DIR'])/'GTP_APM_E2.v').read_text()
header=vendor[vendor.index('module GTP_APM_E2'):].split(');',1)[0]+'); endmodule\n'
stubs.append('(* blackbox *) '+re.sub(r'//[^\n]*','',header))
(base/'stubs.v').write_text('\n'.join(stubs))
for phase in sys.argv[1:]:
    out=base/phase
    out.mkdir(exist_ok=True)
    if phase=='before':
        sources=[]
        for name in files:
            if 'edrv32_mac_npu_int8_chain' in name:
                name=name.replace('edrv32_mac_npu_int8_chain','edrv32_mul_npu_int8_pair')
            target=out/'src'/name
            target.parent.mkdir(parents=True,exist_ok=True)
            target.write_bytes(subprocess.check_output(['git','show',commit+':'+name]))
            sources.append(str(target))
        inc=out/'src/rtl/include'
        inc.mkdir(parents=True,exist_ok=True)
        (inc/'edrv32_build_mode.vh').write_bytes(subprocess.check_output(
            ['git','show',commit+':rtl/include/edrv32_build_mode.vh']))
    else:
        sources=files
        inc=root/'rtl/include'
    for top in ['edrv32_npu_window','edrv32_npu_weight_store','edrv32_npu_mac_array','edrv32_npu_datapath']:
        d=out/top
        d.mkdir(exist_ok=True)
        script=f'read_verilog -D FPGA_MODE -I{inc} '+' '.join(sources)+f' {base}/stubs.v\n'
        script+=f'hierarchy -top {top}\nproc\nflatten\nopt\nwreduce\nopt_clean\nwrite_json {d}/coarse.json\n'
        (d/'coarse.ys').write_text(script)
        subprocess.run(['yosys','-Q','-T','-l',str(d/'coarse.log'),'-s',str(d/'coarse.ys')],
                       stdout=subprocess.DEVNULL,check=True)
        design=json.loads((d/'coarse.json').read_text())
        muls=[]
        for name,cell in design['modules'][top]['cells'].items():
            if cell['type']!='$mul': continue
            kind='ip_npu_measure_mul_'+str(len(muls))
            ports={}
            offset=2
            for pn,bits in cell['connections'].items():
                ports[pn]={'direction':cell['port_directions'][pn],
                           'bits':list(range(offset,offset+len(bits)))}
                offset+=len(bits)
            design['modules'][kind]={'attributes':{'blackbox':'1'},'ports':ports,
                                     'cells':{},'netnames':{}}
            muls.append({'cell':name,'widths':{p:len(b) for p,b in cell['connections'].items()},
                         'parameters':cell['parameters']})
            cell['type']=kind
            cell['parameters']={}
        (d/'multipliers.json').write_text(json.dumps(muls,indent=2)+'\n')
        # JSON parameter defaults are not imported as Verilog parameter declarations.
        # Parameters are fixed on the already-flat blackboxes; mapping keeps their ports only.
        for cell in design['modules'][top]['cells'].values():
            if 'GTP_APM_E2' in cell['type']: cell['parameters']={}
        (d/'blackbox.json').write_text(json.dumps(design))
        script=f'read_json {d}/blackbox.json\nrename -enumerate\nsynth -top {top} -flatten -noabc\n'
        script+=f'abc -lut 6 -dress\nopt_clean\nwrite_json {d}/netlist.json\nstat\n'
        (d/'map.ys').write_text(script)
        subprocess.run(['yosys','-Q','-T','-l',str(d/'map.log'),'-s',str(d/'map.ys')],
                       stdout=subprocess.DEVNULL,check=True)
        net=json.loads((d/'netlist.json').read_text())
        counts=collections.Counter(c['type'] for c in net['modules'][top]['cells'].values())
        result={'LUT':counts['$lut'],'FF':sum(n for k,n in counts.items() if 'DFF' in k.upper()),
                'APM':sum(n for k,n in counts.items() if 'GTP_APM_E2' in k),
                'quant_APM':sum(n for k,n in counts.items() if k.startswith('ip_mul_npu_quant_')),
                'generic_mul':muls,'cells':dict(counts)}
        (d/'resources.json').write_text(json.dumps(result,indent=2)+'\n')
        print(phase,top,{k:result[k] for k in ['LUT','FF','APM','quant_APM']},flush=True)
        if top=='edrv32_npu_datapath':
            # The repository analyzer identifies synchronous IP boundaries by ip_ prefix.
            for kind in list(net['modules']):
                if 'GTP_APM_E2' in kind:
                    renamed='ip_measure_'+kind.replace('$','_').replace('\\','_')
                    net['modules'][renamed]=net['modules'].pop(kind)
                    for cell in net['modules'][top]['cells'].values():
                        if cell['type']==kind: cell['type']=renamed
            (d/'paths-netlist.json').write_text(json.dumps(net))
            filters=[('apm_to_r1',r'u_mac_array.*u_multiply.product_w',r'u_mac_array.*r1_data_r'),
                     ('chain_to_r4',r'u_mac_array.*cascade_w\[8\]',r'u_accum.*r4_data_r'),
                     ('r3_to_r4',r'u_mac_array.*r3_data_r',r'u_accum.*r4_data_r')]
            for label,start,end in filters:
                result=analyze(net,[start],[end])
                (d/(label+'.json')).write_text(json.dumps(result,indent=2)+'\n')
```

