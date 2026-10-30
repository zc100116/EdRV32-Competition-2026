# PIX 共享灰度与移位加资源测量（T-PIX1）

| 项目 | 条件 |
|---|---|
| 日期 | 2026-10-30 |
| 改前 RTL | `b09d3c8fc0de456e5b68b613f8324d516fbd6f04` |
| 改后 RTL | `236ad647051089a839e7a9ab4d265b83c2fe5589` |
| 规格 / 决策 | `pix-spec.md` v0.1 2.1、2.4–2.9、7；`2026-10-30-pix-gray-sharing.md` 方案 A+B |
| 单元 / 模块验收环境 | 用户提供的仿真主机（环境不记录） |
| 本机板级 / 资源 / 性能工具 | Verilator 5.020；Yosys 0.70+219（5053d0e26），通用 LUT6 |
| 物理目标 | PG2L200H-6/FBB676，clk_mem 125 MHz（8 ns） |
| PDS 起点 | `origin/win/20261030-10-b3-timing-rerun` B3F，RTL `05088f4b`，PDS 2022.2-SP6.1；综合估算，非布线结果 |
| PDS 产物提交 | `2f43834d5d5a2759f200c7c4a86e020125748b61`，`tasks/win/20261030-10-b3-timing-rerun/artifacts/` |
| 原始测量 | 本 worktree `build/pix-resource/`；单元/模块验收保留 worker 自主汇总 `validation-final-summary.log`，原始日志和临时构建按要求清理；板级本机记录 `board-local.log` |

## 实现与延迟

每个 3×3 级在行 RAM 输出捕获后，对新进入的六个 RGB888 像素计算一次 Y，两个核共用 Y 窗口。灰度采用四层寄存加法：系数的并行部分项、加减合成系数值、77R+150G 与 29B+128、最终求和取 [15:8]。77 = 64+8+4+1，150 = 128+16+4+2，29 = 32−(2+1)；所有中间量以 16 位无符号数表达，最终最大值为 65408，不改变舍入。

为同时满足单级延迟和全链路冲刷上限，颜色流水与共享灰度并行：`early_rgb_i[215:0]` 在原时刻启动颜色运算，`window_i[71:0]` 在四次 advance 后送入对应的九个 Y，直接接原 S5 Sobel/min/max。Y 由自己的窗口寄存器移动，左、右边界显式取 0，上、下边界由补零 RGB 得到 Y=0；未使用的 RGB 延迟副本没有保留。滤波器 valid/帧标记相应从共享 Y 窗口开始移四拍，核结果仍为 early RGB 窗口之后八拍。以上内部接口重定时经本 Dispatch 的 ask 获得协调者同意。

point2 的第一层系数移位加直接使用上一级输出寄存器，后接三层寄存加法，保持原四拍；RGB、配置、阈值和帧标记仍走原流水。均值 3641 乘法及 point1 可配对比度乘法保持不变，其输入、输出仍直接连接寄存器。所有 valid 与 payload 分开书写，沿用现有 advance、clear 和帧状态机制。

输出始终接收、输入连续，1280×8、两级 Sobel，同一 bench 改前/改后各运行一次，结果如下。资源和性能测量后仅修正核单测的新 Y 输入打包，RTL 与表中改后提交相同。

| 实测指标 | 改前 | 改后 |
|---|---:|---:|
| 第一级首输出相对本级输入 SOF | 651 拍 = 1 行 + 11 拍 | 651 拍 = 1 行 + 11 拍 |
| 第二级首输出相对本级输入 SOF | 651 拍 = 1 行 + 11 拍 | 651 拍 = 1 行 + 11 拍 |
| 输入拍数 / 首尾输入跨度 | 5120 / 5120 拍 | 5120 / 5120 拍 |
| 输出拍数 / 首尾输出跨度 | 5120 / 5120 拍 | 5120 / 5120 拍 |
| 持续吞吐 | 2 像素/拍，无空拍 | 2 像素/拍，无空拍 |
| 输入 EOF 到输出 EOF | 1312 拍 | 1312 拍 |

两级均满足 1 行 + ≤16 拍；冲刷为 `2×640+32=1312`，满足规格 2.7。点运算 2 保持四次 advance 的原流水。原始输出为 `before/perf-run.log`、`after/perf-run.log`；改前完整滤波器单测另验证 192 帧全部 OP、边界和随机间隙/冻结，最大延迟为 1 行 + 11 拍（`before/filter-run.log`）。

## Yosys 资源和逻辑级数

| 代理指标 | 改前 | 改后 | 变化 |
|---|---:|---:|---:|
| `$mul` 总数（展开后及粗网表 opt 后相同） | 132 | 18 | −114 |
| 变量×变量 `$mul`（硬块） | 6 | 6 | 0 |
| 常数 `$mul`（单列） | 126 | 12 | −114 |
| LUT6 | 20608 | 19719 | −889 |
| FF | 13236 | 13356 | +120 |
| 行 RAM 黑盒 | 4 | 4 | 0 |
| 全模块最大 LUT6 级数 | 11 | 11 | 0 |

