#!/usr/bin/env python3
# File: run.py
# Spec: Task T-NPU4; CLAUDE.md 9.2; edrv32-soc-spec 6.3, 7.4, 7.5.
# Description: Run the original board ELF through BIOS with behavioral/vendor MACs.
#              Only the ELF PT_LOAD bytes are preloaded; CPU initializes NPU data.
# Clock domain: none (host tool).
"""Run the unchanged B3N board_npu ELF until the first B-OP-01 result."""
import argparse
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))
from tools.fpga.mem_init import pack_image
from tools.elf2mem import convert  # noqa: E402
from tools.regress import expand_files  # noqa: E402

HERE = Path(__file__).resolve().parent
OUT = ROOT / 'build/board_npu_program'
CARD = ROOT / 'tasks/win/20261030-13-b3n-npu'
PREFIX = 'NPU B-OP-01-c16_32 '


def command(args, log):
    with log.open('w') as output:
        subprocess.run(args, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, check=True)


def compare(log):
    # The debug record quotes the original card-13 UART line verbatim.
    board = next(line for line in
                 (ROOT / 'docs/debug/2026-10-30-npu-b3n-board-op01.md').read_text().splitlines()
                 if line.startswith(PREFIX))
    simulation = next(line for line in log.read_text().splitlines() if line.startswith(PREFIX))
    print(simulation, flush=True)
    for name in ('result', 'desc', 'addr', 'expected', 'actual', 'mismatches', 'PERF0', 'MAC'):
        def field(line):
            if name == 'result':
                return line[len(PREFIX):].split()[0]
            return next((word.split('=', 1)[1] for word in line.split()
                         if word.startswith(name + '=')), 'absent')
        actual = field(simulation)
        expected = field(board)
        print(f'{name}: board={expected} simulation={actual} equal={actual == expected}',
              flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mac', choices=('sim', 'vendor', 'both'), default='both')
    parser.add_argument('--lint-only', action='store_true')
    parser.add_argument('--ddr-latency', type=int, default=3,
                        help='DDR command latency in clk_mem cycles (default: 3)')
    parser.add_argument('--ddr-read-gaps', action='store_true',
                        help='insert 0-31 extra clk_mem cycles between read beats')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    # Preserve the common board IP shell. Cover the ELF's stack at physical 0x3fffffff,
    # as well as NPU data through 0x16000000; changing the ELF's stack would hide behavior.
    shell = OUT / 'ip_ddr3.sv'
    shell.write_text((ROOT / 'verif/soc/board_render/ip_ddr3.sv').read_text().replace(
        'pango_ddr3_ip_model u_user (',
        'pango_ddr3_ip_model #(\n'
        '        .MEMORY_BYTES(1073741824),\n'
        f'        .COMMAND_LATENCY({args.ddr_latency})\n'
        '    ) u_user ('))
    # A dense 1 GiB array exceeds Verilator's single-dimension limit. Keep the
    # byte-addressed storage contract, with sparse keys sized by MEMORY_BYTES.
    original_ddr = ROOT / 'verif/models/pango_ddr3_ip_model.sv'
    sparse_ddr = OUT / original_ddr.name
    model = original_ddr.read_text().replace(
        'reg [7:0] memory_r [0:MEMORY_BYTES-1];',
        'reg [7:0] memory_r [bit [$clog2(MEMORY_BYTES)-1:0]];').replace(
        "memory_r[{2'b00, addr_r, 2'b00} + g]",
        "memory_r[$clog2(MEMORY_BYTES)'({2'b00, addr_r, 2'b00} + g)]").replace(
        "memory_r[{2'b00, addr_r, 2'b00} + lane]",
        "memory_r[$clog2(MEMORY_BYTES)'({2'b00, addr_r, 2'b00} + lane)]")
    if args.ddr_read_gaps:
        # Use the model's existing LFSR, seeded with 0x1234abcd at reset.
        # Delay the next beat after delivery; data/address advance together as before.
        model = model.replace('                        if (axi_rlast_o)',
                              "                        delay_r <= {27'b0, lfsr_r[7:3]};\n"
                              '                        if (axi_rlast_o)')
    sparse_ddr.write_text(model)
    sources = [str(sparse_ddr) if source == str(original_ddr) else source
               for source in expand_files(HERE / 'files.f')] + [str(shell)]
    if not args.lint_only:
        command(['make', '-C', 'sw', 'PROGRAM=bootloader', '-j', '1'], OUT / 'bootloader.log')
        pack_image(ROOT / 'build/sw/bootloader/rom.hex', 2048, OUT / 'rom64.hex')
        convert(CARD / 'src/board_npu.elf', OUT / 'image')
    failed = False
    for mode in (('sim', 'vendor') if args.mac == 'both' else (args.mac,)):
        directory = OUT / mode
        directory.mkdir(exist_ok=True)
        selected = list(sources)
        if mode == 'vendor':
            vendor = (Path(os.environ['EDRV32_PANGO_SIM_DIR']) / 'GTP_APM_E2.v').resolve()
            original = ROOT / 'rtl/tech/edrv32_mac_npu_int8_chain.v'
            wrapper = directory / original.name
            wrapper.write_text('`define EDRV32_FPGA_MEMORY_MODE\n'
                               '/* verilator lint_off PINCONNECTEMPTY */\n'
                               + original.read_text().replace(
                                   '`ifdef EDRV32_FPGA_MEMORY_MODE',
                                   '    edrv32_board_npu_program_grs GRS_INST();\n'
                                   '`ifdef EDRV32_FPGA_MEMORY_MODE')
                               + '\n/* verilator lint_on PINCONNECTEMPTY */\n'
                               '`undef EDRV32_FPGA_MEMORY_MODE\n')
            selected = [str(wrapper) if source == str(original) else source
                        for source in selected]
            # Vendor coding warnings are scoped to the external model. Project RTL
            # and the new testbench retain -Wall, including the MAC wrapper above.
            config = directory / 'vendor.vlt'
            config.write_text('`verilator_config\n'
                              f'lint_off -file "{vendor}"\n')
            selected += [str(config), str(vendor),
                         str(HERE / 'edrv32_board_npu_program_grs.sv')]
        common = ['--timing', '-Wall', '+define+SIM_MODE', '--top-module',
                  'edrv32_board_npu_program_tb'] + selected
        command(['verilator', '--lint-only'] + common, directory / 'lint.log')
        print(f'PASS board_npu_program {mode} lint, 0 warnings', flush=True)
        if args.lint_only:
            continue
        obj = directory / 'obj'
        command(['verilator', '--binary', '-j', '1', '-CFLAGS', '-O1', '--Mdir', str(obj),
                 '-o', 'sim'] + common, directory / 'compile.log')
        log = directory / 'simulation.log'
        with log.open('w') as output:
            result = subprocess.run([str(obj / 'sim'),
                                     '+ROM_HEX=' + str(OUT / 'rom64.hex'),
                                     '+DDR_HEX=' + str(OUT / 'image/ddr.hex')], cwd=ROOT,
                                    stdout=output, stderr=subprocess.STDOUT)
        print(f'{mode}: exit={result.returncode} UART={log}', flush=True)
        compare(log)
        failed |= result.returncode != 0
    return int(failed)


if __name__ == '__main__':
    sys.exit(main())
