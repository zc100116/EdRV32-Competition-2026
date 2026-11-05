#!/usr/bin/env python3
# File: b2_run.py
# Spec: cpu-testplan 2.2, 3.8; cpu-plan C-R4, C-I3.
# Description: Build software through sw/Makefile and execute the real-cache B2 bench.
#              Preserve console output and print CoreMark CRC and normalized throughput.
# Clock domain: none (host tool).
"""Run cpu_smoke or R-01..R-05 in the B2 environment."""
import argparse
from pathlib import Path
import re
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.regress import expand_files  # noqa: E402


def run(args):
    arch = 'rv32im_zicsr'
    if args.test == 'r05':
        arch += '_zifencei'
    program = 'coremark' if args.test == 'r05' else (
        'cpu_smoke' if args.test == 'cpu_smoke' else 'cpu_b2_' + args.test)
    image = ROOT / 'build/sw' / program
    flags = (f'-march={arch} -mabi=ilp32 -std=c11 -Wall -Wextra -Werror -O2 '
             '-ffreestanding -fno-builtin -ffunction-sections -fdata-sections '
             f'-I{ROOT}/sw/bsp/include')
    make = ['make', '-C', str(ROOT / 'sw'), f'PROGRAM={program}', 'MEMORY=sram',
            f'ARCH={arch}', 'BSP=sw/bsp/start.S sw/tests/cpu_perf/host.c',
            'LDFLAGS=-nostdlib -Wl,--gc-sections -Wl,-T,sw/bsp/ld/sram.ld '
            '-Wl,--defsym,b2_console=0x40007000 -Wl,--wrap=main']
    if args.test == 'r05':
        flags = flags.replace('-O2', '-O3 -funroll-all-loops -finline-limit=600 '
                              '-falign-functions=4 -falign-jumps=4 -falign-loops=4')
        flags += (f' -I{ROOT}/sw/apps/coremark -I{ROOT}/third_party/coremark '
                  '-DITERATIONS=10')
    elif args.test != 'cpu_smoke':
        make += ['SOURCES=sw/bsp/start.S sw/tests/cpu_perf/host.c '
                 f'sw/tests/cpu_perf/{args.test}/main.c']
    make += ['CFLAGS=' + flags]
    subprocess.run(make, cwd=ROOT, check=True)
    elf = image / (program + '.elf')
    symbols = {}
    listing = subprocess.check_output(['riscv-none-elf-nm', str(elf)], text=True)
    for line in listing.splitlines():
        parts = line.split()
        if len(parts) == 3:
            symbols[parts[2]] = int(parts[0], 16)
    out = ROOT / 'build/cpu_b2' / args.test / 'no-c'
    out.mkdir(parents=True, exist_ok=True)
    # Reset always starts in ROM; a two-instruction trampoline enters the SRAM ELF.
    entry = struct.unpack_from('<I', elf.read_bytes(), 24)[0]
    upper = (entry + 0x800) >> 12
    lower = entry & 0xfff
    boot = struct.pack('<II', (upper << 12) | 0x2b7, (lower << 20) | 0x28067)
    rom = out / 'boot.hex'
    rom.write_text('@00000000\n' + ''.join(f'{v:02x}\n' for v in boot))
    obj = ROOT / 'build/cpu_b2' / 'obj'
    sources = expand_files(ROOT / 'verif/block/cpu_b2/files.f')
    compile_args = ['verilator', '--binary', '--timing', '-Wall', '+define+SIM_MODE',
                    '--top-module', 'edrv32_cpu_b2_tb',
                    '--Mdir', str(obj), '-o', 'sim', '-j', '1', *sources]
    print(f'B2 test={args.test} no-C compile_log={out / "compile.log"}',
          flush=True)
    with (out / 'compile.log').open('w') as log:
        subprocess.run(compile_args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    command = [str(obj / 'sim'), f'+ROM_HEX={rom}', f'+SRAM_HEX={image}/sram.hex',
               f'+DDR_HEX={image}/ddr.hex', f'+TOHOST={symbols["tohost"]:x}',
               f'+TIMEOUT={args.max_cycles}', f'+READ_LATENCY={args.read_latency}']
    markers = [('start_time', 'stop_time')] if args.test == 'r05' else [
        ('b2_perf_begin', 'b2_perf_end'), ('b2_perf2_begin', 'b2_perf2_end')]
    for index, (begin, end) in enumerate(markers):
        if begin in symbols:
            prefix = 'PERF2' if index else 'PERF'
            command += [f'+{prefix}_BEGIN={symbols[begin]:x}',
                        f'+{prefix}_END={symbols[end]:x}']
    if args.test == 'r04':
        command.append('+R04_CHECK')
    result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
    output = result.stdout
    print(output, end='')
    if args.test in ('r01', 'r02', 'r03', 'r04'):
        for match in re.finditer(r'B2_WINDOW window=(\d+) cycles=(\d+) instret=(\d+)', output):
            window, cycles, instructions = map(int, match.groups())
            work = {'r01': 16384, 'r02': 16384, 'r03': 4096, 'r04': 65536}[args.test]
            summary = (f'B2_PERF test={args.test} window={window} cycles={cycles} '
                       f'instret={instructions} IPC={instructions / cycles:.6f} '
                       f'work_items={work} cycles_per_item={cycles / work:.6f}')
            print(summary)
            output += summary + '\n'
    if args.test == 'r05':
        # Ten iterations are deliberately shorter than the CoreMark reporting minimum.
        # Check the canonical algorithm CRCs independently of the >=10 second rule.
        actual = [re.search(r'\[0\]crc' + name + r'\s*:\s*0x([0-9a-f]+)', output)
                  for name in ('list', 'matrix', 'state')]
        crc_ok = all(actual) and [int(m[1], 16) for m in actual] == [0xe714, 0x1fd7, 0x8e3a]
        ticks = re.search(r'Total ticks\s*:\s*(\d+)', output)
        score = 10 * 1000000 / int(ticks[1]) if ticks else None
        throughput = f'{score:.6f}' if score is not None else 'unavailable'
        summary = (f'B2_COREMARK iterations=10 CRC={"PASS" if crc_ok else "FAIL"} '
                   f'cycles={ticks[1] if ticks else "unavailable"} '
                   f'CoreMark/MHz={throughput}')
        print(summary)
        output += summary + '\n'
        if not crc_ok:
            result.returncode = 1
        if args.check_cycles:
            # Report 2026-11-02-perf-cpu-predictor-pipe1: specification-index
            # V3s, BTB/PHT/RAS=128/4096/4, GCC15.2 tuned, ten iterations.
            predicted = 2058075
            limit = predicted * 105 // 100
            window = re.search(r'B2_WINDOW window=0 cycles=(\d+)', output)
            cycles = int(window[1])
            passed = cycles <= limit
            summary = (f'B2_R05_CYCLES {"PASS" if passed else "FAIL"} '
                       f'actual={cycles} model_V3s_128_4096={predicted} '
                       f'limit={limit} source=2026-11-02-perf-cpu-predictor-pipe1')
            print(summary)
            output += summary + '\n'
            if not passed:
                result.returncode = 1
    (out / 'run.log').write_text(output)
    return result.returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('test', choices=['cpu_smoke', 'r01', 'r02', 'r03', 'r04', 'r05'])
    parser.add_argument('--check-cycles', action='store_true',
                        help='R-05 perf: assert GCC15.2 tuned V3s 128/4096 report limit')
    parser.add_argument('--read-latency', type=int, default=2,
                        help='AR-to-first-R latency in cycles (minimum 2)')
    parser.add_argument('--max-cycles', type=int, default=100000000)
    args = parser.parse_args()
    if args.check_cycles and args.test != 'r05':
        parser.error('--check-cycles requires r05')
    if args.read_latency < 2:
        parser.error('the reused AXI model has a minimum read latency of 2 cycles')
    return run(args)


if __name__ == '__main__':
    sys.exit(main())
