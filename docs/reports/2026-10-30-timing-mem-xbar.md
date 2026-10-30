# X-F1 mem_xbar timing candidate

- Date: 2026-10-30; clk_mem target 125 MHz / 8 ns.
- Baseline RTL: `8977d1f43484942b32319d4e7046dbf9f673f219`; `git diff origin/win/20261029-07-b3-rerun 8977d1f -- rtl/mem/edrv32_mem_xbar*.v` is empty.
- B3V routed reference: `d0dd945e1bbcb889e2c16f6e361d2c687430e771`, `tasks/win/20261029-07-b3-rerun/artifacts/B3V/timing_all_paths.tsv`.
- Candidate RTL commit: `ef82f515d942e03cbb2d52c7f90714471de2d933` (`mem_xbar: shorten read-buffer and error capture paths`).
- Reference PDS: 2022.2-SP6.1 build138931, PG2L200H-6/FBB676 (from the B3 result); the new generic synthesis has no device/speed-grade mapping.
- Yosys: 0.70+219 (5053d0e26); generic LUT6, synchronous IP port-only blackboxes; no new PDS result.
- Standard simulation/lint: Verilator 5.020, sourced from `~/.local/opt/edrv32/env.sh`; test.yaml files unchanged.

## Behavior and changes

`edrv32_mem_xbar.v`: register each ingress violation pulse, then use the address/type payload captured at that same handshake to select the original last-port/AW-priority error. ERR_ADDR/ERR_PORT/ERR_TYPE and IRQ_STAT.ERROR update **one clk_mem cycle later**; coordinator approved this on 2026-10-30. A reporting violation still wins over a same-cycle software IRQ clear. SLVERR routing, downstream-error pass-through and statistics timing stay unchanged. WAIT+1 is predicted per head on the preceding edge, including W-complete, saturation, enqueue and retirement.

`edrv32_mem_xbar_rbuf.v`: retain the active descriptor's available beats and next address per port, so arbitration no longer selects a descriptor and then adds its start/fetched offsets. Cache the round-robin mask and pending destination valid bits; drive the RAM address by a one-hot selection. Allocation, return/fetch coincidence, per-port order and global ring retirement retain their existing edges.

`edrv32_mem_xbar_sched.v`: cache rotation masks in place of encoded pointers; calculate the read/write DRR choices and token candidate arithmetic in parallel before final class/direction selection. The original prepare/grant cadence is preserved. An earlier registered-output variant reduced throughput and was removed.

`edrv32_mem_xbar_regs.v`: perform event arithmetic at each port before selection; cache carry predicates for +1 counters and update their bytes in parallel. SNAPSHOT still captures pre-update values and CLEAR still wins over increments. Added control predicates reset; payload/prediction registers do not reset.

`verif/unit/mem_xbar/tb.sv`: cover delayed ingress errors, error-versus-clear priority, unchanged violation/grant counts, SNAPSHOT+CLEAR, and +1 counter carry boundaries. Existing scheduler/rate tests and workloads are unchanged. No PERF_MON, shared filelist, IP wrapper or specification file changed.

## Path measurements

All Yosys counts below are **logic levels, not ns**. The flattened table uses the same flow before/after: `synth -flatten -noabc; dffunmap; abc -lut 6 -dress; opt_clean`, then `tools/synth/netlist_paths.analyze`. Register-family filters include D/enable endpoints and the new carry predicates. Disconnected direct paths are shown as cut, never as an invented zero-depth measurement.

| Task class | B3V actual PDS path / slack | Flattened Yosys before | Flattened Yosys after | Interpretation / residual |
|---|---|---:|---:|---|
| 1 | port_head → RBUF DRM read ADB / −0.085 ns | 23 | direct path cut | Replacement RBUF FF→RAM-address maximum **11**; isolated RBUF **19→9**. Replacement starts at skid_valid/pending-valid, not port_head. |
| 2 | VIN memory-source AR → ERR_ADDR/ERR_PORT CE / +0.005 ns | 12 | direct path cut | New ingress stage **5**, capture stage **7** maximum across all ports; approved one-cycle reporting delay. |
| 3 | VIN channel AW → ERR registers / +0.053 ns | 11 | direct path cut | Same new 5/7-stage bounds as class 2. Upstream VIN logic is outside this XBAR synthesis boundary. |
| 4 | SCHED preferred → token state / +0.103 ns | 15 | **13** | Entire flattened SCHED FF→FF alternative maximum **16→15**; isolated scheduler all-start/all-end maximum **15→8**. Flattened alternatives remain above 8. |
| 5 | SCHED preferred → cmd_wait / +0.352 ns | 18 | **13** | Flattened alternative maximum over all SCHED state→cmd_wait **19→15**, now starting at a starvation rotation mask. Above-8 residual is disclosed. |
| 6 | RBUF DRM output → ar_wait CE / +0.375 ns; PDS 4 levels | not reachable | not reachable | This specific combinational route is absent in both Yosys netlists. Its PDS result must be checked in the next routed run. |
| 7 | WR_TXN[6] internal → WR_TXN[6] / +0.374 ns | 14 | **6** | New byte carry pipeline cuts the reported family. Other flattened statistics FF→FF alternatives remain **15→14** (WR_BEAT), isolated entire register block **12→10** (WAIT_SUM input path). These are Yosys alternatives, not a new PDS measurement. |

