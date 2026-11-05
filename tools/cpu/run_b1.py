#!/usr/bin/env python3
# File: run_b1.py; Spec: cpu-testplan 2-6; Clock: host.
# Build one CPU regression program, run real-core B1, and compare its reference.
"""Run a generated CPU regression case."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from regress import expand_files
import build_directed
import build_tests
import randgen
from b1_stimulus import plusargs as stimulus_plusargs
from run_spike import run, symbols
from trace_compare import compare, rtl_events, spike_events

ROOT = Path(__file__).resolve().parents[2]


def simulator():
    out = ROOT / 'build/cpu/b1' / 'no-c'
    out.mkdir(parents=True, exist_ok=True)
    binary = out / 'obj/sim'
    files = expand_files(ROOT / 'verif/block/cpu/b1/core.f')
    # Timestamp dependencies cover RTL, the harness and nested filelists.
    sources = [Path(name) for name in files if not name.startswith('+')]
    sources += [ROOT / 'verif/block/cpu/b1/core.f', ROOT / 'rtl/filelists/cpu.f']
    sources += list((ROOT / 'verif/block/cpu/b1').glob('*.svh'))
    if not binary.exists() or any(p.stat().st_mtime > binary.stat().st_mtime for p in sources):
        command = ['verilator', '--binary', '--timing', '-Wall', '-j', '1', '--top-module',
                   'edrv32_cpu_b1_core_tb', '--Mdir', str(out / 'obj'), '-o', 'sim',
                   '+define+SIM_MODE']
        with (out / 'compile.log').open('w') as log:
            subprocess.run(command + files, stdout=log, stderr=subprocess.STDOUT, check=True)
    return binary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('case', type=Path)
    args = parser.parse_args()
    case = json.loads(args.case.read_text())
    compressed = False
    suite = case['suite']
    name = case['name']
    binary = simulator()
    config = None
    if suite in ('riscv-tests', 'arch-test'):
        elf = build_tests.build(ROOT / case['source'], name, suite == 'arch-test', compressed)
        out = elf.parent
    elif suite == 'random':
        out, source, generator = randgen.write_program(name, case['seed'], compressed)
        randgen.build_run(out, source, generator, compressed)
        elf = out / 'program.elf'
    elif suite == 'directed':
        source = ROOT / 'sw/tests/cpu' / name / 'main.S'
        config = json.loads((source.parent / 'b1.json').read_text())
        out = ROOT / 'build/cpu/directed' / name / 'no-c'
        if case.get('fence_irq'):
            out /= 'irq'
        elf = build_directed.build(source, out, False, compressed,
                                   ('FENCEI_IRQ=1',) if case.get('fence_irq') else ())
        if case.get('fence_irq'):
            config['spike'] = 'smoke'
            config['schedule'].append(dict(kind='irq', when='FENCE.I.clean',
                pc='self_modify_fence', source='MEIP', clear='trap entry'))
        if config['spike'] == 'compare':
            run(elf, out, compressed)
        else:
            reference = out / 'spike-smoke'
            reference_elf = build_directed.build(source, reference, True, compressed)
            run(reference_elf, reference, compressed)
            print('PASS SPIKE_SMOKE (reference sanity only; no retirement comparison)')
    else:
        raise ValueError(suite)
    names = symbols(elf)
    plusargs = [f'+MEM_HEX={out}/mem.hex', f'+TOHOST_ADDR={names["tohost"]:x}',
                f'+TRACE_FILE={out}/rtl.trace', f'+COVERAGE_FILE={out}/coverage.json']
    if config is not None:
        plusargs += stimulus_plusargs(config, names, out)
    if suite == 'random':
        plusargs += ['+IC_MISS_PCT=20', '+DC_MISS_PCT=20',
                     '+IC_READY_LOW_PCT=20', '+DC_READY_LOW_PCT=20',
                     '+verilator+seed+' + str(case['seed'] + 1)]
    if suite == 'arch-test':
        plusargs += [f'+SIGNATURE_BEGIN={names["begin_signature"]:x}',
                     f'+SIGNATURE_END={names["end_signature"]:x}',
                     f'+SIGNATURE_FILE={out}/rtl.signature']
    with (out / 'run.log').open('w') as log:
        result = subprocess.run([str(binary)] + plusargs, stdout=log,
                                stderr=subprocess.STDOUT, timeout=120)
    print((out / 'run.log').read_text(), end='')
    result.check_returncode()
    if name != 'rv32mi-p-ma_fetch' and (config is None or config['spike'] == 'compare'):
        if compare(rtl_events(out / 'rtl.trace'), spike_events(out / 'spike.log')):
            return 1
    if suite == 'arch-test':
        subprocess.run([sys.executable, str(ROOT / 'tools/cpu/compare_signatures.py'),
                        str(out / 'rtl.signature'), str(out / 'reference.signature')], check=True)
    if config is not None:
        for event in config['schedule']:
            if event['kind'] == 'paired_run':
                paired = out / 'paired'
                paired.mkdir(exist_ok=True)
                patch = event['patch']
                word = int(patch['word'], 0)
                image = (out / 'mem.hex').read_text()
                image += f'@{names[patch["pc"]]:08x}\n'
                image += '\n'.join(f'{byte:02x}' for byte in word.to_bytes(4, 'little')) + '\n'
                (paired / 'mem.hex').write_text(image)
                arguments = []
                for arg in plusargs:
                    for filename in ('mem.hex', 'rtl.trace', 'coverage.json', 'predictor.txt'):
                        arg = arg.replace(str(out / filename), str(paired / filename))
                    arguments.append(arg)
                with (paired / 'run.log').open('w') as log:
                    result = subprocess.run([str(binary)] + arguments, stdout=log,
                                            stderr=subprocess.STDOUT, timeout=120)
                print((paired / 'run.log').read_text(), end='')
                result.check_returncode()
                if compare(rtl_events(paired / 'rtl.trace'), spike_events(out / 'spike.log')):
                    return 1
                if (out / 'predictor.txt').read_text() != (paired / 'predictor.txt').read_text():
                    raise AssertionError('B-06 predictor state/probe differs after flushed branch patch')
                print('PASS B-06 paired predictor state and probe prediction')
    mode = 'b1-selfcheck' if config is not None and config['spike'] != 'compare' else \
        'tohost-only' if name == 'rv32mi-p-ma_fetch' else 'spike-compare'
    print(f'PASS {suite} {name} no-C mode={mode}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
