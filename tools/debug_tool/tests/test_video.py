"""test_video.py — B2 design 3.4a/3.5a video and comparisons; host clock domain.

Exercise wire bytes, reorder/loss, display frame association and real UDP paths.
Reference execution uses a small UPSAMPLE descriptor with known output bytes.
"""

from pathlib import Path
import socket
import subprocess
import sys
import struct
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from tools.debug_tool.core.engine import SerialEngine
from tools.debug_tool.core.ethernet import HEADER, packets
from tools.debug_tool.core.video import FrameRate, VideoReceiver, parse_detections
from tools.debug_tool.core.yolo import (
    INPUT_BYTES, OUTPUT_BYTES, YoloTool, byte_difference, detection_difference,
    reference_input, reference_output,
)
from test_program import wait_for
from test_telemetry import wire


def frame_header(frame_id=9):
    return struct.pack('<4sHHHHIIQI', b'EDVF', 1, 1, 32, 20, 64,
                       frame_id, frame_id * 10000000, 1)


def detection_wire(frame_id=9):
    return (struct.pack('<4sHHII', b'EDDT', 1, 2, frame_id, 0) +
            struct.pack('<4hHH', -2, 20, 120, 200, 0, 876) +
            struct.pack('<4hHH', 400, 300, 700, 600, 79, 1000))


def upsample_case(directory):
    directory = Path(directory)
    (directory / 'regs.txt').write_text(
        'DESC_BASE 00080000\nMODEL_BASE 00100000\nDESC_COUNT 00000001\n'
        'WORK_BASE 01000000\nINPUT_BASE 04000000\nOUTPUT_BASE 05000000\n')
    words = [0] * 16
    words[0] = 2 | (2 << 12) | (3 << 14)
    words[2], words[4] = 16, 64
    words[8], words[9], words[10] = (1 << 16) | 1, (2 << 16) | 2, 1
    raw = struct.pack('<16I', *words)
    (directory / 'mem_desc.hex').write_text('@00004000\n' + '\n'.join(
        raw[i:i + 32][::-1].hex() for i in range(0, 64, 32)))


def feed_frame(video, frame_id=9, missing=None, reverse=False):
    video.receive(0, 0, frame_header(frame_id), False)
    pixels = bytes(range(256)) * 5
    parts = [(32 + i, pixels[i:i + 1024], i + 1024 >= len(pixels))
             for i in range(0, len(pixels), 1024)]
    if missing is not None:
        parts.pop(missing)
    for offset, data, notify in reversed(parts) if reverse else parts:
        video.receive(0, offset, data, notify)
    return pixels


