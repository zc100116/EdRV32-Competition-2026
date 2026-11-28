#!/usr/bin/env python3
# File: run_v2_round4.py; Spec: C2-I4 five independent studies; Clock: host.
# Replay both round-three reference points and combinations on actual traces.
# One workload per process; generated results stay in build/.
"""Source edrv32 env; python3 tools/cpu/eval/run_v2_round4.py coremark."""
import argparse
import json
from pathlib import Path

from ooo_model import memory_trace
from pipe_model import program_and_trace, simulate
from run_frontend_t2_eval import IcacheProbe
from run_v2_round2 import CONFIGS as SECOND, divider_cycles
from run_v2_round3 import CONFIGS as THIRD
from v2_round4_structures import LoadMerge, RamTage


BASES = {'default': SECOND['default2-early-div'],
         'full': THIRD['full2-no-late/combo-control'],
         'small': SECOND['small2-early-div']}
EXPERIMENTS = {'base': {}, 'tournament4096': dict(direction_predictor='tournament',
                                                second_level=True),
               'bank-fetch': dict(unaligned_fetch=True), 'fetch128': dict(fetch_bytes=16),
               'rf-async': {}, 'rf-sync': dict(decode_split=True), 'zba': {}}
for count, entries in ((3, 128), (3, 256), (3, 512), (4, 256), (4, 512),
                       (5, 256), (5, 512), (5, 1024)):
    EXPERIMENTS[f'tage{count}-{entries}'] = dict(tage=(count, entries))
for width in (8, 16, 32):
    EXPERIMENTS[f'load{width * 8}'] = dict(read_bytes=width)
    EXPERIMENTS[f'load{width * 8}-early'] = dict(read_bytes=width, merge_early=True)
for count, entries in ((3, 256), (4, 512), (5, 1024)):
    EXPERIMENTS[f'combo{count}'] = dict(tage=(count, entries), unaligned_fetch=True,
                                        rf='ff')
    EXPERIMENTS[f'combo{count}-load'] = dict(EXPERIMENTS[f'combo{count}'], read_bytes=32)
    EXPERIMENTS[f'combo{count}-zba'] = dict(EXPERIMENTS[f'combo{count}'], zba=True)
EXPERIMENTS['combo4-sync'] = dict(EXPERIMENTS['combo4'], decode_split=True, rf='sync')
EXPERIMENTS['combo3-sync'] = dict(EXPERIMENTS['combo3'], decode_split=True, rf='sync')
EXPERIMENTS['combo5-sync'] = dict(EXPERIMENTS['combo5'], decode_split=True, rf='sync')
EXPERIMENTS['combo4-zba-sync'] = dict(EXPERIMENTS['combo4-zba'], decode_split=True, rf='sync')
EXPERIMENTS['combo4-load-early'] = dict(EXPERIMENTS['combo4'], read_bytes=32, merge_early=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('workload', choices=('coremark', 'vision', 'render'))
    parser.add_argument('--names', nargs='+', choices=EXPERIMENTS, default=list(EXPERIMENTS))
    parser.add_argument('--bases', nargs='+', choices=BASES, default=['default', 'full'])
    parser.add_argument('--input-root', type=Path, default=Path('build/v017/input'))
    parser.add_argument('--zba-root', type=Path, default=Path('build/cpu-v2/isa/zba'))
    parser.add_argument('--output', type=Path)
    parser.add_argument('--completion-entries', type=int, default=4)
    args = parser.parse_args()
    output = args.output or Path('build/cpu-v2-round4') / (args.workload + '.jsonl')
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('w') as stream:
        # Never retain the original and ISA traces simultaneously on this host.
        for isa in (False, True):
            names = [n for n in args.names if (n == 'zba' or
                     EXPERIMENTS[n].get('zba', False)) == isa]
            if not names:
                continue
            directory = (args.zba_root if isa else args.input_root) / args.workload
            program, symbols, trace = program_and_trace(directory)
            addresses = memory_trace(directory, program, trace)
            divs = {mode: divider_cycles(directory, program, trace, mode, complete_schedule=True)
                    for mode in ('early-div', 'radix4-early')}
            instructions = trace.index(symbols['stop_time']) - trace.index(symbols['start_time'])
            for base in args.bases:
                for name in names:
                    changes = dict(EXPERIMENTS[name])
                    tage = changes.pop('tage', None)
                    read_bytes = changes.pop('read_bytes', None)
                    merge_early = changes.pop('merge_early', False)
                    changes.pop('rf', None)
                    changes.pop('zba', None)
                    options = dict(BASES[base], **changes)
                    if tage:
                        options.update(direction_predictor=RamTage(*tage), second_level=True)
                    merge = LoadMerge(addresses, read_bytes, merge_early) if read_bytes else None
                    options.update(division_cycles=divs['radix4-early' if base == 'full'
                                                       else 'early-div'], load_merge=merge)
                    result = simulate(program, trace, symbols['start_time'], symbols['stop_time'],
                                      'V3s', **options, frontend_probe=IcacheProbe(1),
                                      frontend_registered_margin=True,
                                      completion_entries=args.completion_entries,
                                      completion_addresses=addresses)
                    result.update(instructions=instructions, ipc=instructions / result['cycles'])
                    if merge:
                        result['merge'] = dict(candidates=merge.candidates, merged=merge.merged,
                                               replays=merge.replays, coverage=merge.coverage,
                                               early_merged=merge.early_merged)
                    stream.write(json.dumps(dict(workload=args.workload, base=base, name=name,
                                                 **result)) + '\n')
                    stream.flush()
                    print(args.workload, base, name, result['cycles'], flush=True)
            del program, symbols, trace, addresses, divs


if __name__ == '__main__':
    main()
