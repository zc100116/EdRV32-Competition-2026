#!/usr/bin/env python3
"""run.py: gpu-testplan 2, 4, 6; generate, export, compare and run block cases.
Host Python, no clock domain. Generated files live under build/gpu/block.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import random
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(ROOT), str(HERE)]
from tools.gpu.model import GPU
from tools.gpu.scene import Memory, SCHEMA
from scene_support import Case

REGISTERS = {}
for register in SCHEMA['registers']:
    dimensions = register['dimensions']
    count = dimensions[0]['count'] if dimensions else 1
    stride = dimensions[0]['stride'] if dimensions else 0
    for index in range(count):
        name = register['name'] + (f'[{index}]' if dimensions else '')
        REGISTERS[name] = int(register['offset'], 0) + index*stride
CHECKED = ['STATUS', 'IRQ_STAT', 'ERR_CODE', 'DONE_COUNT', 'OBJ_HIT_COUNT',
           'OBJ_FREE_COUNT', 'OBJ_ALIVE_COUNT', 'OBJ_STAT'] + [f'PERF[{i}]' for i in range(1, 5)]
SAMPLED = CHECKED + [f'PERF[{i}]' for i in (0, 5, 6, 7, 8)]


def metadata(test):
    return dict(line.split(':', 1) for line in (HERE/test/'test.yaml').read_text().splitlines()
                if ':' in line and not line.lstrip().startswith('#'))


def model_export(out):
    # Consume the bench control file, including its integer/hex conventions.
    records = (out/'control.txt').read_text().splitlines()
    origin, words, write_count, sample_count = records[0].split()
    base = int(origin, 16)
    writes = [[int(a, 16), int(v, 16)] for a, v in
              (line.split() for line in records[1:1+int(write_count)])]
    offsets = [int(line, 16) for line in records[1+int(write_count):]]
    assert len(offsets) == int(sample_count)
    gpu = GPU(Memory.read_hex(out/'initial.hex', base)).execute(writes)
    # Export numeric little-endian words exactly as the DDR BFM's dump task does.
    (out/'actual.ddr.hex').write_text(''.join(
        f'{int.from_bytes(gpu.memory.read(base+index*4, 4), "little"):08x}\n'
        for index in range(int(words))))
    names = {offset: name for name, offset in REGISTERS.items()}
    (out/'actual.regs.txt').write_text(''.join(
        f'{offset:03x} {gpu.regs[names[offset]]:08x}\n' for offset in offsets))


def generate(test, out):
    seed = int(metadata(test)['seed'])
    spec = importlib.util.spec_from_file_location(test, HERE/test/'scene.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    case = Case()
    module.build(case, random.Random(seed))
    out.mkdir(parents=True, exist_ok=True)
    writes = case.scene.export(out/'initial.hex', out/'writes.json')
    # Re-import the exact serialized image and numeric APB writes consumed by the bench.
    writes = [[REGISTERS[name], value] for name, value in writes]
    gpu = GPU(Memory.read_hex(out/'initial.hex', case.scene.memory.base)).execute(writes)
    for check in case.checks:
        check(gpu)
    gpu.memory.write_hex(out/'expected.ddr.hex')
    expected = {name: gpu.regs[name] for name in CHECKED}
    (out/'expected.regs.json').write_text(json.dumps(expected, indent=2) + '\n')
    (out/'regions.json').write_text(json.dumps(dict(surfaces=case.surfaces,
                                                  regions=case.regions), indent=2) + '\n')
    for index, region in enumerate(case.surfaces + case.regions):
        (out/f'expected.region{index}.bin').write_bytes(
            gpu.memory.read(region['address'], region['size']))
    (out/'commands.bin').write_bytes(b''.join(case.scene.commands))
    words = len((out/'initial.hex').read_text().splitlines())
    header = f'{case.scene.memory.base:08x} {words:d} {len(writes):d} {len(SAMPLED):d}\n'
    (out/'control.txt').write_text(header + ''.join(f'{a:03x} {v:08x}\n' for a, v in writes)
                                  + ''.join(f'{REGISTERS[n]:03x}\n' for n in SAMPLED))
    # Expected IRQ_STAT selects normal completion or the specified command error path.
    (out/'completion.txt').write_text(f'{gpu.regs["IRQ_STAT"]:08x}\n')


def compare(out):
    base = int((out/'control.txt').read_text().split()[0], 16)
    expected = (out/'expected.ddr.hex').read_text().splitlines()
    actual = (out/'actual.ddr.hex').read_text().splitlines()
    if len(expected) != len(actual):
        raise AssertionError(f'DDR words expected={len(expected)} actual={len(actual)}')
    for index, (left, right) in enumerate(zip(expected, actual)):
        if int(left, 16) != int(right, 16):
            want = int(left, 16).to_bytes(4, 'little')
            got = int(right, 16).to_bytes(4, 'little')
            byte = next(n for n in range(4) if want[n] != got[n])
            raise AssertionError(f'DDR address={base+index*4+byte:#x} '
                                 f'expected={want[byte]:#04x} actual={got[byte]:#04x}')
    registers = {int(a, 16): int(v, 16) for a, v in
                 (line.split() for line in (out/'actual.regs.txt').read_text().splitlines())}
    for name, value in json.loads((out/'expected.regs.json').read_text()).items():
        observed = registers[REGISTERS[name]]
        if value != observed:
            raise AssertionError(f'{name} expected={value:#x} actual={observed:#x}')
    regions = json.loads((out/'regions.json').read_text())
    memory = Memory.read_hex(out/'actual.ddr.hex', base)
    for index, region in enumerate(regions['surfaces'] + regions['regions']):
        (out/f'actual.region{index}.bin').write_bytes(
            memory.read(region['address'], region['size']))
    print(f'PASS {out.name}: DDR={len(expected)*4} bytes, registers={len(CHECKED)}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['generate', 'compare', 'model', 'rtl'])
    parser.add_argument('tests', nargs='*', default=[])
    args = parser.parse_args()
    tests = args.tests or [f'gt{i:02d}' for i in range(1, 9)]
    for test in tests:
        out = ROOT/'build/gpu/block'/test
        if args.mode == 'compare':
            compare(out)
            continue
        generate(test, out)
        if args.mode == 'generate':
            continue
        if args.mode == 'model':
            model_export(out)
        else:
            from tools.regress import expand_files
            obj = ROOT/'build/gpu/block/obj'
            subprocess.run(['verilator', '--binary', '--timing', '-Wall', '-j', '1',
                            '--top-module', 'edrv32_gpu_tb', '--Mdir', str(obj), '-o', 'sim',
                            '+define+SIM_MODE', *expand_files(HERE/test/'files.f')],
                           cwd=ROOT, check=True)
            subprocess.run([str(obj/'sim'), f'+CASE_DIR={out}',
                            f'+SEED={int(metadata(test)["seed"])}'], cwd=ROOT, check=True)
        compare(out)


if __name__ == '__main__':
    main()
