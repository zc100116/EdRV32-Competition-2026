#!/usr/bin/env python3
# File: b2_measure.py
# Spec: cpu-testplan 3.8 R-01..R-05; cpu-plan C-I3.
# Description: Measure the requested B2/CoreMark matrix and preserve commands and raw logs.
#              Compile the no-C bench once, with one compilation job.
# Clock domain: none (host tool).
"""Run from the repository root after sourcing ~/.local/opt/edrv32/env.sh."""
import csv
from pathlib import Path
import re
import shlex
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.regress import expand_files  # noqa: E402

OUT = ROOT / 'build/cpu_b2_measure'
OPTIONS = {
    'o2': '-O2',
    'o3': '-O3',
    'unroll': '-O3 -funroll-all-loops',
    'tuned': ('-O3 -funroll-all-loops -finline-limit=600 '
              '-falign-functions=4 -falign-jumps=4 -falign-loops=4'),
    'legacy': '-O2 -mno-relax',
}


def logged(command, path, check=True):
    with path.open('w') as log:
        log.write('$ ' + shlex.join(command) + '\n')
        log.flush()
        result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=log)
    if check:
        result.check_returncode()
    return result


def compile_bench():
    obj = OUT / 'obj'
    command = ['verilator', '--binary', '--timing', '-Wall', '+define+SIM_MODE',
               '--top-module', 'edrv32_cpu_b2_tb',
               '--Mdir', str(obj), '-o', 'sim', '-j', '1',
               *expand_files(ROOT / 'verif/block/cpu_b2/files.f')]
    logged(command, OUT / 'compile.log')
    return obj / 'sim'


def build(test, rvc, option):
    name = f'rvc{rvc}_{test}_{option}'
    out = OUT / name
    out.mkdir(parents=True, exist_ok=True)
    arch = 'rv32im_zicsr'
    if option == 'legacy':
        arch += '_zifencei'
    program = 'coremark' if test == 'r05' else 'cpu_b2_' + test
    flags = (f'-march={arch} -mabi=ilp32 -std=c11 -Wall -Wextra -Werror '
             f'{OPTIONS[option]} -ffreestanding -fno-builtin '
             f'-ffunction-sections -fdata-sections -I{ROOT}/sw/bsp/include')
    command = ['make', '-C', 'sw', f'PROGRAM={program}', 'MEMORY=sram',
               f'OUT={out}', f'ARCH={arch}',
               'BSP=sw/bsp/start.S sw/tests/cpu_perf/host.c',
               'LDFLAGS=-nostdlib -Wl,--gc-sections -Wl,-T,sw/bsp/ld/sram.ld '
               f'-Wl,-Map,{out}/{program}.map '
               '-Wl,--defsym,b2_console=0x40007000 -Wl,--wrap=main']
    if option == 'legacy':
        command[-1] += ' -nostartfiles -Wl,--build-id=none'
    if test == 'r05':
        flags += (f' -I{ROOT}/sw/apps/coremark -I{ROOT}/third_party/coremark '
                  '-DITERATIONS=10')
    else:
        command += ['SOURCES=sw/bsp/start.S sw/tests/cpu_perf/host.c '
                    f'sw/tests/cpu_perf/{test}/main.c']
    command += ['CFLAGS=' + flags]
    result = logged(command, out / 'build.log', check=False)
    if result.returncode:
        # SRAM overflow is an explicitly requested measurement outcome.
        if 'will not fit in region' in (out / 'build.log').read_text():
            print(f'{name}: SRAM overflow (see build.log)', flush=True)
            return out, None
        result.check_returncode()
    elf = out / (program + '.elf')
    logged(['riscv-none-elf-size', str(elf)], out / 'size.log')
    return out, elf


