#!/usr/bin/env python3
# File: run_v2_schedule.py; Spec: C2-I2 software scheduling study; Clock: host.
# Rebuild the archived b1e9d08b workloads with GCC 15.2 scheduling alternatives.
# Preserve -O3 and all original loop/alignment flags; replay hardware separately.
"""Source env; python3 tools/cpu/eval/run_v2_schedule.py build (or replay)."""
import argparse
import json
from pathlib import Path
import shlex
import subprocess

from ooo_model import memory_trace
from pipe_model import program_and_trace, simulate
from run_frontend_t2_eval import IcacheProbe
from run_pipeline_cut_eval import MemoryProbe
from run_v2_eval import V5, cpi_stack

TUNES = {
    'rocket': '-mtune=rocket -fsched-pressure -frename-registers',
    'sifive7': '-mtune=sifive-7-series -fsched-pressure -frename-registers',
    'load2': '-mtune=sifive-7-series -fsched-pressure -frename-registers ' +
             '-fplugin=' + str(Path('build/cpu-v2-round2/plugin/load2.so').resolve()),
}
OUT = Path('build/cpu-v2-round2/schedule')


def build(tunes):
    source = Path('build/c2i-source').resolve()
    if 'load2' in tunes:
        plugin = OUT.parent / 'plugin'
        plugin.mkdir(parents=True, exist_ok=True)
        headers = subprocess.check_output(
            ['riscv-none-elf-gcc', '-print-file-name=plugin'], text=True).strip()
        subprocess.run(['g++', '-shared', '-fPIC', '-fno-rtti', '-Wall', '-Wextra',
                        '-I' + headers + '/include', 'tools/cpu/eval/gcc_load2.cc',
                        '-o', str(plugin / 'load2.so')], check=True)
    for tune in tunes:
        flags = TUNES[tune]
        for workload in ('coremark', 'vision', 'render'):
            original = source / 'build' / ('cpu_predictor_eval/tuned' if
                       workload == 'coremark' else 'second-workloads/' + workload)
            destination = (OUT / tune / workload).resolve()
            (destination / 'obj').mkdir(parents=True, exist_ok=True)
            commands = original.joinpath('commands.txt').read_text().replace(
                str(original), str(destination)).replace('-O3 ', '-O3 ' + flags + ' ')
            if workload == 'coremark':
                commands = commands.replace('make -C sw ', 'make -B -C sw ', 1)
            lines = commands.splitlines()
            destination.joinpath('commands.txt').write_text(commands)
            with destination.joinpath('build.log').open('w') as log:
                for command in lines[:-1]:
                    subprocess.run(shlex.split(command), cwd=source,
                                   stdout=log, stderr=log, check=True)
            symbols = subprocess.check_output(
                ['riscv-none-elf-nm', str(destination / 'coremark.elf')], text=True)
            stop = next(line.split()[0] for line in symbols.splitlines()
                        if line.endswith(' T stop_time'))
            destination.joinpath('debug.cmd').write_text(f'until pc 0 {stop}\nrs 1\nquit\n')
            with destination.joinpath('console.log').open('w') as log:
                subprocess.run(shlex.split(lines[-1]), cwd=source,
                               stdout=log, stderr=log, check=True)
            print('built', tune, workload, flush=True)


def replay(workload, tunes):
    for tune in tunes:
        directory = OUT / tune / workload
        program, symbols, trace = program_and_trace(directory)
        addresses = memory_trace(directory, program, trace)
        icache, memory = IcacheProbe(1), MemoryProbe(addresses)
        result = simulate(program, trace, symbols['start_time'], symbols['stop_time'],
                          'V3s', **V5, frontend_probe=icache,
                          frontend_registered_margin=True, memory_probe=memory)
        row = dict(workload=workload, name='schedule-' + tune, **result,
                   **cpi_stack(result, icache.roi_misses))
        (directory / 'result.json').write_text(json.dumps(row) + '\n')
        print(workload, tune, result['instructions'], result['cycles'], flush=True)
        del program, symbols, trace, addresses, memory


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=('build', 'replay'))
    parser.add_argument('--workload', choices=('coremark', 'vision', 'render'))
    parser.add_argument('--tunes', nargs='+', choices=TUNES, default=list(TUNES))
    args = parser.parse_args()
    if args.phase == 'build':
        build(args.tunes)
    else:
        replay(args.workload, args.tunes)


if __name__ == '__main__':
    main()