通用代理中 FF 增加 120，**没有取得设计记录估算的 FF 降幅**；以上为实际工具结果，不把估算写成实测。通用 LUT6 流程将 Gamma 和常数乘法映射到普通逻辑，与 PDS 的分布式 RAM/DRM、APM 和进位链映射不同，因此只比较同口径前后变化。

最深路径改前/改后均为 `u_stage1.u_kernel0.g_color[0].op_color_r[0]` → `u_stage1.u_kernel1.g_color[2].s2_pair_r[2][8]`，11 LUT6 级；这是未改动的颜色路径，Yosys 合并了配置副本。原始路径和汇总见 `before/paths.json`、`after/paths.json` 及对应 `paths-summary.log`。没有将 LUT6 级数换算为物理裕量或 Fmax。

变量×变量 `$mul` 保留为端口同宽的硬块黑盒，常数 `$mul` 单列并由通用综合映射为 LUT。行 RAM 使用原 FPGA_MODE 包装及端口级 IP 黑盒，Gamma 保留原 RTL；同一脚本分别读取改前快照与改后源文件，使用 `synth -flatten -noabc; abc -lut 6 -dress; opt_clean`。同时记录 `proc; flatten` 后及 `opt` 后的 `$mul` 数，区分 RTL 展开计数和 Yosys 公共子表达式合并后的计数。

PDS B3F 原资源为 PIX 5000 LUT、7860 FF、132 APM（`resource_hier.txt`）。移除的灰度常数乘法按实例计 114 个，留下均值 12 个及对比度 6 个；**18 是 RTL 乘法实例口径，APM 最终数量仍以改后 PDS 为准**。本轮未运行 PDS，不能从通用 LUT6 数字推算 PDS LUT、FF、裕量或 Fmax。

卡 10 B3V/B3VN/B3R/B3F 的 `synthesis_paths.tsv` 中均没有以 `u_soc/u_pix/` 内部寄存器为起点或终点的已导出路径，因此本报告没有可引用的 PIX PDS 起点裕量/级数。复位控制器 `u_sys/u_reset_ctrl/u_pix/` 属于显示像素时钟复位，不能误作 PIX 图像处理数据路径。

## 验收

| 目录 | smoke | full |
|---|---|---|
| `verif/unit/pix_kernel` | PASS | PASS |
| `verif/unit/pix_filter` | PASS | PASS |
| `verif/unit/pix_point` | PASS | PASS |
| `verif/unit/pix_control` | PASS | PASS |
| `verif/block/pix` | PASS | PASS |
| `verif/soc/board_vision` | PASS（本机） | 不要求 |

四个单元两档均有用例。模块 smoke 包含模型自测及 12 个场景；full 执行 25 个场景，包括全部 7×7 级联组合、1280×720 全链路、各尺寸边界、随机间隙/反压、不完整帧及配置/复位行为。核单测只按新内部接口打包 Y 并延迟四次 advance，参考期望值、原有效序列和停顿激励不变。

单元/模块按协调者批准的新增主机安排执行，结果仅保留 worker 自主汇总；原始日志、构建和临时工具已清理。board_vision 在该主机的软件构建阶段失败，尚未进入仿真，按协调者要求回本机指定工具重跑并 PASS（102 s，`board-local.log`；详细记录 `build/board_vision/`），不修改 RTL 或测试去迁就该差异。

实际测试命令如下（执行时将各命令放在一个外层 flock 保护的串行批次；下列为等价的逐项命令）：

```sh
for unit in pix_kernel pix_filter pix_point pix_control; do
    flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path "verif/unit/$unit" -j 1
    flock /tmp/edrv32-sim.lock python3 tools/regress.py full --path "verif/unit/$unit" -j 1
done
flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/block/pix -j 1
flock /tmp/edrv32-sim.lock python3 tools/regress.py full --path verif/block/pix -j 1
flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/soc/board_vision -j 1
```

风格检查 `python3 tools/check/verilog_style.py rtl/media/pix`：6 文件，0 warnings（`style.log`）。在 `rtl/filelists/` 执行 `verilator --lint-only -Wall -DSIM_MODE --top-module edrv32_pix -f pix.f`：0 warnings（`lint.log`）。

所有 Verilator 编译/运行、回归和 Yosys 命令均由 `flock /tmp/edrv32-sim.lock` 串行执行；回归和仿真编译使用 `-j 1`，本机仿真与 lint 保持任务指定的 Verilator 5.020；新增主机的工具使用方式经协调者确认。

## 复现参考综合

