#!/usr/bin/env python3
# File: run_frontend_t2_eval.py; Spec: T-CPU-N-T2FE follow-up; Clock: host.
# Compare incremental miss recovery and registered eight-entry frontend credits.
# Cache probes count modeled F1 requests; existing refill and D$ latency stay absent.
"""Run from the repository root with build/v017/input/{coremark,vision,render}."""
import json
from pathlib import Path

from pipe_model import program_and_trace, simulate


class IcacheProbe:
    """cache-spec 2.1: 32 KiB, two ways, 32-byte lines, 512 sets, exact LRU."""

    def __init__(self, recovery):
        self.recovery = recovery
        self.sets = [[] for _ in range(512)]
        self.total_requests = 0
        self.total_misses = 0
        self.roi_requests = 0
        self.roi_misses = 0

    def query(self, pc, active):
        line = pc >> 5
        ways = self.sets[line & 511]
        miss = line not in ways
        if miss:
            if len(ways) == 2:
                ways.pop(0)
        else:
            ways.remove(line)
        ways.append(line)
        self.total_requests += 1
        self.total_misses += miss
        self.roi_requests += active
        self.roi_misses += active and miss
        return self.recovery if miss else 0

    def invalidate(self):
        self.sets = [[] for _ in range(512)]


OPTIONS = [('baseline', 0, False), ('miss+1', 1, False),
           ('miss+2', 2, False), ('registered-margin', 0, True)]


def main():
    output = Path('build/fe-t2/frontend-model.jsonl')
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('w') as stream:
        for workload in ('coremark', 'vision', 'render'):
            program, symbols, trace = program_and_trace(Path('build/v017/input') / workload)
            for name, recovery, margin in OPTIONS:
                probe = IcacheProbe(recovery)
                result = simulate(program, trace, symbols['start_time'], symbols['stop_time'],
                                  'V3s', btb_entries=128, gshare_entries=4096, ras_entries=4,
                                  gshare_pc_shift=2, e_penalty=4, d_penalty=3, mul_latency=4,
                                  registered_control=True, early_address='v017',
                                  direction_predictor='tournament', second_level=True,
                                  frontend_probe=probe, frontend_registered_margin=margin)
                row = dict(workload=workload, option=name, cycles=result['cycles'],
                           roi_requests=probe.roi_requests, roi_misses=probe.roi_misses,
                           total_requests=probe.total_requests, total_misses=probe.total_misses)
                line = json.dumps(row)
                stream.write(line + '\n')
                stream.flush()
                print(line, flush=True)


if __name__ == '__main__':
    main()
