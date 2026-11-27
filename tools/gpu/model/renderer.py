"""renderer.py — gpu-spec 2–6 serial functional GPU reference.
Integer geometry, scan conversion, pixel operations, objects and resolve.
Host execution, no clock domain; cycle counters are outside this functional model.
"""
from array import array
import struct

from ..scene import SCHEMA, LAYOUTS, OPCODES, BusError, pack, unpack
from .arithmetic import (CLIP_BITS, CLIP_FRAC, GUARD, RECIPROCAL_FRAC, W_NEAR,
                         d, divide, edge, expand, logarithm, p565, reciprocal, saturate,
                         shift, signed, top_left)
from .texture import Texture
from .planes import PixelArithmetic


OBJECT_UPDATE_MASK = sum(((1 << field['width']) - 1)
                         << (int(field['offset'], 0) * 8 + field['lsb'])
                         for field in LAYOUTS['OBJ']['fields']
                         if field['name'] in ('ALIVE', 'PX', 'PY', 'VX', 'VY', 'LIFE'))


class GPUError(Exception):
    def __init__(self, code):
        self.code = code
        super().__init__(f'GPU ERR_CODE={code}')


class GPU:
    _pixel_arithmetic = PixelArithmetic

    def __init__(self, memory, reference_size=None):
        self.memory = memory
        self.regs = {}
        self.register_names = {}
        self.register_access = {}
        self.register_masks = {}
        for item in SCHEMA['registers']:
            dimensions = item['dimensions']
            count = dimensions[0]['count'] if dimensions else 1
            stride = dimensions[0]['stride'] if dimensions else 0
            for index in range(count):
                name = item['name'] + (f'[{index}]' if dimensions else '')
                self.regs[name] = item['reset']
                self.register_names[int(item['offset'], 0) + stride * index] = name
                self.register_access[name] = item['access']
                fields = item['fields']
                self.register_masks[name] = (sum(((1 << field['width']) - 1) << field['lsb']
                                                 for field in fields) if fields else 0xffffffff)
        self.width, self.height = reference_size if reference_size else (640, 180)
        pixels = self.width * self.height
        self.color = array('H', [0]) * pixels
        self.depth = array('H', [0]) * pixels
        self.stencil = bytearray(pixels)
        self.ram = bytearray(192 * 1024)
        self.palettes = [[0] * 256 for _ in range(16)]

    def perf(self, index, count=1):
        name = f'PERF[{index}]'
        self.regs[name] = (self.regs[name] + count) & 0xffffffff

    def write_register(self, name, value):
        if isinstance(name, int):
            name = self.register_names[name]
        access = self.register_access[name]
        value &= self.register_masks[name]
        if access == 'RO':
            return
        if access == 'RW1C':
            self.regs[name] &= ~value
        elif name == 'DOORBELL':
            self.run()
        elif name == 'CTRL':
            self.regs[name] = value & 1
            if value & 8:
                self.__init__(self.memory)
        else:
            self.regs[name] = value & 0xffffffff
            if name == 'TGT_CFG':
                self.width, self.height = (1280, 90) if value & 1 else (640, 180)

    def execute(self, writes):
        """Apply ordered (register name or offset, value) writes; DOORBELL runs synchronously."""
        for name, value in writes:
            self.write_register(name, value)
        return self

    def run(self, commands=None):
        """Execute DDR DESC_BASE/COUNT, or an explicitly supplied list of encoded commands."""
        self.regs['STATUS'] = 1
        try:
            if commands is None:
                for index in range(self.regs['DESC_COUNT']):
                    data = self.memory.read(self.regs['DESC_BASE'] + index * 32, 32)
                    self.command(data)
            else:
                for data in commands:
                    self.command(data)
        except BusError:
            self.error(2)
            return self
        except GPUError as error:
            self.error(error.code)
            return self
        self.regs['STATUS'] = 2
        self.regs['DONE_COUNT'] = (self.regs['DONE_COUNT'] + 1) & 0xffffffff
        self.regs['IRQ_STAT'] |= 1
        return self

    def error(self, code):
        self.regs['STATUS'] = 6
        self.regs['ERR_CODE'] = code
        self.regs['IRQ_STAT'] |= 2

    def command(self, data):
        opcode = data[0]
        names = {value: name for name, value in OPCODES.items()}
        if opcode not in names:
            raise GPUError(1)
        name = names[opcode]
        fields = unpack('CMD_' + name, data)
        if name == 'SET_MATRIX':
            self.matrix = struct.unpack('<16i', self.memory.read(fields['ADDR'], 64))
        elif name == 'SET_LIGHT':
            self.light = fields
        elif name == 'SET_TEX':
            texture = Texture(self.ram, self.palettes, fields)
            if texture.end > len(self.ram):
                raise GPUError(3)
            self.texture = texture
        elif name == 'SET_PIXEL':
            self.pixel_state = fields
        elif name == 'SET_TARGET':
            self.target = fields
        elif name == 'CLEAR':
            self.clear(fields)
        elif name == 'DRAW_TRI':
            for index in range(fields['COUNT']):
                vertices = [unpack('VERTEX', self.memory.read(
                    fields['ADDR'] + (index * 3 + vertex) * 16, 16)) for vertex in range(3)]
                self.draw_triangle(vertices)
        elif name == 'DRAW_QUAD':
            for index in range(fields['COUNT']):
                self.quad(unpack('QUAD', self.memory.read(fields['ADDR'] + index * 16, 16)))
        elif name == 'OBJ_STEP':
            self.objects(fields)
        elif name == 'TEX_LOAD':
            start, size = fields['DST'], fields['BYTES']
            if start + size > len(self.ram):
                raise GPUError(4)
            self.ram[start:start + size] = self.memory.read(fields['SRC'], size)
        elif name == 'PAL_LOAD':
            for index in range(fields['ENTRIES']):
                value = self.memory.read(fields['SRC'] + 4 * index, 4)
                self.palettes[fields['GROUP']][index] = int.from_bytes(value, 'little')
        elif name == 'RESOLVE':
            self.resolve(fields)

    def bounds(self):
        target = self.target
        return (max(target['SC_X0'], target['TGT_X0']),
                max(target['SC_Y0'], target['TGT_Y0']),
                min(target['SC_X1'], target['TGT_X0'] + self.width),
                min(target['SC_Y1'], target['TGT_Y0'] + self.height))

    def address(self, x, y):
        return (y - self.target['TGT_Y0']) * self.width + x - self.target['TGT_X0']

    def clear(self, fields):
        x0, y0, x1, y1 = self.bounds()
        for y in range(y0, y1):
            for x in range(x0, x1):
                index = self.address(x, y)
                if fields['EN_COLOR']:
                    self.color[index] = fields['COLOR']
                if fields['EN_DEPTH']:
                    self.depth[index] = fields['DEPTH']
                if fields['EN_STENCIL']:
                    self.stencil[index] = fields['STENCIL']

    def stencil_op(self, index, operation):
        state = self.pixel_state
        old = self.stencil[index]
        value = (old, 0, state['ST_REF'], min(255, old + 1), max(0, old - 1),
                 old ^ 255)[operation]
        mask = state['ST_WMASK']
        self.stencil[index] = (old & (255 ^ mask)) | (value & mask)

    def pixel(self, x, y, depth, rgba, transparent=False):
        # Bounds are checked before shading in the rasterizer/quad loops.
        if transparent:
            return
        index = self.address(x, y)
        state = self.pixel_state
        ref = state['ST_REF'] & state['ST_RMASK']
        stencil = self.stencil[index] & state['ST_RMASK']
        test = (False, ref < stencil, ref == stencil, ref <= stencil,
                ref > stencil, ref != stencil, ref >= stencil, True)[state['ST_FUNC']]
        if not test:
            self.stencil_op(index, state['ST_SFAIL'])
            return
        if state['DEPTH_FUNC'] == 0 and depth > self.depth[index]:
            self.stencil_op(index, state['ST_ZFAIL'])
            return
        self.perf(4)
        self.stencil_op(index, state['ST_ZPASS'])
        if state['DEPTH_WRITE']:
            self.depth[index] = depth
        if state['COLOR_WRITE']:
            destination = expand(self.color[index])
            output = []
            for source, dest in zip(rgba[:3], destination):
                factors = (0, 255, rgba[3], 255 - rgba[3], source, 255 - source,
                           dest, 255 - dest, state['BL_CONST_A'], 255 - state['BL_CONST_A'])
                a = d(source * factors[state['BL_FS']])
                b = d(dest * factors[state['BL_FD']])
                value = (a + b, a - b, b - a, min(a, b), max(a, b))[state['BL_OP']]
                output.append(saturate(value, 0, 255))
            self.color[index] = p565(output)

    def quad(self, quad):
        self.perf(3)
        x0, y0, x1, y1 = self.bounds()
        for y in range(max(y0, quad['Y']), min(y1, quad['Y'] + quad['H'])):
            row = y - quad['Y']
            if quad['FLIP_V']:
                row = quad['H'] - 1 - row
            for group in range((max(x0, quad['X']) // 4) * 4,
                               min(x1, quad['X'] + quad['W']), 4):
                for x in range(max(group, x0, quad['X']),
                               min(group + 4, x1, quad['X'] + quad['W'])):
                    column = x - quad['X']
                    if quad['FLIP_H']:
                        column = quad['W'] - 1 - column
                    rgba = self.texture.sample((quad['U0'] + column) << 8,
                                               (quad['V0'] + row) << 8, 0,
                                               quad['PAL_GROUP'], nearest=True)
                    self.pixel(x, y, quad['DEPTH'], (*rgba[:3], d(rgba[3] * quad['ALPHA'])),
                               transparent=rgba[3] == 0)

    def transform(self, vertex):
        position = [vertex[name] for name in ('X', 'Y', 'Z')] + [1]
        coords = []
        for row in range(4):
            products = [self.matrix[row * 4 + column]
                        * position[column] for column in range(4)]
            value = sum(products)
            coords.append(saturate(value, -(1 << (CLIP_BITS - 1)),
                                   (1 << (CLIP_BITS - 1)) - 1))
        light = self.light
        dot = max(0, sum(vertex[n] * light[l] for n, l in
                         zip(('NX', 'NY', 'NZ'), ('LX', 'LY', 'LZ'))))
        colors = []
        for channel, bit in zip(expand(vertex['COLOR']), (16, 8, 0)):
            ambient = (light['AMB_RGB'] >> bit) & 255
            directional = (light['DIR_RGB'] >> bit) & 255
            illumination = (ambient << 21) + dot * directional
            value = divide(channel * illumination, 255 << 21)
            colors.append(saturate(value, 0, 255) << 16)
        return coords + [vertex['U'], vertex['V']] + colors

    def clip(self, polygon):
        near, guard = W_NEAR, GUARD
        planes = (lambda v: v[3] - near, lambda v: guard * v[3] + v[0],
                  lambda v: guard * v[3] - v[0], lambda v: guard * v[3] + v[1],
                  lambda v: guard * v[3] - v[1])
        for distance in planes:
            result = []
            if not polygon:
                break
            previous = polygon[-1]
            dp = distance(previous)
            for current in polygon:
                dc = distance(current)
                if (dp >= 0) != (dc >= 0):
                    # Symmetric intersection is independent of traversal direction.
                    result.append([divide(a * dc - b * dp, dc - dp)
                                   for a, b in zip(previous, current)])
                if dc >= 0:
                    result.append(current)
                previous, dp = current, dc
            polygon = result
        return polygon

    def project(self, vertex):
        q = reciprocal(vertex[3], CLIP_FRAC)
        scale = 1 << (CLIP_FRAC + RECIPROCAL_FRAC)
        vx, vy, width, height = (self.target[name] for name in
                                 ('VP_X0', 'VP_Y0', 'VP_W', 'VP_H'))
        x = vx * 16 + divide((vertex[0] * q + scale) * width * 8, scale)
        y = vy * 16 + divide((scale - vertex[1] * q) * height * 8, scale)
        x, y = saturate(x, -65536, 65535), saturate(y, -65536, 65535)
        depth = saturate(divide(vertex[2] * q * 65535, scale), 0, 65535)
        return [x, y, depth, q, vertex[4] * q, vertex[5] * q] + vertex[6:]

    def draw_triangle(self, vertices):
        self.perf(1, 3)
        polygon = self.clip([self.transform(vertex) for vertex in vertices])
        if len(polygon) < 3:
            return
        screen = [self.project(vertex) for vertex in polygon]
        for index in range(1, len(screen) - 1):
            self.triangle([screen[0], screen[index], screen[index + 1]])

    def triangle(self, vertices):
        for x, y, depth, u, v, lod, colors in self.fragments(vertices):
            texel = self.texture.sample(u, v, lod)
            rgba = tuple(d(t * color) for t, color in zip(texel[:3], colors))
            self.pixel(x, y, depth, (*rgba, texel[3]), transparent=texel[3] == 0)

    def fragments(self, vertices):
        """Rasterize [xQ4,yQ4,depthU16,qQF,uQ8*q,vQ8*q,rQ16,gQ16,bQ16]."""
        a, b, c = vertices
        area = edge(a, b, c[0], c[1])
        cull = self.pixel_state['CULL']
        if area == 0 or (cull == 1 and area > 0) or (cull == 2 and area < 0):
            return
        if area < 0:
            b, c = c, b
            area = -area
        self.perf(2)
        x0, y0, x1, y1 = self.bounds()
        x0 = max(x0, (min(a[0], b[0], c[0]) - 8 + 15) // 16)
        y0 = max(y0, (min(a[1], b[1], c[1]) - 8 + 15) // 16)
        x1 = min(x1, (max(a[0], b[0], c[0]) - 8) // 16 + 1)
        y1 = min(y1, (max(a[1], b[1], c[1]) - 8) // 16 + 1)
        edges = ((b, c), (c, a), (a, b))
        inclusive = [top_left(start, end) for start, end in edges]
        arithmetic = self._pixel_arithmetic((a, b, c), area, self.bounds())
        # P-A origin belongs to SC intersect TGT; no step is rounded.
        row = arithmetic.at(x0, y0)
        quad_row = None
        lod_cache = {}
        for y in range(y0, y1):
            if quad_row != y // 2:
                lod_cache.clear()
                quad_row = y // 2
            attrs = row.copy()
            for group in range((x0 // 4) * 4, x1, 4):
                for x in range(max(x0, group), min(group + 4, x1)):
                    weights = [edge(start, end, x * 16 + 8, y * 16 + 8)
                               for start, end in edges]
                    covered = all(value > 0 or (value == 0 and include)
                                  for value, include in zip(weights, inclusive))
                    if covered:
                        depth, u, v, lod, colors = arithmetic.shade(attrs)
                        if arithmetic.LOD_QUAD:
                            key = x // 2
                            if key not in lod_cache:
                                span = arithmetic.quad_span(x, y)
                                lod_cache[key] = logarithm(span) if span else 0
                            lod = lod_cache[key]
                        yield x, y, depth, u, v, lod, colors
                    attrs = [value + coeff[1] for value, coeff in
                             zip(attrs, arithmetic.coefficients)]
            row = [value + coeff[2] for value, coeff in zip(row, arithmetic.coefficients)]

    def register_rect(self, first, second):
        return (signed(self.regs[first], 16), signed(self.regs[first] >> 16, 16),
                signed(self.regs[second], 16), signed(self.regs[second] >> 16, 16))

    def objects(self, fields):
        counts = {'HIT': 0, 'FREE': 0, 'ALIVE': 0}
        self.regs['OBJ_STAT'] = 0
        live = self.register_rect('OBJ_LIVE_RECT0', 'OBJ_LIVE_RECT1')
        targets = [self.register_rect(f'OBJ_TGT0[{index}]', f'OBJ_TGT1[{index}]')
                   for index in range(8)]
        for index in range(fields['COUNT']):
            address = fields['ADDR'] + index * 32
            original = self.memory.read(address, 32)
            obj = unpack('OBJ', original)
            if not obj['ALIVE']:
                continue
            if not fields['STEP']:
                counts['ALIVE'] += 1
                if fields['DRAW']:
                    self.object_quad(obj)
                continue
            for axis in ('X', 'Y'):
                obj['V' + axis] = signed(obj['V' + axis] + shift(obj['A' + axis], 4), 16)
                obj['P' + axis] = signed(obj['P' + axis] + obj['V' + axis], 24)
            if obj['LIFE']:
                obj['LIFE'] -= 1
                if obj['LIFE'] == 0:
                    obj['ALIVE'] = 0
            px, py = obj['PX'], obj['PY']
            collision_x, collision_y = px // 256, py // 256
            if not (live[0] * 256 <= px < live[2] * 256
                    and live[1] * 256 <= py < live[3] * 256):
                obj['ALIVE'] = 0
            if obj['ALIVE']:
                counts['ALIVE'] += 1
                for target, rect in enumerate(targets):
                    if (obj['TGT_MASK'] & (1 << target)
                            and collision_x + obj['COL_HW'] > rect[0]
                            and collision_x - obj['COL_HW'] < rect[2]
                            and collision_y + obj['COL_HH'] > rect[1]
                            and collision_y - obj['COL_HH'] < rect[3]):
                        self.append_list('HIT', counts['HIT'], index | (target << 24))
                        counts['HIT'] += 1
            else:
                self.append_list('FREE', counts['FREE'], index)
                counts['FREE'] += 1
            old = int.from_bytes(original, 'little')
            updated = int.from_bytes(pack('OBJ', **obj), 'little')
            updated = (old & ~OBJECT_UPDATE_MASK) | (updated & OBJECT_UPDATE_MASK)
            self.memory.write(address, updated.to_bytes(32, 'little'))
            if fields['DRAW'] and obj['ALIVE']:
                self.object_quad(obj)
        for name, count in counts.items():
            self.regs[f'OBJ_{name}_COUNT'] = count & 0xffffff

    def object_quad(self, obj):
        quad = {key: obj[key] for key in ('W', 'H', 'U0', 'V0', 'FLIP_H', 'FLIP_V',
                                         'PAL_GROUP', 'ALPHA', 'DEPTH')}
        quad.update(X=obj['PX'] // 256 - obj['W'] // 2,
                    Y=obj['PY'] // 256 - obj['H'] // 2)
        self.quad(quad)

    def append_list(self, kind, index, value):
        if index < self.regs[f'OBJ_{kind}_MAX']:
            address = self.regs[f'OBJ_{kind}_BASE'] + 4 * index
            self.memory.write(address, struct.pack('<I', value))
        else:
            self.regs['OBJ_STAT'] |= 1 if kind == 'HIT' else 2

    def resolve(self, fields):
        x0, y0, x1, y1 = (fields[name] for name in ('X0', 'Y0', 'X1', 'Y1'))
        for y in range(y0, y1):
            row = bytearray()
            for x in range(x0, x1):
                color = self.color[self.address(x, y)]
                if fields['FXAA']:
                    coords = ((x, y), (x, max(y0, y - 1)), (x, min(y1 - 1, y + 1)),
                              (max(x0, x - 1), y), (min(x1 - 1, x + 1), y))
                    samples = [expand(self.color[self.address(*point)]) for point in coords]
                    luminances = [(r + 2 * g + b) >> 2 for r, g, b in samples]
                    if max(luminances) - min(luminances) >= fields['FXAA_TH']:
                        _, n, s, w, e = luminances
                        left, right = (1, 2) if abs(n - s) >= abs(w - e) else (3, 4)
                        color = p565(tuple((2 * samples[0][c] + samples[left][c]
                                            + samples[right][c]) >> 2 for c in range(3)))
                row.extend(struct.pack('<H', color))
            self.memory.write(fields['BASE'] + y * fields['STRIDE'] + x0 * 2, row)
