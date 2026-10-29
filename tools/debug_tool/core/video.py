"""video.py — B2 design 3.4a/3.5a EDVF and EDDT; host receive thread.

Keep one EDVF frame until every byte arrives, accepting reordered chunks.
A following frame header retires an incomplete frame without retransmission.
"""

from bisect import bisect_left
from dataclasses import dataclass
import struct
import threading
import time
from collections import deque

VIDEO_HEADER = struct.Struct('<4sHHHHIIQI')
DETECTION_HEADER = struct.Struct('<4sHHII')
DETECTION = struct.Struct('<4hHH')


@dataclass(frozen=True)
class Detections:
    frame_id: int
    boxes: tuple


def parse_detections(data):
    magic, version, count, frame_id, _ = DETECTION_HEADER.unpack_from(data)
    if magic != b'EDDT' or version != 1:
        raise ValueError(f'EDDT magic/version: {magic!r}/{version}')
    if len(data) != DETECTION_HEADER.size + count * DETECTION.size:
        raise ValueError(f'EDDT length {len(data)} does not match count {count}')
    boxes = tuple(DETECTION.unpack_from(data, DETECTION_HEADER.size + i * DETECTION.size)
                  for i in range(count))
    return Detections(frame_id, boxes)


class Block:
    """Byte coverage is required to discard missing UDP payloads, including holes."""

    def __init__(self):
        self.chunks = {}
        self.ranges = []
        self.end = None

    def receive(self, offset, data, notify):
        self.chunks[offset] = bytes(data)
        start, end = offset, offset + len(data)
        index = bisect_left(self.ranges, (start, end))
        if index and self.ranges[index - 1][1] >= start:
            index -= 1
            start = self.ranges[index][0]
        stop = index
        while stop < len(self.ranges) and self.ranges[stop][0] <= end:
            end = max(end, self.ranges[stop][1])
            stop += 1
        self.ranges[index:stop] = [(start, end)]
        if notify:
            self.end = offset + len(data)

    def complete(self, size=None):
        size = self.end if size is None else size
        if size is None:
            return False
        return self.ranges == [(0, size)]

    def data(self, size=None):
        size = self.end if size is None else size
        result = bytearray(size)
        for offset, data in self.chunks.items():
            result[offset:offset + len(data)] = data
        return bytes(result)


@dataclass(frozen=True)
class VideoFrame:
    width: int
    height: int
    stride: int
    frame_id: int
    mtime: int
    scene: int
    pixels: bytes


class FrameRate:
    def __init__(self):
        self.times = deque()

    def add(self, now):
        self.times.append(now)
        self.prune(now)

    def prune(self, now):
        while len(self.times) > 2 and now - self.times[0] > 1:
            self.times.popleft()

    def fps(self, now):
        self.prune(now)
        if len(self.times) < 2 or now - self.times[-1] > 1:
            return 0.0
        return (len(self.times) - 1) / (self.times[-1] - self.times[0])


class VideoReceiver:
    def __init__(self, clock=time.monotonic):
        self.lock = threading.Lock()
        self.clock = clock
        self.block = Block()
        self.detection_block = Block()
        self.header = None
        self.finished = False
        self.frame = None
        self.detections = None
        self.frame_detections = None
        self.received = 0
        self.dropped = 0
        self.rate = FrameRate()

    def receive(self, window, offset, data, notify):
        with self.lock:
            if window == 2:
                if offset == 0:
                    self.detection_block = Block()
                self.detection_block.receive(offset, data, notify)
                if self.detection_block.complete():
                    self.detections = parse_detections(self.detection_block.data())
                return
            if window != 0:
                return
            if offset == 0:
                header = VIDEO_HEADER.unpack_from(data)
                if header[0] != b'EDVF' or header[1:3] != (1, 1):
                    raise ValueError(f'EDVF magic/version/format: {header[:3]}')
                if self.header is not None and not self.finished:
                    self.dropped += 1
                self.block = Block()
                self.header = header
                self.finished = False
            if self.header is None or self.finished:
                if notify:
                    self.dropped += 1  # A pixel batch without its EDVF header.
                return
            self.block.receive(offset, data, notify)
            if self.header is not None:
                _, _, _, width, height, stride, frame_id, mtime, scene = self.header
                size = VIDEO_HEADER.size + height * stride
                if self.block.complete(size):
                    self.frame = VideoFrame(width, height, stride, frame_id, mtime, scene,
                                            self.block.data(size)[VIDEO_HEADER.size:])
                    self.frame_detections = (self.detections if self.detections is not None
                                             and self.detections.frame_id == frame_id else None)
                    self.received += 1
                    self.rate.add(self.clock())
                    self.finished = True

    def finish(self):
        with self.lock:
            if not self.finished and (self.header is not None or self.block.chunks):
                self.dropped += 1
                self.finished = True

    def snapshot(self):
        with self.lock:
            detections = self.frame_detections
            if (self.frame is not None and self.detections is not None
                    and self.detections.frame_id == self.frame.frame_id):
                detections = self.detections
            return dict(frame=self.frame, detections=detections,
                        received=self.received, dropped=self.dropped,
                        fps=self.rate.fps(self.clock()))
