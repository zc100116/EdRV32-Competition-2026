#!/usr/bin/env python3
# File: run_v2_isa.py; Spec: C2-I Zba/Zbb evaluation, cpu-spec 2.1; Clock: host.
# Recompile the recorded old-source workloads with each ISA, then replay V5.
# Execute one compiler/Spike/model at a time; generated files stay under build/.
"""Run after the old-source inputs are prepared in build/c2i-source/build/."""
import json
from pathlib import Path
import shlex
import subprocess

from pipe_model import program_and_trace, simulate
from run_frontend_t2_eval import IcacheProbe
from run_v2_eval import V5, cpi_stack


def main():
    source = Path('build/c2i-source').resolve()
    output = Path('build/cpu-v2/isa')
    output.mkdir(parents=True, exist_ok=True)
    with (output / 'results.jsonl').open('w') as results:
        for isa in ('zba', 'zbb', 'zba_zbb'):
            arch = 'rv32im_' + isa + '_zicsr_zifencei'
            for workload in ('coremark', 'vision', 'render'):
                original = source / 'build' / ('cpu_predictor_eval/tuned' if
                                               workload == 'coremark' else
                                               'second-workloads/' + workload)
                destination = (output / isa / workload).resolve()
                (destination / 'obj').mkdir(parents=True, exist_ok=True)
                commands = original.joinpath('commands.txt').read_text().replace(
                    str(original), str(destination)).replace('rv32im_zicsr_zifencei', arch)
                destination.joinpath('commands.txt').write_text(commands)
                # Spike's debugger command file is independent of its old entry PC;
                # rebuild it after linking because the new ISA changes code layout.
                lines = commands.splitlines()
                with destination.joinpath('build.log').open('w') as log:
                    for command in lines[:-1]:
                        subprocess.run(shlex.split(command), cwd=source,
                                       stdout=log, stderr=log, check=True)
                symbols = subprocess.check_output(
                    ['riscv-none-elf-nm', str(destination / 'coremark.elf')], text=True)
                stop = next(line.split()[0] for line in symbols.splitlines()
                            if line.endswith(' T stop_time'))
                destination.joinpath('debug.cmd').write_text(
                    f'until pc 0 {stop}\nrs 1\nquit\n')
                with destination.joinpath('console.log').open('w') as log:
                    subprocess.run(shlex.split(lines[-1]), cwd=source,
                                   stdout=log, stderr=log, check=True)
                program, symbols, trace = program_and_trace(destination)
                icache = IcacheProbe(1)
                result = simulate(program, trace, symbols['start_time'], symbols['stop_time'],
                                  'V3s', **V5, frontend_probe=icache,
                                  frontend_registered_margin=True)
                row = dict(workload=workload, name='V5-' + isa, **result,
                           **cpi_stack(result, icache.roi_misses))
                results.write(json.dumps(row) + '\n')
                results.flush()
                print(workload, isa, result['instructions'], result['cycles'], flush=True)


if __name__ == '__main__':
    main()