class VideoTest(unittest.TestCase):
    def test_edvf_header_and_reordered_pixels(self):
        video = VideoReceiver()
        pixels = feed_frame(video, reverse=True)
        result = video.snapshot()
        self.assertEqual((result['received'], result['dropped']), (1, 0))
        frame = result['frame']
        self.assertEqual((frame.width, frame.height, frame.stride), (32, 20, 64))
        self.assertEqual((frame.frame_id, frame.mtime, frame.scene), (9, 90000000, 1))
        self.assertEqual(frame.pixels, pixels)

    def test_missing_middle_and_last_drop_at_next_header_or_stop(self):
        video = VideoReceiver()
        feed_frame(video, missing=1)
        self.assertIsNone(video.snapshot()['frame'])
        feed_frame(video, 10, missing=-1)
        self.assertEqual(video.snapshot()['dropped'], 1)
        video.finish()
        video.finish()
        self.assertEqual(video.snapshot()['dropped'], 2)
        self.assertEqual(video.snapshot()['received'], 0)

    def test_lost_header_batch_is_discarded_and_counted(self):
        video = VideoReceiver()
        video.receive(0, 32, b'x' * 100, True)
        self.assertEqual(video.snapshot()['dropped'], 1)
        self.assertIsNone(video.snapshot()['frame'])
        feed_frame(video, 11)
        video.receive(0, 32, b'x' * 100, True)
        self.assertEqual(video.snapshot()['dropped'], 2)
        self.assertEqual(video.snapshot()['frame'].frame_id, 11)

    def test_duplicate_packets_do_not_complete_a_frame_with_a_hole(self):
        video = VideoReceiver()
        video.receive(0, 0, frame_header(), False)
        first = bytes(range(256)) * 4
        video.receive(0, 32, first, False)
        video.receive(0, 32, first, False)
        self.assertIsNone(video.snapshot()['frame'])
        video.receive(0, 1056, b'z' * 256, True)
        frame = video.snapshot()['frame']
        self.assertEqual(frame.pixels, first + b'z' * 256)
        video.receive(0, 1056, b'z' * 256, True)
        self.assertEqual(video.snapshot()['received'], 1)
        self.assertEqual(video.snapshot()['dropped'], 0)
        feed_frame(video, 10)
        self.assertEqual(frame.pixels, first + b'z' * 256)
        self.assertTrue(frame.pixels.readonly)

    def test_missing_packet_with_duplicates_is_dropped(self):
        video = VideoReceiver()
        video.receive(0, 0, frame_header(), False)
        for _ in range(3):
            video.receive(0, 1056, b'z' * 256, True)
        video.finish()
        self.assertEqual(video.snapshot()['received'], 0)
        self.assertEqual(video.snapshot()['dropped'], 1)

    def test_frame_id_gap_is_not_network_skip_counter(self):
        video = VideoReceiver()
        feed_frame(video, 1)
        feed_frame(video, 7)
        self.assertEqual(video.snapshot()['dropped'], 0)
        self.assertEqual(video.snapshot()['received'], 2)

    def test_eddt_signed_coords_class_score_and_empty(self):
        detections = parse_detections(detection_wire())
        self.assertEqual(detections.frame_id, 9)
        self.assertEqual(detections.boxes, ((-2, 20, 120, 200, 0, 876),
                                          (400, 300, 700, 600, 79, 1000)))
        self.assertEqual(parse_detections(struct.pack('<4sHHII', b'EDDT', 1, 0, 8, 0)).boxes,
                         ())
        with self.assertRaisesRegex(ValueError, 'magic/version'):
            parse_detections(b'BAD!' + detection_wire()[4:])
        with self.assertRaisesRegex(ValueError, 'length'):
            parse_detections(detection_wire()[:-1])

    def test_detections_match_displayed_frame_while_next_result_arrives(self):
        video = VideoReceiver()
        video.receive(2, 0, detection_wire(9), True)
        feed_frame(video, 9)
        self.assertEqual(video.snapshot()['detections'].frame_id, 9)
        video.receive(2, 0, detection_wire(10), True)
        self.assertEqual(video.snapshot()['detections'].frame_id, 9)
        feed_frame(video, 10)
        self.assertEqual(video.snapshot()['detections'].frame_id, 10)
        feed_frame(video, 11)
        self.assertIsNone(video.snapshot()['detections'])

    def test_fps_intervals_and_idle_expiry(self):
        rate = FrameRate()
        rate.add(0)
        self.assertEqual(rate.fps(0), 0)
        for time in (.1, .2, .3):
            rate.add(time)
        self.assertAlmostEqual(rate.fps(.3), 10)
        self.assertEqual(rate.fps(2), 0)
        rate.add(2)
        rate.add(2.2)
        self.assertAlmostEqual(rate.fps(2.2), 5)
        slow = FrameRate()
        slow.add(0)
        slow.add(1.01)
        self.assertAlmostEqual(slow.fps(1.2), 1 / 1.01)

    def test_vid_skip_wire_offset_accumulation_and_duplicate_record(self):
        engine = SerialEngine()
        for seq, value in [(0, 4), (1, 3), (1, 3)]:
            data = bytearray(wire(seq))
            struct.pack_into('<I', data, 292, value)
            engine.telemetry.ingest(data)
        self.assertEqual(engine.telemetry.status()['latest']['vid_skip'], 3)
        self.assertEqual(engine.telemetry.status()['video_skipped'], 7)

    def test_real_udp_video_and_detection_without_raw_frame_file(self):
        engine = SerialEngine()
        engine.ethernet.local_ip = "127.0.0.1"
        self.addCleanup(engine.ethernet.stop_receive)
        with TemporaryDirectory() as directory:
            rx = engine.ethernet.start_receive(0, directory, mode='video')
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
                dest = '127.0.0.1', rx['localPort']
                sock.sendto(next(packets(detection_wire(), 2, 0)), dest)
                sock.sendto(HEADER.pack(0, 0, 0, 0) + frame_header(), dest)
                for packet in reversed(list(packets(bytes(1280), 0, 32))):
                    sock.sendto(packet, dest)
            wait_for(self, lambda: engine.video.snapshot()['received'] == 1)
            engine.ethernet.stop_receive()
            self.assertEqual(list(Path(directory).iterdir()), [])
            self.assertIsNone(engine.ethernet.status()['rx']['error'])
            self.assertEqual(engine.video.snapshot()['detections'].frame_id, 9)

    def test_process_frame_survives_slot_reuse_and_restart(self):
        engine = SerialEngine()
        engine.ethernet.local_ip = '127.0.0.1'
        self.addCleanup(engine.ethernet.stop_receive)
        with TemporaryDirectory() as directory:
            state = engine.ethernet.start_receive(0, directory, mode='video')
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as source:
                first = None
                for frame_id in range(4):
                    destination = '127.0.0.1', state['localPort']
                    source.sendto(HEADER.pack(0, 0, 0, 0) + frame_header(frame_id), destination)
                    for packet in packets(bytes([frame_id]) * 1280, 0, 32):
                        source.sendto(packet, destination)
                    wait_for(self, lambda: engine.video.snapshot()['received'] == frame_id + 1)
                    if first is None:
                        first = engine.video.snapshot()['frame']
                self.assertEqual(bytes(first.pixels), bytes(1280))
                self.assertTrue(first.pixels.readonly)
                engine.ethernet.stop_receive()
                self.assertIsNone(engine.ethernet.rx_memory)
                state = engine.ethernet.start_receive(0, directory, mode='video')
                destination = '127.0.0.1', state['localPort']
                source.sendto(HEADER.pack(0, 0, 0, 0) + frame_header(4), destination)
                for packet in packets(bytes([4]) * 1280, 0, 32):
                    source.sendto(packet, destination)
                wait_for(self, lambda: engine.video.snapshot()['received'] == 5)
                self.assertEqual(bytes(first.pixels), bytes(1280))

    def test_simulator_udp_yolo_return(self):
        engine = SerialEngine()
        engine.yolo.request = 0
        engine.ethernet.local_ip = "127.0.0.1"
        self.addCleanup(engine.ethernet.stop_receive)
        tool = Path(__file__).resolve().parents[1]
        with TemporaryDirectory() as directory:
            rx = engine.ethernet.start_receive(0, directory, mode='yolo')
            subprocess.run([sys.executable, str(tool / 'telemetry_sim.py'), '--mode', 'yolo',
                            '--port', str(rx['localPort'])], check=True, timeout=15)
            wait_for(self, lambda: engine.yolo.snapshot()[1] is not None)
            engine.ethernet.stop_receive()
            _, (ch2, output, detections) = engine.yolo.snapshot()
            self.assertEqual(ch2, bytes(INPUT_BYTES))
            self.assertEqual(output, bytes(OUTPUT_BYTES))
            self.assertEqual(detections.frame_id, 42)
            self.assertEqual(len(detections.boxes), 3)
            for window, data in [(0, ch2), (1, output)]:
                self.assertEqual((Path(directory) / f'window{window}.bin').read_bytes(), data)
            self.assertIsNone(engine.ethernet.status()['rx']['error'])


