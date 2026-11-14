# RND COPY 位列控制扇出参考测量
版本：本报告所在提交，接续 `b8c5e211`；rnd-spec 2.6、5.2、5.3。
8 个位列各收集 64 个同字节位，右移偏移后取 32 位并交织输出；仍是单次对齐，无新增流水级。
8 份 `align_offset_r` 均带 keep/syn_preserve，仅在 S_COUNTS 更新、不复位，语义不变。
8 份 `read_overflow_r` 带 keep/syn_preserve，各仅选择一个位列的 32 位当前数据；删除组合副本。
选择标志异步清零、取消时保持，S_WRITE 握手置零，S_STREAM 握手取 `(write_next_w + align_ahead_r)[9]`。
与写索引同拍更新，RAM 读地址逻辑不变。

Yosys 0.70+219，COPY 单模块 LUT6 参考映射：**3,319 LUT6、1,432 FF**；RAM 和两处变量乘法器作为硬边界。

| 位列 | 偏移 bit[0..4] 的输入负载 | read_overflow_r 负载 |
|---|---|---|
| 0、2、4、6 | 60,60,49,48,32 | 每份 32 |
| 1、3、5 | 60,60,50,48,32 | 每份 32 |
| 7 | 62,60,50,48,32 | 32 |

相较 b8c5e211：偏移每份最大 197–226 → 60–62，选择信号 256 → 每份 32；非 PDS 布线测量。
`python3 tools/regress.py smoke --path verif/unit/rnd_copy -j 4`：仅跑一次，1 PASS / 0 FAIL；
1,024 偏移、64 最大行、重叠、4 KiB、背压、连续输出、取消/重启全部 PASS；未跑 block/rnd。
`python3 tools/check/verilog_style.py rtl/media/rnd/edrv32_rnd_copy.v`：1 文件、0 告警；diff 检查通过，跨 generate 层次引用 0 处。
Verilator 5.020 `--lint-only --timing -Wall -j 1 -DSIM_MODE --top-module <top>`：RND/SoC/FPGA full 均 0 告警。
用 tools.regress.expand_files 展开 rnd.f/soc.f；FPGA full 使用 board_vnpu/files.f + rnd.f + full_top.v，无告警屏蔽。

仅综合一次；原始数据 `build/fanout-rnd2/yosys/{loads.tsv,hardnet.json,*.ys,*.log}`；复现单模块测量：
```python
from pathlib import Path
import subprocess
from tools.synth.fanout_soc import run_yosys, preserve_registers, census
from tools.rnd.timing_measure import retain_multipliers
p = Path('build/fanout-rnd2/yosys').resolve()
p.mkdir(parents=True, exist_ok=True)
(p/'ram.v').write_text(Path('rtl/tech/edrv32_ram_rnd_line.v').read_text().split(');', 1)[0] + ');\nendmodule\n')
top = 'edrv32_rnd_copy'
run_yosys(p, 'proc', [f'read_verilog -lib -D SIM_MODE -Irtl/include {p}/ram.v', 'read_verilog rtl/media/rnd/edrv32_rnd_decode.v rtl/media/rnd/edrv32_rnd_copy.v', f'hierarchy -top {top}', 'proc', 'flatten', f'write_json {p}/proc.json'])
preserve_registers(p, top)
run_yosys(p, 'coarse', [f'read_json {p}/preserved.json', 'opt', 'wreduce', 'opt_clean', f'write_json {p}/coarse.json'])
retain_multipliers(p, top)
subprocess.run(['yosys', '-Q', '-T', '-s', str(p/'hardmul.ys')], check=True)
census(p, top)
```
