#!/usr/bin/env python3
# File: test_wide_model.py; Spec: cpu-spec 4.1-4.4; Clock: host.
# Verify ordered prefixes, v0.15 pairing, FU capacities and result latencies.
# Exercise real frontend metadata and redirects rather than fitting cycle totals.
"""Run with python3 tools/cpu/eval/test_wide_model.py."""
from collections import deque
import unittest

from pipe_model import Predictor
from test_ooo_model import instruction, when
from wide_model import fill_width, fits, simulate


def run(stream, **options):
    end = max(i.pc + i.size for i in stream)
    program = {pc: instruction(pc) for pc in range(0, end + 1024, 2)}
    program.update({i.pc: i for i in stream})
    program[end] = instruction(end, 'csr')
    timeline = []
    result = simulate(program, [i.pc for i in stream] + [end], stream[0].pc,
                      end, timeline=timeline, **options)
    return result, timeline


class WideInOrder(unittest.TestCase):
    def test_v015_pair_mapping(self):
        branch = instruction(0, 'branch')
        load = instruction(4, 'load')
        jalr = instruction(4, 'jalr')
        for pair in ([branch, load], [load, branch]):
            self.assertTrue(fits(pair, 2, 2, 1, 1, True))
        self.assertFalse(fits([branch, jalr], 2, 2, 1, 1, True))
        self.assertFalse(fits([load, instruction(8, 'mul')], 2, 2, 1, 1, True))
        self.assertTrue(fits([load, instruction(8, 'mul')], 2, 2, 1, 1, False))

    def test_prefix_stops_at_raw(self):
        _, timeline = run([instruction(0, rd=1), instruction(4, sources=(1,)),
                           instruction(8)], width=4, alus=4)
        self.assertEqual(when(timeline, 'issue', 1), when(timeline, 'issue', 0) + 1)
        self.assertGreaterEqual(when(timeline, 'issue', 2), when(timeline, 'issue', 1))

    def test_four_independent(self):
        _, timeline = run([instruction(pc) for pc in range(0, 64, 4)], width=4, alus=4)
        groups = {}
        for tick, name, _, _ in timeline:
            if name == 'issue':
                groups[tick] = groups.get(tick, 0) + 1
        self.assertEqual(max(groups.values()), 4)

    def test_fu_limits(self):
        alupair = [instruction(0), instruction(4), instruction(8)]
        self.assertFalse(fits(alupair, 3, 2, 1, 1, False))
        self.assertTrue(fits(alupair, 3, 3, 1, 1, False))
        loads = [instruction(0, 'load'), instruction(4, 'load')]
        self.assertFalse(fits(loads, 3, 3, 1, 1, False))
        self.assertTrue(fits(loads, 3, 3, 2, 1, False))
        self.assertFalse(fits([instruction(0, 'mul'), instruction(4, 'mul')],
                              3, 3, 2, 1, False))
        controls = [instruction(0, 'branch'), instruction(4, 'branch')]
        self.assertFalse(fits(controls, 4, 4, 2, 1, False))
        self.assertTrue(fits(controls, 4, 4, 2, 2, False))

    def test_latency_and_x0(self):
        for kind, latency in [('alu', 1), ('load', 2), ('mul', 3), ('div', 34)]:
            _, timeline = run([instruction(0, kind, rd=1), instruction(4, sources=(1,))])
            self.assertEqual(when(timeline, 'issue', 1) - when(timeline, 'issue', 0), latency)
        _, timeline = run([instruction(0, 'load'), instruction(4, sources=(0,))])
        self.assertEqual(when(timeline, 'issue', 1), when(timeline, 'issue', 0))

    def test_second_lsu(self):
        stream = [instruction(0, 'load'), instruction(4, 'load')]
        _, one = run(stream)
        _, two = run(stream, lsus=2)
        self.assertEqual(when(one, 'issue', 1) - when(one, 'issue', 0), 1)
        self.assertEqual(when(two, 'issue', 1), when(two, 'issue', 0))

    def test_jalr_sequential_target_replays(self):
        result, timeline = run([instruction(0), instruction(4, 'jalr'), instruction(8),
                                instruction(12)])
        committed = [index for _, name, index, _ in timeline if name == 'commit']
        self.assertEqual(committed, [0, 1, 2, 3])
        self.assertEqual(result['instructions'], 4)

    def test_waw_youngest_bypass(self):
        for first, second, interval in [('load', 'alu', 1), ('alu', 'load', 2)]:
            _, timeline = run([instruction(0, first, rd=1), instruction(4, second, rd=1),
                               instruction(8, sources=(1,))])
            self.assertEqual(when(timeline, 'issue', 0), when(timeline, 'issue', 1))
            self.assertEqual(when(timeline, 'issue', 2) - when(timeline, 'issue', 1), interval)

    def test_csr_drains_older_pipeline(self):
        _, timeline = run([instruction(0), instruction(4, 'csr'), instruction(8)])
        self.assertGreaterEqual(when(timeline, 'issue', 1), when(timeline, 'commit', 0))
        self.assertGreater(when(timeline, 'issue', 2), when(timeline, 'issue', 1))

    def test_predictor_metadata(self):
        predictor = Predictor(128, 4096, 8, 4, 2)
        predictor.history = 0x800
        pc = 0x1234
        ib = deque()
        fill_width({pc: instruction(pc)}, ib, [(pc, predictor.query(pc)),
                                              (pc + 2, predictor.query(pc))], 2)
        self.assertEqual(ib[0].index, ((pc >> 2) ^ 0x800) & 4095)


if __name__ == '__main__':
    unittest.main()