class ComparisonTest(unittest.TestCase):
    def test_byte_differences_first_position_and_length(self):
        self.assertEqual(byte_difference(b'abc', b'abc'), dict(count=0, first=None))
        self.assertEqual(byte_difference(b'abcde', b'azcz'), dict(count=3, first=1))
        self.assertEqual(byte_difference(b'abc', b'abcdef'), dict(count=3, first=3))
        self.assertEqual(byte_difference(b'', b'x'), dict(count=1, first=0))

    def test_detection_exact_wire_units_and_order(self):
        boxes = parse_detections(detection_wire()).boxes
        self.assertEqual(detection_difference(list(boxes), boxes)['count'], 0)
        self.assertEqual(detection_difference(list(reversed(boxes)), boxes)['count'], 2)
        self.assertEqual(detection_difference(boxes[:1], boxes)['count'], 1)

    def test_yolo_capture_and_comparison_uses_returned_ch2(self):
        yolo = YoloTool(None)
        ch2, output = bytes(INPUT_BYTES), bytes(OUTPUT_BYTES)
        for window, data in [(0, ch2), (1, output), (2, detection_wire())]:
            for packet in packets(data, window, 0):
                _, notify, _, offset = HEADER.unpack_from(packet)
                yolo.receive(window, offset, packet[8:], bool(notify and window == 2))
        reference = bytearray(output)
        reference[123] = 1
        quant = {'convolutions': []}
        with (patch('tools.debug_tool.core.yolo.reference_output', return_value=reference) as npu,
              patch('tools.debug_tool.core.yolo.reference_input', return_value=ch2),
              patch('tools.debug_tool.core.yolo.reference_detections',
                    return_value=parse_detections(detection_wire()).boxes) as post):
            result = yolo.compare('original.png', 'compiler', quant)
        npu.assert_called_once_with('compiler', ch2)
        post.assert_called_once_with(reference, quant)
        self.assertEqual(result['output'], dict(count=1, first=123))
        self.assertEqual(result['input']['count'], 0)
        self.assertEqual(result['detections']['count'], 0)

    def test_yolo_missing_return_fails_loudly(self):
        yolo = YoloTool(None)
        yolo.reset_capture()
        yolo.receive(2, 0, detection_wire(), True)
        with self.assertRaisesRegex(ValueError, '回传不完整'):
            yolo.complete_capture()
        self.assertIn('window 0: missing 983040 B', yolo.error)
        self.assertEqual(yolo.failed, 1)
        self.assertFalse(yolo.capture_pending)

    def test_real_npu_reference_small_upsample(self):
        import importlib.util
        if importlib.util.find_spec('numpy') is None:
            self.skipTest('NPU tool environment is required for real reference execution')
        with TemporaryDirectory() as directory:
            directory = Path(directory)
            upsample_case(directory)
            ch2 = bytes(range(16)) + bytes(INPUT_BYTES - 16)
            result = reference_output(directory, ch2)
        self.assertEqual(result, bytes(range(16)) * 4 + bytes(OUTPUT_BYTES - 64))


    def test_real_input_pack_letterbox_and_int8_c4(self):
        import importlib.util
        if importlib.util.find_spec('torch') is None:
            self.skipTest('NPU tool environment is required for input_pack')
        from PySide6.QtGui import QImage, QColor
        with TemporaryDirectory() as directory:
            image = QImage(1280, 720, QImage.Format_RGB888)
            image.fill(QColor('red'))
            path = Path(directory) / 'red.png'
            self.assertTrue(image.save(str(path)))
            actual = reference_input(path)
        padding = bytes([57, 57, 57, 0]) * (640 * 12)
        red = bytes([127, 0, 0, 0]) * (640 * 360)
        self.assertEqual(actual, padding + red + padding)


    def test_real_reference_pipeline_input_output_and_postprocess(self):
        import importlib.util
        if importlib.util.find_spec('torch') is None:
            self.skipTest('NPU tool environment is required for reference pipeline')
        from PySide6.QtGui import QImage, QColor
        # Red letterbox input and the first 16 bytes repeated into a 2x2 C16 output.
        padding = bytes([57, 57, 57, 0]) * (640 * 12)
        ch2 = bytearray(padding + bytes([127, 0, 0, 0]) * (640 * 360) + padding)
        ch2[-1] = 1
        output = bytearray(bytes([57, 57, 57, 0]) * 16 + bytes(OUTPUT_BYTES - 64))
        output[125] = 1
        quant = {'convolutions': [
            dict(name=f'D{scale}.{branch}.out', output_scale=.1, output_zero_point=127)
            for scale in range(3) for branch in ('box', 'cls')]}
        board_boxes = (struct.pack('<4sHHII', b'EDDT', 1, 1, 42, 0) +
                       struct.pack('<4hHH', 10, 20, 100, 200, 0, 900))
        yolo = YoloTool(None)
        yolo.receive(0, 0, ch2, False)
        yolo.receive(1, 0, output, False)
        yolo.receive(2, 0, board_boxes, True)
        with TemporaryDirectory() as directory:
            upsample_case(directory)
            image = QImage(1280, 720, QImage.Format_RGB888)
            image.fill(QColor('red'))
            path = Path(directory) / 'red.png'
            self.assertTrue(image.save(str(path)))
            result = yolo.compare(path, directory, quant)
        self.assertEqual(result['input'], dict(count=1, first=INPUT_BYTES - 1))
        self.assertEqual(result['output'], dict(count=1, first=125))
        self.assertEqual(result['detections'], dict(count=1, expected=0, actual=1))
