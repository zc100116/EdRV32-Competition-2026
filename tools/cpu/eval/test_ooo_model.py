#!/usr/bin/env python3
# File: test_ooo_model.py; Spec: cpu-spec 2.3/4.4 and C-E8; Clock: host.
# Check renamed dependencies, memory ordering, redirects and finite ROB capacity.
# Directed event timestamps verify scheduling independently of aggregate speed.
"""Run with python3 tools/cpu/eval/test_ooo_model.py."""
from dataclasses import replace
import unittest

from analyze import Instruction
from ooo_model import RENAME_CAUSES, simulate


def instruction(pc, kind='alu', rd=0, sources=(), target=0, bits=0x2013, size=4):
    return Instruction(pc, bits, size, kind, rd, sources, target, False, False)


def run(stream, addresses=None, wrong_path=(), **options):
    end = max(i.pc + i.size for i in stream)
    program = {pc: instruction(pc) for pc in range(0, end + 1024, 2)}
    program.update({i.pc: i for i in stream})
    program.update({i.pc: i for i in wrong_path})
    program[end] = instruction(end, 'csr')
    trace = [i.pc for i in stream] + [end]
    timeline = []
    result = simulate(program, trace, (addresses or [0] * len(stream)) + [0],
                      stream[0].pc, end, timeline=timeline, **options)
    return result, timeline


def when(timeline, name, index):
    return next(tick for tick, event, slot, pc in timeline if event == name and slot == index)


