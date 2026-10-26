"""Build and run the unmodified legacy core with a timed AXI256 memory.

SoC spec 8.9 evaluation only. No FPGA_MODE; Verilator -j 1. The C++ AXI
model uses a shared R/W payload budget, four queued reads/writes and fixed
AR-to-first-R / last-W-to-B latency. Generated files stay in build/npu_eval.
"""

import argparse
from pathlib import Path
import re
import shlex
import subprocess
import time

from legacy_plan import BUILD, ROOT

STAGES = ('control', 'quant', 'weight', 'feature', 'mac', 'write_drain',
          'write_response', 'patch_pipeline', 'row_prepare', 'nonconv')


def wrapper():
    core = ROOT / 'legacy/rtl/vision/yolo/edrv32_yolo_v8n_core.v'
    port_text = core.read_text().split('module edrv32_yolo_v8n_core (')[1].split(');')[0]
    ports = re.findall(r'\b(?:input|output)\s+wire\s*(?:\[[^\]]+\]\s*)?(\w+)', port_text)
    profile_names = ('cycles', 'mac', 'rbeats', 'wbeats', 'arstall', 'rwait',
                     'awstall', 'wstall', 'bwait')
    extra = ['output wire [3:0] stage_o', 'input wire [6:0] profile_step_i']
    extra += [f'output wire [31:0] profile_{n}_o' for n in profile_names]
    text = '// Evaluation wrapper; observation only, legacy RTL stays unchanged.\n'
    text += 'module legacy_eval_top (' + port_text + ',\n' + ',\n'.join(extra) + '\n);\n'
    text += 'edrv32_yolo_v8n_core dut (\n'
    text += ',\n'.join(f'.{p}({p})' for p in ports) + '\n);\n'
    layer = 'dut.u_exec.u_conv.u_layer'
    writer = layer + '.u_writer'
    text += f'''assign stage_o = dut.cmd_op_w != 0 ? 4'd9 :
        mac_beat_o ? 4'd4 :
        (dut.u_exec.u_conv.state_r == 1 || dut.u_exec.u_conv.state_r == 2) ? 4'd1 :
        ({layer}.state_r == 1 || {layer}.state_r == 2) ? 4'd2 :
        {layer}.state_r == 4 ? 4'd3 :
        {layer}.state_r == 6 ?
            (({writer}.accepted_r == {writer}.pair_count_r) ?
                (({writer}.bank_full_r == 0 && {writer}.drain_state_r == 0) ?
                    4'd6 : 4'd5) : 4'd7) :
        ({layer}.state_r == 3 || {layer}.state_r == 5) ? 4'd8 : 4'd0;
'''
    conn = {'clk_i': 'clk_i', 'rst_n_i': 'rst_n_i', 'run_start_i': 'start_i',
            'run_done_i': 'done_o', 'step_i': 'step_o', 'mac_beat_i': 'mac_beat_o',
            'read_step_i': 'profile_step_i'}
    for name in ('arvalid', 'arready', 'arlen', 'rvalid', 'rready', 'awvalid',
                 'awready', 'awlen', 'wvalid', 'wready', 'bvalid', 'bready'):
        direction = 'i' if name in ('arready', 'rvalid', 'awready', 'wready', 'bvalid') else 'o'
        conn[name + '_i'] = 'm_' + name + '_' + direction
    conn.update({f'read_{n}_o': f'profile_{n}_o' for n in profile_names})
    text += 'edrv32_yolo_v8n_profiler profiler (\n'
    text += ',\n'.join(f'.{p}({v})' for p, v in conn.items()) + '\n);\nendmodule\n'
    path = BUILD / 'legacy_eval_top.sv'
    path.write_text(text)
    return path


def compile_rtl():
    top = wrapper()
    filelist = ROOT / 'legacy/sim/cases/vision/yolo-ddr-stream/files.f'
    names = [line.strip() for line in filelist.read_text().splitlines()
             if line.startswith('rtl/')]
    names += ['rtl/vision/yolo/' + n + '.v' for n in (
        'edrv32_yolo_conv_group', 'edrv32_yolo_c16_residual_add',
        'edrv32_yolo_c16_residual_dma', 'edrv32_yolo_maxpool5_dma',
        'edrv32_yolo_upsample2x_dma', 'edrv32_yolo_v8n_exec',
        'edrv32_yolo_v8n_program', 'edrv32_yolo_quant_cfg_dma',
        'edrv32_yolo_v8n_core', 'edrv32_yolo_v8n_profiler')]
    cmd = ['verilator', '--cc', '--exe', '--build', '--timing', '-j', '1',
           '--top-module', 'legacy_eval_top', '--Mdir', str(BUILD / 'obj'),
           '-O3', '-CFLAGS', '-O3', '+define+SIM_MODE',
           '+incdir+' + str(ROOT / 'legacy/rtl/include'),
           '-Wno-WIDTH', '-Wno-TIMESCALEMOD', str(top)]
    cmd += [str(ROOT / 'legacy' / n) for n in names]
    cmd += [str(ROOT / 'tools/npu/eval/axi256_eval.cpp')]
    (BUILD / 'compile_command.txt').write_text(shlex.join(cmd) + '\n')
    with (BUILD / 'compile.log').open('w') as log:
        subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, check=True)
    # Existing legacy sources are read-only; retain their known warning
    # classes explicitly, while making new unhandled lint warnings fail.
    lint = ['verilator', '--lint-only', '--timing', '-Wall',
            '--top-module', 'legacy_eval_top', '+define+SIM_MODE',
            '+incdir+' + str(ROOT / 'legacy/rtl/include')]
    lint += ['-Wno-' + warning for warning in (
        'WIDTH', 'TIMESCALEMOD', 'PINCONNECTEMPTY', 'UNUSEDSIGNAL',
        'UNUSEDPARAM', 'VARHIDDEN', 'BLKSEQ')]
    lint += [str(top)] + [str(ROOT / 'legacy' / n) for n in names]
    (BUILD / 'lint_command.txt').write_text(shlex.join(lint) + '\n')
    with (BUILD / 'lint.log').open('w') as log:
        subprocess.run(lint, stdout=log, stderr=subprocess.STDOUT, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compile', action='store_true')
    parser.add_argument('--latency', type=int, default=0)
    parser.add_argument('--bandwidth-gbps', type=float, default=4.8)
    parser.add_argument('--stop-step', type=int, default=73)
    args = parser.parse_args()
    BUILD.mkdir(parents=True, exist_ok=True)
    if args.compile:
        compile_rtl()
    tag = f'l{args.latency}_b{args.bandwidth_gbps:g}'
    cmd = [str(BUILD / 'obj/Vlegacy_eval_top'), str(args.latency),
           str(args.bandwidth_gbps), str(args.stop_step), str(BUILD / tag)]
    start = time.monotonic()
    with (BUILD / (tag + '.log')).open('w') as log:
        subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, check=True)
    elapsed = time.monotonic() - start
    print(f'{tag}: {elapsed:.3f} seconds; {BUILD / (tag + ".csv")}')


if __name__ == '__main__':
    main()
