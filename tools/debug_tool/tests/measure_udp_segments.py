"""measure_udp_segments.py — UDP video loss location; host benchmark only.

Count missing bitmap entries in each third of a 720p line-rate burst.
Instrument only the spawned receiver, leaving the application path unchanged.
"""

import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from core import ethernet
from core.video import VideoReceiver
from stress_test import udp_stress

receive_process = ethernet._video_process


def segment_process(*args):
    initialize = VideoReceiver.__init__
    receive = VideoReceiver.receive
    finish = VideoReceiver.finish

    def measured_init(self, *args, **kwargs):
        initialize(self, *args, **kwargs)
        self.segment_missing = [0, 0, 0]
        self.segment_frames = 0
        self.segment_incomplete = 0

    def record(self):
        if self.header is None:
            return
        self.segment_frames += 1
        self.segment_incomplete += not self.finished
        for index in range(3):
            self.segment_missing[index] += self.seen[index * 600:(index + 1) * 600].count(0)

    def measured_receive(self, window, offset, data, notify):
        if window == 0 and offset == 0:
            record(self)
        receive(self, window, offset, data, notify)

    def measured_finish(self):
        record(self)
        finish(self)
        print('SEGMENT_SUMMARY=' + json.dumps(dict(
            tracked_frames=self.segment_frames,
            incomplete_frames=self.segment_incomplete,
            missing_first_600=self.segment_missing[0],
            missing_middle_600=self.segment_missing[1],
            missing_last_600=self.segment_missing[2])), flush=True)

    VideoReceiver.__init__ = measured_init
    VideoReceiver.receive = measured_receive
    VideoReceiver.finish = measured_finish
    receive_process(*args)


if __name__ == '__main__':
    ethernet._video_process = segment_process
    udp_stress('line')