在已配置上述本机工具的仓库根目录，将下面脚本保存为 `build/pix-resource/measure.py`。改前源文件快照按如下命令从 git 读取，其他未改动 RTL/头文件使用当前提交：

```sh
mkdir -p build/pix-resource/before build/pix-resource/after
git archive b09d3c8fc0de456e5b68b613f8324d516fbd6f04 rtl/media/pix | tar -xf - --strip-components=3 -C build/pix-resource/before
```

```python
import json, pathlib, subprocess, sys
from collections import Counter
root=pathlib.Path.cwd(); base=root/'build/pix-resource'; label=sys.argv[1]; out=base/label; out.mkdir(exist_ok=True)
src=out if label=='before' else root/'rtl/media/pix'
(base/'ram_stub.v').write_text('''(* blackbox *) module ip_ram_pix_line(input wr_clk,wr_rst,wr_en,input [9:0] wr_addr,input [47:0] wr_data,input rd_clk,rd_rst,rd_clk_en,input [9:0] rd_addr,output [47:0] rd_data); endmodule
''')
files=' '.join(str(p) for p in sorted(src.glob('*.v')))
commands=[f'read_verilog -D FPGA_MODE -I rtl/include {base}/ram_stub.v rtl/tech/edrv32_ram_pix_line.v {files}', 'hierarchy -top edrv32_pix', 'proc', 'flatten', f'write_json {out}/expanded.json', 'opt', f'write_json {out}/rtlil.json']
(out/'coarse.ys').write_text('\n'.join(commands)+'\n')
subprocess.run(['yosys','-Q','-T','-l',str(out/'coarse.log'),'-s',str(out/'coarse.ys')],check=True,stdout=subprocess.DEVNULL)
design=json.loads((out/'rtlil.json').read_text());raw=design['modules']['edrv32_pix']['cells']; mul=[]
for name,c in raw.items():
 if c['type']!='$mul':continue
 const=any(all(isinstance(x,str) for x in c['connections'][port]) for port in ['A','B'])
 mul.append({'name':name,'constant':const,'parameters':c['parameters'],'widths':{p:len(bits) for p,bits in c['connections'].items()}})
 if not const:
  kind='ip_mul_pix_'+str(len(mul));ports={};offset=2
  for p,bits in c['connections'].items():
   ports[p]={'direction':c['port_directions'][p],'bits':list(range(offset,offset+len(bits)))};offset+=len(bits)
  design['modules'][kind]={'attributes':{'blackbox':'1'},'ports':ports,'cells':{},'netnames':{}}
  c['type']=kind;c['parameters']={}
for module in design['modules'].values():
 for field in ['cells','netnames']:
  module[field]={('$pix_measure$'+name if name.startswith('$') else name):value for name,value in module[field].items()}
(out/'hard.json').write_text(json.dumps(design));(out/'multipliers.json').write_text(json.dumps(mul,indent=2))
commands=[f'read_json {out}/hard.json','synth -top edrv32_pix -flatten -noabc','abc -lut 6 -dress','opt_clean',f'write_json {out}/netlist.json','stat']
(out/'synth.ys').write_text('\n'.join(commands)+'\n')
subprocess.run(['yosys','-Q','-T','-l',str(out/'synth.log'),'-s',str(out/'synth.ys')],check=True,stdout=subprocess.DEVNULL)
net=json.loads((out/'netlist.json').read_text())['modules']['edrv32_pix'];counts=Counter(c['type'] for c in net['cells'].values());expanded=json.loads((out/'expanded.json').read_text())['modules']['edrv32_pix']['cells']
summary={'mul_expanded':sum(c['type']=='$mul' for c in expanded.values()),'mul_variable':sum(not x['constant'] for x in mul),'mul_constant':sum(x['constant'] for x in mul),'LUT':counts['$lut'],'FF':sum(v for k,v in counts.items() if 'DFF' in k),'cells':dict(counts)}
(out/'summary.json').write_text(json.dumps(summary,indent=2));print(summary)
```

```sh
flock /tmp/edrv32-sim.lock python3 build/pix-resource/measure.py before
flock /tmp/edrv32-sim.lock python3 build/pix-resource/measure.py after
python3 tools/synth/netlist_paths.py build/pix-resource/before/netlist.json
python3 tools/synth/netlist_paths.py build/pix-resource/after/netlist.json
```

计数来自 `summary.json`，`multipliers.json` 保留常数/变量分类及乘法端口宽度；`expanded.json`、`rtlil.json`、`hard.json`、`netlist.json` 分别对应展开、优化后粗网表、变量乘法黑盒化、最终 LUT6 网表。固定硬块端口逐项保持原连接和位宽，仅清空黑盒实例的原 `$mul` 参数；JSON 重载前为内部生成的单元/信号名加前缀，避免 Yosys 自动名称重用，RTL 寄存器名与连线不变；常数乘法原样留给通用综合。

