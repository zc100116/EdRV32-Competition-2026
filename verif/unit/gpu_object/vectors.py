#!/usr/bin/env python3
"""gpu-spec 2.9: model-derived object stream expectations; fixed seed 303."""
import random
from pathlib import Path

from tools.gpu.model import GPU
from tools.gpu.scene import LAYOUTS, Memory, pack, unpack


class ObjectReference(GPU):
    def __init__(self, memory):
        super().__init__(memory, reference_size=(1, 1))
        self.quads = []

    def quad(self, fields):
        self.quads.append(fields.copy())


def rectangle(rect):
    return sum((value & 0xffff) << (16 * axis) for axis, value in enumerate(rect))


def generate(out):
    rng = random.Random(303)
    fields_mask = sum(((1 << f['width']) - 1) << (int(f['offset'], 0) * 8 + f['lsb'])
                      for f in LAYOUTS['OBJ']['fields'])
    records, updates, events, quads, positions, configs = [], [], [], [], [], []
    default = dict(ALIVE=1, TGT_MASK=255, LIFE=0, PX=0, PY=0, VX=0, VY=0,
                   AX=0, AY=0, COL_HW=5, COL_HH=7, W=17, H=19, PAL_GROUP=13,
                   FLIP_H=1, FLIP_V=1, ALPHA=173, U0=233, V0=197, DEPTH=0xbeef)
    live = (-32768, -32768, 32767, 32767)
    targets = [(-4, -6, 4, 6)] * 8

    def obj(**changes):
        return {**default, **changes}

    def case(name, objects, step=1, draw=1, area=live, boxes=targets,
             hit_max=0xffffff, free_max=0xffffff, stall=0, throughput=0):
        start = len(records)
        raw = [int.from_bytes(pack('OBJ', **o), 'little') |
               (rng.getrandbits(256) & ~fields_mask) for o in objects]
        memory = Memory(0, bytes(0x40000))
        for index, value in enumerate(raw):
            memory.write(32 * index, value.to_bytes(32, 'little'))
        gpu = ObjectReference(memory)
        gpu.regs.update(OBJ_LIVE_RECT0=rectangle(area) & 0xffffffff,
                        OBJ_LIVE_RECT1=rectangle(area) >> 32, OBJ_HIT_BASE=0x10000,
                        OBJ_FREE_BASE=0x30000, OBJ_HIT_MAX=hit_max, OBJ_FREE_MAX=free_max)
        for k, box in enumerate(boxes):
            gpu.regs[f'OBJ_TGT0[{k}]'] = rectangle(box) & 0xffffffff
            gpu.regs[f'OBJ_TGT1[{k}]'] = rectangle(box) >> 32
        gpu.objects(dict(COUNT=len(raw), ADDR=0, STEP=step, DRAW=draw))
        # A second capacity-unlimited model exposes every hit event, including overflow.
        all_gpu = ObjectReference(Memory(0, bytes(0x40000)))
        all_gpu.memory.data[:] = bytes(0x40000)
        for index, value in enumerate(raw):
            all_gpu.memory.write(32 * index, value.to_bytes(32, 'little'))
        all_gpu.regs.update(gpu.regs)
        all_gpu.regs.update(OBJ_HIT_MAX=0xffffff, OBJ_FREE_MAX=0xffffff)
        all_gpu.objects(dict(COUNT=len(raw), ADDR=0, STEP=step, DRAW=draw))
        masks = [0] * len(raw)
        for k in range(all_gpu.regs['OBJ_HIT_COUNT']):
            entry = int.from_bytes(all_gpu.memory.read(0x10000 + k * 4, 4), 'little')
            masks[entry & 0xffffff] |= 1 << (entry >> 24)
        quad_index = 0
        for index, original in enumerate(raw):
            updated = int.from_bytes(memory.read(index * 32, 32), 'little')
            alive = (updated if step else original) & 1
            free = bool(step and (original & 1) and not alive)
            update = bool(step and original & 1)
            quad = bool(draw and alive)
            qdata = 0
            qpos = 0
            if quad:
                fields = gpu.quads[quad_index]
                quad_index += 1
                qpos = (fields['X'] & 0x1ffff) | ((fields['Y'] & 0x1ffff) << 17)
                qdata = int.from_bytes(pack('QUAD', **{**fields, 'X': 0, 'Y': 0}), 'little')
            records.append(original)
            updates.append(updated)
            events.append(masks[index] | (free << 8) | (update << 9) |
                          (quad << 10) | (alive << 11))
            quads.append(qdata)
            positions.append(qpos)
        value = rectangle(area) | (sum(rectangle(b) << (64 * k) for k, b in
                                     enumerate(boxes)) << 64)
        for bit, number in [(576, hit_max), (600, free_max), (624, step), (625, draw),
                            (626, len(raw)), (650, start),
                            (674, gpu.regs['OBJ_HIT_COUNT']),
                            (698, gpu.regs['OBJ_FREE_COUNT']),
                            (722, gpu.regs['OBJ_ALIVE_COUNT']),
                            (746, gpu.regs['OBJ_STAT']), (748, stall), (749, throughput)]:
            value |= number << bit
        configs.append(value)
        print(f'vector {len(configs)-1}: {name}, {len(raw)} objects')

    case('advance rounding ties velocity and position wrap', [
        obj(AX=a, AY=-a, VX=v, VY=-v, PX=p, PY=-p)
        for a in [0, 7, 8, 9, 15, 16, 24, 32767, -32768]
        for v, p in [(0, 0), (32767, 8388607), (-32768, -8388608)]])
    case('lifetime and region invalidation before collisions', [
        obj(LIFE=1), obj(LIFE=2), obj(LIFE=0), obj(PX=10*256),
        obj(PX=-10*256), obj(PY=10*256), obj(PY=-10*256),
        obj(ALIVE=0, LIFE=1), obj(PX=-10*256-1), obj(PY=-10*256-1)],
        area=(-10, -10, 10, 10), hit_max=1, free_max=1)
    boxes = [(-5, -7, 5, 7), (5, -7, 10, 7), (-10, -7, -5, 7),
             (-5, 7, 5, 10), (-5, -10, 5, -7), (4, 6, 6, 8),
             (6, -7, 10, 7), (-5, 8, 5, 10)]
    case('eight half-open targets touching and one-unit gaps',
         [obj(TGT_MASK=mask) for mask in [255, 0] + [1 << k for k in range(8)]], boxes=boxes)
    case('negative floor odd quad size s17 positions',
         [obj(PX=p, PY=p, W=511, H=509) for p in [-8388608, -257, -256, -1, 0, 255, 8388352]],
         step=0)
    case('step zero bypass live life motion lists',
         [obj(LIFE=1, AX=32767, PX=500*256), obj(ALIVE=0), obj()],
         step=0, area=(1, 1, 2, 2), hit_max=0, free_max=0, stall=1)
    case('step zero draw disabled', [obj(), obj(ALIVE=0)], step=0, draw=0)
    case('step one draw disabled', [obj(), obj(LIFE=1), obj(ALIVE=0)], draw=0)
    case('zero capacity and eight hits per beat', [obj()] * 64, hit_max=0, free_max=0,
         throughput=1)
    case('exact capacity does not overflow', [obj(), obj(), obj(LIFE=1)],
         hit_max=16, free_max=1)
    case('free overflow', [obj(LIFE=1)] * 32, hit_max=0, free_max=3)
    case('all output streams continuous II1', [obj() for _ in range(256)], throughput=1)
    case('independent backpressure and randomized records', [obj(
        ALIVE=rng.randrange(2), LIFE=rng.choice([0, 1, 2, 65535]),
        PX=rng.randrange(-8388608, 8388608), PY=rng.randrange(-8388608, 8388608),
        VX=rng.randrange(-32768, 32768), VY=rng.randrange(-32768, 32768),
        AX=rng.randrange(-32768, 32768), AY=rng.randrange(-32768, 32768),
        TGT_MASK=rng.randrange(256), COL_HW=rng.randrange(256), COL_HH=rng.randrange(256),
        W=rng.randrange(1, 512), H=rng.randrange(1, 512), ALPHA=rng.randrange(256))
        for _ in range(1024)], stall=1, hit_max=11, free_max=13)
    case('backpressured live collisions', [obj(PX=(k % 9-4)*256, LIFE=k % 3,
         TGT_MASK=(k*31)&255) for k in range(128)], stall=1, hit_max=17, free_max=5)
    case('empty command', [])
    case('empty step zero command', [], step=0)
    for name, values, digits in [('records', records, 64), ('updates', updates, 64),
                                 ('events', events, 3), ('quads', quads, 32),
                                 ('positions', positions, 9), ('configs', configs, 192)]:
        (out / f'{name}.hex').write_text(''.join(f'{v:0{digits}x}\n' for v in values))
    (out / 'sizes.svh').write_text(f'localparam CASES = {len(configs)};\n'
                                  f'localparam RECORDS = {len(records)};\n')
