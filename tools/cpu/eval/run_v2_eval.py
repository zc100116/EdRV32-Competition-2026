#!/usr/bin/env python3
# File: run_v2_eval.py; Spec: C2-I architecture study, cpu-spec 2.3/4/7; Clock: host.
# Replay B0 and five-stage candidates sequentially; report exclusive lost-slot CPI.
# Timing and area are explicit planning estimates, never PDS measurements.
"""Source edrv32 env; inputs: build/v017/input; outputs: build/cpu-v2/*.jsonl."""
import argparse
import json
from pathlib import Path

from ooo_model import memory_trace
from pipe_model import SLOT_CAUSES, program_and_trace, simulate
from run_frontend_t2_eval import IcacheProbe
from run_pipeline_cut_eval import BASE, MemoryProbe


V5 = dict(btb_entries=128, gshare_entries=4096, ras_entries=4, gshare_pc_shift=2,
          e_penalty=2, d_penalty=1, load_latency=2, mul_latency=4)
CONFIGS = {
    'B0': BASE,
    'B0-no-ic-recovery': dict(BASE, icache_recovery=0),
    'V5': V5,
    'V5-redirect3': dict(V5, e_penalty=3, d_penalty=2),
    'V5-dual-lsu': dict(V5, dual_lsu=True),
    'V5-cascade': dict(V5, serial_alu='simple'),
    'V5-fuse-lui': dict(V5, fusion=('lui-addi',)),
    'V5-fuse-call': dict(V5, fusion=('auipc-jalr',)),
    'V5-fuse-compare': dict(V5, fusion=('compare-branch',)),
    'V5-tournament': dict(V5, direction_predictor='tournament', second_level=True),
    'V5-gshare1024': dict(V5, gshare_entries=1024),
    'V5-btb64': dict(V5, btb_entries=64),
    'V5-btb256': dict(V5, btb_entries=256),
    'V5-ras8': dict(V5, ras_entries=8),
    'V5-default': dict(V5, btb_entries=64, gshare_entries=1024),
    'V5-full': dict(V5, direction_predictor='tournament', second_level=True,
                    ras_entries=8, fusion=('lui-addi', 'auipc-jalr', 'compare-branch')),
    'V5-ip-full': dict(V5, direction_predictor='tournament', second_level=True, ras_entries=8),
    'V5-1': dict(V5, issue_width=1, btb_entries=64, gshare_entries=1024),
    'V5-drm-fetch': dict(V5, e_penalty=3, d_penalty=2, taken_bubble=1),
}


def cpi_stack(result, icache_misses):
    """Half an exclusive lost issue slot is one dual-issue cycle equivalent.

    The IcacheProbe adds exactly one request recovery cycle per miss; its cost
    overlaps other pipeline stalls.  Therefore leave it in frontend and report
    miss counts separately, rather than subtracting non-exclusive HPM counts.
    """
    insns = result['instructions']
    categories = {
        'load_use': ('load_use',),
        'mispredict': ('wrong_path', 'redirect_e', 'redirect_m', 'redirect_d'),
        'intra_pair_raw': ('pair_raw',),
        'pairing': ('pair_structural', 'pair_type', 'pair_one'),
        'multiply_divide_csr': ('other_result', 'csr_serial'),
        'frontend_including_icache': ('frontend',),
        'training': ('training_structural',),
    }
    stack = {key: sum(result['slots_' + cause] for cause in causes) / (2 * insns)
             for key, causes in categories.items()}
    stack['effective'] = result['slots_effective'] / (2 * insns)
    stack['boundary'] = result['cycles'] / insns - sum(stack.values())
    return dict(cpi=stack, icache_misses=icache_misses,
                slot_sum=sum(result['slots_' + cause] for cause in SLOT_CAUSES))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input-root', type=Path, default=Path('build/v017/input'))
    parser.add_argument('--workload', choices=('coremark', 'vision', 'render'))
    parser.add_argument('--names', nargs='+', choices=CONFIGS, default=list(CONFIGS))
    parser.add_argument('--output', type=Path, default=Path('build/cpu-v2/results.jsonl'))
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('w') as output:
        for workload in ((args.workload,) if args.workload else ('coremark', 'vision', 'render')):
            directory = args.input_root / workload
            program, symbols, trace = program_and_trace(directory)
            addresses = memory_trace(directory, program, trace)
            for name in args.names:
                options = dict(CONFIGS[name])
                icache = IcacheProbe(options.pop('icache_recovery', 1))
                memory = MemoryProbe(addresses)
                result = simulate(program, trace, symbols['start_time'], symbols['stop_time'],
                                  'V3s', **options, frontend_probe=icache,
                                  frontend_registered_margin=True, memory_probe=memory)
                row = dict(workload=workload, name=name, options=CONFIGS[name], **result,
                           dc_misses=memory.misses, device_accesses=memory.devices,
                           **cpi_stack(result, icache.roi_misses))
                output.write(json.dumps(row) + '\n')
                output.flush()
                print(workload, name, result['instructions'], result['cycles'], flush=True)


if __name__ == '__main__':
    main()