The coordinator accepted this candidate and its disclosed >8-level residuals on 2026-10-30, explicitly requesting no further expansion and deferring the final decision to PDS.

Generic flattened resources: **14979→16001 LUT6 (+1022)**, **6781→7198 FF (+417)**; seven RAM blackboxes in both versions. These are Yosys estimates, not PG2L200H utilization or a PDS area acceptance result.

Raw evidence:

- `build/x_f1/baseline.json`, `wait_prediction.json`, corresponding `.ys` and `.log`.
- `build/x_f1/baseline_primary.json`, `wait_prediction_primary.json`, `primary_paths.log`.
- `build/x_f1/baseline_paths.json`, `wait_prediction_paths.json` for broad alternative families.
- `build/x_f1/module_before_rbuf*`, `module_after2_rbuf*`, `module_before_regs*`, `regs_carry_final_regs*`, `module_before_sched*`, `sched_parallel_final*` for isolated modules.
- `build/x_f1/synth.py`, `module_measure.py`, `sched_measure.py`, `measure.py`, `primary_paths.py` reproduce the build-local measurements. The analyzer input discards dangling, undriven aliases left by optimization; connected nets/cells are unchanged.

## Steady-state throughput

Same `build/x_f1/throughput.sv` bench and 1920-cycle measurement window after 128 warm-up cycles, no RATE restriction, nonzero equal weights. Baseline and final RTL have identical first-grant cycle (3) and grant counts; normal grant interval is 2 cycles, with 4-cycle deficit-refill intervals.

| Workload | Baseline grants / 1920 cycles | Final grants / 1920 cycles |
|---|---:|---:|
| One saturated port, 1 beat | 956 | 956 |
| Two saturated ports, 1 beat | 958 | 958 |
| Three saturated ports, 1 beat | 959 | 959 |
| Three saturated ports, 16 beats | 939 | 939 |

Commands (after sourcing env.sh):

```sh
iverilog -g2012 -s throughput -o build/x_f1/throughput_before build/x_f1/throughput.sv build/x_f1/before_src/edrv32_mem_xbar_sched.v
vvp build/x_f1/throughput_before
iverilog -g2012 -s throughput -o build/x_f1/throughput_restored build/x_f1/throughput.sv rtl/mem/edrv32_mem_xbar_sched.v
vvp build/x_f1/throughput_restored
```

The rejected output-register variant produced 638/639/640/630 grants in those four rows; it is not in the candidate. MX-02 remains the original single-beat, 50000-cycle rate test.

## Validation

- Style: `python3 tools/check/verilog_style.py rtl/mem/edrv32_mem_xbar*.v`: four files, **0 warnings**.
- Lint: `tools/check/lint.sh -DSIM_MODE -Irtl/include --top-module edrv32_mem_xbar rtl/mem/edrv32_mem_xbar*.v rtl/tech/edrv32_ram_mem_xbar_r.v rtl/tech/edrv32_ram_mem_xbar_w.v`: **0 warnings**.
- `git diff --check`: PASS.
- `python3 tools/regress.py smoke --path verif/unit/mem_xbar -j 1`: **2 PASS, 0 FAIL**, **72.78 s**; Verilator 70 s, Icarus 3 s. Evidence `build/x_f1/unit_smoke_final.log` and `build/regress/smoke/unit/mem_xbar/`.
- Additional Icarus full-unit bench: `iverilog -g2012 -DSIM_MODE -s tb -Ptb.FULL=1 -o ../../../build/x_f1/unit_carry_full -f files.f` from `verif/unit/mem_xbar`, then `vvp`: **PASS**, **77.20 s**. Covers the unmodified MX-02 single-beat token rate, DRR shares/starvation, byte/high-half carry, WAIT timestamps, saturation and atomic snapshots. Evidence `build/x_f1/iverilog_full_final2.log`.
- SAT proof: `yosys -Q -T -l build/x_f1/count_proof.log -p 'read_verilog build/x_f1/count_proof.v; prep -top count_proof; flatten; sat -verify -prove mismatch_o 0 -show-inputs'`: **SUCCESS**. Compares the implemented byte increment to mathematical 32-bit saturating +1 and proves the cached-predicate invariant for every value/update combination.
- `python3 tools/regress.py smoke --path verif/block/mem_subsys -j 1`: **17 PASS, 0 FAIL**, **363.77 s**, standard unmodified test.yaml settings and no other worker compiler running at start. Evidence `build/x_f1/block_smoke_final.log` and `build/regress/smoke/block/mem_subsys/`.

