#!/usr/bin/env python3
# File: run_tournament_eval.py; Spec: cpu-spec v0.18 4.4; Clock: host.
# Replay the CoreMark S2 configuration with tournament, without LCB.
# Input uses the existing v0.17 ELF and architectural trace format.
import argparse
import json
from pathlib import Path

from pipe_model import program_and_trace, simulate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    args = parser.parse_args()
    program, symbols, trace = program_and_trace(args.input)
    result = simulate(program, trace, symbols['start_time'], symbols['stop_time'],
                      'V3s', btb_entries=128, gshare_entries=4096, ras_entries=4,
                      gshare_pc_shift=2, e_penalty=4, d_penalty=3, mul_latency=4,
                      registered_control=True, early_address='v017',
                      direction_predictor='tournament', second_level=True)
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
