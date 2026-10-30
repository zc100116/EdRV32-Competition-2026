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
    source = ROOT / 'rtl/tech/edrv32_mac_npu_int8_chain.v'
    # Compile the same fixed wrapper twice; only its module name and build mode differ.
    fpga = OUT / 'edrv32_mac_npu_int8_chain_fpga.v'
    fpga.write_text('`define EDRV32_FPGA_MEMORY_MODE\n' + source.read_text().replace(
        'edrv32_mac_npu_int8_chain', 'edrv32_mac_npu_int8_chain_fpga'))
    subprocess.run(['iverilog', '-g2012', '-DSIM_MODE', '-I', str(ROOT / 'rtl/include'),
                    '-s', 'tb_npu_mac_chain', '-o', str(OUT / 'sim'), str(source),
                    str(fpga), str(vendor), str(TEST / 'tb_npu_mac_chain.sv')], check=True)
    subprocess.run(['vvp', str(OUT / 'sim')], check=True)


if __name__ == '__main__':
    main()