Earlier non-acceptance runs encountered compile timeouts/OOM while other workloads were active. Temporary test build flags were restored; no test.yaml or regression-tool change is in the candidate. The final standard-settings unit smoke ran with no other worker's Verilator/cc1plus process and passed; exit 132 did not recur, so the coordinator's conditional B3 tool-reproduction step was not triggered.

## Reproduction sources

Run from the repository root at candidate RTL commit `ef82f515d942e03cbb2d52c7f90714471de2d933`, after sourcing `~/.local/opt/edrv32/env.sh`. Save the following code blocks under the indicated `build/x_f1/` filenames; all generated files remain under build. This keeps the measurement and throughput evidence reproducible after the worker worktree is released.

Create the baseline source directory first:

```sh
mkdir -p build/x_f1/before_src
for module in rbuf sched xbar regs; do
    if [ "$module" = xbar ]; then
        file=edrv32_mem_xbar.v
    else
        file=edrv32_mem_xbar_${module}.v
    fi
    git show 8977d1f43484942b32319d4e7046dbf9f673f219:rtl/mem/$file > build/x_f1/before_src/$file
done
```

`build/x_f1/synth.py`:

```python
from pathlib import Path
import sys, subprocess
root=Path.cwd(); out=root/'build/x_f1'; tag=sys.argv[1]
stubs=out/'stubs.v'
stubs.write_text('\n'.join(f'''(* blackbox *) module ip_ram_mem_xbar_{n} (
input wr_clk, input wr_rst, input wr_en, input [8:0] wr_addr,
input [{width-1}:0] wr_data, input rd_clk, input rd_rst, input rd_clk_en,
input [8:0] rd_addr, output [{width-1}:0] rd_data);
endmodule''' for n,width in [('r',259),('w',288)]))
base=Path('build/x_f1/before_src' if tag=='baseline' else 'rtl/mem')
files=[base / n for n in ['edrv32_mem_xbar_rbuf.v', 'edrv32_mem_xbar_sched.v', 'edrv32_mem_xbar.v', 'edrv32_mem_xbar_regs.v']]+[Path('rtl/tech/edrv32_ram_mem_xbar_r.v'),Path('rtl/tech/edrv32_ram_mem_xbar_w.v'),stubs]
script=out/f'{tag}.ys'
script.write_text('read_verilog -D FPGA_MODE -Irtl/include '+' '.join(map(str,files))+f'\nhierarchy -top edrv32_mem_xbar\nsynth -top edrv32_mem_xbar -flatten -noabc\ndffunmap\nabc -lut 6 -dress\nopt_clean\nwrite_json {out}/{tag}.json\nstat\n')
subprocess.run(['yosys','-Q','-T','-l',str(out/f'{tag}.log'),'-s',str(script)],check=True,stdout=subprocess.DEVNULL)
```

`build/x_f1/module_measure.py`:

```python
from pathlib import Path
import sys,subprocess,json
sys.path.insert(0,str(Path.cwd()))
from tools.synth.netlist_paths import analyze
name,tag=sys.argv[1:];p=Path('build/x_f1');top='edrv32_mem_xbar_'+name
src=Path('build/x_f1/before_src') if tag=='module_before' else Path('rtl/mem')
extra=' rtl/tech/edrv32_ram_mem_xbar_r.v build/x_f1/stubs.v' if name=='rbuf' else ''
script=p/f'{tag}_{name}.ys';script.write_text(f'read_verilog -D FPGA_MODE -Irtl/include {src}/{top}.v{extra}\nsynth -top {top} -flatten -noabc\ndffunmap\nabc -lut 6 -dress\nopt_clean\nwrite_json {p}/{tag}_{name}.json\n')
subprocess.run(['yosys','-Q','-T','-l',str(p/f'{tag}_{name}.log'),'-s',str(script)],check=True,stdout=subprocess.DEVNULL)
x=json.loads((p/f'{tag}_{name}.json').read_text())
# Remove dangling aliases before asking for register-start cuts.
m=x['modules'][top];driven={b for c in m['cells'].values() for pt,bits in c['connections'].items() if c['port_directions'][pt]=='output' for b in bits};driven.update(b for v in m['ports'].values() for b in v['bits'])
for n,v in list(m['netnames'].items()):
 if any(isinstance(b,int) and b not in driven for b in v['bits']):del m['netnames'][n]
r=analyze(x,ends=[r'u_ram.*rd_addr'] if name=='rbuf' else None)
(p/f'{tag}_{name}_paths.json').write_text(json.dumps(r,indent=2));print(name,tag,r['max_levels']);print([(v['start']['signal'],v['end']['signal'],v['levels']) for v in r['paths'][:4]])
```

