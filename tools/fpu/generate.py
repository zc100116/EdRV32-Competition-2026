#!/usr/bin/env python3
# File: generate.py
# Spec: fpu-testplan FV01-FV09, FT01; fpu-spec 2.
# Description: Stream TestFloat and RISC-V directed raw-bit unit vectors.
# Clock: host only.
import argparse
from functools import lru_cache
import itertools
from pathlib import Path
import random
import subprocess
import time
from reference import (ROOT, Reference, ROUNDING, ROUNDED, box, instruction,
                       operations, testfloat_function)


def boundaries(width):
    if width == 32:
        return [0, 0x80000000, 0x7f800000, 0xff800000, 0x7fc12345, 0xffc54321,
                0x7f800001, 0xff800001, 1, 0x80000001, 0x7fffff, 0x807fffff,
                0x800000, 0x80800000, 0x3f800000, 0xbf800000, 0x7f7fffff,
                0xff7fffff, 0x3f800001, 0x3f7ffffe, 0x4f000000, 0xcf000001,
                0x4f800000, 0x3f000000, 0xbf000000, 0x33800000, 0x33000000,
                0xcf000000, 0xceffffff, 0x4effffff, 0x4f7fffff]
    return [0, 0x8000000000000000, 0x7ff0000000000000, 0xfff0000000000000,
            0x7ff8123456789abc, 0xfff8abcdef123456, 0x7ff0000000000001,
            0xfff0000000000001, 1, 0x8000000000000001, 0xfffffffffffff,
            0x800fffffffffffff, 0x10000000000000, 0x8010000000000000,
            0x3ff0000000000000, 0xbff0000000000000, 0x7fefffffffffffff,
            0xffefffffffffffff, 0x3ff0000000000001, 0x3feffffffffffffe,
            0x41e0000000000000, 0xc1e0000000200000, 0x41f0000000000000,
            0x3fe0000000000000, 0xbfe0000000000000, 0x3ca0000000000000,
            0x3c90000000000000, 0xc1e0000000000000, 0x41dfffffffc00000,
            0x41efffffffe00000, 0x41f0000000100000]


def directed(op, width, flen):
    values = boundaries(width)
    ternary = op in ['madd', 'msub', 'nmadd', 'nmsub']
    binary = op in ['add', 'sub', 'mul', 'div', 'min', 'max', 'eq', 'lt', 'le',
                    'sgnj', 'sgnjn', 'sgnjx']
    if ternary:
        # All special triples; then normal/subnormal boundaries in each source.
        rows = list(itertools.product(values[:10], repeat=3))
        rows += [(x, values[18], values[15]) for x in values]
        rows += [(values[18], x, values[15]) for x in values]
        rows += [(values[18], values[19], x) for x in values]
        # Per-variant fused cancellation, with input signs adjusted to same exact result.
        sign = 1 << (width - 1)
        a, b, c = values[18], values[19], values[15]
        if op in ['nmadd', 'nmsub']:
            a ^= sign
        if op in ['msub', 'nmadd']:
            c ^= sign
        rows += [(a, b, c)]
        # Overflowing unrounded product must cancel before final rounding.
        a, b, c = values[16], (0x40000000 if width == 32 else 0x4000000000000000), values[17]
        if op in ['nmadd', 'nmsub']:
            a ^= sign
        if op in ['msub', 'nmadd']:
            c ^= sign
        rows += [(a, b, c)]
    elif binary:
        rows = itertools.product(values, values, [0])
    else:
        rows = [(x, 0, 0) for x in values]
    for a, b, c in rows:
        integer = a & 0xffffffff if op in ['from_w', 'from_wu', 'mv_w_x'] else 0
        yield box(a, width, flen), box(b, width, flen), box(c, width, flen), integer
    if op in ['from_w', 'from_wu', 'mv_w_x']:
        for integer in [0, 1, 0xffffffff, 0x7fffffff, 0x80000000, 0x1000001]:
            yield 0, 0, 0, integer
    if width == 32 and flen == 64:
        # Invalid boxing in every used source, preserving low sNaN/payloads.
        for a in values:
            yield a, box(values[14], width, flen), box(0, width, flen), 0
            if binary or ternary:
                yield box(values[14], width, flen), a, box(0, width, flen), 0
            if ternary:
                yield box(values[14], width, flen), box(values[14], width, flen), a, 0


COMMANDS = []


def command(function, rm, seed, level, count=None):
    args = [str(ROOT / 'build/fpu/testfloat/testfloat_gen'), '-level', str(level),
            '-seed', str(seed), ROUNDING[rm], '-tininessafter', '-exact']
    # Pinned upstream f32 unary level2 has only 8800 cases. Extend that stream
    # to 10000 for the ten required sampled sequences (genCases_f32.c).
    if count == 10000 and function in ['f32_sqrt', 'f32_to_i32', 'f32_to_ui32', 'f32_to_f64']:
        args += ['-n', '10000']
    args += [function]
    return args


