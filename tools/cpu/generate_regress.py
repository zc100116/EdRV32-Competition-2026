#!/usr/bin/env python3
# File: generate_regress.py; Spec: cpu-testplan 2-6; Clock: host.
# Materialize test.yaml cases for the real-core B1 regression.
"""Generate CPU regression descriptors under verif/block/cpu/."""
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'verif/block/cpu'


def emit(directory, case, tier):
    out = DEST / directory
    out.mkdir(parents=True, exist_ok=True)
    (out / 'case.json').write_text(json.dumps(case, indent=2) + '\n')
    (out / 'files.f').write_text('-f ../b1/core.f\n')
    runner = f'python3 tools/cpu/run_b1.py {out.relative_to(ROOT)}/case.json'
    (out / 'test.yaml').write_text(
        'top: edrv32_cpu_b1_core_tb\nfiles: files.f\ndefines: SIM_MODE\n'
        'parameters:\nsoftware:\ntimeout: 240\n'
        f'pass: PASS\nsimulator: runner\ntier: {tier}\nrunner: {runner}\n')


def main():
    count = 0
    for group in ('rv32ui', 'rv32um', 'rv32mi'):
        sources = [p for p in sorted((ROOT / 'third_party/riscv-tests/isa' / group).glob('*.S'))
                   if (group, p.stem) not in (('rv32ui', 'ma_data'), ('rv32mi', 'pmpaddr'), ('rv32mi', 'breakpoint'))]
        for index, source in enumerate(sources):
            name = group + '-p-' + source.stem
            for compressed in (False,):
                variant = 'c' if compressed else 'no-c'
                emit(f'isa-{name}-{variant}', dict(suite='riscv-tests', name=name,
                     source=str(source.relative_to(ROOT)), rvc=compressed),
                     'smoke' if index < 3 else 'full')
                count += 1
    arch = ROOT / 'third_party/riscv-arch-test/riscv-test-suite/rv32i_m'
    for group in ('I', 'M', 'Zifencei', 'privilege'):
        for source in sorted((arch / group / 'src').glob('*.S')):
            required = re.search(r'RVTEST_ISA\("([^"]+)"\)', source.read_text())[1]
            if not re.fullmatch(r'RV32I[MC]*(_Zicsr|_Zifencei)*', required):
                continue
            name = group + '-' + source.stem
            for compressed in (False,):
                variant = 'c' if compressed else 'no-c'
                emit(f'arch-{name.lower()}-{variant}', dict(suite='arch-test', name=name,
                     source=str(source.relative_to(ROOT)), rvc=compressed), 'full')
                count += 1
    for path in sorted((ROOT / 'sw/tests/cpu').glob('*/b1.json')):
        config = json.loads(path.read_text())
        for compressed in (False,):
            name = path.parent.name
            variant = 'c' if compressed else 'no-c'
            emit(f'{name}-{variant}', dict(suite='directed', name=name, rvc=compressed),
                 config['tier'])
            count += 1
    for compressed in (False,):
        variant = 'c' if compressed else 'no-c'
        emit(f'm-04-{variant}-irq', dict(suite='directed', name='m-04',
             rvc=compressed, fence_irq=True), 'full')
        count += 1
    for name in ('high-dep', 'low-dep', 'memory', 'branch'):
        for compressed in (False,):
            for seed in range(50):
                variant = 'c' if compressed else 'no-c'
                emit(f'random-{name}-{variant}-{seed:02}', dict(suite='random', name=name,
                     seed=seed, rvc=compressed), 'smoke' if seed < 2 else 'full')
                count += 1
    print(f'Generated {count} CPU B1 regression cases')


if __name__ == '__main__':
    main()