`build/x_f1/measure.py`:

```python
import sys,json
from pathlib import Path
sys.path.insert(0,str(Path.cwd()))
from tools.synth.netlist_paths import analyze
x=json.loads(Path('build/x_f1/'+sys.argv[1]+'.json').read_text())
m=x['modules']['edrv32_mem_xbar']
driven={b for c in m['cells'].values() for p,bits in c['connections'].items() if c['port_directions'][p]=='output' for b in bits}
driven.update(b for p in m['ports'].values() for b in p['bits'])
for n,v in list(m['netnames'].items()):
 if any(isinstance(b,int) and b not in driven for b in v['bits']):del m['netnames'][n]
cases=[('1',None,[r'u_rbuf.u_ram.u_ip.rd_addr'],None),('2/3',[r'^p[0-6]_(ar|aw)'],[r'u_regs.err_(addr|port|type)_r'],None),('4',[r'u_sched\..*_r'],[r'u_sched\..*_r'],None),('5',[r'u_sched\..*_r'],[r'cmd_wait_r'],None),('6',[r'u_rbuf.u_ram.rd_data_o'],[r'ar_wait_r'],None),('7',[r'u_regs\..*_r'],[r'u_regs\..*_r'],None)]
results={}
for n,a,b,c in cases:
 r=analyze(x,a,b,c);results[n]=r
 print(n,r['max_levels'], 'endpoints',r['endpoint_count'])
 for p in r['paths'][:2]:print(p['start']['signal'],'->',p['end']['signal'],p['end']['pin'])
Path('build/x_f1/'+sys.argv[1]+'_paths.json').write_text(json.dumps(results,indent=2))
```

`build/x_f1/primary_paths.py`:

```python
from pathlib import Path
import json
from tools.synth.netlist_paths import analyze
cases=[
 ('1_primary',[r'^u_rbuf.port_head_r'],[r'u_rbuf.u_ram.u_ip.rd_addr']),
 ('1_replacement',None,[r'u_rbuf.u_ram.u_ip.rd_addr']),
 ('2_primary',[r'^p1_ar'],[r'^u_regs.err_(addr|port|type)_r']),
 ('3_primary',[r'^p1_aw'],[r'^u_regs.err_(addr|port|type)_r']),
 ('23_ingress',[r'^p[0-6]_(ar|aw)'],[r'^ingress_error_r']),
 ('23_capture',[r'^(ingress_error_r|ar_error_r|aw_error_r|araddr_r|awaddr_r)'],[r'^u_regs.err_(addr|port|type)_r']),
 ('4_primary',[r'^u_sched.preferred_r'],[r'^u_sched.tokens_r']),
 ('5_primary',[r'^u_sched.preferred_r'],[r'^cmd_wait_r']),
 ('7_primary',[r'^u_regs.wr_txn(_carry)?_r'],[r'^u_regs.wr_txn(_carry)?_r'])]
for tag in ['baseline','wait_prediction']:
 d=json.loads(Path('build/x_f1/'+tag+'.json').read_text());m=d['modules']['edrv32_mem_xbar']
 driven={b for c in m['cells'].values() for p,bits in c['connections'].items() if c['port_directions'][p]=='output' for b in bits};driven.update(b for v in m['ports'].values() for b in v['bits'])
 for n,v in list(m['netnames'].items()):
  if any(isinstance(b,int) and b not in driven for b in v['bits']):del m['netnames'][n]
 out={}
 for n,a,b in cases:
  r=analyze(d,a,b);out[n]=r
  print(tag,n,r['max_levels'],flush=True)
 Path('build/x_f1/'+tag+'_primary.json').write_text(json.dumps(out,indent=2))
```

`build/x_f1/throughput.sv`:

