#!/usr/bin/env python3
"""game_record.py — showcase design 4.4 / 4.5.5 game records and packs.
Render names and decode covers with Qt on the host; no board clock domain.
"""
import argparse
import math
import os
from pathlib import Path
import struct

from PySide6.QtCore import QPointF, Qt
from PySide6.QtGui import (
    QFont, QFontDatabase, QImage, QImageReader, QPainter, QTextLayout, QTextOption,
)
from PySide6.QtWidgets import QApplication

ROOT = Path(__file__).resolve().parents[2]
HEADER = struct.Struct('<4sHHIHHIHHIII64s')
PACK_HEADER = struct.Struct('<4sHH')
_app = None


def name_bitmap(name):
    global _app
    if QApplication.instance() is None:
        os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
        _app = QApplication([])
    font_id = QFontDatabase.addApplicationFont(str(
        ROOT / 'third_party/lvgl/tests/src/test_files/fonts/noto/NotoSansSC-Regular.ttf'))
    if font_id == -1:
        raise ValueError('Cannot load Noto Sans SC font')
    font = QFont(QFontDatabase.applicationFontFamilies(font_id)[0])
    font.setPixelSize(20)
    text = QTextLayout(name, font)
    option = QTextOption()
    option.setWrapMode(QTextOption.WrapAnywhere)
    text.setTextOption(option)
    text.beginLayout()
    height = 0
    width = 0
    while True:
        line = text.createLine()
        if not line.isValid():
            break
        line.setLineWidth(180)
        line.setPosition(QPointF(0, height))
        height += line.height()
        width = max(width, math.ceil(line.naturalTextWidth()))
    text.endLayout()
    image = QImage(width, math.ceil(height), QImage.Format_ARGB32_Premultiplied)
    image.fill(Qt.transparent)
    painter = QPainter(image)
    painter.setPen(Qt.white)
    text.draw(painter, QPointF(0, 0))
    painter.end()
    image = image.convertToFormat(QImage.Format_Alpha8)
    raw = bytes(image.constBits())
    pixels = b''.join(raw[y * image.bytesPerLine():y * image.bytesPerLine() + width]
                      for y in range(image.height()))
    return width, image.height(), pixels


def cover_bitmap(path):
    reader = QImageReader(str(path))
    image = reader.read()
    if image.isNull():
        raise ValueError(f'Cannot read cover {path}: {reader.errorString()}')
    image = image.scaled(120, 160, Qt.KeepAspectRatio, Qt.SmoothTransformation)
    canvas = QImage(120, 160, QImage.Format_RGB888)
    canvas.fill(Qt.white)
    painter = QPainter(canvas)
    painter.drawImage((120 - image.width()) // 2, (160 - image.height()) // 2, image)
    painter.end()
    raw = bytes(canvas.constBits())
    pixels = bytearray()
    for y in range(160):
        for x in range(120):
            offset = y * canvas.bytesPerLine() + x * 3
            r, g, b = raw[offset:offset + 3]
            pixels.extend(struct.pack('<H', ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)))
    return 120, 160, bytes(pixels)


def build_record(name: str, rom: bytes, cover: Path | None) -> bytes:
    encoded = name.encode('utf-8')
    if not encoded or len(encoded) > 63:
        raise ValueError('Game name must contain 1..63 UTF-8 bytes')
    name_w, name_h, bitmap = name_bitmap(name)
    result = bytearray(HEADER.size)

    def append(data):
        result.extend(bytes(-len(result) % 4))
        offset = len(result)
        result.extend(data)
        return offset

    name_off = append(bitmap)
    cover_w = cover_h = cover_off = 0
    if cover is not None:
        cover_w, cover_h, bitmap = cover_bitmap(cover)
        cover_off = append(bitmap)
    rom_off = append(rom)
    result.extend(bytes(-len(result) % 4))
    HEADER.pack_into(result, 0, b'EDG2', 2, 0, len(result), name_w, name_h, name_off,
                     cover_w, cover_h, cover_off, rom_off, len(rom), encoded)
    return bytes(result)


def build_pack(records: list[bytes]) -> bytes:
    result = bytearray(PACK_HEADER.pack(b'EDGP', 2, len(records)) + bytes(4 * len(records)))
    for index, record in enumerate(records):
        result.extend(bytes(-len(result) % 4))
        struct.pack_into('<I', result, PACK_HEADER.size + index * 4, len(result))
        result.extend(record)
    return bytes(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    pack = commands.add_parser('pack')
    pack.add_argument('games', type=Path)
    pack.add_argument('output', type=Path)
    args = parser.parse_args()
    records = []
    for line in args.games.read_text(encoding='utf-8').splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        name, rom, cover = (field.strip() for field in line.split('|'))
        records.append(build_record(name, (ROOT / 'third_party/nes' / rom).read_bytes(),
                                    args.games.parent / cover if cover else None))
    data = build_pack(records)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(data)
    print(f'{len(records)} games, {len(data)} bytes -> {args.output}')


if __name__ == '__main__':
    main()
