"""yolo.py — B2 design 3.3–3.5a model/image transport; host clock domain.

Read compiler readmemh outputs and send sparse EDNM blocks with one NOTIFY.
Image decoding uses the existing PySide6 dependency, imported only when needed.
"""

from pathlib import Path
import struct


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
        self.image_bytes = 0

    def send_model(self, path, board_ip, board_port, local_port):
        blocks = pack_model(path)
        self.image_bytes = sum(len(data) for _, _, data in blocks)
        return self.ethernet.send_blocks(blocks, board_ip, board_port, local_port,
                                         name=str(path))

    def send_image(self, path, board_ip, board_port, local_port, window=0):
        if window not in (0, 1):
            raise ValueError('test image window must be 0 or 1 (B2 design 3.5a)')
        return self.ethernet.send_blocks([(window, 0, image_rgb565(path))],
                                         board_ip, board_port, local_port, name=str(path))
