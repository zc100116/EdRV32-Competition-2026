"""pipeline.py — vision pipeline design 7.1/7.3, host clock domain.
Encode frozen chain blocks and explain board validation failures in Chinese.
"""
import copy
import struct

BLOCK = struct.Struct('<BB5h')
NAMES = ('', '亮度 / 对比度', '伽马', '滤波', '灰度', '二值化', '反色', '几何', '检测', '叠加')
FILTERS = ('均值', '高斯', '锐化', 'Sobel', '腐蚀', '膨胀')
PRESETS = ('标准识别', '边缘识别', '旋转识别', '局部放大', '整屏旋转',
           '夜视增强', '多级滤波', 'PC 图片')
ENGINES = ('摄像头 → PIX · 融合', '摄像头 → DDR', '内存源 → PIX',
           '内存源 → NPU', 'GEO · 几何', 'RND · 叠加')
PARAMS = {
    1: (('亮度', -256, 255), ('对比度 Q8', 0, 512)),
    2: (('伽马 × 10', 3, 30),), 3: (('滤波', 1, 6),),
    5: (('阈值', 0, 255),),
    7: (('角度 °', -180, 180), ('缩放 %', 50, 400),
        ('水平平移', -1280, 1280), ('垂直平移', -720, 720)),
}


def block(kind, flags=0, p=None):
    values = {1: [0, 256], 2: [10], 3: [2], 5: [128], 7: [0, 100]}
    params = list(values.get(kind, []) if p is None else p)
    return dict(type=kind, flags=flags, p=params + [0] * (5 - len(params)))


def preset(number):
    detect, overlay = block(8), block(9, 1)
    chains = [
        [detect, overlay],
        [block(4), block(3, p=[4]), detect, overlay],
        [block(7, p=[90, 100]), detect, overlay],
        [block(7, p=[0, 200, -320, -180]), detect, overlay],
        [detect, block(9, 3), block(7, p=[30, 80])],
        [block(2, p=[16]), block(1, p=[0, 320]), block(3), detect, overlay],
        [block(3), block(3, p=[4]), block(5), block(3, p=[6]), block(3)],
        [detect, overlay],
    ]
    if not 1 <= number <= 8:
        raise ValueError('预设必须为 1–8')
    return copy.deepcopy(dict(source=int(number == 8), view=255, preset=number,
                              blocks=chains[number - 1]))


def pack_chain(chain):
    blocks = chain['blocks']
    return (struct.pack('<4B', chain['source'], len(blocks), chain['view'], chain['preset'])
            + b''.join(BLOCK.pack(b['type'], b['flags'], *b['p']) for b in blocks)
            + bytes(max(0, 8 - len(blocks)) * 12))


def unpack_chain(data):
    source, count, view, selected = struct.unpack_from('<4B', data)
    blocks = []
    for k in range(count):
        kind, flags, *params = BLOCK.unpack_from(data, 4 + 12 * k)
        blocks.append(dict(type=kind, flags=flags, p=params))
    return dict(source=source, view=view, preset=selected, blocks=blocks)


def chain_error(data):
    """Only the frozen 7.1 boundary rules; rejected chains are never corrected."""
    if len(data) != 100:
        return 1, '积木链长度必须为 100 字节'
    source, count, view, selected = data[:4]
    if source > 2 or count > 8 or selected > 8:
        return 2, '来源为摄像头、PC 图片或测试图；积木最多 8 块；预设为 0–8'
    if view not in (254, 255) and view >= count:
        return 2, '查看的积木必须在当前链内，或选择来源原图 / 最终输出'
    if any(data[4 + 12 * count:]):
        return 2, '未使用的积木字段必须为 0'
    seen = False
    for index, item in enumerate(unpack_chain(data)['blocks']):
        kind, flags, params = item['type'], item['flags'], item['p']
        prefix = f'第 {index + 1} 块：'
        if not 1 <= kind <= 9:
            return 2, prefix + '积木类型必须为 1–9'
        if (kind not in (7, 9) and flags) or (kind in (7, 9) and flags & ~3):
            return 2, prefix + '未使用的标志位必须为 0'
        fields = PARAMS.get(kind, ())
        for value, (name, low, high) in zip(params, fields):
            if not low <= value <= high:
                return 2, prefix + f'{name}必须为 {low}…{high}'
        if any(params[len(fields):]):
            return 2, prefix + '未使用的参数必须为 0'
        if kind == 8:
            if seen:
                return 2, prefix + '检测最多 1 块，因为 NPU 只有一个'
            seen = True
        if kind == 9:
            if not flags:
                return 2, prefix + '叠加必须选择检测框或界面'
            if flags & 1 and not seen:
                return 2, prefix + '叠加检测框之前必须有检测积木'
    return 0, ''


def pack_stats(stats):
    hops = stats['hops']
    return (struct.pack('<5IB3x', *(stats[k] for k in
            ('fps', 'e2e_us', 'box_lag_us', 'npu_us', 'ddr_mbps')), len(hops))
            + b''.join(struct.pack('<4BI', h['engine'], h['first'], h['last'], 0, h['us'])
                       for h in hops))


def unpack_stats(data):
    if len(data) < 24 or len(data) != 24 + 8 * data[20] or data[20] > 12:
        raise ValueError('PIPE_STATS 跳数或长度不符')
    stats = dict(zip(('fps', 'e2e_us', 'box_lag_us', 'npu_us', 'ddr_mbps'),
                     struct.unpack_from('<5I', data)))
    stats['hops'] = [dict(zip(('engine', 'first', 'last', 'us'),
                            struct.unpack_from('<BBBxI', data, 24 + 8 * i)))
                     for i in range(data[20])]
    return stats


class PipelineControl:
    def __init__(self, engine):
        self.engine = engine

    def status(self):
        return copy.deepcopy(self.engine.board.chain)

    def send(self, chain):
        from .showcase import CHAIN
        result = self.engine.ethernet.showcase.command(CHAIN, pack_chain(chain))
        return dict(seq=result['seq'])

    def preset(self, number):
        from .showcase import PRESET
        result = self.engine.ethernet.showcase.command(PRESET, struct.pack('<B3x', number))
        return dict(seq=result['seq'])
