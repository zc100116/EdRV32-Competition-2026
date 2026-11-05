#!/usr/bin/env python3
# File: b2_early_stats.py
# Spec: cpu-spec 4.10; T-CPU-N-BE performance follow-up.
# Description: Replay the step-2 RTL snapshot and count early-query outcomes in B2.
# Requires R-05 software/images built by b2_run.py; instrumentation is testbench-only.
# Clock: none (host tool).
from pathlib import Path
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from tools.regress import expand_files
out=ROOT/'build/cpu/early-stats/c03b5f35'
out.mkdir(parents=True,exist_ok=True)
bench=out/'edrv32_cpu_b2_tb.sv'
s=subprocess.check_output(['git','show','c03b5f35:verif/block/cpu_b2/edrv32_cpu_b2_tb.sv'],cwd=ROOT,text=True)
pos=s.index('    task automatic load_image')
s=s[:pos]+'''    longint unsigned load_issued=0;
    longint unsigned eligible=0;
    longint unsigned successes=0;
    longint unsigned fail_port=0;
    longint unsigned fail_store=0;
    longint unsigned fail_device=0;
    longint unsigned fail_miss=0;
    longint unsigned fail_hold=0;
    longint unsigned repair_cycles=0;
    int reason_r=0;
    always @(posedge clk_i) begin
        if (rst_n_i) begin
            if (measuring_r[0]) begin
                if (u_dut.u_core.d_issue_w!=0 &&
                    u_dut.u_core.d_class_w[u_dut.u_core.d_map_w[0]]==6) load_issued++;
                if (u_dut.dc_early_valid_w) eligible++;
                if (u_dut.u_core.e_repair_pending_r) repair_cycles++;
                if (u_dut.u_core.e_early_r && u_dut.u_core.e_valid_r[0]) begin
                    if (!u_dut.u_core.e_advance_w) fail_hold++;
                    else if (u_dut.dc_early_hit_w) successes++;
                    else if (reason_r==1) fail_store++;
                    else if (reason_r==2) fail_device++;
                    else if (reason_r==3) fail_port++;
                    else if ((u_dut.u_dcache.buffer_valid_r &&
                        u_dut.u_dcache.buffer_addr_r[31:2]==u_dut.u_dcache.early_addr_r[31:2]) ||
                        (u_dut.u_dcache.store_pending_r &&
                        u_dut.u_dcache.store_addr_r[31:2]==u_dut.u_dcache.early_addr_r[31:2]))
                        fail_store++;
                    else fail_miss++;
                end
            end
            if (u_dut.dc_early_valid_w) begin
                if (u_dut.u_dcache.early_conflict_w) reason_r<=1;
                else if (!u_dut.u_dcache.early_cacheable_w) reason_r<=2;
                else if (!u_dut.u_dcache.early_read_w) reason_r<=3;
                else reason_r<=4;
            end
        end
    end
'''+s[pos:]
s=s.replace('    task automatic report_window(input int w);', '''    task automatic report_window(input int w);
        $display("EARLY_STATS issued=%0d eligible=%0d success=%0d port=%0d store=%0d device=%0d miss=%0d hold=%0d repair_cycles=%0d",
            load_issued,eligible,successes,fail_port,fail_store,fail_device,fail_miss,
            fail_hold,repair_cycles);''')
bench.write_text(s)
sources=expand_files(ROOT/'verif/block/cpu_b2/files.f')
snapshot_sources=[]
for source in sources:
 path=Path(source)
 if path.suffix=='.v' and path.is_relative_to(ROOT/'rtl'):
  relative=path.relative_to(ROOT)
  target=out/relative
  target.parent.mkdir(parents=True,exist_ok=True)
  target.write_bytes(subprocess.check_output(['git','show',f'c03b5f35:{relative}'],cwd=ROOT))
  snapshot_sources.append(str(target))
 elif path.name=='edrv32_cpu_b2_tb.sv':
  snapshot_sources.append(str(bench))
 else:
  snapshot_sources.append(source)
sources=snapshot_sources
with (out/'compile.log').open('w') as log:
 subprocess.run(['verilator','--binary','--timing','-Wall','+define+SIM_MODE','--top-module','edrv32_cpu_b2_tb','--Mdir',str(out/'obj'),'-o','sim','-j','1',*sources],stdout=log,stderr=subprocess.STDOUT,check=True,cwd=ROOT)
elf=ROOT/'build/sw/coremark/coremark.elf'
symbols={line.split()[2]:line.split()[0] for line in subprocess.check_output(['riscv-none-elf-nm',str(elf)],text=True).splitlines() if len(line.split())==3}
cmd=[str(out/'obj/sim'),f'+ROM_HEX={ROOT}/build/cpu_b2/r05/no-c/boot.hex',f'+SRAM_HEX={elf.parent}/sram.hex',f'+DDR_HEX={elf.parent}/ddr.hex',f'+TOHOST={symbols["tohost"]}',f'+PERF_BEGIN={symbols["start_time"]}',f'+PERF_END={symbols["stop_time"]}','+READ_LATENCY=2','+TIMEOUT=100000000']
with (out/'run.log').open('w') as log:
 subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,check=True,cwd=ROOT)
print('\n'.join(l for l in (out/'run.log').read_text().splitlines() if 'EARLY_STATS' in l or 'B2_WINDOW' in l))
