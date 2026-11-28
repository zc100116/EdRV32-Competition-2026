#!/usr/bin/env python3
# File: run_model_conformance.py; cpu-v2-testplan CV15; clock: host.
"""A00: build isolated hot streams, replay unchanged models, measure three RTL cores.

Source the EDRV32 environment. Run on the simulation host from a frozen source tree:
python3 tools/cpu/run_model_conformance.py build
python3 tools/cpu/run_model_conformance.py run
All generated images, logs, traces and cycle tables are under build/cpu2-conformance/.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import re
import subprocess
import struct
import sys

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/cpu2-conformance'
PERF = ROOT / 'verif/block/cpu2_core/perf'
CASES = ('alu_stream', 'alu_chain', 'load_stream', 'load_address_chain', 'load_use',
         'store_stream', 'load_store', 'mul_stream', 'mul_chain', 'div_stream',
         'branch_taken', 'branch_not_taken', 'branch_alternating', 'jal', 'jalr',
         'call_return', 'pair_AL', 'pair_LA', 'pair_AB', 'late_AA', 'agu_ineligible',
         'csr_read', 'shift_chain', 'pair_AM', 'pair_AS', 'late_AB', 'pair_BA', 'pair_MA',
         'pair_DA', 'pair_AD',
         'pair_BM', 'pair_MB', 'pair_BL', 'pair_LB', 'pair_LM', 'pair_ML',
         'ordinary_load_use', 'div_zero')

sys.path.insert(0, str(ROOT / 'tools'))
sys.path.insert(0, str(ROOT / 'tools/cpu/eval'))
from regress import expand_files
from pipe_model import program_and_trace, simulate
from ooo_model import memory_trace
from run_v2_round2 import divider_cycles
from run_v2_round4 import BASES, EXPERIMENTS
from run_frontend_t2_eval import IcacheProbe
from v2_round4_structures import RamTage


def execute(command, log=None, cwd=ROOT):
    if log:
        with log.open('w') as stream:
            subprocess.run(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT, check=True)
    else:
        subprocess.run(command, cwd=cwd, check=True)


def symbols(elf):
    output = subprocess.check_output(['riscv-none-elf-nm', str(elf)], text=True)
    return {p[2]: int(p[0], 16) for line in output.splitlines() if len(p := line.split()) == 3}


def build(names):
    for name in names:
        number = CASES.index(name)
        directory = OUT / name
        directory.mkdir(parents=True, exist_ok=True)
        elf = directory / 'coremark.elf'
        execute(['riscv-none-elf-gcc', '-march=rv32im_zicsr_zifencei_zba', '-mabi=ilp32',
                 '-mcmodel=medany', '-nostdlib', '-nostartfiles', '-static', '-Wl,--no-relax',
                 '-T' + str(PERF.parent / 'env/link.ld'), '-Wl,-e,_start',
                 '-DCASE=' + str(number),
                 str(PERF / 'kernels.S'), '-o', str(elf)])
        execute([sys.executable, str(ROOT / 'tools/elf2mem.py'), str(elf), str(directory)],
                directory / 'image.log')
        entry = symbols(elf)['_start']
        boot = struct.pack('<II', (((entry + 0x800) >> 12) << 12) | 0x2b7,
                           ((entry & 0xfff) << 20) | 0x28067)
        image = ['@00000000'] + [f'{byte:02x}' for byte in boot]
        for region, base in [('rom', 0), ('sram', 0x10000000), ('ddr', 0x80000000)]:
            for line in (directory / (region + '.hex')).read_text().splitlines():
                image.append(f'@{int(line[1:], 16)+base:08x}' if line.startswith('@') else line)
        (directory / 'mem.hex').write_text('\n'.join(image) + '\n')


def compile_cores(lint=False):
    jobs = [('w1', 'probe_tb', ROOT / 'verif/block/cpu2_core/files.f', ['-GISSUE_WIDTH=1']),
            ('w2', 'probe_tb', ROOT / 'verif/block/cpu2_core/files.f', ['-GISSUE_WIDTH=2']),
            ('old', 'old_tb', ROOT / 'verif/block/cpu/b1/core.f', [])]

    def compile_one(job):
        name, top, filelist, parameters = job
        directory = OUT / name
        directory.mkdir(exist_ok=True)
        files = (['-F', str(filelist)] if name != 'old' else expand_files(filelist))
        if name == 'old':
            files.append(str(PERF / 'old_tb.sv'))
        else:
            files.append(str(PERF / 'probe_tb.sv'))
        action = ['--lint-only'] if lint else ['--binary', '-j', '4']
        execute(['verilator', *action, '--timing', '-Wall', '-Wno-PROCASSINIT', '-DSIM_MODE',
                 '--top-module', top, '--Mdir', str(directory / 'obj'), '-o', 'sim',
                 *parameters, *files], directory / ('lint.log' if lint else 'compile.log'))
    with ThreadPoolExecutor(max_workers=3) as pool:
        list(pool.map(compile_one, jobs))


def model(directory, width, entries):
    program, names, trace = program_and_trace(directory)
    addresses = memory_trace(directory, program, trace)
    options = dict(BASES['small' if width == 1 else 'full'])
    if width == 2:
        changes = dict(EXPERIMENTS['combo4-zba'])
        tage = changes.pop('tage')
        changes.pop('rf')
        changes.pop('zba')
        options.update(changes, direction_predictor=RamTage(*tage), second_level=True)
    options.update(division_cycles=divider_cycles(directory, program, trace,
                   'early-div' if width == 1 else 'radix4-early', complete_schedule=True),
                   completion_entries=entries, completion_addresses=addresses,
                   frontend_probe=IcacheProbe(1), frontend_registered_margin=True)
    result = simulate(program, trace, names['start_time'], names['stop_time'], 'V3s', **options)
    return result


def reference(directory):
    elf = directory / 'coremark.elf'
    execute(['spike', '--isa=rv32im_zicsr_zifencei_zicntr_zba', '--priv=m', '--pmpregions=0',
             '-m0x10000000:0x10000,0x80000000:0x100000',
             '--pc=0x80000000', '--disable-dtb', '-l', '--log-commits',
             '--log=' + str(directory / 'spike.log'), str(elf)], directory / 'spike.stdout')
    names = symbols(elf)
    lines = []
    for line in (directory / 'spike.log').read_text().splitlines(keepends=True):
        lines.append(line)
        match = re.search(r' mem 0x([0-9a-f]+) 0x([0-9a-f]+)', line)
        if match and int(match[1], 16) == names['tohost'] and int(match[2], 16):
            break
    (directory / 'spike.log').write_text(''.join(lines))


def check_trace(directory, target):
    expected = []
    for line in (directory / 'spike.log').read_text().splitlines():
        match = re.match(r'core\s+0:\s+3 0x([\da-f]+) \(0x([\da-f]+)\)(.*)', line)
        if match:
            reg = re.search(r'\bx(\d+)\s+0x([\da-f]+)', match[3])
            rd, value = (int(reg[1]), int(reg[2], 16)) if reg else (0, 0)
            expected.append((int(match[1], 16), int(match[2], 16), rd, value if rd else 0))
    actual = []
    for line in (directory / (target + '.trace')).read_text().splitlines():
        fields = line.split()[1:] if target != 'old' else line.split()
        pc, instr, rd, value = fields
        rd = int(rd, 16 if target == 'old' else 10)
        if int(instr, 16) & 0x7f in (0x23, 0x63):
            rd = 0
        actual.append((int(pc, 16), int(instr, 16), rd, int(value, 16) if rd else 0))
    # RTL alone executes the reset trampoline before the identical ELF entry.
    first = next(i for i, record in enumerate(actual) if record[0] == expected[0][0])
    actual = actual[first:]
    if actual != expected:
        mismatch = next((i for i, pair in enumerate(zip(actual, expected))
                         if pair[0] != pair[1]), min(len(actual), len(expected)))
        raise AssertionError(f'{directory.name}/{target} trace mismatch at {mismatch}: '
                             f'{actual[mismatch:mismatch+1]} != {expected[mismatch:mismatch+1]}')


def run(names):
    rows = []
    for name in names:
        directory = OUT / name
        reference(directory)
        names = symbols(directory / 'coremark.elf')
        row = dict(name=name)
        for width in (1, 2):
            for entries in (0, 4):
                result = model(directory, width, entries)
                key = f'model_w{width}' + ('_n4' if entries else '')
                (directory / (key + '.json')).write_text(json.dumps(result, indent=2) + '\n')
                row[key] = result['cycles']
        for target in ('w1', 'w2', 'old'):
            command = [str(OUT / target / 'obj/sim'), '+MEM_HEX=' + str(directory / 'mem.hex'),
                       f'+TOHOST_ADDR={names["tohost"]:x}',
                       f'+PERF_BEGIN={names["start_time"]:x}',
                       f'+PERF_END={names["stop_time"]:x}']
            command += ([f'+TRACE_FILE={directory}/old.trace',
                         f'+COVERAGE_FILE={directory}/old.coverage.json'] if target == 'old' else
                        [f'+TRACE={directory}/{target}.trace',
                         f'+PROBE={directory}/{target}.csv', '+CONTROL_LOG'])
            execute(command, directory / (target + '.log'))
            log = (directory / (target + '.log')).read_text()
            row[target] = int(re.search(r'PERF (?:old|width=\d+) cycles=(\d+)', log)[1])
            check_trace(directory, target)
        rows.append(row)
        print(json.dumps(row), flush=True)
        (OUT / 'cycles.json').write_text(json.dumps(rows, indent=2) + '\n')
    print('PASS all streams: Spike register/PC trace comparison for all three RTL cores')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', choices=('build', 'run', 'lint'))
    parser.add_argument('--names', nargs='+', choices=CASES, default=CASES)
    args = parser.parse_args()
    if args.stage == 'build':
        build(args.names)
        compile_cores()
        print(f'PASS build: {len(args.names)} programs and three RTL configurations')
    elif args.stage == 'lint':
        compile_cores(lint=True)
        print('PASS lint: W1 NONE, W2 NONE and competition core')
    else:
        run(args.names)