```systemverilog
module throughput;
reg clk=0; always #4 clk=!clk;
reg rst_n=0;
reg [13:0] candidates=0;
reg [69:0] beats=0;
wire prepare;
wire grant;
wire [2:0] port;
wire write;
wire urgent;
wire dswitch;
reg [27:0] weight=28'hfffffff;
edrv32_mem_xbar_sched dut(.clk_i(clk),.rst_n_i(rst_n),.enable_i(1'b1),
 .candidates_i(candidates),.queued_i(candidates),.prepare_o(prepare),
 .eligible_i(candidates),.beats_i(beats),.starved_i(14'b0),.urgent_i(2'b0),
 .grant_o(grant),.port_o(port),.write_o(write),.urgent_o(urgent),.dir_switch_o(dswitch),
 .urg_max_i(8'd8),.dir_batch_i(8'd4),.weight_i(weight),.rate_i(63'b0));
integer n,p,cycle,count,last,min_gap,max_gap,first;
initial begin
 for(n=1;n<=4;n=n+1)begin
  rst_n=0;candidates=0;
  for(p=0;p<14;p=p+1)beats[p*5+:5]=n==4?16:1;
  candidates[6]=1;if(n>=2)candidates[8]=1;if(n>=3)candidates[10]=1;
  repeat(3)@(negedge clk);rst_n=1;count=0;last=-1;min_gap=999;max_gap=0;first=-1;
  for(cycle=0;cycle<2048;cycle=cycle+1)begin
   @(posedge clk);
   if(grant)begin
    if(first<0)first=cycle;
    if(cycle>=128)begin
     count=count+1;
     if(last>=128)begin
      if(cycle-last<min_gap)min_gap=cycle-last;
      if(cycle-last>max_gap)max_gap=cycle-last;
     end
     last=cycle;
    end
   end
   @(negedge clk);
  end
  $display("ports=%0d beats=%0d grants=%0d/1920 first=%0d gap=%0d..%0d",n==4?3:n,n==4?16:1,count,first,min_gap,max_gap);
 end
 $finish;
end
endmodule
```

`build/x_f1/count_proof.v`:

```verilog
module count_proof(input [31:0] value_i, input update_i, output mismatch_o);
    function [31:0] count_inc;
        input [31:0] value_i;
        input [3:0] carry_i;
        begin
            count_inc = carry_i[3] ? value_i :
                {(value_i[31:24] + {7'b0, carry_i[2]}),
                    (value_i[23:16] + {7'b0, carry_i[1]}),
                    (value_i[15:8] + {7'b0, carry_i[0]}), (value_i[7:0] + 8'd1)};
        end
    endfunction

    function [3:0] count_carry;
        input [31:0] value_i;
        input update_i;
        input full_i;
        begin
            count_carry = update_i && !full_i ?
                {value_i == 32'hffff_fffe, value_i[23:0] == 24'hffff_fe,
                    value_i[15:0] == 16'hfffe, value_i[7:0] == 8'hfe} :
                {(&value_i), (&value_i[23:0]), (&value_i[15:0]), (&value_i[7:0])};
        end
    endfunction


wire [3:0] carry_w = {(&value_i), (&value_i[23:0]), (&value_i[15:0]), (&value_i[7:0])};
wire [31:0] expected_w = !update_i || value_i == 32'hffffffff ? value_i : value_i + 32'd1;
wire [31:0] actual_w = update_i ? count_inc(value_i,carry_w) : value_i;
wire [3:0] expected_carry_w = {(&expected_w), (&expected_w[23:0]),
 (&expected_w[15:0]), (&expected_w[7:0])};
assign mismatch_o = expected_w != actual_w ||
 expected_carry_w != count_carry(value_i,update_i,carry_w[3]);
endmodule
```

Re-run the flattened measurements and isolated checks:

```sh
python3 build/x_f1/synth.py baseline
python3 build/x_f1/synth.py wait_prediction
python3 build/x_f1/measure.py baseline
python3 build/x_f1/measure.py wait_prediction
PYTHONPATH=. python3 build/x_f1/primary_paths.py
python3 build/x_f1/module_measure.py rbuf module_before
python3 build/x_f1/module_measure.py rbuf module_after2
python3 build/x_f1/module_measure.py regs module_before
python3 build/x_f1/module_measure.py regs regs_carry_final
python3 build/x_f1/module_measure.py sched module_before
python3 build/x_f1/module_measure.py sched module_after
```

The throughput and SAT commands above use the embedded bench/proof sources. The fixed `count_proof.v` contains the two functions taken from the candidate RTL and proves both the increment and predicate-next-state relation.
