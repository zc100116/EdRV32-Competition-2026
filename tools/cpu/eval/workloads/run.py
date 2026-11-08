#!/usr/bin/env python3
# run.py — cpu-spec 4.1–4.4 evaluation; build/trace real C workloads on host Spike.
# Keep generated ELF/logs and single-run model results under build/second-workloads.
"""Source edrv32/env.sh; invoke under flock -s /tmp/edrv32-sim.lock."""
import argparse
from bisect import bisect_left, bisect_right
from collections import Counter
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor
import json
from pathlib import Path
import shlex
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(HERE.parent))
from analyze import DISASM
from pipe_model import program_and_trace, simulate
from run_fmax_eval import CONFIGS, LIMITS
from run_predictor_eval import TUNED

OUT = ROOT / 'build/second-workloads'
ARCH = 'rv32im_zicsr_zifencei'


def prepare(name):
    out = OUT / name
    out.mkdir(parents=True, exist_ok=True)
    sources = [HERE / 'start.S', HERE / ('vision.c' if name == 'vision' else 'render.c')]
    includes = [HERE, ROOT / 'sw/lib', ROOT / 'sw/apps/showcase/board/vision']
    if name == 'vision':
        sources += [ROOT / 'sw/apps/showcase/board/vision/post.c', ROOT / 'sw/lib/yolo_tables.c']
    else:
        sources += sorted((ROOT / 'third_party/lvgl/src').rglob('*.c'))
        includes += [ROOT / 'third_party/lvgl']
    command = ['riscv-none-elf-gcc', '-march=' + ARCH, '-mabi=ilp32', '-std=c11',
               '-Wall', '-Wextra', '-Werror', *shlex.split(TUNED), '-ffreestanding',
               '-fno-builtin', '-ffunction-sections', '-fdata-sections',
               '-DLV_CONF_INCLUDE_SIMPLE', *['-I' + str(p) for p in includes]]
    objects = out / 'obj'
    objects.mkdir(exist_ok=True)

    def compile_source(source):
        obj = objects / ('_'.join(source.relative_to(ROOT).parts) + '.o')
        cmd = command + ['-c', str(source), '-o', str(obj)]
        log_path = obj.with_suffix('.log')
        with log_path.open('w') as log:
            subprocess.run(cmd, stdout=log, stderr=log, check=True)
        return obj, cmd, log_path

    with ThreadPoolExecutor(max_workers=4) as pool:
        compiled = list(pool.map(compile_source, sources))
    link = ['riscv-none-elf-gcc', '-march=' + ARCH, '-mabi=ilp32',
               *[str(obj) for obj, _, _ in compiled], '-nostdlib', '-Wl,--gc-sections',
               '-T' + str(HERE / 'spike.ld'), '-Wl,-Map=' + str(out / 'workload.map'),
               '-lc', '-lgcc', '-o', str(out / 'coremark.elf')]
    # coremark.elf is the existing trace loader's filename contract, not the workload.
    with (out / 'build.log').open('w') as log:
        for _, _, log_path in compiled:
            log.write(log_path.read_text())
        subprocess.run(link, stdout=log, stderr=log, check=True)
    symbols = subprocess.check_output(['riscv-none-elf-nm', str(out / 'coremark.elf')], text=True)
    stop = next(line.split()[0] for line in symbols.splitlines() if line.endswith(' T stop_time'))
    (out / 'debug.cmd').write_text(f'until pc 0 {stop}\nrs 1\nquit\n')
    spike = ['spike', '--isa=' + ARCH + '_zicntr_zihpm', '--priv=m', '--pmpregions=0',
             '--no-dm', '-m0x80000000:0x2000000', '--pc=0x80000000', '--disable-dtb',
             '-d', '--debug-cmd=' + str(out / 'debug.cmd'), '-l', '--log-commits',
             '--log=' + str(out / 'spike.log'), str(out / 'coremark.elf')]
    commands = [cmd for _, cmd, _ in compiled] + [link, spike]
    (out / 'commands.txt').write_text('\n'.join(map(shlex.join, commands)) + '\n')
    with (out / 'console.log').open('w') as log:
        subprocess.run(spike, stdout=log, stderr=log, check=True)


def statistics(out, program, symbols, trace):
    trace = trace[trace.index(symbols['start_time']):trace.index(symbols['stop_time'])]
    names = {int(m[1], 16): m[3] for line in (out / 'numeric.dis').read_text().splitlines()
             if (m := DISASM.match(line))}
    raw, loads, loops = Counter(), Counter(), Counter()
    static_pcs = sorted(program)
    for a, b in zip(trace, trace[1:]):
        older, younger = program[a], program[b]
        if older.rd and older.rd in younger.sources:
            raw[names[a], names[b]] += 1
            if older.kind == 'load':
                loads[names[a], names[b]] += 1
        if older.kind == 'branch' and b < a:
            size = bisect_right(static_pcs, a) - bisect_left(static_pcs, b)
            if size <= 8:
                loops[b, a] += 1
    hottest = loops.most_common(2)
    # Use the two hottest short-loop spans; union avoids counting overlaps twice.
    intervals = {(a, b) for (a, b), _ in hottest}
    coverage = sum(any(a <= pc <= b for a, b in intervals) for pc in trace)
    comparison = sum(n for (a, b), n in loads.items()
                     if b in ('beq', 'bne', 'blt', 'bge', 'bltu', 'bgeu'))
    macros = raw['addi', 'andi'] + raw['srli', 'or']
    result = dict(instructions=len(trace), raw_total=sum(raw.values()),
                  raw_top5=raw.most_common(5), load_use_total=sum(loads.values()),
                  load_use_pairs=loads.most_common(), load_compare=comparison,
                  macros=macros, pointer_lw_lbu=loads['lw', 'lbu'],
                  short_loop_coverage=coverage,
                  short_loops=[dict(start=hex(a), end=hex(b), backedges=n,
                                    size=bisect_right(static_pcs, b) - bisect_left(static_pcs, a))
                               for (a, b), n in hottest])
    (out / 'statistics.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result), flush=True)


def load(name):
    global PROGRAM, SYMBOLS, TRACE
    PROGRAM, SYMBOLS, TRACE = program_and_trace(OUT / name)


def evaluate(item):
    name, options = item
    return dict(name=name, **simulate(PROGRAM, TRACE, SYMBOLS['start_time'],
                SYMBOLS['stop_time'], 'V3s', btb_entries=128, gshare_entries=4096,
                ras_entries=4, gshare_pc_shift=2, **options))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=('prepare', 'measure'))
    parser.add_argument('workload', choices=('vision', 'render'))
    args = parser.parse_args()
    if args.phase == 'prepare':
        prepare(args.workload)
    else:
        out = OUT / args.workload
        load(args.workload)
        statistics(out, PROGRAM, SYMBOLS, TRACE)
        with (out / 'results.jsonl').open('w') as log:
            with ProcessPoolExecutor(max_workers=2, initializer=load,
                                     initargs=(args.workload,)) as pool:
                for row in pool.map(evaluate, (CONFIGS | LIMITS).items()):
                    line = json.dumps(row)
                    log.write(line + '\n')
                    log.flush()
                    print(line, flush=True)


if __name__ == '__main__':
    main()
