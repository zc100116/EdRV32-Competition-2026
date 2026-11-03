"""processing.py — P5 frozen interface 8.3, full PIX/GEO parameter block.
Board STATE is authoritative; pending edits are sent as one PROCESS command.
"""
import struct

PROCESS_BLOCK = struct.Struct('<IhHHBBBBhHhhH')
DEFAULTS = dict(enabled=0, brightness=0, contrast=256, gamma_tenths=10,
                stage1=2, stage2=2, threshold=128, view=0, angle=0,
                scale_percent=100, translate_x=0, translate_y=0)
ITEMS = (
    ('亮度 / 对比度', ('brightness', 'contrast')),
    ('伽马', ('gamma_tenths',)), ('第一级滤波 S1', ('stage1',)),
    ('第二级滤波 S2', ('stage2',)), ('灰度', ()), ('二值化', ('threshold',)),
    ('反色', ()), ('旋转', ('angle',)), ('缩放', ('scale_percent',)),
    ('平移', ('translate_x', 'translate_y')), ('水平镜像', ()), ('垂直镜像', ()),
)
RANGES = dict(enabled=(0, 4095), brightness=(-256, 255), contrast=(0, 512),
              gamma_tenths=(3, 30), stage1=(1, 6), stage2=(1, 6), threshold=(0, 255),
              view=(0, 1), angle=(-180, 180), scale_percent=(50, 400),
              translate_x=(-1280, 1280), translate_y=(-720, 720))


def pack_process(values):
    for key, value in values.items():
        low, high = RANGES[key]
        if type(value) is not int or not low <= value <= high:
            raise ValueError(f'PROCESS {key} must be {low}..{high}')
    return PROCESS_BLOCK.pack(*(values[key] for key in DEFAULTS), 0)


def unpack_process(payload):
    return dict(zip(DEFAULTS, PROCESS_BLOCK.unpack(payload)[:-1]))


class ProcessingControl:
    def __init__(self, engine):
        self.engine = engine

    def send(self, values):
        from .showcase import PROCESS
        state = dict(self.status(), **values)
        result = self.engine.ethernet.showcase.command(PROCESS, pack_process(state))
        return dict(queued=result.get('queued', False), seq=result.get('seq'))

    def defaults(self, bit=None):
        values = self.status()
        if bit is None:
            values = dict(DEFAULTS)
        else:
            for key in ITEMS[bit][1]:
                values[key] = DEFAULTS[key]
        return self.send(values)

    def status(self):
        return dict(self.engine.board.board_state['process'])
