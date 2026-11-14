"""yolo.py — showcase design 4.5.4 model/image transport; host clock domain.

Read compiler readmemh outputs and send contiguous EDNM through BULK.
Image decoding uses the existing PySide6 dependency, imported only when needed.
"""

from pathlib import Path
import struct
import subprocess
import sys
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
    data = bytearray(0x100000 + len(model))
    data[:len(header)] = header
    data[0x1000:0x1000 + len(desc)] = desc
    data[0x100000:] = model
    return bytes(data)


def rgb_to_rgb565(rgb):
    """SoC 4.5: first/left pixel is the low 16 bits, little endian in DDR."""
    result = bytearray(len(rgb) // 3 * 2)
    for pixel in range(len(rgb) // 3):
        r, g, b = rgb[pixel * 3:pixel * 3 + 3]
        value = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
        struct.pack_into('<H', result, pixel * 2, value)
    return bytes(result)


def letterbox_geometry(width, height):
    """The integer resize dimensions are shared by upload and result display."""
    from PySide6.QtCore import QSize, Qt
    size = QSize(width, height).scaled(1280, 720, Qt.KeepAspectRatio)
    return size.width(), size.height(), (1280 - size.width()) // 2, (720 - size.height()) // 2


def original_boxes(boxes, width, height):
    scaled_w, scaled_h, left, top = letterbox_geometry(width, height)
    result = []
    for x0, y0, x1, y1, category, score in boxes:
        x0, x1 = max(left, x0), min(left + scaled_w, x1)
        y0, y1 = max(top, y0), min(top + scaled_h, y1)
        if x0 < x1 and y0 < y1:
            result.append(((x0 - left) * width / scaled_w,
                           (y0 - top) * height / scaled_h,
                           (x1 - left) * width / scaled_w,
                           (y1 - top) * height / scaled_h, category, score))
    return tuple(result)


def image_rgb565(path):
    from PySide6.QtCore import Qt
    from PySide6.QtGui import QImage, QImageReader, QPainter
    reader = QImageReader(str(path))
    image = reader.read()
    if image.isNull():
        raise ValueError(f'Cannot read image {path}: {reader.errorString()}')
    width, height, left, top = letterbox_geometry(image.width(), image.height())
    image = image.scaled(width, height, Qt.IgnoreAspectRatio, Qt.SmoothTransformation)
    canvas = QImage(1280, 720, QImage.Format_RGB888)
    canvas.fill(Qt.black)
    painter = QPainter(canvas)
    painter.drawImage(left, top, image)
    painter.end()
    return rgb_to_rgb565(bytes(canvas.constBits()))


class YoloTool:
    def __init__(self, ethernet):
        self.ethernet = ethernet
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
        self.failed = 0
        self.error = None
        self.capture_error = None
        self.request = None
        self.images = []
        self.image_index = 0
        self.image_status = '等待'
        self.image_destination = None

    def reset_capture(self):
        with self.lock:
            self.blocks = [Block() for _ in range(3)]
            self.capture = None
            self.capture_pending = True
            self.capture_started = False
            self.return_view = True
            self.error = None
            self.capture_error = None
            if self.ethernet is not None and self.ethernet.rx_capture_event is not None:
                self.ethernet.rx_capture_event.set()
                with self.ethernet.rx_capture_epoch.get_lock():
                    self.ethernet.rx_capture_epoch.value += 1

    def receive(self, window, offset, data, notify):
        if window not in (0, 1, 2):
            return
        with self.lock:
            self.blocks[window].receive(offset, data, notify)
            if window == 2 and notify:
                # A malformed EDDT is a protocol error even when image bytes are missing.
                if self.blocks[2].complete(offset + len(data)):
                    result = self.blocks[2].data(offset + len(data))
                    if (self.ethernet is not None and
                            struct.unpack_from('<I', result, 12)[0] != self.request):
                        self.blocks[2] = Block()
                        return
                    parse_detections(result)
                if not self.blocks[1].ranges or self.blocks[1].ranges[0][0] != 0 or (
                        self.blocks[1].ranges[0][1] < 4):
                    self.capture_error = '回传不完整：window 1 missing candidate count'
                    return
                candidate_count = struct.unpack_from('<I', self.blocks[1].data(4))[0]
                if candidate_count > 5040:
                    raise ValueError('NPU candidate count exceeds 5040')
                sizes = (INPUT_BYTES, 4 + candidate_count * 24, offset + len(data))
                missing = []
                for index, size in enumerate(sizes):
                    if size and not self.blocks[index].complete(size):
                        covered = sum(end - start for start, end in self.blocks[index].ranges)
                        missing.append(f'window {index}: missing {size - covered} B / {size} B')
                if missing:
                    self.capture_error = '回传不完整：' + '; '.join(missing)
                    return
                ch2, output, detections = (block.data(size)
                                           for block, size in zip(self.blocks, sizes))
                parse_candidates(output)
                self.capture = (ch2, output, parse_detections(detections))
        if window == 2 and notify and self.ethernet is not None and self.ethernet.session:
            self.ethernet.session.notify()

    def complete_capture(self):
        """Design 4.5.9: DONE commits the image after all return data arrived."""
        with self.lock:
            if self.capture is None:
                self._fail_capture(self.capture_error or '回传不完整：未收到完整 CH2 / candidates / EDDT')
                raise ValueError(self.error)
            if self.sent_at is not None:
                self.timings.append(dict(path=self.source_image,
                                         seconds=time.monotonic() - self.sent_at))
                self.sent_at = None
            self.generation += 1
            self.capture_pending = False
            self.image_status = '完成'

    def _fail_capture(self, error):
        """Called with the capture lock held; missing UDP bytes fail this image only."""
        self.image_status = '失败'
        self.error = error
        self.failed += 1
        self.generation += 1
        self.capture = None
        self.capture_pending = False
        self.capture_started = False
        self.sent_at = None
        if self.ethernet is not None and self.ethernet.rx_capture_event is not None:
            self.ethernet.rx_capture_event.clear()
            with self.ethernet.rx_capture_epoch.get_lock():
                self.ethernet.rx_capture_epoch.value += 1
        if self.ethernet is not None and self.ethernet.session:
            self.ethernet.session.log(f'{self.source_image}: {error}')

    def snapshot(self):
        with self.lock:
            return self.generation, self.capture

    def compare(self, image, directory, quant_params):
        _, capture = self.snapshot()
        if capture is None:
            raise ValueError('YOLO: no complete return received')
        ch2, output, detections = capture
        directory = directory or Path(__file__).resolve().parents[3] / 'build/npu/software_model'
        reference = reference_output(directory, ch2)
        boxes = reference_detections(reference, quant_params)
        expected_input = reference_input(image)
        return dict(input=byte_difference(expected_input, ch2),
                    output=candidate_difference(
                        reference_candidates(reference, quant_params), output),
                    detections=detection_difference(boxes, detections.boxes))

    def camera_detection(self, board_ip, board_port, local_port):
        self.return_view = False
        from .pipeline import pack_chain
        from .showcase import CHAIN
        destination = board_ip, board_port
        result = self.ethernet.showcase.app(1, destination=destination)
        chain = self.ethernet.session.engine.pipeline.status()
        chain.update(source=0, preset=0)
        self.ethernet.showcase.command(CHAIN, pack_chain(chain), destination)
        return result

    def send_model(self, path, board_ip, board_port, local_port):
        if not path:
            root = Path(__file__).resolve().parents[3]
            path = root / 'build/npu/software_model'
            subprocess.run([sys.executable, str(root / 'tools/npu/compile_yolo.py'),
                            '--model-source',
                            str(root / 'tasks/win/20261029-09-b3-software/src/npu'),
                            '--out', str(path)], check=True)
        data = pack_model(path)
        self.image_bytes = len(data)
        return self.ethernet.showcase.bulk(1, data, board_ip, board_port,
                                            local_port, str(path))

    def select_folder(self, path):
        self.images = sorted(item for item in Path(path).iterdir()
                             if item.suffix.lower() in ('.png', '.jpg', '.jpeg', '.bmp'))
        if not self.images:
            raise ValueError('文件夹没有图片')
        self.image_index = 0
        self.image_status = '等待'
        self.image_destination = (*self.ethernet.session.network_endpoint, 6000)

    def step(self, direction):
        if self.capture_pending or self.ethernet.tx['active']:
            self.ethernet.session.log('当前图片未完成，忽略翻页')
            return
        target = self.image_index + direction
        if not 0 <= target < len(self.images):
            return
        self.image_index = target
        self.send_image(self.images[target], *self.image_destination)

    def send_image(self, path, board_ip, board_port, local_port):
        pixels = image_rgb565(path)
        path = Path(path)
        if path not in self.images:
            self.images = [path]
        self.image_index = self.images.index(path)
        self.image_destination = (board_ip, board_port, local_port)
        self.source_image = str(path)
        self.request = None
        self.reset_capture()
        self.image_status = '发送中'
        self.sent_at = time.monotonic()
        name = path.name.encode('utf-8')
        if len(name) > 256:
            raise ValueError('图片文件名超过 256 字节')
        info = struct.pack('<HHH2x', self.image_index + 1, len(self.images), len(name)) + name
        return self.ethernet.showcase.bulk(2, pixels, board_ip, board_port, local_port,
                                            str(path), image_info=info)


OUTPUT_BYTES = 725760
INPUT_BYTES = 983040


CANDIDATE_BYTES = 4 + 5040 * 24


def pack_candidates(candidates):
    return struct.pack('<I', len(candidates)) + b''.join(
        struct.pack('<4iIHH', *box, probability, category, anchor)
        for box, probability, category, anchor in candidates)


def parse_candidates(data):
    count, = struct.unpack_from('<I', data)
    if count > 5040 or len(data) != 4 + count * 24:
        raise ValueError('NPU candidate count/length')
    return tuple(struct.unpack_from('<4iIHH', data, 4 + i * 24) for i in range(count))


def reference_candidates(output, quant_params):
    from tools.npu import yolo_post_ref as reference
    stats = dict.fromkeys(reference.STAT_KEYS, 0)
    return pack_candidates(reference.decode_candidates(output,
        reference.make_heads(quant_params), stats))


def candidate_difference(expected, actual):
    # Hardware enqueue order is independent of the oracle head/cell traversal.
    left = sorted(parse_candidates(expected), key=lambda row: row[-1])
    right = sorted(parse_candidates(actual), key=lambda row: row[-1])
    return byte_difference(b''.join(struct.pack('<4iIHH', *row) for row in left),
                           b''.join(struct.pack('<4iIHH', *row) for row in right))


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
