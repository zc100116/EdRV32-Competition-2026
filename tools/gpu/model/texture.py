"""texture.py — gpu-spec 2.6: packed mipmaps, palettes and deterministic filtering.
Host integer reference, no clock domain. UV uses eight fractional bits.
"""
from .arithmetic import divide, expand, saturate, shift
from .layout import mip_layout, texel_address


class Texture:
    def __init__(self, ram, palettes, descriptor, numeric):
        self.ram = ram
        self.palettes = palettes
        self.desc = descriptor
        self.numeric = numeric
        self.levels = mip_layout(1 << descriptor['LOG2_W'], 1 << descriptor['LOG2_H'],
                                 descriptor['LEVELS'], descriptor['FORMAT'],
                                 descriptor['OFFSET'])
        self.end = descriptor['OFFSET'] + sum(level[3] for level in self.levels)

    def texel(self, x, y, level, group):
        offset, width, height, _ = self.levels[level]
        format = self.desc['FORMAT']
        address, bit = texel_address(x, y, width, height, format, offset)
        word = int.from_bytes(self.ram[address:address + 2], 'little')
        if format == 2:
            return (*expand(word), 255)
        entry = (word >> bit) & (15 if format == 0 else 255)
        color = self.palettes[group][entry]
        return (*expand(color & 65535), ((color >> 16) & 15) * 17)

    def bilinear(self, u, v, level, group):
        u, v = u >> level, v >> level
        x, y, fx, fy = u >> 8, v >> 8, u & 255, v & 255
        samples = (self.texel(x, y, level, group), self.texel(x + 1, y, level, group),
                   self.texel(x, y + 1, level, group),
                   self.texel(x + 1, y + 1, level, group))
        weights = ((256 - fx) * (256 - fy), fx * (256 - fy),
                   (256 - fx) * fy, fx * fy)
        return tuple(shift(sum(sample[c] * w for sample, w in zip(samples, weights)), 16)
                     for c in range(4))

    def sample(self, u, v, lod, group=None, nearest=False):
        if group is None:
            group = self.desc['PAL_GROUP']
        if nearest:
            return self.texel(u >> 8, v >> 8, 0, group)
        bits = self.numeric.log_frac
        bias = shift(self.desc['LOD_BIAS'], 4 - bits)
        lod = saturate(lod + bias, 0, (len(self.levels) - 1) << bits)
        level = lod >> bits
        mode = self.desc['SAMPLE']
        if mode == 0:
            return self.texel(u >> (8 + level), v >> (8 + level), level, group)
        first = self.bilinear(u, v, level, group)
        if mode == 1 or level == len(self.levels) - 1:
            return first
        second = self.bilinear(u, v, level + 1, group)
        fraction = lod & ((1 << bits) - 1)
        return tuple(divide(a * ((1 << bits) - fraction) + b * fraction, 1 << bits)
                     for a, b in zip(first, second))
