# File: stream.py
# Spec: npu-spec 2.2, 5.6; npu-testplan PP-P-02.
# Description: 12600 labelled beats and acceptance scoreboard for the branch adapter.
# Clock domain: host; cycle values are clk_npu edges supplied by the adapter.
"""The RTL interface adapter is intentionally pending the coordinator's interface report."""
from oracle import SHAPES


def beats():
    """The real row/C32/plane/pair sequence; each tuple includes two passing anchors."""
    for head, (width, height, _, base) in enumerate(SHAPES):
        for row in range(height):
            for block in range(3):
                for first_pair in range(0, width // 2, 16):
                    for plane in range(block * 2, min(block * 2 + 2, 5)):
                        for pair in range(first_pair, min(first_pair + 16, width // 2)):
                            left = base + row * width + pair * 2
                            # Both halves pass; plane4 closes both 80-way maxima.
                            data = bytes([127] * 32)
                            yield (head, row, block, plane, pair, left, left + 1, data)


class Acceptance:
    def __init__(self):
        self.expected = list(beats())
        self.cycles = []
        self.enqueued = []

    def accept(self, cycle, beat):
        index = len(self.cycles)
        assert beat == self.expected[index], f'beat={index} label/data mismatch'
        if self.cycles:
            assert cycle == self.cycles[-1] + 1, f'II != 1 at beat={index}'
        self.cycles.append(cycle)

    def enqueue(self, anchor):
        self.enqueued.append(anchor)

    def finish(self, first_enqueue_cycle):
        assert len(self.cycles) == 12600
        assert self.enqueued == list(range(5040)), 'queue loss/duplicate/order'
        return dict(received_beats=len(self.cycles),
                    pipeline_latency=first_enqueue_cycle - self.cycles[next(
                        i for i, beat in enumerate(self.expected) if beat[3] == 4)],
                    receive_cycles=self.cycles[-1] - self.cycles[0] + 1,
                    receive_us_200mhz=len(self.cycles) / 200,
                    budget_us_200mhz=63)
