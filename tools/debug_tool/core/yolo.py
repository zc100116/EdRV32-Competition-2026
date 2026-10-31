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
        self.mode = 'B3VN'
        self.input_tensor = None
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
                sizes = (0 if self.mode == 'B3N' else INPUT_BYTES,
                         OUTPUT_BYTES, offset + len(data))
                for index, size in enumerate(sizes):
                    if size and not self.blocks[index].complete(size):
                        raise ValueError(f'YOLO WIN {index}: incomplete return ({size} B expected)')
                ch2, output, detections = (block.data(size)
                                           for block, size in zip(self.blocks, sizes))
                if self.mode == 'B3N':
                    ch2 = self.input_tensor
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
        expected_input = (reference_b3n_input(image) if self.mode == 'B3N'
                          else reference_input(image))
        return dict(input=byte_difference(expected_input, ch2),
                    output=byte_difference(reference, output),
                    detections=detection_difference(boxes, detections.boxes))

    def send_model(self, path, board_ip, board_port, local_port):
        blocks = pack_model(path)
        self.image_bytes = sum(len(data) for _, _, data in blocks)
        return self.ethernet.send_blocks(blocks, board_ip, board_port, local_port,
                                         name=str(path))

    def send_image(self, path, board_ip, board_port, local_port, window=0):
        if window not in (0, 1):
            raise ValueError('test image window must be 0 or 1 (B2 design 3.5a)')
        pixels = reference_b3n_input(path) if self.mode == 'B3N' else image_rgb565(path)
        self.input_tensor = pixels if self.mode == 'B3N' else None
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


def reference_input(path):
    # The NPU scripts use sibling imports; the fixed repository path is shared with CLI.
    import sys
    root = Path(__file__).resolve().parents[3]
    sys.path.insert(0, str(root / 'third_party/ultralytics'))
    npu_path = str(root / 'tools/npu')
    if npu_path not in sys.path:
        sys.path.insert(0, npu_path)
    from input_pack import pack
    return pack(Path(path))


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


def reference_b3n_input(path):
    """T-NETN: resize arbitrary sources to display geometry, then use input_pack."""
    import cv2
    from tempfile import TemporaryDirectory
    image = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if image is None:
        raise ValueError(f'Cannot read image {path}')
    image = cv2.resize(image, (1280, 720), interpolation=cv2.INTER_LINEAR)
    scratch = Path(__file__).resolve().parents[3] / 'build/debug_tool'
    scratch.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(dir=scratch) as directory:
        resized = Path(directory) / 'input.png'
        if not cv2.imwrite(str(resized), image):
            raise ValueError(f'Cannot write resized image {resized}')
        return reference_input(resized)
