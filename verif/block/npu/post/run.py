#!/usr/bin/env python3
# File: run.py
# Spec: npu-testplan TL-05, PP-01-13, PP-P-01/02; CLAUDE.md 9.1.
# Description: Prepare directed post fixtures, compile public-port harness, run serially.
# Clock domain: host.
"""Run under flock /tmp/edrv32-sim.lock; Verilator always uses one build job."""
import argparse
import csv
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from fixtures import BUILD, ROOT, TIERS, fixture, variants
from stream import Acceptance, beats  # noqa: E402
from oracle import check_image  # noqa: E402
sys.path.insert(0, str(ROOT))
from tools.regress import expand_files  # noqa: E402


def build(lint=False):
    target = BUILD / 'post_sim'
    target.mkdir(parents=True, exist_ok=True)
    args = ['verilator', '--lint-only' if lint else '--binary', '--timing', '-Wall',
            '--top-module', 'tb_post', '-j', '1', '+define+SIM_MODE',
            '--Mdir', str(target), '-o', 'sim']
    args += expand_files(HERE / 'sources.f') + expand_files(HERE.parent / 'dut.f')
    with (target / 'compile.log').open('w') as log:
        result = subprocess.run(args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError((target / 'compile.log').read_text())
    print('PASS Verilator -Wall ' + ('lint' if lint else 'compile'))
    return target / 'sim'


def tl05(path):
    # Consume the public hex/regs products only, never compiler field encoders.
    spec = importlib.util.spec_from_file_location('nb_prepare', HERE.parent / 'prepare.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    memory = module.Image(path)
    regs = module.regs(path)
    heads = json.loads((ROOT / 'sw/lib/yolo_tables.json').read_text())
    words = [[memory.word(regs['DESC_BASE'] + n * 64 + w * 4) for w in range(16)]
             for n in range(regs['DESC_COUNT'])]
    def read(address, size):
        return bytes(memory.data[address + i] for i in range(size))
    check_image(words, read, regs['MODEL_BASE'], heads)
    print('PASS TL-05: 68 descriptors, six tags, three complete 2048B tables')


def network_raw(path):
    """Read the public reference hex, including cls even when DUT debug writes are disabled."""
    regs = dict((name, int(value, 16)) for name, value in
                (line.split() for line in (path / 'regs.txt').read_text().splitlines()))
    data = {}
    address = 0
    for token in (path / 'ref_out.hex').read_text().split():
        if token.startswith('@'):
            address = int(token[1:], 16) * 32
        else:
            data.update(enumerate(bytes.fromhex(token)[::-1], address))
            address += 32
    return bytes(data[regs['OUTPUT_BASE'] + i] for i in range(725760))


def stream_test(path):
    """Adapt only the branch ports documented in the RTL delivery report."""
    import struct
    target = BUILD / 'post_stream_sim'
    target.mkdir(parents=True, exist_ok=True)
    sources = [str(HERE.parent / 'lint.vlt'), str(HERE / 'tb_post_stream.sv')]
    sources += expand_files(HERE.parent / 'dut.f')
    command = ['verilator', '--binary', '--timing', '-Wall', '-j', '1',
               '+define+SIM_MODE', '--top-module', 'tb_post_stream',
               '--Mdir', str(target), '-o', 'sim', *sources]
    with (target / 'compile.log').open('w') as log:
        subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    log_path = path / 'run.log'
    with log_path.open('w') as log:
        subprocess.run([str(target / 'sim'), f'+CASE_DIR={path}'], cwd=ROOT,
                       stdout=log, stderr=subprocess.STDOUT, check=True, timeout=1200)
    scoreboard = Acceptance()
    first_enqueue = None
    for line in log_path.read_text().splitlines():
        fields = line.split()
        if fields[0] == 'ACCEPT':
            cycle, head, row, block, plane, pair = map(int, fields[1:7])
            base, width = ((0, 80), (3840, 40), (4800, 20))[head]
            left = base + row * width + pair * 2
            scoreboard.accept(cycle, (head, row, block, block * 2 + plane, pair,
                                      left, left + 1, bytes.fromhex(fields[7])[::-1]))
        elif fields[0] == 'FIRST_ENQUEUE':
            first_enqueue = int(fields[1])
    packed = b''.join(bytes.fromhex(line)[::-1]
                      for line in (path / 'output.hex').read_text().splitlines())
    assert len(packed) == 5040 * 24
    for record in struct.iter_unpack('<4iIHH', packed):
        assert record[4:6] == (16777216, 0), record
        scoreboard.enqueue(record[6])
    result = scoreboard.finish(first_enqueue)
    (path / 'performance.json').write_text(json.dumps(result, indent=2) + '\n')
    print(f'PASS PP-P-02 {result}: {log_path}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--test', choices=list(TIERS), required=True)
    parser.add_argument('--prepare-only', action='store_true')
    parser.add_argument('--lint-only', action='store_true')
    parser.add_argument('--compile-only', action='store_true')
    parser.add_argument('--network', type=Path)
    args = parser.parse_args()
    if args.lint_only or args.compile_only:
        build(args.lint_only)
        return
    if args.test == 'TL-05':
        path = args.network
        if path is None:
            path = BUILD / 'post' / 'tl05'
            subprocess.run([sys.executable, '-S', str(ROOT / 'tools/npu/compile_yolo.py'),
                            '--model-source',
                            str(ROOT / 'tasks/win/20261029-09-b3-software/src/npu'),
                            '--out', str(path)], cwd=ROOT, check=True)
        tl05(path)
        return
    if args.network is None:
        args.network = BUILD / 'yolo'
    if args.test == 'PP-P-02':
        path = BUILD / 'post' / 'pp-p-02'
        path.mkdir(parents=True, exist_ok=True)
        (path / 'stream.txt').write_text(''.join(
            ' '.join(str(value) for value in beat[:-1]) + ' ' + beat[-1].hex() + '\n'
            for beat in beats()))
        if not args.prepare_only:
            stream_test(path)
        print(f'PASS PP-P-02 stimulus: {path}, 12600 beats / 5040 anchors')
        return
    executable = None if args.prepare_only else build()
    performance = []
    baselines = {}
    for name, options in variants(args.test):
        if args.test == 'PP-11' or (args.test == 'PP-10' and name == 'real'):
            options['raw_override'] = network_raw(args.network)
        path = fixture(BUILD / 'post' / args.test.lower() / name, **options)
        plus = [f'+CASE_DIR={path}', f'+TEST_ID={args.test}', '+MEM_MODE=bw']
        if args.test in ('PP-07', 'PP-12'):
            plus += ['+POST_STALLS', '+MEM_B_DELAY=200']
        if args.test == 'PP-P-01':
            plus[-1] = '+MEM_MODE=' + name.rsplit('_', 1)[1]
        if args.test == 'PP-13':
            second = fixture(path.parent / 'frame2', count=3, frame=1, pattern=1)
            plus += [f'+FRAME2_DIR={second}']
        subcases = [[]]
        if args.test == 'PP-06':
            subcases = [[f'+FENCE_PHASE={phase}']
                        for phase in ((4,) if options['count'] == 0 else (2, 3, 4))]
        if args.test == 'PP-08':
            subcases = [[f'+FAULT_PHASE={phase}', f'+POST_ERROR_RESP={response:02b}']
                        for phase in (1, 2, 3) for response in (2, 3)]
        if args.test == 'PP-09':
            subcases = [[f'+ABORT_PHASE={phase}'] for phase in (1, 2, 3)]
        for index, extra in enumerate(subcases):
            if args.prepare_only:
                print(path, ' '.join(plus + extra))
                continue
            log = path / f'run_{index}.log'
            with log.open('w') as out:
                subprocess.run([str(executable)] + plus + extra, cwd=ROOT, stdout=out,
                               stderr=subprocess.STDOUT, check=True, timeout=1200)
            assert 'PASS POST' in log.read_text(), f'missing PASS: {log}'
            print(f'PASS {args.test} {name}/{index}: {log}')
            if args.test == 'PP-P-01':
                import re
                row = dict(variant=name)
                row.update({key: int(value) for key, value in
                            re.findall(r'(\w+)=(-?\d+)', log.read_text())})
                key = (options['count'], name.rsplit('_', 1)[1])
                if options['ctrl'] == 0:
                    baselines[key] = row['core_cycles']
                row['core_delta_from_raw'] = row['core_cycles'] - baselines[key]
                row['tail_us_180mhz'] = row['tail_cycles'] / 180
                row['compute_budget_us_200mhz'] = options['count'] * 320 / 200
                performance.append(row)
    if performance:
        target = BUILD / 'post' / 'pp-p-01' / 'performance.csv'
        with target.open('w') as out:
            writer = csv.DictWriter(out, fieldnames=list(performance[0]))
            writer.writeheader()
            writer.writerows(performance)
        print(f'PERFORMANCE {target}')


if __name__ == '__main__':
    main()
