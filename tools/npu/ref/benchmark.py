#!/usr/bin/env python3
# File: benchmark.py
# Spec: npu-spec 2.1–2.4, 4.1–4.3; N-M2 performance acceptance.
# Description: Build an independent 68-descriptor synthetic fixture and time execution.
#              Use typical L7 and L15.split shapes without compiler dependencies.
# Clock domain: none (host tool).
"""Run with OPENBLAS_NUM_THREADS=1 on the shared three-core development host."""

from pathlib import Path
import resource
import struct
from time import perf_counter

import npu_ref as ref
from test_ref import BASES, DESC_BASE, build_case, write_case


def main():
    directory = Path('build/npu/ref_benchmark')
    memory, registers, l7 = build_case(seed=7, shape=(24, 40), kernel=3, step=2,
                                      cin_blocks=8, cout_blocks=8)
    other, _, l15 = build_case(seed=15, shape=(48, 80), kernel=1,
                               cin_blocks=12, cout_blocks=2)
    delta = 0x800000
    for page, data in other.pages.items():
        if page != DESC_BASE // 4096:
            memory.write(page * 4096 + delta, data)
    for field in (1, 3, 5, 6, 7):
        l15['words'][field] += delta
    l15['output_address'] += delta
    cases = [('L7', l7), ('L15.split', l15)]
    layers = []
    total_macs = 0
    for name, case in cases:
        desc = ref.Descriptor(tuple(case['words']))
        ref.check_descriptor(desc, 0)
        layers.append(desc)
        start = perf_counter()
        ref.execute_descriptor(memory, BASES, desc)
        elapsed = perf_counter() - start
        macs = (case['output_shape'][0] * case['output_shape'][1] * case['channels']
                * case['data'].shape[2] * case['kernel'] ** 2)
        total_macs += 34 * macs
        print(f'{name}: {macs:,} MAC, {elapsed:.6f} s', flush=True)
    for index in range(68):
        memory.write(DESC_BASE + 64 * index, struct.pack('<16I', *layers[index % 2].words))
    registers['DESC_COUNT'] = 68
    write_case(directory, memory, registers, l7)
    (directory / 'check.txt').write_text(''.join(
        f"{name} {case['output_address']:08x} "
        f"{case['words'][4] * (case['channels'] // 16 + 1):x}\n" for name, case in cases))
    start = perf_counter()
    ref.execute(memory, registers)
    elapsed = perf_counter() - start
    print(f'Synthetic 68 descriptors: {total_macs:,} MAC, {elapsed:.6f} s', flush=True)
    print(f'Arithmetic estimate for 2.6e9 MAC: {elapsed * 2.6e9 / total_macs:.6f} s')
    print(f'Peak RSS (fixture construction included): '
          f'{resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024:.2f} MiB')
    print(f'Fixture: {directory}')


if __name__ == '__main__':
    main()
