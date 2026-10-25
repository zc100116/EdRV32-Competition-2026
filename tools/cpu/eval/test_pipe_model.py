#!/usr/bin/env python3
# File: test_pipe_model.py; Spec: cpu-spec 2.3, 4.2-4.4; Clock: host.
# Check pipeline latencies, exchange dependencies and prediction timing on directed streams.
"""Run with python3 tools/cpu/eval/test_pipe_model.py."""
from dataclasses import replace
import unittest

from analyze import Instruction
from pipe_model import Predictor, Record, SLOT_CAUSES, simulate


def instruction(pc, kind='alu', rd=0, sources=(), size=4, target=0):
    return Instruction(pc, 0x13, size, kind, rd, sources, target, False, False)


def run(instructions, variant='V0', **options):
    end = instructions[-1].pc + instructions[-1].size
    program = {i.pc: i for i in instructions}
    program.update({pc: instruction(pc) for pc in range(end, end + 64, 4)})
    program[end] = instruction(end, 'serial')
    return simulate(program, [i.pc for i in instructions] + [end],
                    instructions[0].pc, end, variant, **options)


class Pipeline(unittest.TestCase):
    def test_restricted_branch_lane(self):
        for older in ('branch', 'jal'):
            for younger in ('branch', 'jal'):
                with self.subTest(older=older, younger=younger):
                    program = {pc: instruction(pc) for pc in range(0, 128, 4)}
                    program[32] = instruction(32, older, target=36)
                    program[36] = instruction(36, younger, target=40)
                    program[40] = instruction(40, 'serial')
                    trace = list(range(0, 44, 4))
                    # Remove fetch/redirect availability so only the two-control rule differs.
                    options = dict(perfect_frontend=True, perfect_prediction=True)
                    unrestricted = simulate(program, trace, 0, 40, 'V2', **options)
                    result = simulate(program, trace, 0, 40, 'V2s', **options)
                    self.assertEqual(unrestricted['hpm1'], 5)
                    self.assertEqual(result['hpm1'], 4)
                    self.assertEqual(result['hpm7'], 2)
                    self.assertEqual(result['hpm4'], 2)

    def test_latency_parameters(self):
        for kind, parameter, values in (('load', 'load_latency', (1, 2, 3)),
                                        ('mul', 'mul_latency', (1, 2, 3, 4))):
            for latency in values:
                result = run([instruction(0, kind, rd=10), instruction(4, sources=(10,))],
                             **{parameter: latency})
                self.assertEqual(result['cycles'], latency + 1)

    def test_redirect_parameters(self):
        for kind, parameter, values in (('branch', 'e_penalty', (2, 3, 4)),
                                        ('jal', 'd_penalty', (1, 2, 3))):
            program = {pc: instruction(pc) for pc in range(0, 128, 4)}
            program[0] = instruction(0, kind, target=16)
            program[20] = instruction(20, 'serial')
            for penalty in values:
                result = simulate(program, [0, 16, 20], 0, 20, **{parameter: penalty})
                self.assertEqual(result['cycles'], penalty + 2)

    def test_idealized_limits(self):
        dependent = [instruction(0, rd=10), instruction(4, sources=(10,))]
        self.assertEqual(run(dependent, relax_raw=True)['cycles'], 1)
        mixed = [instruction(0), instruction(4, 'load')]
        self.assertEqual(run(mixed, all_slot1_types=True)['cycles'], 1)
        program = {pc: instruction(pc) for pc in range(0, 128, 4)}
        program[0] = instruction(0, 'branch', target=16)
        program[20] = instruction(20, 'serial')
        result = simulate(program, [0, 16, 20], 0, 20, perfect_prediction=True)
        self.assertEqual(result['hpm16'], 0)
        self.assertEqual(result['instructions'], 2)
        self.assertLessEqual(result['cycles'], 2)
        result = simulate(program, [0, 16, 20], 0, 20, perfect_frontend=True)
        self.assertEqual(result['instructions'], 2)
        self.assertEqual(result['cycles'], 5)

    def test_mutually_exclusive_slots_and_squash(self):
        program = {pc: instruction(pc) for pc in range(0, 160, 4)}
        program[32] = instruction(32, 'branch', target=64)
        program[68] = instruction(68, 'serial')
        trace = list(range(0, 36, 4)) + [64, 68]
        result = simulate(program, trace, 0, 68)
        self.assertEqual(result['slots_wrong_path'], 1)
        self.assertGreater(result['slots_redirect_e'], 0)
        self.assertEqual(sum(result['slots_' + key] for key in SLOT_CAUSES),
                         2 * result['cycles'])

    def test_result_latency(self):
        for kind, expected in (('alu', 0), ('load', 1), ('mul', 2), ('csr', 1)):
            with self.subTest(kind=kind):
                stream = [instruction(0, kind, rd=10), instruction(4, sources=(10,))]
                result = run(stream)
                self.assertEqual(result['instructions'], 2)
                self.assertEqual(result['cycles'], 2 + expected)

    def test_exchange_and_raw(self):
        stream = [instruction(0, rd=10), instruction(4, 'load', rd=11, sources=(12,))]
        self.assertEqual(run(stream)['hpm1'], 0)
        self.assertEqual(run(stream, 'V1')['hpm1'], 1)
        stream[1] = replace(stream[1], sources=(10,))
        self.assertEqual(run(stream, 'V1')['hpm1'], 0)
        stream[1] = replace(stream[1], rd=10, sources=(12,))
        stream.append(instruction(8, sources=(10,)))
        result = run(stream, 'V1')
        self.assertEqual(result['hpm1'], 1)
        self.assertEqual(result['cycles'], 3)

    def test_branch_lane_and_redirect(self):
        stream = [instruction(0), instruction(4, 'branch', target=8), instruction(8, 'load')]
        self.assertGreater(run(stream, 'V2')['hpm1'], run(stream)['hpm1'])
        # Cold taken branch: three lost cycles beyond its own execution cycle.
        stream = [instruction(0, 'branch', target=16), instruction(16)]
        program = {pc: instruction(pc) for pc in range(0, 80, 4)}
        program[0] = stream[0]
        program[20] = instruction(20, 'serial')
        result = simulate(program, [0, 16, 20], 0, 20)
        self.assertEqual(result['cycles'], 5)

    def test_saved_gshare_index(self):
        predictor = Predictor(32, 512, 8)
        branch = instruction(0, 'branch', target=0)
        record = Record(branch, False, False, 0, 0, (0, 0, 0), next_pc=0)
        predictor.history = 7
        predictor.update(record)
        self.assertEqual(predictor.pht[0], 2)
        self.assertEqual(predictor.pht[7], 1)

    def test_jal_decode_redirect_penalty(self):
        program = {pc: instruction(pc) for pc in range(0, 80, 4)}
        program[0] = instruction(0, 'jal', target=16)
        program[20] = instruction(20, 'serial')
        result = simulate(program, [0, 16, 20], 0, 20)
        self.assertEqual(result['cycles'], 4)
        program[0] = instruction(0)
        program[4] = instruction(4, 'jal', target=16)
        for variant in ('V1', 'V2', 'V3'):
            result = simulate(program, [0, 4, 16, 20], 0, 20, variant)
            self.assertEqual(result['instructions'], 3)
            self.assertEqual(result['cycles'], 4)

    def test_hpm_raw_priority_and_load_use(self):
        stream = [instruction(pc) for pc in range(0, 32, 4)]
        stream += [instruction(32, rd=10), instruction(36, 'load', rd=11, sources=(10,)),
                   instruction(40, sources=(11,)), instruction(44, 'serial')]
        result = run(stream)
        self.assertGreaterEqual(result['hpm5'], 1)
        self.assertEqual(result['hpm9'], 1)

    def test_compressed_cross_group(self):
        stream = [instruction(0, size=2), instruction(2), instruction(6), instruction(10)]
        self.assertEqual(run(stream)['instructions'], 4)

    def test_wide_fetch_independent_half_group_predictions(self):
        program = {pc: instruction(pc) for pc in range(0, 128, 4)}
        program[0] = instruction(0, 'branch', target=16)
        program[8] = instruction(8, 'branch', target=0)
        program[12] = instruction(12, 'serial')
        trace = [0, 4, 8] * 40 + [12]
        narrow_btb = simulate(program, trace, 0, 12, 'V4a')
        split_btb = simulate(program, trace, 0, 12, 'V4b')
        self.assertEqual(split_btb['instructions'], 120)
        self.assertEqual(split_btb['hpm4'], 80)
        self.assertLess(split_btb['hpm16'], narrow_btb['hpm16'])


if __name__ == '__main__':
    unittest.main()