## 连续流测量复现

将下面测量 bench 保存为 `build/pix-resource/perf_tb.sv`，使用上面的改前快照及改后 RTL，各发送同一组 1280×8 像素。配置为两级 Sobel，输出 ready 恒为 1；运行终止由输出 EOF 触发。它只记录性能，逐位正确性由仓库原有回归判定。

```systemverilog
module perf_tb;
    bit clk=0;
    always #4 clk=~clk;
    bit rst_n=0;
    bit in_valid=0;
    wire in_ready;
    logic [31:0] in_data=0;
    bit in_sof=0;
    bit in_eol=0;
    bit in_eof=0;
    wire out_valid;
    wire [31:0] out_data;
    wire out_sof,out_eol,out_eof;
    bit [11:0] addr=0;
    bit sel=0,en=0,wr=0;
    bit [31:0] wdata=0;
    wire ready,err,irq;
    wire [31:0] rdata;
    int cycle=0, first_in, last_in,first_out,last_out;
    int in_count=0,out_count=0;
    int stage1_in,stage2_in;
    int stage1_latency,stage2_latency;
    edrv32_pix dut (
        .clk_mem_i(clk),.rst_mem_n_i(rst_n),
        .pix_in_valid_i(in_valid),.pix_in_ready_o(in_ready),.pix_in_data_i(in_data),
        .pix_in_sof_i(in_sof),.pix_in_eol_i(in_eol),.pix_in_eof_i(in_eof),
        .pix_out_valid_o(out_valid),.pix_out_ready_i(1'b1),.pix_out_data_o(out_data),
        .pix_out_sof_o(out_sof),.pix_out_eol_o(out_eol),.pix_out_eof_o(out_eof),
        .apb_paddr_i(addr),.apb_psel_i(sel),.apb_penable_i(en),.apb_pwrite_i(wr),
        .apb_pwdata_i(wdata),.apb_pstrb_i(4'hf),.apb_pready_o(ready),
        .apb_prdata_o(rdata),.apb_pslverr_o(err),.irq_o(irq)
    );
    always @(posedge clk) begin
        cycle++;
        if (rst_n) begin
            if (in_valid && in_ready) begin
                if (in_sof) first_in=cycle;
                if (in_eof) last_in=cycle;
                in_count++;
            end
            if (dut.point1_valid_w && dut.point1_sof_w) stage1_in=cycle;
            if (dut.stage1_valid_w && dut.stage1_sof_w) begin
                stage1_latency=cycle-stage1_in;
                stage2_in=cycle;
            end
            if (dut.stage2_valid_w && dut.stage2_sof_w)
                stage2_latency=cycle-stage2_in;
            if (out_valid) begin
                if (out_sof) first_out=cycle;
                out_count++;
                if (out_eof) begin
                    last_out=cycle;
                    $display("PERF width=1280 height=8 inputs=%0d input_cycles=%0d outputs=%0d output_cycles=%0d s1=%0d s2=%0d eof_flush=%0d",in_count,last_in-first_in+1,out_count,last_out-first_out+1,stage1_latency,stage2_latency,last_out-last_in);
                    $finish;
                end
            end
        end
    end
    task automatic apb_write(input bit [11:0] a,input bit [31:0] d);
        @(negedge clk);addr=a;wdata=d;sel=1;wr=1;
        @(negedge clk);en=1;
        @(negedge clk);sel=0;wr=0;en=0;
    endtask
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        apb_write(12'h100,32'h00000440);
        apb_write(12'h004,1);
        for (int beat=0;beat<5120;beat++) begin
            @(negedge clk);
            in_valid=1;in_data=32'(beat*123471);
            in_sof=beat==0;in_eol=beat%640==639;in_eof=beat==5119;
            do begin @(posedge clk);end while(!in_ready);
        end
        @(negedge clk);in_valid=0;
    end
endmodule
```

将下列命令保存为 `build/pix-resource/perf.sh`，执行 `flock /tmp/edrv32-sim.lock bash build/pix-resource/perf.sh`：

```sh
#!/bin/bash
set -e
for phase in before after; do
    source_dir=rtl/media/pix
    if [ "$phase" = before ]; then source_dir=build/pix-resource/before; fi
    verilator --binary --timing -j 1 -DSIM_MODE +incdir+rtl/include --top-module perf_tb --Mdir "build/pix-resource/$phase/perf-obj" -o sim rtl/tech/edrv32_ram_pix_line.v "$source_dir"/*.v build/pix-resource/perf_tb.sv > "build/pix-resource/$phase/perf-build.log" 2>&1
    "build/pix-resource/$phase/perf-obj/sim" > "build/pix-resource/$phase/perf-run.log" 2>&1
done
```
