#!/usr/bin/env python3
# File: test_pipe_model.py; Spec: cpu-spec 2.3, 4.2-4.4, 4.10-4.11; Clock: host.
# Check pipeline latencies, exchange dependencies and prediction timing on directed streams.
"""Run with python3 tools/cpu/eval/test_pipe_model.py."""
from dataclasses import replace
import unittest

from ipc_structures import Direction, FUSIONS, Macro
from analyze import Instruction
from pipe_model import (INORDER_VARIANTS, Predictor, Record, SLOT_CAUSES, fill_ib,
                        simulate, early_address_allowed, lcb_allowed)
from collections import deque


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
    def test_two_cycle_alu_and_shift_results(self):
        producer = instruction(0, rd=1, sources=(2,))
        consumer = instruction(4, rd=3, sources=(1,))
        options = dict(perfect_frontend=True, perfect_prediction=True)
        base = run([producer, consumer], **options)['cycles']
        self.assertEqual(run([producer, consumer], alu_latency=2, **options)['cycles'],
                         base + 1)
        self.assertEqual(run([producer, consumer], shift_latency=2, **options)['cycles'],
                         base)
        shift = replace(producer, bits=0x1013)
        self.assertEqual(run([shift, consumer], shift_latency=2, **options)['cycles'],
                         base + 1)
        independent = replace(consumer, sources=(4,))
        self.assertEqual(run([shift, independent], shift_latency=2, **options)['cycles'],
                         run([shift, independent], **options)['cycles'])

    def test_v017_early_address_exclusion_list(self):
        load = instruction(0, 'load', rd=11, sources=(10,))
        def producer(kind, rd=10, latency=0):
            return Record(instruction(4, kind, rd=rd), False, False, 0, 0, (0, 0, 0),
                          result_latency=latency)
        for kind in ('alu', 'load', 'csr', 'mul', 'div', 'jal', 'jalr'):
            record = producer(kind)
            self.assertFalse(early_address_allowed(load, [record], [], [], [], 4), kind)
            self.assertFalse(early_address_allowed(load, [], [record], [], [], 4), kind)
        for kind in ('load', 'csr', 'mul'):
            self.assertFalse(early_address_allowed(load, [], [], [producer(kind)], [], 4))
        # Even an early load in M is excluded: do not replace the list with readiness.
        self.assertFalse(early_address_allowed(load, [], [], [producer('load', latency=1)],
                                              [], 4))
        self.assertFalse(early_address_allowed(load, [], [], [], [producer('mul')], 4))
        self.assertTrue(early_address_allowed(load, [], [], [], [producer('mul')], 3))
        self.assertTrue(early_address_allowed(load, [], [], [producer('alu')], [], 4))
        self.assertTrue(early_address_allowed(load, [], [], [], [producer('load')], 4))
        # A fused ADD+load has an ALU destination as well as the load destination.
        first = instruction(4, rd=10)
        second = instruction(8, 'load', rd=12, sources=(10,))
        macro = Macro(4, second.bits, 8, 'load', 12, (), 0, False, False,
                      (first, second), 'add-load')
        record = replace(producer('load'), instruction=macro)
        self.assertTrue(early_address_allowed(load, [], [], [record], [], 4))
        self.assertFalse(early_address_allowed(replace(load, sources=(12,)), [], [],
                                              [record], [], 4))
        self.assertTrue(early_address_allowed(load, [], [producer('alu', 12)], [], [], 4))
        self.assertTrue(early_address_allowed(replace(load, sources=(0,)), [], [], [], [], 4))
        stream = [instruction(0, 'load', rd=10, sources=(2,)),
                  instruction(4, sources=(10,))]
        self.assertEqual(run(stream, early_address='v017')['cycles'], 2)
        self.assertEqual(run(stream, early_address='v017')['early_loads'], 1)

    def test_v017_lcb_sources_and_youngest(self):
        branch = instruction(12, 'branch', sources=(10, 11), target=16)
        def producer(kind, rd, latency):
            return Record(instruction(0, kind, rd=rd), False, False, 0, 0, (0, 0, 0),
                          result_latency=latency)
        loads = [producer('load', 10, 2), producer('load', 11, 2)]
        self.assertTrue(lcb_allowed(branch, loads, {10: 1, 11: 1}))
        self.assertTrue(lcb_allowed(branch, loads[:1], {10: 1, 11: 0}))
        self.assertFalse(lcb_allowed(branch, loads[:1], {10: 1, 11: 2}))
        self.assertFalse(lcb_allowed(branch, [producer('mul', 10, 4)], {10: 2}))
        self.assertFalse(lcb_allowed(branch, [producer('load', 10, 1)], {}))
        self.assertFalse(lcb_allowed(branch, [producer('load', 10, 3)], {10: 1}))
        self.assertFalse(lcb_allowed(replace(branch, kind='jalr'), loads, {10: 1}))
        options = dict(perfect_frontend=True, perfect_prediction=True, lcb='v017')
        # Slot one may consume an E load even without static adjacency.
        stream = [instruction(0, 'load', rd=10), instruction(4), instruction(8),
                  instruction(12, 'branch', sources=(10,), target=16)]
        self.assertEqual(run(stream, 'V3s', **options)['lcb_branches'], 1)
        # A slot-zero branch paired with an independent younger ALU must wait.
        stream = [instruction(0, 'load', rd=10), instruction(4),
                  instruction(8, 'branch', sources=(10,), target=12), instruction(12)]
        self.assertEqual(run(stream, 'V3s', **options)['lcb_branches'], 0)
        # A same-group producer cannot use LCB.
        stream = [instruction(0, 'load', rd=10),
                  instruction(4, 'branch', sources=(10,), target=8)]
        self.assertEqual(run(stream, 'V3s', **options)['hpm1'], 0)
        self.assertEqual(run(stream, 'V3s', **options)['lcb_branches'], 1)

    def test_v017_registered_training_visibility(self):
        predictor = Predictor(128, 4096, 8, gshare_pc_shift=2, registered=True,
                              direction='tournament', second_level=True)
        branch = instruction(0, 'branch', target=0)
        record = Record(branch, False, False, 0, 0, (0, 0, 0), next_pc=0)
        _, token = predictor.direction.predict(0, False, 0)
        record.direction_meta = token
        predictor.edge([record])
        self.assertIsNone(predictor.query(0)[0])
        self.assertEqual((predictor.pht[0], predictor.history), (1, 0))
        self.assertEqual(predictor.direction.local_history[0], 0)
        predictor.edge([])
        self.assertIsNotNone(predictor.query(0)[0])
        self.assertEqual((predictor.pht[0], predictor.history), (2, 1))
        self.assertEqual(predictor.direction.local_history[0], 1)
        # A concurrent query sees the state before the training edge.
        self.assertFalse(predictor.query(0)[1])  # history=1 selects untouched counter 1.

    def test_v017_registered_redirect_costs_and_w2(self):
        from run_v017_eval import S1, S3
        for kind, expected in (('branch', 6), ('jal', 5)):
            program = {pc: instruction(pc) for pc in range(0, 128, 4)}
            program[0] = instruction(0, kind, target=32)
            program[36] = instruction(36, 'serial')
            timeline = []
            result = simulate(program, [0, 32, 36], 0, 36, 'V3s', timeline=timeline, **S1)
            self.assertEqual(result['cycles'], expected)
            resolved = next(e[0] for e in timeline if e[1] == 'resolve')
            applied = next(e[0] for e in timeline if e[1] == 'redirect')
            self.assertEqual(applied, resolved + 1)
        program[0] = instruction(0, 'load', rd=10)
        program[4] = instruction(4, 'branch', sources=(10,), target=32)
        program[8] = instruction(8, 'serial')
        timeline = []
        result = simulate(program, [0, 4, 32, 36], 4, 36, 'V3s', timeline=timeline,
                          **dict(S3, early_address=0))
        self.assertEqual(result['lcb_misses'], 1)
        self.assertEqual(result['cycles'], 7)  # branch + five lost cycles + successor.
        resolved = next(e[0] for e in timeline if e[1:2] == ('resolve',) and e[2] == 4)
        applied = next(e[0] for e in timeline if e[1:2] == ('redirect',) and e[2] == 4)
        self.assertEqual(applied, resolved + 1)
        stream = [instruction(0, 'mul', rd=10), instruction(4, sources=(10,))]
        self.assertEqual(run(stream, 'V3s', **S1)['cycles'], 5)
        self.assertEqual(run([instruction(0), instruction(4)], 'V3s', **S1)['cycles'], 1)

    def test_v017_lcb_control_issue_restriction_and_split(self):
        from run_v017_eval import S3
        stream = [instruction(0, 'load', rd=10), instruction(4),
                  instruction(8, 'branch', sources=(10,), target=12), instruction(12)]
        options = dict(S3, early_address=0, perfect_frontend=True, perfect_prediction=True)
        self.assertEqual(run(stream, 'V3s', **options)['lcb_branches'], 0)
        self.assertEqual(run(stream, 'V3s', lcb_split=True, **options)['lcb_branches'], 1)
        warm = [instruction(pc) for pc in range(0, 32, 4)]
        warm += [replace(inst, pc=inst.pc + 32,
                         target=inst.target + 32 if inst.kind == 'branch' else 0)
                 for inst in stream]
        self.assertEqual(run(warm, 'V3s', lcb_split=True, **options)['lcb_branches'], 1)
        for kind in ('branch', 'jal', 'jalr'):
            stream = [instruction(0, 'load', rd=10), instruction(4), instruction(8),
                      instruction(12, 'branch', sources=(10,), target=16),
                      instruction(16, kind, target=20), instruction(20)]
            timeline = []
            result = run(stream, 'V3s', timeline=timeline, **options)
            self.assertEqual(result['lcb_branches'], 1)
            trains = [(t, pc) for t, event, pc, meta in timeline if event == 'train_capture']
            first = next(t for t, pc in trains if pc == 12)
            second = next(t for t, pc in trains if pc == 16)
            self.assertGreater(second, first)
            self.assertEqual(result['training_conflicts'], 0)

    def test_v017_f2_correction_bubble(self):
        from unittest.mock import patch
        from pipe_model import Predictor as BasePredictor
        class FixedPredictor(BasePredictor):
            def __init__(self, *args):
                super().__init__(*args)
                branch = instruction(4, 'branch', target=0)
                self.btb[0] = branch, 0
                self.direction.chooser = [3] * len(self.direction.chooser)
                self.direction.local = [3] * len(self.direction.local)
            def update(self, record):
                pass  # Hold the directed F1=false / F2=true conflict constant.
        program = {pc: instruction(pc) for pc in range(0, 96, 4)}
        program[4] = instruction(4, 'branch', target=0)
        program[12] = instruction(12, 'serial')
        trace = [0, 4] * 10 + [8, 12]
        options = dict(direction_predictor='tournament', registered_control=True,
                       e_penalty=4, d_penalty=3)
        with patch('pipe_model.Predictor', FixedPredictor):
            ideal = simulate(program, trace, 0, 12, 'V3s', **options)
            real = simulate(program, trace, 0, 12, 'V3s', second_level=True, **options)
        self.assertEqual(real['instructions'], 21)
        self.assertGreater(real['f2_corrections'], 0)
        # Nine measured loop intervals each pay one F2-to-F1 correction bubble.
        self.assertEqual(real['cycles'] - ideal['cycles'], 9)
        self.assertEqual(real['hpm16'], ideal['hpm16'])
        class FallthroughPredictor(FixedPredictor):
            def __init__(self, *args):
                super().__init__(*args)
                self.btb[0] = instruction(0, 'branch', target=32), 32
                self.pht = [3] * len(self.pht)
                self.direction.local = [0] * len(self.direction.local)
        program[0] = instruction(0, 'branch', target=32)
        program[4] = instruction(4)
        with patch('pipe_model.Predictor', FallthroughPredictor):
            real = simulate(program, [0, 4, 8, 12], 0, 12, 'V3s', second_level=True,
                            **options)
        self.assertEqual(real['instructions'], 3)
        self.assertEqual(real['hpm16'], 0)  # F2 restores the fall-through group tail.

    def test_v017_registered_system_restart(self):
        from run_v017_eval import S1
        for bits in (0x30200073, 0x10500073, 0x0000100f):
            program = {pc: instruction(pc) for pc in range(0, 96, 4)}
            program[0] = replace(instruction(0, 'serial'), bits=bits)
            program[36] = instruction(36, 'serial')
            timeline = []
            trace = [0, 32, 36] if bits == 0x30200073 else list(range(0, 40, 4))
            result = simulate(program, trace, 0, 36, 'V3s', timeline=timeline, **S1)
            resolve = next(t for t, event, pc, meta in timeline if event == 'resolve')
            redirect = next(t for t, event, pc, meta in timeline if event == 'redirect')
            self.assertEqual(redirect, resolve + 1)
            self.assertEqual(result['instructions'], len(trace) - 1)

    def test_v017_cold_slot_zero_jal_during_active_window(self):
        from run_v017_eval import S1
        program = {pc: instruction(pc) for pc in range(0, 128, 4)}
        program[32] = instruction(32, 'jal', target=64)
        program[68] = instruction(68, 'serial')
        trace = list(range(0, 36, 4)) + [64, 68]
        result = simulate(program, trace, 0, 68, 'V3s', **S1)
        self.assertEqual(result['instructions'], 10)
        self.assertEqual(result['hpm16'], 1)

    def test_v017_dual_lsu_program_order_pairing(self):
        from run_v017_eval import S3
        options = dict(S3, perfect_frontend=True, perfect_prediction=True)
        for older in ('load', 'store'):
            for younger in ('load', 'store'):
                stream = [instruction(0, older, rd=10 if older == 'load' else 0,
                                      sources=(2,)),
                          instruction(4, younger, sources=(3,))]
                self.assertEqual(run(stream, 'V3s', **options)['hpm1'], 0)
                self.assertEqual(run(stream, 'V3s', dual_lsu=True, **options)['hpm1'], 1)
        stream = [instruction(0, 'load', rd=10, sources=(2,)),
                  instruction(4, 'store', sources=(10, 2))]
        self.assertEqual(run(stream, 'V3s', dual_lsu=True, **options)['hpm1'], 0)

    def test_v017_tournament_confidence(self):
        for kind, confident in (('tournament', False), ('tournament-confident', True)):
            predictor = Predictor(128, 4096, 8, direction=kind, second_level=True)
            branch = instruction(0, 'branch', target=32)
            predictor.btb[0] = branch, 32
            predictor.direction.chooser[0] = 2
            predictor.direction.local[0] = 3
            query = predictor.query(0)
            self.assertFalse(query[1])  # F1 remains gshare.
            self.assertEqual(query[3].second, not confident)
            predictor.direction.chooser[0] = 3
            self.assertTrue(predictor.query(0)[3].second)
            predictor.direction.local[0] = 2
            self.assertEqual(predictor.query(0)[3].second, not confident)

    def test_lcb_m_compare_and_registered_redirect(self):
        stream = [instruction(0, 'load', rd=10),
                  instruction(4, 'branch', sources=(10,), target=8), instruction(8)]
        base = run(stream, 'V3s')
        result = run(stream, 'V3s', lcb='same-cycle')
        self.assertEqual(result['cycles'], base['cycles'] - 1)
        self.assertEqual(result['lcb_branches'], 1)
        self.assertEqual(result['lcb_misses'], 0)
        program = {pc: instruction(pc) for pc in range(0, 128, 4)}
        program[0], program[4] = stream[:2]
        program[4] = replace(program[4], target=32)
        program[36] = instruction(36, 'serial')
        same = simulate(program, [0, 4, 32, 36], 0, 36, 'V3s', lcb='same-cycle')
        registered = simulate(program, [0, 4, 32, 36], 0, 36, 'V3s', lcb='registered')
        self.assertEqual(same['lcb_misses'], 1)
        self.assertEqual(registered['cycles'], same['cycles'] + 1)
        # An intervening instruction makes this an ordinary branch.
        stream = [instruction(0, 'load', rd=10), instruction(4),
                  instruction(8, 'branch', sources=(10,), target=12), instruction(12)]
        self.assertEqual(run(stream, 'V3s', lcb='same-cycle')['lcb_branches'], 0)

    def test_all_fusion_templates_and_dual_retirement(self):
        encodings = ((0x13, 0x7013), (0x5013, 0x6033), (0x37, 0x13),
                     (0x1013, 0x33), (0x33, 0x2003), (0x17, 0x67))
        for template, (a, b) in zip(FUSIONS, encodings):
            first = replace(instruction(0, rd=10, sources=(2,)), bits=a)
            second = replace(instruction(4, rd=11, sources=(10, 3)), bits=b)
            if template == 'add-load':
                second = replace(second, kind='load', sources=(10,))
            if template == 'auipc-jalr':
                second = replace(second, kind='jalr', sources=(10,))
            result = run([first, second], 'V3s', fusion=(template,),
                         perfect_frontend=True, perfect_prediction=True)
            self.assertEqual(result['instructions'], 2, template)
            self.assertEqual(result['fused'], 1, template)
            self.assertEqual(result['cycles'], 1, template)
            # A fused unit occupies one slot and can pair with a third instruction.
            third = instruction(8, sources=(4,))
            result = run([first, second, third], 'V3s', fusion=(template,),
                         perfect_frontend=True, perfect_prediction=True)
            self.assertEqual(result['cycles'], 1, template)
            self.assertEqual(result['instructions'], 3, template)
        first = replace(instruction(0, rd=10), bits=0x37)
        second = instruction(4, rd=11, sources=(10,))
        for rd in (10, 11):
            result = run([first, second, instruction(8, sources=(rd,))],
                         fusion=('lui-addi',))
            self.assertEqual(result['cycles'], 2)
        second = replace(second, sources=(3,))
        self.assertEqual(run([first, second], fusion=('lui-addi',))['fused'], 0)

    def test_early_address_history_and_same_group_base(self):
        for gap, expected in ((0, 0), (1, 1), (2, 1)):
            stream = [instruction(0, rd=10)]
            stream += [instruction(4 + i * 4, 'load', rd=20 + i, sources=(2,))
                       for i in range(gap)]
            pc = 4 + gap * 4
            stream += [instruction(pc, 'load', rd=11, sources=(10,)),
                       instruction(pc + 4, sources=(11,))]
            one = run(stream, early_address=1)
            two = run(stream, early_address=2)
            self.assertEqual(one['early_loads'] - gap, expected)
            self.assertEqual(two['early_loads'] - gap, int(gap == 2))
            self.assertEqual(one['adjacent_load_base'], int(gap == 0))
        stream = [instruction(0, 'load', rd=10, sources=(2,)),
                  instruction(4, sources=(10,))]
        self.assertEqual(run(stream, early_address=1)['cycles'], 2)

    def test_fused_address_is_not_an_early_load(self):
        first = replace(instruction(0, rd=10, sources=(2, 3)), bits=0x33)
        second = replace(instruction(4, 'load', rd=11, sources=(10,)), bits=0x2003)
        result = run([first, second, instruction(8, sources=(11,))], 'V3s',
                     fusion=('add-load',), early_address=1)
        self.assertEqual(result['instructions'], 3)
        self.assertEqual(result['early_loads'], 0)
        self.assertEqual(result['adjacent_load_base'], 1)

    def test_serial_alu_producer_restriction(self):
        for bits, simple in ((0x13, True), (0x37, True), (0x7013, True),
                             (0x1013, True), (0x33, False), (0x40000033, False)):
            first = replace(instruction(0, rd=10), bits=bits)
            stream = [first, instruction(4, sources=(10,))]
            self.assertEqual(run(stream, serial_alu='any')['cycles'], 1)
            self.assertEqual(run(stream, serial_alu='simple')['cycles'], 1 if simple else 2)
        stream[0] = instruction(0, 'load', rd=10)
        self.assertEqual(run(stream, serial_alu='any')['cycles'], 3)
        # V3s exchanges a younger LSU into lane 0: it cannot consume lane 1.
        stream = [instruction(0, rd=10), instruction(4, 'load', sources=(10,))]
        self.assertEqual(run(stream, 'V3s', serial_alu='any')['hpm1'], 0)

    def test_loop_cache_replays_groups_and_exits(self):
        program = {pc: instruction(pc) for pc in range(0, 128, 4)}
        program[12] = instruction(12, 'branch', target=0)
        program[20] = instruction(20, 'serial')
        trace = [0, 4, 8, 12] * 30 + [16, 20]
        base = simulate(program, trace, 0, 20, 'V3s', taken_bubble=1)
        result = simulate(program, trace, 0, 20, 'V3s', loop_cache=True, taken_bubble=1)
        self.assertEqual(result['instructions'], 121)
        self.assertGreater(result['cache_hits'], 0)
        self.assertGreater(result['cache_instructions'], 100)
        self.assertLess(result['cycles'], base['cycles'])
        # A head inside an existing normal pair is still cacheable on re-entry.
        program[0] = instruction(0)
        program[12] = instruction(12, 'branch', target=4)
        trace = [0] + [4, 8, 12] * 30 + [16, 20]
        result = simulate(program, trace, 0, 20, 'V3s', loop_cache=True)
        self.assertEqual(result['instructions'], 92)
        self.assertGreater(result['cache_hits'], 0)
        self.assertGreater(result['cache_instructions'], 60)
        # The 17-instruction static interval exceeds the cache's loop-length limit.
        program[12] = instruction(12)
        program[64] = instruction(64, 'branch', target=0)
        program[72] = instruction(72, 'serial')
        trace = list(range(0, 68, 4)) * 5 + [68, 72]
        result = simulate(program, trace, 0, 72, 'V3s', loop_cache=True)
        self.assertEqual(result['cache_hits'], 0)

    def test_second_level_predictors_train_saved_metadata(self):
        branch = instruction(0, 'branch', target=0)
        for kind in ('loop', 'tournament', 'tage'):
            predictor = Predictor(128, 4096, 8, direction=kind)
            predictor.btb[0] = branch, 0
            for taken in ([True] * 7 + [False]) * 16:
                query = predictor.query(0)
                ib = deque()
                fill_ib({0: branch}, ib, [(0, query), (2, query)], pht_size=4096)
                record = ib[0]
                self.assertIsNotNone(record.direction_meta)
                record.next_pc = 0 if taken else 4
                predictor.update(record)
            self.assertLessEqual(predictor.direction.bits, 32768)
            self.assertEqual(predictor.history & 255, 254)
        direction = Direction('loop')
        for taken in ([True] * 3 + [False]) * 8:
            prediction, token = direction.predict(0, False, 0)
            direction.update(0, taken, token)
        self.assertTrue(direction.predict(0, False, 0)[0])

    def test_gshare_pc_index_shift(self):
        branch = instruction(1024, 'branch', target=16)
        for shift, index in ((1, 7), (2, 263)):
            predictor = Predictor(32, 512, 8, gshare_pc_shift=shift)
            predictor.history = 7
            predictor.btb[0] = branch, 16
            predictor.pht[index] = 3
            query = predictor.query(1024)
            self.assertTrue(query[1])
            ib = deque()
            fill_ib({1024: branch}, ib, [(1024, query), (1026, query)],
                    pht_size=512, gshare_pc_shift=shift)
            self.assertEqual(ib[0].index, index)
            predictor.history = 123
            ib[0].next_pc = 1028
            predictor.update(ib[0])
            self.assertEqual(predictor.pht[index], 2)
            self.assertEqual(predictor.pht[123], 1)

    def test_predictor_scan_sizes(self):
        for btb in (32, 64, 128, 256):
            for pht in (512, 1024, 2048, 4096):
                for ras in (4, 8):
                    predictor = Predictor(btb, pht, 8, ras)
                    first = instruction(0, 'branch', target=16)
                    other = instruction(btb * 4, 'branch', target=16)
                    collision = instruction(btb * 8, 'branch', target=16)
                    for inst in (first, other):
                        predictor.update(Record(inst, False, False, 0, pht - 1,
                                                predictor.snapshot(), next_pc=16))
                    self.assertIsNotNone(predictor.query(0)[0])
                    self.assertIsNotNone(predictor.query(other.pc)[0])
                    self.assertEqual(predictor.pht[-1], 3)
                    self.assertEqual(predictor.pht[pht // 2 - 1], 1)
                    predictor.update(Record(collision, False, False, 0, 0,
                                            predictor.snapshot(), next_pc=16))
                    self.assertIsNone(predictor.query(0)[0])
                    predictor.history = pht - 1
                    predictor.update(Record(first, False, False, 0, 0,
                                            predictor.snapshot(), next_pc=4))
                    self.assertEqual(predictor.history, pht - 2)
                    for pc in range(0, (ras + 2) * 4, 4):
                        predictor.action(replace(instruction(pc, 'jal'), push=True))
                    self.assertEqual(predictor.count, ras)
                    returns = []
                    for _ in range(ras):
                        returns.append(predictor.snapshot()[2])
                        predictor.action(replace(instruction(64, 'jalr'), pop=True))
                    self.assertEqual(returns, list(range((ras + 2) * 4, 8, -4)))

    def test_predictor_parameter_defaults_and_v3s(self):
        stream = [instruction(0), instruction(4, 'branch', target=8),
                  instruction(8, 'branch', target=12), instruction(12, 'load')]
        for variant, sizes in (('V0', (32, 512, 4)), ('V5', (64, 1024, 4)),
                               ('B6', (128, 2048, 8))):
            options = dict(zip(('btb_entries', 'gshare_entries', 'ras_entries'), sizes))
            self.assertEqual(run(stream, variant), run(stream, variant, **options))
        options = dict(perfect_frontend=True, perfect_prediction=True)
        for older in ('branch', 'jal', 'jalr'):
            for younger in ('branch', 'jal'):
                stream = [instruction(0, older, target=4),
                          instruction(4, younger, target=8)]
                self.assertEqual(run(stream, 'V3', **options)['hpm1'], 1)
                self.assertEqual(run(stream, 'V3s', **options)['hpm1'], 0)
        stream = [instruction(0), instruction(4, 'load')]
        self.assertEqual(run(stream, 'V3s', **options)['hpm1'], 1)

    def test_v3s_older_branch_exchange(self):
        options = dict(perfect_frontend=True, perfect_prediction=True)
        for younger in ('load', 'store', 'mul', 'jalr'):
            stream = [instruction(0, 'branch', target=4), instruction(4, younger)]
            expected = 0 if younger == 'jalr' else 1
            self.assertEqual(run(stream, 'V3s', **options)['hpm1'], expected)
            self.assertEqual(run(stream, 'V2s', **options)['hpm1'], 0)

    def test_taken_fetch_bubble(self):
        stream = [instruction(0, 'alu'), instruction(4, 'branch', target=0)]
        program = {i.pc: i for i in stream}
        program.update({pc: instruction(pc) for pc in range(8, 80, 4)})
        program[8] = instruction(8, 'serial')
        trace = [0, 4] * 20 + [8]
        base = simulate(program, trace, 0, 8, 'V3s')
        delayed = simulate(program, trace, 0, 8, 'V3s', taken_bubble=1)
        self.assertGreater(delayed['cycles'], base['cycles'])
        self.assertEqual(delayed['instructions'], base['instructions'])

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

    def test_deferred_cold_jal_redirects_once(self):
        program = {pc: instruction(pc) for pc in range(0, 256, 4)}
        program[32] = instruction(32, 'load', rd=10)
        program[36] = instruction(36, 'branch', sources=(10,), target=96)
        program[40] = instruction(40, 'jal', target=128)
        program[132] = instruction(132, 'serial')
        trace = list(range(0, 44, 4)) + [128, 132]
        result = simulate(program, trace, 0, 132, 'B4')
        self.assertEqual(result['cycles'], 9)
        self.assertEqual(result['hpm16'], 1)
        self.assertEqual(result['hpm4'], 2)
        self.assertEqual(result['slots_redirect_m'], 0)
        self.assertGreater(result['slots_redirect_d'], 0)
        self.assertEqual(result['training_conflicts'], 1)
        program[100] = instruction(100, 'serial')
        trace = list(range(0, 40, 4)) + [96, 100]
        result = simulate(program, trace, 0, 100, 'B4')
        self.assertEqual(result['hpm4'], 1)
        self.assertEqual(result['training_conflicts'], 0)
        self.assertGreater(result['slots_redirect_m'], 0)
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

    def test_backend_redirect_and_result_limits(self):
        changes = {}
        for variant in ('B1', 'B2', 'B3', 'B4', 'B6', 'B7'):
            changes.update(INORDER_VARIANTS[variant])
        INORDER_VARIANTS['B8-directed'] = changes
        self.addCleanup(INORDER_VARIANTS.pop, 'B8-directed')
        for variant in ('B0', 'B8-directed'):
            for kind, parameter, expected in (('branch', 'e_penalty', 4),
                                               ('jal', 'd_penalty', 3)):
                program = {pc: instruction(pc) for pc in range(0, 128, 4)}
                program[0] = instruction(0, kind, target=32)
                program[36] = instruction(36, 'serial')
                timing = {parameter: 2 if kind == 'branch' else 1}
                result = simulate(program, [0, 32, 36], 0, 36, variant, **timing)
                self.assertEqual(result['cycles'], expected)
            program[0] = instruction(0, 'load', rd=10)
            program[4] = instruction(4, 'branch', sources=(10,), target=32)
            result = simulate(program, [0, 4, 32, 36], 4, 36, variant, e_penalty=2)
            self.assertEqual(result['cycles'], 5)  # M recovery falls from four to three.
            for latency in (1, 2):
                stream = [instruction(0, 'mul', rd=10), instruction(4, sources=(10,))]
                result = run(stream, variant, mul_latency=latency)
                self.assertEqual(result['cycles'], latency)
            stream = [instruction(0, 'load', rd=10),
                      instruction(4, 'load', sources=(10,))]
            self.assertEqual(run(stream, variant, load_latency=1)['cycles'], 2)

    def test_load_use_address_consumer_statistics(self):
        for kind, sources, load_address, store_address in (
                ('load', (10,), 1, 0), ('store', (2, 10), 0, 1),
                ('store', (10, 2), 0, 0), ('store', (10, 10), 0, 1),
                ('mul', (10,), 0, 0)):
            stream = [instruction(pc) for pc in range(0, 32, 4)]
            stream += [instruction(32, 'load', rd=10), instruction(36, kind, sources=sources)]
            statistics = {}
            result = run(stream, 'B0', statistics=statistics)
            self.assertEqual(result['slots_load_use'], 2, (kind, sources))
            self.assertEqual(statistics['load_use_load_address_cycles'], load_address)
            self.assertEqual(statistics['load_use_store_address_cycles'], store_address)

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

    def test_jalr_to_fallthrough_replays_squashed_trace_match(self):
        stream = [instruction(pc) for pc in range(0, 40, 4)]
        stream[0] = instruction(0, 'load', rd=11)
        stream[1] = instruction(4, 'jalr', sources=(11,))
        for variant in ('V0', 'V3s'):
            result = run(stream, variant)
            self.assertEqual(result['instructions'], len(stream))
            self.assertEqual(result['hpm4'], 1)
            self.assertEqual(result['hpm16'], 1)

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