class OutOfOrder(unittest.TestCase):
    def test_rename_waw_and_same_cycle_raw(self):
        stream = [instruction(0, 'mul', rd=1), instruction(4, rd=1),
                  instruction(8, rd=2, sources=(1,))]
        result, timeline = run(stream)
        # The consumer sees the younger ALU, rather than the older MUL writing x1.
        self.assertEqual(when(timeline, 'execute', 2), when(timeline, 'execute', 1) + 1)
        self.assertLess(when(timeline, 'execute', 2), when(timeline, 'commit', 0))
        # Same RN pair must build a RAW edge, even with the same destination.
        _, timeline = run([instruction(0, rd=1), instruction(4, rd=1, sources=(1,))])
        self.assertEqual(when(timeline, 'execute', 1), when(timeline, 'execute', 0) + 1)

    def test_war(self):
        _, timeline = run([instruction(0, 'mul', rd=2),
                           instruction(4, rd=3, sources=(1, 2)), instruction(8, rd=1)])
        self.assertLess(when(timeline, 'execute', 2), when(timeline, 'execute', 1))

    def test_independent_bypasses_blocked(self):
        _, timeline = run([instruction(0, 'mul', rd=1), instruction(4, sources=(1,)),
                           instruction(8, rd=2)])
        self.assertLess(when(timeline, 'execute', 2), when(timeline, 'execute', 1))

    def test_unknown_store_address(self):
        stream = [instruction(0, 'mul', rd=1), instruction(4, 'store', sources=(2, 1)),
                  instruction(8, 'load', rd=3, sources=(4,))]
        result, timeline = run(stream, [0, 0x1000, 0x2000])
        self.assertGreater(when(timeline, 'execute', 2), when(timeline, 'execute', 1))
        # The condition can occur before the timing window begins; use a long producer.
        stream[0] = replace(stream[0], kind='div')
        stream.insert(0, instruction(-4))
        result, _ = run(stream, [0, 0, 0x1000, 0x2000])
        self.assertGreater(result['store_unknown'], 0)

    def test_store_forward_and_nonoverlap(self):
        # Older DIV holds retirement, so the store stays in the ROB when load executes.
        stream = [instruction(0), instruction(4, 'div', rd=1),
                  instruction(8), instruction(12),
                  instruction(16, 'store', sources=(2, 3)),
                  instruction(20, 'load', rd=4, sources=(3,))]
        result, timeline = run(stream, [0, 0, 0, 0, 0x1000, 0x1000])
        self.assertGreater(result['forwarded'], 0)
        self.assertLess(when(timeline, 'execute', 5), when(timeline, 'commit', 4))
        result, timeline = run(stream, [0, 0, 0, 0, 0x1000, 0x2000])
        self.assertEqual(result['forwarded'], 0)
        self.assertLess(when(timeline, 'execute', 5), when(timeline, 'commit', 4))

    def test_partial_overlap_waits_for_commit(self):
        stream = [instruction(0), instruction(4, 'div', rd=1),
                  instruction(8, 'store', sources=(2, 3)),
                  instruction(12, 'load', rd=4, sources=(3,), bits=0x1013)]
        result, timeline = run(stream, [0, 0, 0x1000, 0x1002])
        self.assertGreater(result['store_overlap'], 0)
        self.assertGreaterEqual(when(timeline, 'execute', 3), when(timeline, 'commit', 2))

    def test_store_data_wait(self):
        stream = [instruction(0), instruction(4, 'div', rd=1),
                  instruction(8, 'store', sources=(1, 3)),
                  instruction(12, 'load', rd=4, sources=(3,))]
        result, timeline = run(stream, [0, 0, 0x1000, 0x1000])
        self.assertGreater(result['store_data'], 0)
        self.assertLess(when(timeline, 'execute', 2), when(timeline, 'execute', 1) + 34)
        self.assertGreaterEqual(when(timeline, 'execute', 3), when(timeline, 'execute', 1) + 34)

    def test_mispredict_squash_penalty(self):
        for penalty in (5, 7, 9):
            stream = [instruction(0), instruction(4, 'branch', target=32), instruction(32)]
            _, timeline = run(stream, penalty=penalty)
            self.assertEqual(when(timeline, 'execute', 2) - when(timeline, 'execute', 1),
                             penalty + 1)
            wrong_commits = [index for _, name, index, _ in timeline
                             if name == 'commit' and index < 0]
            self.assertEqual(wrong_commits, [])

    def test_rob_full_and_commit_order(self):
        stream = [instruction(0), instruction(4, 'div', rd=1)]
        stream += [instruction(pc, rd=2) for pc in range(8, 160, 4)]
        result, timeline = run(stream, rob_size=16, iq_size=8)
        self.assertGreater(result['rename_slots_rob_full'], 0)
        committed = [index for _, name, index, _ in timeline if name == 'commit']
        self.assertEqual(committed, list(range(len(stream))))
        self.assertEqual(sum(result['rename_slots_' + k] for k in RENAME_CAUSES),
                         2 * result['cycles'])

    def test_iq_full(self):
        stream = [instruction(0), instruction(4, 'div', rd=1)]
        stream += [instruction(pc, rd=2, sources=(1,)) for pc in range(8, 160, 4)]
        result, _ = run(stream, rob_size=32, iq_size=8)
        self.assertGreater(result['rename_slots_iq_full'], 0)

    def test_wrong_path_memory_stays_in_iq(self):
        stream = [instruction(0), instruction(4, 'div', rd=1),
                  instruction(8, 'branch', sources=(1,), target=64), instruction(64)]
        wrong = [instruction(12, 'store', sources=(2, 3)),
                 instruction(16, 'load', rd=4, sources=(3,))]
        result, timeline = run(stream, wrong_path=wrong)
        self.assertEqual(result['squashed_memory'], 2)
        self.assertFalse(any(pc in (12, 16) and name == 'execute'
                             for _, name, _, pc in timeline))

    def test_load_mul_latency(self):
        for kind, latency in (('alu', 1), ('load', 2), ('mul', 3), ('div', 34)):
            _, timeline = run([instruction(0, kind, rd=1), instruction(4, sources=(1,))])
            self.assertEqual(when(timeline, 'execute', 1) - when(timeline, 'execute', 0),
                             latency)

    def test_issue_three_unit_limits(self):
        stream = [instruction(0), instruction(4, 'div', rd=1)]
        stream += [instruction(pc, 'mul' if pc % 12 == 0 else 'alu', rd=2, sources=(1,))
                   for pc in range(8, 80, 4)]
        _, timeline = run(stream, issue_width=3)
        groups = {}
        for tick, name, index, _ in timeline:
            if name == 'select' and 0 <= index < len(stream):
                groups.setdefault(tick, []).append(stream[index].kind)
        self.assertTrue(any(len(kinds) == 3 for kinds in groups.values()))
        for kinds in groups.values():
            self.assertLessEqual(kinds.count('alu'), 2)
            self.assertLessEqual(kinds.count('mul'), 1)


if __name__ == '__main__':
    unittest.main()
