#!/usr/bin/env python3
# File: run_c3_eval.py; Spec: T-CPU-N-T4BE / cpu-spec 4.10; Clock: host.
# Isolate ordinary load result registration without moving M commit or traps.
"""Use prepared build/v017/input/{coremark,vision,render} warm Spike traces."""
import json
from pathlib import Path

from ooo_model import memory_trace
from pipe_model import program_and_trace, simulate
from run_frontend_t2_eval import IcacheProbe
from run_pipeline_cut_eval import BASE, MemoryProbe

CONFIGS = {
    'baseline': {},
    'C3': dict(load_latency=3, late_load_result=True),
    'C3-M2': dict(load_latency=3, memory_capture=True),
}


def main():
    output = Path('build/t4be/c3')
    output.mkdir(parents=True, exist_ok=True)
    for workload in ('coremark', 'vision', 'render'):
        directory = Path('build/v017/input') / workload
        program, symbols, trace = program_and_trace(directory)
        addresses = memory_trace(directory, program, trace)
        with (output / (workload + '.jsonl')).open('w') as stream:
            for name, changes in CONFIGS.items():
                probe = MemoryProbe(addresses, repair=int(name != 'baseline'))
                result = simulate(program, trace, symbols['start_time'], symbols['stop_time'],
                                  'V3s', **dict(BASE, **changes),
                                  frontend_probe=IcacheProbe(1), frontend_registered_margin=True,
                                  memory_probe=probe)
                row = dict(workload=workload, name=name, **result,
                           repairs=probe.repairs, early_failures=probe.early_failures,
                           dc_misses=probe.misses, devices=probe.devices)
                stream.write(json.dumps(row) + '\n')
                stream.flush()
                print(workload, name, result['cycles'], flush=True)


if __name__ == '__main__':
    main()