def execute(sim, out, elf, test, latency, inner=False):
    symbols = {}
    for line in subprocess.check_output(['riscv-none-elf-nm', str(elf)], text=True).splitlines():
        fields = line.split()
        if len(fields) == 3:
            symbols[fields[2]] = int(fields[0], 16)
    entry = struct.unpack_from('<I', elf.read_bytes(), 24)[0]
    boot = struct.pack('<II', (((entry + 0x800) >> 12) << 12) | 0x2b7,
                       ((entry & 0xfff) << 20) | 0x28067)
    rom = out / 'boot.hex'
    rom.write_text('@00000000\n' + ''.join(f'{value:02x}\n' for value in boot))
    command = [str(sim), f'+ROM_HEX={rom}', f'+SRAM_HEX={out}/sram.hex',
               f'+DDR_HEX={out}/ddr.hex', f'+TOHOST={symbols["tohost"]:x}',
               '+TIMEOUT=100000000', f'+READ_LATENCY={latency}']
    markers = [('start_time', 'stop_time')] if test == 'r05' else [
        ('b2_perf_begin', 'b2_perf_end'), ('b2_perf2_begin', 'b2_perf2_end')]
    for index, (begin, end) in enumerate(markers):
        if begin in symbols:
            prefix = 'PERF2' if index else 'PERF'
            begin_pc, end_pc = symbols[begin], symbols[end]
            if inner:
                # The existing directed tests use norvc, an 8-byte-aligned loop
                # after the marker NOP, and fixed instruction repetition counts.
                body = (begin_pc + 11) & ~7
                offsets = {'r01': (64, 192), 'r02': (64, 192),
                           'r03': (64, 96), 'r04': (1024, 2040)}
                first, last = offsets[test]
                begin_pc, end_pc = body + first, body + last
            command += [f'+{prefix}_BEGIN={begin_pc:x}', f'+{prefix}_END={end_pc:x}']
    log = out / (f'inner_l{latency}.log' if inner else f'run_l{latency}.log')
    logged(command, log)
    return log.read_text()


def coremark_row(rvc, option, latency, output):
    cycles = int(re.search(r'Total ticks\s*:\s*(\d+)', output)[1])
    crcs = [int(re.search(r'\[0\]crc' + name + r'\s*:\s*0x([0-9a-f]+)', output)[1], 16)
            for name in ('list', 'matrix', 'state')]
    row = {'rvc': rvc, 'option': option, 'latency': latency, 'cycles': cycles,
           'coremark_per_mhz': f'{10000000 / cycles:.9f}',
           'crc': 'PASS' if crcs == [0xe714, 0x1fd7, 0x8e3a] else 'FAIL'}
    window = re.search(r'B2_WINDOW window=0 cycles=(\d+) instret=(\d+)', output)
    row.update(window_cycles=int(window[1]), instret=int(window[2]))
    for event, count in re.findall(r'B2_HPM window=0 event=(\d+) count=(\d+)', output):
        row[f'hpm{event}'] = int(count)
    print(f'RVC={rvc} {option} L={latency}: cycles={cycles} '
          f'CoreMark/MHz={row["coremark_per_mhz"]} CRC={row["crc"]}', flush=True)
    return row


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    with (OUT / 'versions.log').open('w') as log:
        for command in (['git', 'rev-parse', 'HEAD'], ['git', 'submodule', 'status',
                         'third_party/coremark'], ['verilator', '--version'],
                        ['riscv-none-elf-gcc', '--version'], ['g++', '--version'],
                        ['python3', '--version'], ['uname', '-a']):
            subprocess.run(command, cwd=ROOT, stdout=log, stderr=log, check=True)
    fields = ['rvc', 'option', 'latency', 'cycles', 'coremark_per_mhz', 'crc',
              'window_cycles', 'instret'] + [f'hpm{event}' for event in range(1, 17)]
    with (OUT / 'coremark.csv').open('w') as table:
        writer = csv.DictWriter(table, fieldnames=fields)
        writer.writeheader()
        rvc = 0
        print(f'Compiling B2 RVC_EN={rvc} (-j 1)', flush=True)
        sim = compile_bench()
        for test in ('r01', 'r02', 'r03', 'r04'):
            out, elf = build(test, rvc, 'o2')
            output = execute(sim, out, elf, test, 2)
            print(f'RVC={rvc} {test}: '
                  + ' '.join(re.findall(r'B2_WINDOW[^\n]+', output)), flush=True)
            execute(sim, out, elf, test, 2, inner=True)
        measured = []
        images = {}
        for option in ('o2', 'o3', 'unroll', 'tuned'):
            out, elf = build('r05', rvc, option)
            if elf is None:
                writer.writerow({'rvc': rvc, 'option': option, 'latency': 2,
                                 'crc': 'SRAM overflow'})
            else:
                images[option] = (out, elf)
                row = coremark_row(rvc, option, 2, execute(sim, out, elf, 'r05', 2))
                writer.writerow(row)
                measured.append(row)
            table.flush()
        best = min((row for row in measured if row['crc'] == 'PASS'),
                   key=lambda row: row['cycles'])['option']
        for option in dict.fromkeys(('o2', best)):
            out, elf = images[option]
            writer.writerow(coremark_row(rvc, option, 3,
                                         execute(sim, out, elf, 'r05', 3)))
            table.flush()



if __name__ == '__main__':
    main()
