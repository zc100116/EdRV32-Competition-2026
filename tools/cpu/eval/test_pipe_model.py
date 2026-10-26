#!/usr/bin/env python3
# File: test_pipe_model.py; Spec: cpu-spec 2.3, 4.2-4.4; Clock: host.
# Check pipeline latencies, exchange dependencies and prediction timing on directed streams.
"""Run with python3 tools/cpu/eval/test_pipe_model.py."""
from dataclasses import replace
import unittest

from analyze import Instruction
from pipe_model import INORDER_VARIANTS, Predictor, Record, SLOT_CAUSES, simulate


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
    def test_b1_exchange_capability_and_single_control(self):
        for older in ('alu', 'branch', 'jal'):
            for younger in ('load', 'store', 'mul', 'div', 'jalr'):
                stream = [instruction(0, older, target=4),
                          instruction(4, younger, target=8)]
                options = dict(perfect_frontend=True, perfect_prediction=True)
                result = run(stream, 'B1', **options)
                expected = 0 if older in {'branch', 'jal'} and younger == 'jalr' else 1
                self.assertEqual(result['hpm1'], expected, (older, younger))
        stream = [instruction(0, rd=10), instruction(4, 'load', sources=(10,))]
        self.assertEqual(run(stream, 'B1')['hpm1'], 0)
        stream[1] = instruction(4, 'load', rd=10)
        stream.append(instruction(8, sources=(10,)))
        self.assertEqual(run(stream, 'B1')['cycles'], 2)
        program = {pc: instruction(pc) for pc in range(0, 128, 4)}
        program[0] = instruction(0, 'branch', target=32)
        program[4] = instruction(4, 'div')
        program[36] = instruction(36, 'serial')
        result = simulate(program, [0, 32, 36], 0, 36, 'B1')
        self.assertEqual(result['cycles'], 5)
        self.assertEqual(result['hpm10'], 0)

    def test_b2_unique_lsu_and_load_only(self):
        options = dict(perfect_frontend=True, perfect_prediction=True)
        for variant in ('B2-load', 'B2'):
            for older in ('alu', 'branch', 'mul', 'load', 'store'):
                for younger in ('load', 'store'):
                    stream = [instruction(0, older, target=4), instruction(4, younger)]
                    result = run(stream, variant, **options)
                    expected = older not in {'load', 'store'} and (
                        younger == 'load' or variant == 'B2')
                    self.assertEqual(result['hpm1'], int(expected),
                                     (variant, older, younger))
        for sources in ((10, 2), (2, 10)):
            stream = [instruction(0, rd=10), instruction(4, 'store', sources=sources)]
            self.assertEqual(run(stream, 'B2')['hpm1'], 0)
        stream = [instruction(pc) for pc in range(0, 32, 4)]
        stream += [instruction(32, 'store'), instruction(36, 'load')]
        self.assertGreater(run(stream, 'B2', **options)['slots_pair_structural'], 0)

    def test_b3_unique_pipelined_multiplier(self):
        options = dict(perfect_frontend=True, perfect_prediction=True)
        for older in ('alu', 'load', 'store', 'branch', 'mul'):
            stream = [instruction(0, older, target=4), instruction(4, 'mul')]
            result = run(stream, 'B3', **options)
            self.assertEqual(result['hpm1'], int(older != 'mul'))
        stream = [instruction(0, rd=10), instruction(4, 'mul', sources=(10,))]
        self.assertEqual(run(stream, 'B3')['hpm1'], 0)
        stream = [instruction(0, 'mul', rd=10), instruction(4, 'mul', rd=11),
                  instruction(8, 'load', sources=(11,))]
        result = run(stream, 'B3', **options)
        self.assertEqual(result['cycles'], 5)

    def test_b5_multiplier_latency_two(self):
        stream = [instruction(0, 'mul', rd=10), instruction(4, sources=(10,))]
        self.assertEqual(run(stream, 'B0')['cycles'], 3)
        self.assertEqual(run(stream, 'B5')['cycles'], 2)
        self.assertEqual(run(stream, 'B5')['late_alu'], 1)
        stream[1] = instruction(4, 'load', sources=(10,))
        self.assertEqual(run(stream, 'B5')['cycles'], 3)

    def test_b4_two_controls_and_deferred_younger(self):
        options = dict(perfect_frontend=True, perfect_prediction=True)
        stream = [instruction(0, 'branch', target=4), instruction(4, 'branch', target=8)]
        self.assertEqual(run(stream, 'B0', **options)['hpm1'], 0)
        self.assertEqual(run(stream, 'B4', **options)['hpm1'], 1)
        program = {pc: instruction(pc) for pc in range(0, 192, 4)}
        program[32] = instruction(32, 'load', rd=10)
        program[36] = instruction(36, 'branch', sources=(10,), target=96)
        program[40] = instruction(40, 'branch', target=128)
        program[44] = instruction(44, 'serial')
        result = simulate(program, list(range(0, 48, 4)), 0, 44, 'B4')
        self.assertEqual(result['late_branch'], 1)
        self.assertEqual(result['training_conflicts'], 1)
        self.assertEqual(result['training_peak'], 1)
        self.assertEqual(result['hpm4'], 2)
        program[100] = instruction(100, 'serial')
        result = simulate(program, list(range(0, 40, 4)) + [96, 100], 0, 100, 'B4')
        self.assertEqual(result['hpm4'], 1)
        self.assertEqual(result['training_conflicts'], 0)
        self.assertGreater(result['slots_wrong_path'], 0)

    def test_single_training_buffer_backpressure(self):
        INORDER_VARIANTS['B4-1buf'] = INORDER_VARIANTS['B4'] | {'training_capacity': 1}
        self.addCleanup(INORDER_VARIANTS.pop, 'B4-1buf')
        options = dict(perfect_frontend=True, perfect_prediction=True)
        stream = [instruction(pc, 'branch', target=pc + 4) for pc in range(0, 80, 4)]
        unlimited = run(stream, 'B4', **options)
        limited = run(stream, 'B4-1buf', **options)
        self.assertEqual(unlimited['training_peak'], 10)
        self.assertEqual(limited['training_peak'], 1)
        self.assertEqual(limited['training_over_one'], 0)
        self.assertEqual(limited['cycles'], 19)
        self.assertEqual(limited['hpm4'], 20)
        self.assertEqual(limited['instructions'], 20)
        self.assertGreater(limited['slots_training_structural'], 0)
        self.assertEqual(sum(limited['slots_' + key] for key in SLOT_CAUSES),
                         2 * limited['cycles'])
        # A prior pair occupies the buffer when two M controls arrive together.
        stream = [instruction(pc) for pc in range(0, 32, 4)]
        for pc in range(32, 96, 16):
            stream += [instruction(pc, 'load', rd=10),
                       instruction(pc + 4, 'branch', sources=(10,), target=pc + 8),
                       instruction(pc + 8, 'branch', target=pc + 12),
                       instruction(pc + 12, 'branch', target=pc + 16)]
        limited = run(stream, 'B4-1buf', **options)
        self.assertEqual(limited['cycles'], 20)
        self.assertEqual(limited['slots_training_structural'], 8)
        self.assertEqual(limited['training_peak'], 1)
        self.assertEqual(limited['hpm4'], 12)
        self.assertEqual(limited['instructions'], 24)
        self.assertEqual(sum(limited['slots_' + key] for key in SLOT_CAUSES),
                         2 * limited['cycles'])

    def test_b6_predictor_capacity_and_ras_eight(self):
        self.assertEqual(INORDER_VARIANTS['B6']['predictor'], (128, 2048, 8))
        self.assertEqual(INORDER_VARIANTS['B6-ras']['predictor'], (64, 1024, 8))
        predictor = Predictor(128, 2048, 8, 8)
        call = replace(instruction(0, 'jal'), push=True)
        ret = replace(instruction(64, 'jalr'), pop=True)
        for pc in range(0, 24, 4):
            predictor.action(replace(call, pc=pc))
        predictor.btb[8] = (ret, 100)
        self.assertEqual(predictor.count, 6)
        self.assertEqual(predictor.query(64)[2], 24)
        checkpoint = predictor.snapshot()
        predictor.action(ret)
        predictor.restore(Record(ret, True, True, 24, 0, checkpoint))
        self.assertEqual(predictor.count, 5)
        self.assertEqual(predictor.query(64)[2], 20)
        a, b = instruction(0, 'branch', target=16), instruction(512, 'branch', target=528)
        for inst in (a, b):
            predictor.update(Record(inst, False, False, 0, 1536, predictor.snapshot(),
                                    next_pc=inst.target))
        self.assertIsNotNone(predictor.query(0)[0])
        self.assertIsNotNone(predictor.query(512)[0])
        self.assertEqual(predictor.pht[1536], 3)
        self.assertEqual(predictor.pht[512], 1)

    def test_b7_late_jalr_return_and_link_latency(self):
        program = {pc: instruction(pc) for pc in range(0, 160, 4)}
        program[0] = instruction(0, 'load', rd=10)
        program[4] = replace(instruction(4, 'jalr', rd=1, sources=(10,)), pop=True)
        program[36] = instruction(36, 'serial')
        trace = [0, 4, 32, 36]
        baseline = simulate(program, trace, 4, 36, 'B0')
        result = simulate(program, trace, 4, 36, 'B7')
        self.assertEqual(baseline['cycles'], 5)
        self.assertEqual(result['cycles'], 6)
        self.assertEqual(result['late_branch'], 1)
        self.assertGreater(result['slots_redirect_m'], 0)
        self.assertEqual(sum(result['slots_' + key] for key in SLOT_CAUSES),
                         2 * result['cycles'])
        stream = [instruction(0, rd=10), instruction(4, 'jalr', rd=1, sources=(10,)),
                  instruction(8, sources=(1,))]
        result = run(stream, 'B7', perfect_frontend=True, perfect_prediction=True)
        self.assertEqual(result['hpm1'], 1)  # JALR pairs with its younger late ALU.
        self.assertEqual(result['cycles'], 2)
        self.assertEqual(result['late_branch'], 0)
        self.assertEqual(run(stream[:2], 'B7')['hpm1'], 0)  # JALR stays lane 0 only.

    def test_b8_composition_and_positive_selection(self):
        from run_inorder_max import select
        from run_pipeline_analysis import CONFIGS
        cycles = {'B0': 100, 'B1': 90, 'B2-load': 95, 'B2': 85, 'B3': 110,
                  'B4': 99, 'B5': 50, 'B6': 102, 'B6-ras': 100, 'B7': 100}
        rows = [dict(rvc=rvc, option=option, variant=variant, cycles=cycles[variant])
                for rvc, option in CONFIGS for variant in cycles]
        changes, components = select(rows)
        self.assertEqual(components, 'B1+B2+B4')
        self.assertEqual(changes, {'swap': True, 'lsu': ('load', 'store'),
                                   'dual_control': True})
        # Exercise simultaneous routing/late-control features and unique resources.
        changes = {}
        for variant in ('B1', 'B2', 'B3', 'B4', 'B6', 'B7'):
            changes.update(INORDER_VARIANTS[variant])
        INORDER_VARIANTS['B8-directed'] = changes
        self.addCleanup(INORDER_VARIANTS.pop, 'B8-directed')
        options = dict(perfect_frontend=True, perfect_prediction=True)
        for older, younger, pairs in (('load', 'mul', 1), ('mul', 'load', 1),
                                       ('load', 'store', 0), ('mul', 'mul', 0),
                                       ('branch', 'branch', 1)):
            stream = [instruction(0, older, target=4), instruction(4, younger, target=8)]
            self.assertEqual(run(stream, 'B8-directed', **options)['hpm1'], pairs)
        stream = [instruction(0, rd=10), instruction(4, 'jalr', rd=1, sources=(10,)),
                  instruction(8, sources=(1,))]
        result = run(stream, 'B8-directed', **options)
        self.assertEqual(result['instructions'], 3)
        self.assertEqual(result['cycles'], 2)
        self.assertEqual(result['late_branch'], 1)

    def test_late_same_group_alu(self):
        stream = [instruction(0, rd=10), instruction(4, rd=11, sources=(10,))]
        for variant in ('L1', 'L2'):
            result = run(stream, variant)
            self.assertEqual(result['cycles'], 1)
            self.assertEqual(result['hpm1'], 1)
            self.assertEqual(result['late_alu'], 1)

    def test_load_to_late_alu_and_chains(self):
        stream = [instruction(0, 'load', rd=10), instruction(4, rd=11, sources=(10,))]
        result = run(stream, 'L2')
        self.assertEqual(result['cycles'], 2)
        self.assertEqual(result['hpm1'], 0)
        self.assertEqual(result['late_alu'], 1)
        self.assertEqual(result['slots_load_use'], 0)
        self.assertEqual(run(stream, 'L1')['cycles'], 3)
        # A previous-group late ALU can feed another late ALU, but not in the same M.
        stream.append(instruction(8, rd=12, sources=(11,)))
        result = run(stream, 'L2')
        self.assertEqual(result['cycles'], 3)
        self.assertEqual(result['hpm1'], 0)
        self.assertEqual(result['late_alu'], 2)
        stream[2] = instruction(8, 'load', rd=12, sources=(11,))
        self.assertEqual(run(stream, 'L2')['cycles'], 4)

    def test_late_multiply_and_waw(self):
        stream = [instruction(0, 'mul', rd=10), instruction(4, sources=(10,))]
        self.assertEqual(run(stream, 'L2')['cycles'], 3)
        self.assertEqual(run(stream, 'L2')['late_alu'], 1)
        stream = [instruction(0, 'load', rd=10), instruction(4, rd=11, sources=(10,)),
                  instruction(8, rd=11, sources=(12,)),
                  instruction(12, 'load', rd=13, sources=(11,))]
        result = run(stream, 'L2')
        self.assertEqual(result['cycles'], 3)
        self.assertEqual(result['late_alu'], 1)

    def test_late_store_data_only(self):
        for sources, cycles, count in (((10, 2), 2, 1), ((2, 10), 3, 0), ((10, 10), 3, 0)):
            stream = [instruction(0, 'load', rd=10), instruction(4, 'store', sources=sources)]
            result = run(stream, 'L2s')
            self.assertEqual(result['cycles'], cycles)
            self.assertEqual(result['late_store_data'], count)
        program = {pc: instruction(pc) for pc in range(0, 128, 4)}
        program[32] = instruction(32, rd=10)
        program[36] = instruction(36, 'store', sources=(10, 2))
        program[40] = instruction(40, 'serial')
        result = simulate(program, list(range(0, 44, 4)), 0, 40, 'L2s')
        self.assertGreaterEqual(result['hpm5'], 1)
        self.assertEqual(result['late_store_data'], 0)

    def test_late_branch_redirect_penalty(self):
        program = {pc: instruction(pc) for pc in range(0, 128, 4)}
        program[0] = instruction(0, 'load', rd=10)
        program[4] = instruction(4, 'branch', sources=(10,), target=32)
        program[36] = instruction(36, 'serial')
        for variant, cycles in (('L2', 5), ('L2b', 6)):
            result = simulate(program, [0, 4, 32, 36], 4, 36, variant)
            self.assertEqual(result['cycles'], cycles)
            self.assertEqual(result['late_branch'], int(variant == 'L2b'))

    def test_late_branch_training_and_flush_priority(self):
        program = {pc: instruction(pc) for pc in range(0, 160, 4)}
        program[32] = instruction(32, 'load', rd=10)
        program[36] = instruction(36, 'branch', sources=(10,), target=64)
        program[40] = instruction(40, 'branch', sources=(12,), target=64)
        program[48] = instruction(48, 'serial')
        result = simulate(program, list(range(0, 52, 4)), 0, 48, 'L2b')
        self.assertEqual(result['training_conflicts'], 1)
        self.assertEqual(result['hpm4'], 2)
        self.assertEqual(result['cycles'], 7)
        program[68] = instruction(68, 'serial')
        trace = list(range(0, 40, 4)) + [64, 68]
        result = simulate(program, trace, 0, 68, 'L2b')
        self.assertEqual(result['training_conflicts'], 0)
        self.assertEqual(result['hpm4'], 1)
        self.assertGreater(result['slots_wrong_path'], 0)
        self.assertEqual(sum(result['slots_' + key] for key in SLOT_CAUSES),
                         2 * result['cycles'])

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
