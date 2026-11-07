#!/usr/bin/env python3
# File: run_v021_eval.py; Spec: cpu-spec v0.21 2.3, 4.1-4.10; Clock: host.
# Replay the approved D1/D2 and raw-memory capture stages on three warm Spike traces.
# Retain the previous tournament and v0.20 baselines for direct cycle comparison.
"""Source edrv32 env; inputs are build/v017/input/{coremark,vision,render}."""
import json
from pathlib import Path

from ooo_model import memory_trace
from pipe_model import program_and_trace, simulate
from run_frontend_t2_eval import IcacheProbe
from run_pipeline_cut_eval import BASE, MemoryProbe


def main():
    output = Path('build/t3be/model.jsonl')
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('w') as stream:
        for workload in ('coremark', 'vision', 'render'):
            directory = Path('build/v017/input') / workload
            program, symbols, trace = program_and_trace(directory)
            addresses = memory_trace(directory, program, trace)
            configs = {'tournament': {}, 'v0.20': {},
                       'C1+C3-old': dict(decode_split=True, load_latency=3),
                       'v0.21': dict(decode_split=True, load_latency=3, memory_capture=True)}
            for name, changes in configs.items():
                original = name == 'tournament'
                probe = MemoryProbe(addresses, repair=int(changes.get('load_latency', 2) == 3))
                result = simulate(
                    program, trace, symbols['start_time'], symbols['stop_time'], 'V3s',
                    **dict(BASE, **changes), frontend_probe=None if original else IcacheProbe(1),
                    frontend_registered_margin=not original,
                    memory_probe=None if original else probe)
                row = dict(workload=workload, name=name, **result,
                           dc_misses=probe.misses, devices=probe.devices, repairs=probe.repairs)
                stream.write(json.dumps(row) + '\n')
                stream.flush()
                print(f'{workload} {name}: {result["cycles"]}', flush=True)


if __name__ == '__main__':
    main()
