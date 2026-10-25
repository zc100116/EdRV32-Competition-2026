#!/usr/bin/env python3
# File: test_models.py; Spec: cpu-spec 4.2/4.4; Clock: host.
# Exercise instruction dependencies, grouped BTB lookup and RAS prediction on small traces.
"""Run with python3 tools/cpu/eval/test_models.py."""
import unittest

from analyze import (Instruction, decode, fetch_groups, pairing, prediction_events,
                     predictor as predict_events, ras_update)


def predictor(trace, final_pc, btb, pht, ras):
    return predict_events(prediction_events(trace, final_pc), btb, pht, ras)


def instruction(pc, kind='alu', rd=0, sources=(), target=0, pop=False, push=False):
    return Instruction(pc, 0x13, 4, kind, rd, sources, target, pop, push)


class Models(unittest.TestCase):
    def test_compressed_operands(self):
        self.assertEqual(decode(0, 0x0505, 'c.addi', 'x10,1').sources, (10,))
        self.assertEqual(decode(0, 0x852e, 'c.mv', 'x10,x11').sources, (11,))
        self.assertEqual(decode(0, 0x4102, 'c.lwsp', 'x2,0(x2)').sources, (2,))
        self.assertEqual(decode(0, 0x0048, 'c.addi4spn', 'x10,x2,4').sources, (2,))
        self.assertTrue(decode(0, 0x8082, 'c.jr', 'x1').pop)
        self.assertTrue(decode(0, 0x9082, 'c.jalr', 'x1').push)
        self.assertFalse(decode(0, 0x9082, 'c.jalr', 'x1').pop)

    def test_pairing_raw_waw_and_branch(self):
        a = instruction(0, rd=10)
        b = instruction(4, rd=10, sources=(11,))
        self.assertEqual(pairing([a, b], False)['pairs'], 1)
        b = instruction(4, sources=(10,))
        self.assertEqual(pairing([a, b], False)['raw'], 1)
        b = instruction(4, 'branch', sources=(11,), target=16)
        self.assertEqual(pairing([a, b], False)['slot1_type'], 1)
        self.assertEqual(pairing([a, b], True)['pairs'], 1)
        self.assertEqual(pairing([instruction(0, 'jal'), b], True)['only_one'], 2)

    def test_failure_priority_and_control_boundary(self):
        serial = instruction(0, 'serial', rd=10)
        load = instruction(4, 'load', sources=(10,))
        self.assertEqual(pairing([serial, load], False)['raw'], 1)
        load = instruction(4, 'load', sources=(11,))
        self.assertEqual(pairing([serial, load], False)['structural'], 1)
        trace = [instruction(0, 'branch', target=16), instruction(16)]
        self.assertEqual(pairing(trace, True)['only_one'], 2)

    def test_fetch_groups_straddle_and_same_group_target(self):
        cross = Instruction(6, 0x13, 4, 'alu', 0, (), 0, False, False)
        self.assertEqual(fetch_groups([cross, instruction(10)], 14), 2)
        trace = [instruction(0, 'jal', target=0)] * 3
        self.assertEqual(fetch_groups(trace, 0), 3)

    def test_cold_branch_and_saturation(self):
        loop = instruction(0, 'branch', target=0)
        result = predictor([loop] * 8, 0, 32, 512, 4)
        self.assertEqual(result['btb_miss'], 1)
        self.assertEqual(result['direction_wrong'], 8)
        result = predictor([loop] * 20, 0, 32, 512, 4)
        self.assertEqual(result['direction_wrong'], 10)
        self.assertEqual(result['target_wrong'], 0)

    def test_btb_position_alias_and_capacity(self):
        first = instruction(0, 'branch', target=16)
        second = instruction(4, 'jal', target=0)
        # Both branches share a BTB entry: each visit predicts the later JAL,
        # while the preceding not-taken conditional still trains its counter.
        result = predictor([first, second] * 3, 0, 32, 512, 4)
        self.assertEqual(result['btb_miss'], 4)
        self.assertEqual(result['redirects'], 1)
        a = instruction(0, 'jal', target=128)
        b = instruction(128, 'jal', target=0)
        trace = [a, b] * 3
        self.assertEqual(predictor(trace, 0, 16, 512, 4)['btb_miss'], 6)
        self.assertEqual(predictor(trace, 0, 32, 512, 4)['btb_miss'], 2)

    def test_ras_overwrite_and_cold_call_repair(self):
        stack = []
        for pc in (0, 8, 16):
            ras_update(stack, instruction(pc, 'jal', push=True), 2)
        self.assertEqual(stack, [12, 20])
        call = instruction(0, 'jal', rd=1, target=16, push=True)
        ret = instruction(16, 'jalr', sources=(1,), pop=True)
        back = instruction(4, 'jal', target=0)
        result = predictor([call, ret, back] * 4, 0, 32, 512, 4)
        self.assertEqual(result['ras_empty'], 0)
        self.assertEqual(result['target_wrong'], 0)
        self.assertEqual(result['redirects'], 9)


if __name__ == '__main__':
    unittest.main()
