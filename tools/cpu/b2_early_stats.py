#!/usr/bin/env python3
# File: b2_early_stats.py
# Spec: cpu-spec 4.4, 4.10; T-CPU-N-TOUR.
# Description: Count early-load and tournament outcomes in the R-05 window.
# Use the working tree or a requested git commit; instrumentation is testbench-only.
# Clock: none (host tool).
import argparse
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.regress import expand_files  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--commit', help='Replay RTL and B2 testbench at this git commit')
    args = parser.parse_args()
    revision = subprocess.check_output(
        ['git', 'rev-parse', '--short', args.commit or 'HEAD'], cwd=ROOT, text=True).strip()
    out = ROOT / 'build/cpu/early-stats' / (revision if args.commit else 'worktree')
    out.mkdir(parents=True, exist_ok=True)

    def source(path):
        if args.commit:
            return subprocess.check_output(['git', 'show', f'{args.commit}:{path}'],
                                           cwd=ROOT, text=True)
        return (ROOT / path).read_text()

    subsys = source('rtl/soc/edrv32_cpu_subsys.v')
    early_hit = ('(|u_dut.dc_early_way_hit_w)' if 'dc_early_way_hit_w' in subsys else
                 'u_dut.dc_early_hit_w')
    stats = '''
    longint unsigned load_issued=0, eligible=0, successes=0;
    longint unsigned fail_port=0, fail_store=0, fail_device=0, fail_miss=0;
    longint unsigned fail_hold=0, fail_maintenance=0, repair_cycles=0;
    longint unsigned f2_corrections=0, branches=0, direction_misses=0;
    longint unsigned global_misses=0;
    int reason_r=0;
'''
    stats += '''
    always @(posedge clk_i) begin
        if (rst_n_i) begin
            if (measuring_r[0]) begin
                if (u_dut.u_core.u_frontend.f2_correct_w) f2_corrections++;
                if (u_dut.u_core.e_resolve_w &&
                    u_dut.u_core.e_survive_w[u_dut.u_core.e_branch_lane_w] &&
                    u_dut.u_core.e_class_r[u_dut.u_core.e_branch_lane_w]==5) begin
                    branches++;
                    if (u_dut.u_core.e_record_r[u_dut.u_core.e_branch_lane_w][100] !=
                        u_dut.u_core.e_lane_taken_w[u_dut.u_core.e_branch_lane_w])
                        direction_misses++;
                    if (u_dut.u_core.e_tournament_r[11] !=
                        u_dut.u_core.e_lane_taken_w[u_dut.u_core.e_branch_lane_w])
                        global_misses++;
                end
                if (u_dut.u_core.d_issue_w!=0 &&
                    u_dut.u_core.d_class_w[u_dut.u_core.d_map_w[0]]==6) load_issued++;
                if (u_dut.dc_early_valid_w) eligible++;
                if (u_dut.u_core.e_repair_pending_r) repair_cycles++;
                if (u_dut.u_core.e_early_r && u_dut.u_core.e_valid_r[0]) begin
                    if (!u_dut.u_core.e_advance_w) fail_hold++;
                    else if (EARLY_HIT) successes++;
                    else if (reason_r==1) fail_store++;
                    else if (reason_r==2) fail_device++;
                    else if (reason_r==3) fail_port++;
                    else if (reason_r==4 || u_dut.u_dcache.maintenance_r ||
                        u_dut.u_dcache.maintenance_start_w) fail_maintenance++;
                    else if ((u_dut.u_dcache.buffer_valid_r &&
                        u_dut.u_dcache.buffer_addr_r[31:2]==u_dut.u_dcache.early_addr_r[31:2]) ||
                        (u_dut.u_dcache.store_pending_r &&
                        u_dut.u_dcache.store_addr_r[31:2]==u_dut.u_dcache.early_addr_r[31:2]) ||
                        (u_dut.u_dcache.lookup_valid_r && u_dut.u_dcache.store_r &&
                        u_dut.u_dcache.addr_r[31:2]==u_dut.u_dcache.early_addr_r[31:2]))
                        fail_store++;
                    else fail_miss++;
                end
'''.replace('EARLY_HIT', early_hit)
    stats += '''
            end
            if (u_dut.dc_early_valid_w) begin
                if (u_dut.u_dcache.early_conflict_w) reason_r<=1;
                else if (!u_dut.u_dcache.early_cacheable_w) reason_r<=2;
                else if (u_dut.u_dcache.maintenance_r ||
                    u_dut.u_dcache.maintenance_start_w) reason_r<=4;
                else if (!u_dut.u_dcache.early_read_w) reason_r<=3;
                else reason_r<=0;
            end
'''
    stats += '''
        end
    end
'''
    bench = out / 'edrv32_cpu_b2_tb.sv'
    text = source('verif/block/cpu_b2/edrv32_cpu_b2_tb.sv')
    pos = text.index('    task automatic load_image')
    text = text[:pos] + stats + text[pos:]
    text = text.replace('    task automatic report_window(input int w);', '''
    task automatic report_window(input int w);
        $display("TOURNAMENT_STATS corrections=%0d branches=%0d direction_misses=%0d global_misses=%0d direction_miss_pct=%0.6f",
            f2_corrections,branches,direction_misses,global_misses,
            100.0*real'(direction_misses)/real'(branches));
        $display("EARLY_STATS issued=%0d eligible=%0d success=%0d port=%0d store=%0d device=%0d miss=%0d hold=%0d maintenance=%0d repair_cycles=%0d",
            load_issued,eligible,successes,fail_port,fail_store,fail_device,fail_miss,
            fail_hold,fail_maintenance,repair_cycles);
''')
    bench.write_text(text)
    sources = []
    for name in expand_files(ROOT / 'verif/block/cpu_b2/files.f'):
        path = Path(name)
        if path.name == bench.name:
            sources.append(str(bench))
        elif args.commit and path.suffix == '.v' and path.is_relative_to(ROOT / 'rtl'):
            relative = path.relative_to(ROOT)
            target = out / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(source(relative))
            sources.append(str(target))
        else:
            sources.append(name)
    with (out / 'compile.log').open('w') as log:
        subprocess.run(['verilator', '--binary', '--timing', '-Wall', '+define+SIM_MODE',
                        '--top-module', 'edrv32_cpu_b2_tb', '--Mdir', str(out / 'obj'),
                        '-o', 'sim', '-j', '1', *sources], cwd=ROOT, stdout=log,
                       stderr=subprocess.STDOUT, check=True)
    elf = ROOT / 'build/sw/coremark/coremark.elf'
    symbols = {line.split()[2]: line.split()[0] for line in subprocess.check_output(
        ['riscv-none-elf-nm', str(elf)], text=True).splitlines() if len(line.split()) == 3}
    command = [str(out / 'obj/sim'),
               f'+ROM_HEX={ROOT}/build/cpu_b2/r05/no-c/boot.hex',
               f'+SRAM_HEX={elf.parent}/sram.hex', f'+DDR_HEX={elf.parent}/ddr.hex',
               f'+TOHOST={symbols["tohost"]}', f'+PERF_BEGIN={symbols["start_time"]}',
               f'+PERF_END={symbols["stop_time"]}', '+READ_LATENCY=2', '+TIMEOUT=100000000']
    with (out / 'run.log').open('w') as log:
        subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    print(f'SOURCE commit={revision} snapshot={bool(args.commit)}')
    print('\n'.join(line for line in (out / 'run.log').read_text().splitlines()
                    if any(label in line for label in ('EARLY_STATS', 'TOURNAMENT_STATS', 'B2_WINDOW'))))


if __name__ == '__main__':
    main()
