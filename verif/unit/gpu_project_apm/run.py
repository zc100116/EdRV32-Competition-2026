#!/usr/bin/env python3
# File: run.py
# Spec: gpu-spec 2.4, 2.12, 2.13.1-6; R-6a wrapper equivalence.
# Description: Compare fixed SIM and native APM implementations with exact products.
# Clock domain: host tool.
from pathlib import Path
import os
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'build/r6a-equivalence'
OUT.mkdir(parents=True, exist_ok=True)
VENDOR = Path(os.environ['EDRV32_PANGO_SIM_DIR']) / 'GTP_APM_E2.v'
wrappers = sorted((ROOT / 'rtl/tech').glob('edrv32_apm_gpu_*.v'))
copies = []
for path in wrappers:
    source = path.read_text()
    source = re.sub(r'\bedrv32_apm_gpu_\w+', lambda m: m[0] + '_vendor', source)
    source = source.replace('EDRV32_FPGA_MEMORY_MODE', 'GPU_APM_VENDOR')
    target = OUT / path.name
    target.write_text(source)
    copies.append(target)

text = '''`timescale 1ns/1ps
module GRS_INST;
    wire GRSNET = 1'b1;
endmodule
module tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg enable;
    integer cycle;
    integer count = 0;
    integer j;
'''
stimulus, updates, checks = [], [], []
for path in wrappers:
    match = re.fullmatch(r'edrv32_apm_gpu_([su])(\d+)x([su])(\d+)', path.stem)
    if match is None:
        continue
    sa, aw, sb, bw = match.groups()
    aw, bw = int(aw), int(bw)
    ow = 94 if aw == 94 else aw + bw
    latency = int(re.search(r'(\d+) enabled clocks', path.read_text())[1])
    name = path.stem
    text += f'''
    reg [{aw-1}:0] {name}_a;
    reg [{bw-1}:0] {name}_b;
    wire [{ow-1}:0] {name}_sim;
    wire [{ow-1}:0] {name}_vendor;
    reg [{ow-1}:0] {name}_expected [0:{latency-1}];
'''
    for variant in ('sim', 'vendor'):
        module = name + ('_vendor' if variant == 'vendor' else '')
        text += f'''    {module} u_{name}_{variant} (
        .clk_i(clk),
        .enable_i(enable),
        .a_i({name}_a),
        .b_i({name}_b),
        .p_o({name}_{variant})
    );
'''
    for label, width in [('a', aw), ('b', bw)]:
        stimulus += [f'            {name}_{label} = {{$random, $random, $random}};',
                     f'''            case (cycle % 32)
                0: {name}_{label} = {width}'h0;
                1: {name}_{label} = ~{width}'h0;
                2: {name}_{label} = {width}'h{1 << (width-1):x};
                3: {name}_{label} = {width}'h{(1 << (width-1))-1:x};
                4: {name}_{label} = {width}'h{(1 << (width-1)) if label=='a' else (1 << (width-1))-1:x};
                5: {name}_{label} = {width}'h{(1 << (width-1))-1 if label=='a' else (1 << (width-1)):x};
                default: begin end
            endcase''']
    operand_a = f'$signed({name}_a)' if sa == 's' else f'{name}_a'
    operand_b = f'$signed({name}_b)' if sb == 's' else f'{name}_b'
    # Mixed signed/unsigned products need an explicit zero sign bit for the unsigned input.
    if sa != sb:
        if sa == 'u': operand_a = f"$signed({{1'b0, {name}_a}})"
        if sb == 'u': operand_b = f"$signed({{1'b0, {name}_b}})"
    updates += [f'''            if (enable) begin
                for (j = {latency-1}; j > 0; j = j-1)
                    {name}_expected[j] = {name}_expected[j-1];
                {name}_expected[0] = {operand_a} * {operand_b};
            end''']
    checks += [f'''            if (count >= {latency} &&
                ({name}_sim !== {name}_expected[{latency-1}] ||
                 {name}_vendor !== {name}_sim)) begin
                $display("FAIL {name} cycle=%0d expected=%h SIM=%h vendor=%h", cycle,
                    {name}_expected[{latency-1}], {name}_sim, {name}_vendor);
                $fatal(1);
            end''']
text += '''    initial begin
        for (cycle = 0; cycle < 12000; cycle = cycle+1) begin
            @(negedge clk);
            enable = ($random & 7) != 0;
''' + '\n'.join(stimulus) + '''
            @(posedge clk);
            if (enable) count = count+1;
''' + '\n'.join(updates) + '\n            #1;\n' + '\n'.join(checks) + '''
        end
        $display("PASS 12 fixed multipliers: exact/SIM/vendor, 12000 random/extreme/stall cycles");
        $finish;
    end
endmodule
'''
(OUT / 'tb.v').write_text(text)
subprocess.run(['iverilog', '-g2012', '-DSIM_MODE', '-DGPU_APM_VENDOR',
                '-I' + str(ROOT / 'rtl/include'), '-s', 'tb', '-s', 'GRS_INST',
                '-o', str(OUT / 'eq.vvp'), str(OUT / 'tb.v'),
                *map(str, wrappers), *map(str, copies), str(VENDOR)], check=True)
subprocess.run(['vvp', str(OUT / 'eq.vvp')], check=True)