@lru_cache(maxsize=10)
def sampled(function, rm, seed, count, level):
    args = command(function, rm, seed, level, count)
    with subprocess.Popen(args, stdout=subprocess.PIPE) as proc:
        sample = subprocess.run([str(ROOT / 'build/fpu/sample'), str(count), str(seed)],
                                stdin=proc.stdout, stdout=subprocess.PIPE, check=True)
        proc.stdout.close()
        if proc.wait() != 0:
            raise RuntimeError(f'testfloat_gen failed: {args}')
    return sample.stdout.decode().splitlines()


def tf_rows(op, width, flen, rm, seed, count, level):
    function = testfloat_function(op, width)
    if function is None:
        rng = random.Random(seed)
        for _ in range(count):
            yield tuple(rng.getrandbits(flen) for _ in range(3)) + (rng.getrandbits(32),)
        return
    COMMANDS.append(' '.join(command(function, rm, seed, level, count))
                    + f' | build/fpu/sample {count} {seed}')
    for line in sampled(function, rm, seed, count, level):
        yield decode_tf(line, op, width, flen)


def decode_tf(line, op, width, flen):
    fields = [int(x, 16) for x in line.split()]
    inputs = fields[:-2]
    expected, flags = fields[-2:]
    a, b, c = (inputs + [0, 0, 0])[:3]
    integer = 0
    if op in ['from_w', 'from_wu']:
        integer, a = a & 0xffffffff, 0
    sign = 1 << (width - 1)
    if op in ['nmadd', 'nmsub']:
        a ^= sign
    if op in ['msub', 'nmadd']:
        c ^= sign
    data = (box(a, width, flen), box(b, width, flen), box(c, width, flen), integer)
    return data + (expected, flags)


def full_rows(op, width, flen, rm):
    function = testfloat_function(op, width)
    if function is None:
        return
    args = command(function, rm, 0, 2)
    COMMANDS.append(' '.join(args))
    with subprocess.Popen(args, stdout=subprocess.PIPE, text=True) as proc:
        for line in proc.stdout:
            yield decode_tf(line, op, width, flen)
        if proc.wait() != 0:
            raise RuntimeError(f'testfloat_gen failed: {args}')


def generate(tier, config, output):
    COMMANDS.clear()
    flen = 32 if config == 'F' else 64
    output.mkdir(parents=True, exist_ok=True)
    reference = Reference()
    start = time.monotonic()
    summary = []
    for op, width in operations(flen):
        for rm in (range(5) if op in ROUNDED else [0]):
            path = output / f'{op}_{width}_rm{rm}.vec'
            directed_count = 0
            random_count = 0
            full_count = 0
            with path.open('w') as stream:
                def emit(a, b, c, integer):
                    result, flags, dest = reference.evaluate(op, width, flen, a, b, c, integer, rm)
                    stream.write(f'{instruction(op, width, rm):08x} {rm:x} '
                                 f'{a:016x} {b:016x} {c:016x} {integer:08x} '
                                 f'{result:016x} {flags:02x} {dest:x}\n')
                    return result, flags
                for data in directed(op, width, flen):
                    emit(*data)
                    directed_count += 1
                def emit_tf(row):
                    actual = emit(*row[:4])
                    if len(row) == 6:
                        expected, flags = row[4:]
                        result_width = 32 if op == 'to_s' else 64 if op == 'to_d' else width
                        if op not in ['eq', 'lt', 'le', 'to_w', 'to_wu']:
                            expected = box(expected, result_width, flen)
                        else:
                            expected &= 0xffffffff
                        assert actual == (expected, flags), (op, width, rm, row, actual)
                if tier == 'full':
                    for row in full_rows(op, width, flen, rm):
                        emit_tf(row)
                        full_count += 1
                for seed in (range(10) if tier == 'full' else [0]):
                    for row in tf_rows(op, width, flen, rm, seed,
                                       10000 if tier == 'full' else 32,
                                       2 if tier == 'full' else 1):
                        emit_tf(row)
                        random_count += 1
            summary.append(f'{path.name}: directed={directed_count} '
                           f'random={random_count} level2={full_count}')
    elapsed = time.monotonic() - start
    options = (f'{tier} {config}: tininessafter, exact, '
               f'level={2 if tier == "full" else 1}, '
               f'seeds={"0..9" if tier == "full" else "0"}, '
               f'reservoir={10000 if tier == "full" else 32}, sampling_seed=generator_seed, '
               'rm=RNE/RTZ/RDN/RUP/RMM where applicable; full includes untruncated level2 seed0')
    report = options + '\n' + '\n'.join(summary) + f'\nseconds={elapsed:.3f}\n'
    (output / 'commands.txt').write_text('\n'.join(COMMANDS) + '\n')
    (output / 'counts.txt').write_text(report)
    print(report, end='')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tier', choices=['smoke', 'full'], default='smoke')
    parser.add_argument('--format', choices=['F', 'FD'], default='FD')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/fpu/vectors')
    args = parser.parse_args()
    generate(args.tier, args.format, args.output)
