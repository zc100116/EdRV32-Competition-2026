#!/usr/bin/env python3
# File: run.py
# Spec: npu-testplan 3.8 EQ-01; CLAUDE.md 8.
# Description: Compare the committed SIM and FPGA branches against the local vendor model.
# Clock domain: host tool.
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'build/npu_mac_chain'
TEST = ROOT / 'verif/unit/npu_mac_chain'


def main():
    if 'EDRV32_PANGO_SIM_DIR' not in os.environ:
        sys.exit('EDRV32_PANGO_SIM_DIR must name the directory containing GTP_APM_E2.v')
    vendor = Path(os.environ['EDRV32_PANGO_SIM_DIR']) / 'GTP_APM_E2.v'
    OUT.mkdir(parents=True, exist_ok=True)
    sources = []
    fpga_sources = []
    for kind in ('chain', 'head'):
        name = 'edrv32_mac_npu_int8_' + kind
        source = ROOT / 'rtl/tech' / (name + '.v')
        body = source.read_text().replace(name, name + '_fpga')
        if kind == 'head':
            # Probe the unused vendor CPI with nonzero noise; MODEZ must ignore it.
            body = body.replace('input wire clk_i,',
                                'input wire clk_i,\n    input wire [47:0] cpi_i,')
            body = body.replace(".CPI(48'b0)", '.CPI(cpi_i)')
        fpga = OUT / (name + '_fpga.v')
        fpga.write_text('`define EDRV32_FPGA_MEMORY_MODE\n' + body)
        sources.append(str(source))
        fpga_sources.append(str(fpga))
    # Read every SIM source before FPGA copies define the shared mode macro.
    subprocess.run(['iverilog', '-g2012', '-DSIM_MODE', '-I', str(ROOT / 'rtl/include'),
                    '-s', 'tb_npu_mac_chain', '-o', str(OUT / 'sim'), *sources, *fpga_sources,
                    str(vendor), str(TEST / 'tb_npu_mac_chain.sv')], check=True)
    subprocess.run(['vvp', str(OUT / 'sim')], check=True)


if __name__ == '__main__':
    main()
