#!/usr/bin/env python3
# File: board_cases.py
# Spec: npu-spec 2-5, 7; design/2026-10-30-board-npu-test section 4.
# Description: Generate board cases, pack read-only ELF data and re-execute it
#              with the independent reference model to check the packed bytes.
# Clock domain: none (host tool).
"""Build board_npu data. Run under flock /tmp/edrv32-sim.lock."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

from ref.npu_ref import Descriptor, Memory, execute, load_case, run_case

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'verif/block/npu'))
from cases import recipes  # noqa: E402
from prepare import patch_case  # noqa: E402

RUNTIME_BIAS = 0x10000000
BASE_NAMES = ('MODEL_BASE', 'WORK_BASE', 'INPUT_BASE', 'OUTPUT_BASE', 'DESC_BASE')
# NB preparation uses seed 1 except OP-12's explicitly selected seed.
SMALL_CASES = (
    ('OP-01', 'c16_32'), ('OP-01', 'c48_96'), ('OP-02', 'w12'),
    ('OP-03', 'h5'), ('OP-04', 'c4_cout32_lut0_res0'),
    ('OP-04', 'c4_cout16_lut1_res1'), ('OP-05', 'lut1'),
    ('OP-06', 'work'), ('OP-06', 'output'), ('OP-07', 'cout80'),
    ('OP-09', 'negative_c48'), ('OP-10', 'w2'), ('OP-10', 'w40'),
    ('OP-11', 'concat'), ('OP-12', 'seed00'),
)


def command(*args):
    subprocess.run([str(arg) for arg in args], cwd=ROOT, check=True,
                   env={**os.environ, 'OPENBLAS_NUM_THREADS': '1', 'OMP_NUM_THREADS': '1',
                        'MKL_NUM_THREADS': '1',
                        'PYTHONPATH': str(ROOT / 'third_party/ultralytics')})


def hex_segments(path):
    address = 0
    data = bytearray()
    for word in path.read_text().split():
        if word.startswith('@'):
            if data:
                yield address, bytes(data)
            address = int(word[1:], 16) * 32
            data = bytearray()
        else:
            data.extend(bytes.fromhex(word)[::-1])
    if data:
        yield address, bytes(data)


def merge_ranges(ranges):
    result = []
    for address, size in sorted(ranges):
        end = address + size
        if result and address <= result[-1][0] + result[-1][1]:
            start, previous_size = result[-1]
            result[-1] = (start, max(start + previous_size, end) - start)
        else:
            result.append((address, size))
    return result


def accessed_ranges(memory, registers):
    """Include stride padding, which the interchange format defines as zero."""
    bases = tuple(registers[key] for key in BASE_NAMES[:4])
    ranges = [(registers['DESC_BASE'], registers['DESC_COUNT'] * 64)]
    outputs = []
    for index in range(registers['DESC_COUNT']):
        desc = Descriptor.read(memory, registers['DESC_BASE'] + index * 64)
        height, width = desc.input_shape
        size = (height * width * 4 if desc.op == 0 and desc.flag(8)
                else desc.cin_blocks * desc.words[2])
        ranges.append((desc.address(bases, 'input'), size))
        size = desc.output_channels // 16 * desc.words[4]
        address = desc.address(bases, 'output')
        ranges.append((address, size))
        outputs.append((address, size, index))
        if desc.flag(7):
            ranges.append((desc.address(bases, 'residual'), size))
    return ranges, outputs


def pack_case(directory, name, blob):
    initial, registers = load_case(directory)
    expected = run_case(directory)
    ranges, outputs = accessed_ranges(initial, registers)
    loads = []

    def append(data):
        offset = len(blob)
        blob.extend(data)
        return offset

    for path in sorted(directory.glob('mem_*.hex')):
        for address, data in hex_segments(path):
            loads.append((address + RUNTIME_BIAS, append(data), len(data)))
            ranges.append((address, len(data)))
    checks = []
    for line in (directory / 'check.txt').read_text().splitlines():
        _, address, size = line.split()
        address, size = int(address, 16), int(size, 16)
        producer = max(index for start, count, index in outputs
                       if start <= address < start + count)
        checks.append((address + RUNTIME_BIAS, append(expected.read(address, size)),
                       size, producer))
        ranges.append((address, size))
    config = [registers[key] + RUNTIME_BIAS for key in BASE_NAMES]
    config.append(registers['DESC_COUNT'])
    return dict(name=name, config=config, loads=loads, checks=checks,
                spans=[(address + RUNTIME_BIAS, size)
                       for address, size in merge_ranges(ranges)])


def self_check(case, packed):
    """Reload exactly the uploaded bytes, using their board physical addresses."""
    memory = Memory()
    for address, offset, size in case['loads']:
        memory.write(address, packed[offset:offset + size])
    registers = dict(zip((*BASE_NAMES, 'DESC_COUNT'), case['config'], strict=True))
    execute(memory, registers)
    total = 0
    for address, offset, size, descriptor in case['checks']:
        expected = packed[offset:offset + size]
        actual = memory.read(address, size)
        differences = [index for index, pair in enumerate(zip(expected, actual, strict=True))
                       if pair[0] != pair[1]]
        if differences:
            first = differences[0]
            raise ValueError(f"{case['name']} desc={descriptor} addr={address + first:08x} "
                             f"expected={expected[first]:02x} actual={actual[first]:02x} "
                             f"mismatches={len(differences)}")
        total += size
    print(f"host {case['name']} PASS bytes={total}")


def write_header(path, cases):
    lines = [
        '/* Generated by tools/npu/board_cases.py; npu-spec 4. */',
        'extern const uint8_t _binary_cases_bin_start[];',
        'struct board_span { uint32_t address; uint32_t size; };',
        'struct board_load { uint32_t address; uint32_t offset; uint32_t size; };',
        'struct board_check {',
        '    uint32_t address; uint32_t offset; uint32_t size; uint32_t descriptor;',
        '};',
        'struct board_case {',
        '    const char *name; struct npu_config config;',
        '    const struct board_span *spans; uint32_t span_count;',
        '    const struct board_load *loads; uint32_t load_count;',
        '    const struct board_check *checks; uint32_t check_count;',
        '};',
    ]
    for index, case in enumerate(cases):
        for field, typename in (('spans', 'span'), ('loads', 'load'), ('checks', 'check')):
            lines.append(f'static const struct board_{typename} {field}_{index}[] = {{')
            for row in case[field]:
                lines.append('    {' + ', '.join(f'0x{value:08x}u' for value in row) + '},')
            lines.append('};')
    lines.append('static const struct board_case board_cases[] = {')
    for index, case in enumerate(cases):
        lines.append('    {"' + case['name'] + '",')
        lines.append('     {' + ', '.join(f'0x{n:08x}u' for n in case['config']) + '},')
        for field in ('spans', 'loads', 'checks'):
            lines.append(f'     {field}_{index}, {len(case[field])}u,')
        lines.append('    },')
    lines.append('};')
    path.write_text('\n'.join(lines) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, default=ROOT / 'build/sw/board_npu/data')
    args = parser.parse_args()
    args.out = args.out.resolve()
    args.out.mkdir(parents=True, exist_ok=True)
    blob = bytearray()
    cases = []
    for test, variant in SMALL_CASES:
        _, config, options, patch = next(row for row in recipes(test) if row[0] == variant)
        name = f'B-{test}-{variant}'
        directory = args.out / name
        directory.mkdir(exist_ok=True)
        for path in directory.glob('mem_*.hex'):
            path.unlink()
        config_path = directory / 'config.json'
        # This JSON is the gen_case input graph, not a provenance manifest.
        config_path.write_text(json.dumps(config, indent=2) + '\n')
        command(sys.executable, ROOT / 'tools/npu/gen_case.py', '--config', config_path,
                '--seed', options.get('seed', 1), '--out', directory)
        if patch is not None:
            patch_case(directory, patch)
        cases.append(pack_case(directory, name, blob))
    directory = args.out / 'C-YOLO'
    command(sys.executable, ROOT / 'tools/npu/compile_yolo.py', '--image',
            Path.home() / '.local/share/edrv32/npu/coco128/images/train2017/000000000009.jpg',
            '--out', directory)
    cases.append(pack_case(directory, 'C-YOLO', blob))
    binary = args.out / 'cases.bin'
    binary.write_bytes(blob)
    packed = binary.read_bytes()
    for case in cases:
        self_check(case, packed)
    write_header(args.out / 'board_data.h', cases)
    subprocess.run(['riscv-none-elf-objcopy', '-I', 'binary', '-O', 'elf32-littleriscv',
                    '-B', 'riscv', '--rename-section',
                    '.data=.rodata.board_cases,alloc,load,readonly,data,contents',
                    'cases.bin', 'cases.o'], cwd=args.out, check=True)
    print(f'board data: {len(cases) - 1} small cases + YOLO, {len(blob)} packed bytes')


if __name__ == '__main__':
    main()
