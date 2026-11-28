#!/usr/bin/env python3
# File: test_store_queue.py; Spec: cpu-v2 v0.3 3.7/C11; Clock: host.
# Check beat capacity, retirement, cancellation and local same-word load waits.
"""python3 -m unittest discover -s tools/cpu/eval -p 'test_*.py'."""
from dataclasses import replace
import unittest

from pipe_model import CompletionWindow, Record, StoreQueue
from test_pipe_model import instruction, run


def record(pc, kind='store'):
    return Record(instruction(pc, kind), False, False, 0, 0, (), completion_order=pc)


class StoreQueueTests(unittest.TestCase):
    def test_prepare_commit_drain_and_registered_credit(self):
        queue = StoreQueue(2, 2)
        a, b = record(0), record(4)
        queue.allocate(a, 0x80000000, 1)
        queue.allocate(b, 0x80000004, 1)
        queue.edge(20, False)
        self.assertEqual((len(queue.entries), queue.credit), (2, 0))
        queue.commit([a, b])
        self.assertEqual(len(queue.entries), 2)
        queue.edge(21, False)
        self.assertEqual((len(queue.entries), queue.credit), (1, 0))
        queue.edge(22, False)
        self.assertEqual((len(queue.entries), queue.credit), (0, 1))
        queue.edge(23, False)
        self.assertEqual(queue.credit, 2)

    def test_double_beat_counts_and_load_matches_any_word(self):
        queue = StoreQueue(4, 2)
        a, b = record(0), record(4)
        queue.allocate(a, 0x80000000, 1)
        queue.allocate(b, 0x80000010, 2)
        self.assertEqual(queue.credit, 1)
        self.assertTrue(queue.conflicts(0x80000013))
        self.assertTrue(queue.conflicts(0x80000016))
        self.assertTrue(queue.conflicts(0x8000000c, 2))
        self.assertFalse(queue.conflicts(0x80000018))
        queue.commit([a, b])
        queue.edge(1, False)
        self.assertTrue(queue.conflicts(0x80000010, 2))
        queue.edge(2, False)
        self.assertTrue(queue.conflicts(0x80000010, 2))
        queue.edge(3, False)
        self.assertFalse(queue.conflicts(0x80000010, 2))

    def test_cancel_keeps_committed_and_older_uncommitted(self):
        queue = StoreQueue(4, 2)
        a, b, c = record(0), record(4), record(8)
        for r in (a, b, c):
            queue.allocate(r, 0x80000000 + r.instruction.pc, 1)
        queue.commit([a])
        queue.cancel_after(b)
        self.assertEqual([e[0] for e in queue.entries], [a, b])
        queue.edge(1, False)
        self.assertEqual([e[0] for e in queue.entries], [b])

    def test_early_wait_retries_normal_and_tracks_all_conflicting_stores(self):
        queue = StoreQueue(4, 2)
        a, b = record(0), record(4)
        for r in (a, b):
            queue.allocate(r, 0x80000000, 1)
        load = record(8, 'load')
        load.early_load = True
        load.issue_tick = 1
        window = CompletionWindow(8, 2)
        window.allocate(load, 1, 1)
        entry = window.entries[-1]
        queue.load(load, 0x80000002, 1, entry, 0, True)
        self.assertFalse(load.early_load)
        self.assertEqual(entry[1], float('inf'))
        queue.commit([a, b])
        queue.edge(2, True)
        self.assertEqual(entry[1], float('inf'))
        queue.edge(3, True)
        self.assertEqual((queue.wait_count, queue.wait_cycles), (1, 2))
        self.assertEqual((load.lsu_ready, entry[1]), (4, 5))
        self.assertEqual(window.edge(4), [])
        self.assertEqual(window.edge(5), [load])

    def test_ordinary_query_can_use_a_store_drained_on_its_agu_edge(self):
        queue = StoreQueue(2, 2)
        a = record(0)
        queue.allocate(a, 0x80000000, 1)
        load = record(4, 'load')
        window = CompletionWindow(8, 1)
        window.allocate(load, 1, 2)
        queue.load(load, 0x80000000, 1, window.entries[-1], 0, True)
        queue.commit([a])
        queue.edge(2, True)
        self.assertEqual((queue.wait_count, queue.wait_cycles), (0, 0))
        self.assertEqual(window.entries[-1][1], 4)

    def test_default_model_is_unchanged(self):
        stream = [instruction(0, 'store'), instruction(4, 'load', rd=10)]
        base = run(stream, 'V3s')
        self.assertEqual(run(stream, 'V3s', store_queue_entries=0), base)
        self.assertEqual(run(stream, 'V3s', store_queue_entries=2), base)

    def test_capacity_and_local_wait_for_both_widths(self):
        stream = [instruction(0), instruction(4, 'mul', rd=5)] + [
            instruction(pc, 'store') for pc in range(8, 24, 4)] + [
            instruction(24, 'load', rd=10), instruction(28, sources=(10,))]
        addresses = [0, 0] + [0x80000000] * 5 + [0, 0]
        for width, window in ((1, 8), (2, 16)):
            options = dict(issue_width=width, completion_entries=window,
                           completion_addresses=addresses, store_queue_model=True,
                           perfect_frontend=True, perfect_prediction=True, mul_latency=16,
                           early_address='rf_wb')
            results = {n: run(stream, 'V3s', store_queue_entries=n, **options)
                       for n in (0, 2, 4)}
            self.assertGreater(results[2]['store_queue_full_cycles'], 0)
            self.assertGreater(results[2]['cycles'], results[0]['cycles'])
            self.assertGreater(results[0]['store_queue_load_waits'], 0)
            self.assertEqual(results[0]['early_loads'], 0)
            self.assertEqual(results[0]['instructions'], len(stream))

    def test_full_queue_allows_alu_and_unrelated_load(self):
        stream = [instruction(0, 'mul', rd=5), instruction(4, 'store'),
                  instruction(8, 'store'), instruction(12),
                  instruction(16, 'load', rd=10)]
        timeline = []
        result = run(stream, 'V3s', store_queue_model=True, store_queue_entries=2,
                     completion_entries=8, completion_addresses=[0, 0x80000000, 0x80000004,
                                                                0, 0x80000008, 0],
                     issue_width=1, mul_latency=16, perfect_frontend=True,
                     perfect_prediction=True, timeline=timeline)
        entered = {pc: tick for tick, event, *stages in timeline if event == 'stages'
                   for pc in stages[0]}
        self.assertLess(entered[16] - entered[0], 6)
        self.assertEqual(result['store_queue_load_waits'], 0)

    def test_waiting_load_scoreboard_survives_pipeline_and_younger_waw(self):
        for waw in (False, True):
            stream = [instruction(0, 'mul', rd=5), instruction(4, 'store'),
                      instruction(8, 'load', rd=10)] + [
                instruction(pc, rd=10 if waw and pc == 12 else 0)
                for pc in range(12, 40, 4)] + [instruction(40, sources=(10,))]
            timeline = []
            run(stream, 'V3s', store_queue_model=True, completion_entries=16,
                completion_addresses=[0, 0x80000000, 0x80000000] + [0] * 9,
                issue_width=1, mul_latency=24, perfect_frontend=True,
                perfect_prediction=True, timeline=timeline)
            entered = {pc: tick for tick, event, *stages in timeline if event == 'stages'
                       for pc in stages[0]}
            self.assertGreater(entered[40] - entered[8], 20 if not waw else 0)
            if waw:
                self.assertLess(entered[40] - entered[8], 12)

    def test_device_uses_head_authorization_without_store_queue_allocation(self):
        stream = [instruction(0, 'store'), instruction(4)]
        options = dict(completion_entries=8, completion_addresses=[0x40000000, 0, 0],
                       perfect_frontend=True, perfect_prediction=True)
        queued = run(stream, 'V3s', store_queue_model=True, store_queue_entries=2, **options)
        head = run(stream, 'V3s', completion_head_authorization=True, **options)
        self.assertEqual(queued['cycles'], head['cycles'])
        self.assertEqual(queued['store_queue_full_cycles'], 0)

    def test_double_beat_store_blocks_on_second_word(self):
        stream = [replace(instruction(0, 'store'), bits=0x3027),
                  instruction(4, 'load', rd=10)]
        result = run(stream, 'V3s', store_queue_model=True, store_queue_entries=2,
                     completion_entries=8, completion_addresses=[0x80000000, 0x80000004, 0],
                     issue_width=1, early_address='rf_wb', perfect_frontend=True,
                     perfect_prediction=True)
        self.assertEqual(result['store_queue_load_waits'], 1)
        # The first store is the ROI marker: only the final wait edge is inside.
        self.assertEqual(result['store_queue_load_wait_cycles'], 1)
        self.assertEqual(result['early_loads'], 0)

    def test_fence_waits_for_queue_and_write_buffer(self):
        stream = [instruction(0, 'store'), replace(instruction(4, 'serial'), bits=0x0f),
                  instruction(8, 'load', rd=10)]
        timeline = []
        result = run(stream, 'V3s', store_queue_model=True, store_queue_entries=2,
                     completion_entries=8, completion_addresses=[0x80000000, 0, 0x80000000, 0],
                     issue_width=1, perfect_frontend=True, perfect_prediction=True,
                     timeline=timeline)
        entered = {pc: tick for tick, event, *stages in timeline if event == 'stages'
                   for pc in stages[0]}
        # Store retires at 2, enters the buffer at 3, array write at 4.
        self.assertEqual(entered[4] - entered[0], 4)
        self.assertEqual(result['store_queue_load_waits'], 0)

    def test_cancel_waiting_load_removes_local_lsu_hold(self):
        queue = StoreQueue(2, 2)
        a = record(0)
        queue.allocate(a, 0x80000000, 1)
        load = record(8, 'load')
        load.early_load = True
        window = CompletionWindow(8, 2)
        window.allocate(load, 0, 1)
        load.completion_order = 8
        queue.load(load, 0x80000000, 0, window.entries[-1], 0, True)
        self.assertEqual(len(queue.loads), 1)
        queue.cancel_after(a)
        self.assertEqual(queue.loads, [])
        self.assertEqual(len(queue.entries), 1)


if __name__ == '__main__':
    unittest.main()
