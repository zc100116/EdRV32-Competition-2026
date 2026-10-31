"""yolo.py — B2 design 3.3–3.5a model/image transport; host clock domain.

Read compiler readmemh outputs and send sparse EDNM blocks with one NOTIFY.
Image decoding uses the existing PySide6 dependency, imported only when needed.
"""

from pathlib import Path
import struct
import threading
import time

from .video import Block, parse_detections


def read_hex(path, base):
    data = bytearray()
    address = base
    for token in Path(path).read_text(encoding='ascii').split():
        if token.startswith('@'):
            address = int(token[1:], 16) * 32
        else:
            chunk = bytes.fromhex(token)[::-1]
            offset = address - base
            if offset > len(data):
                data.extend(bytes(offset - len(data)))
            data[offset:offset + len(chunk)] = chunk
            address += len(chunk)
    return bytes(data)


def pack_model(directory):
    directory = Path(directory)
    regs = {key: int(value, 16) for key, value in
            (line.split() for line in (directory / 'regs.txt').read_text().splitlines())}
    desc = read_hex(directory / 'mem_desc.hex', regs['DESC_BASE'])
    model = read_hex(directory / 'mem_model.hex', regs['MODEL_BASE'])
    header = struct.pack('<4s7I', b'EDNM', 1, regs['DESC_COUNT'], len(desc), len(model),
                         regs['WORK_BASE'], regs['INPUT_BASE'], regs['OUTPUT_BASE'])
    return [(2, 0, header), (2, 0x1000, desc), (2, 0x100000, model)]


def rgb_to_rgb565(rgb):
    """SoC 4.5: first/left pixel is the low 16 bits, little endian in DDR."""
    result = bytearray(len(rgb) // 3 * 2)
    for pixel in range(len(rgb) // 3):
        r, g, b = rgb[pixel * 3:pixel * 3 + 3]
        value = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
        struct.pack_into('<H', result, pixel * 2, value)
    return bytes(result)


def image_rgb565(path):
    from PySide6.QtCore import Qt
    from PySide6.QtGui import QImage, QImageReader
    reader = QImageReader(str(path))
    image = reader.read()
    if image.isNull():
        raise ValueError(f'Cannot read image {path}: {reader.errorString()}')
    image = image.scaled(1280, 720, Qt.IgnoreAspectRatio, Qt.SmoothTransformation)
    image = image.convertToFormat(QImage.Format_RGB888)
    return rgb_to_rgb565(bytes(image.constBits()))


class YoloTool:
    def __init__(self, ethernet):
        self.ethernet = ethernet
        self.next_window = 0
        self.sent_at = None
        self.timings = []
        self.image_bytes = 0
        self.source_image = None
        self.return_view = False
        self.lock = threading.Lock()
        self.blocks = [Block() for _ in range(3)]
        self.capture = None
        self.capture_pending = False
        self.capture_started = False
        self.generation = 0

    def reset_capture(self):
        with self.lock:
            self.blocks = [Block() for _ in range(3)]
            self.capture = None
            self.capture_pending = True
            self.capture_started = False
            self.return_view = True

    def receive(self, window, offset, data, notify):
        if window not in (0, 1, 2):
            return
        with self.lock:
            self.blocks[window].receive(offset, data, notify)
            if window == 2 and notify:
                sizes = (INPUT_BYTES,
                         OUTPUT_BYTES, offset + len(data))
                for index, size in enumerate(sizes):
                    if size and not self.blocks[index].complete(size):
                        raise ValueError(f'YOLO return {index}: incomplete return ({size} B expected)')
                ch2, output, detections = (block.data(size)
                                           for block, size in zip(self.blocks, sizes))
                self.capture = (ch2, output, parse_detections(detections))
                if self.sent_at is not None:
                    self.timings.append(dict(path=self.source_image,
                                             seconds=time.monotonic() - self.sent_at))
                    self.sent_at = None
                self.generation += 1
                self.capture_pending = False

    def snapshot(self):
        with self.lock:
            return self.generation, self.capture

    def compare(self, image, directory, quant_params):
        _, capture = self.snapshot()
        if capture is None:
            raise ValueError('YOLO: no complete return received')
        ch2, output, detections = capture
        reference = reference_output(directory, ch2)
        boxes = reference_detections(reference, quant_params)
        expected_input = reference_input(image)
        return dict(input=byte_difference(expected_input, ch2),
                    output=byte_difference(reference, output),
                    detections=detection_difference(boxes, detections.boxes))

    def send_model(self, path, board_ip, board_port, local_port):
        blocks = pack_model(path)
        self.image_bytes = sum(len(data) for _, _, data in blocks)
        return self.ethernet.send_blocks(blocks, board_ip, board_port, local_port,
                                         name=str(path))

    def send_image(self, path, board_ip, board_port, local_port):
        window = self.next_window
        self.next_window = 1 - window
        pixels = image_rgb565(path)
        self.source_image = str(path)
        self.reset_capture()
        self.sent_at = time.monotonic()
        return self.ethernet.send_blocks([(window, 0, pixels)],
                                         board_ip, board_port, local_port, name=str(path))


OUTPUT_BYTES = 725760
INPUT_BYTES = 983040


def byte_difference(expected, actual):
    """Count unequal byte positions, including any unmatched suffix."""
    first = None
    count = abs(len(expected) - len(actual))
    for index, (left, right) in enumerate(zip(expected, actual)):
        if left != right:
            count += 1
            if first is None:
                first = index
    if first is None and len(expected) != len(actual):
        first = min(len(expected), len(actual))
    return dict(count=count, first=first)


def reference_output(directory, ch2):
    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
    from tools.npu.ref.npu_ref import load_case, execute, NpuError
    memory, registers = load_case(directory)
    memory.write(registers['INPUT_BASE'], ch2)
    try:
        execute(memory, registers)
    except NpuError as exc:
        raise ValueError(f'NPU reference: {exc}') from exc
    return memory.read(registers['OUTPUT_BASE'], OUTPUT_BYTES)


def rgb565_ch2(pixels):
    """VIN 2.8 reference, including RGB565 expansion before the 2x2 average."""
    import numpy as np
    image = np.frombuffer(pixels, dtype='<u2').reshape(720, 1280)
    channels = []
    for shift, bits in ((11, 5), (5, 6), (0, 5)):
        value = (image >> shift) & ((1 << bits) - 1)
        expanded = (value << (8 - bits)) | (value >> (2 * bits - 8))
        total = expanded.reshape(360, 2, 640, 2).sum(axis=(1, 3))
        averaged = (total + 2) // 4
        channels.append((254 * averaged + 255) // 510)
    output = np.zeros((384, 640, 4), dtype=np.uint8)
    output[:, :, :3] = 57
    output[12:372, :, :3] = np.stack(channels, axis=-1)
    return output.tobytes()


def reference_input(path):
    return rgb565_ch2(image_rgb565(path))


def reference_detections(output, quant_params):
    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
    from tools.npu import yolo_post_ref
    return yolo_post_ref.run(output, quant_params)


def detection_difference(expected, actual):
    expected = tuple(tuple(box) for box in expected)
    actual = tuple(tuple(box) for box in actual)
    count = sum(left != right for left, right in zip(expected, actual))
    count += abs(len(expected) - len(actual))
    return dict(count=count, expected=len(expected), actual=len(actual))
