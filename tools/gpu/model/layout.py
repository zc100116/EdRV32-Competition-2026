"""layout.py — gpu-spec 2.6 amendment, microarch 7ed45f8e9 section 4.8.
Offline four-bank texture interleaving and the exact physical address formula.
Host Python utility, no clock domain; each mip reserves complete 2x2 halfword groups.
"""


def mip_layout(width, height, levels, format, offset=0):
    block_width, block_height = ((2, 2), (2, 1), (1, 1))[format]
    result = []
    for level in range(levels):
        w, h = max(1, width >> level), max(1, height >> level)
        bx = (w + block_width - 1) // block_width
        by = (h + block_height - 1) // block_height
        size = 8 * ((bx + 1) // 2) * ((by + 1) // 2)
        result.append((offset, w, h, size))
        offset += size
    return result


def texel_address(u, v, width, height, format, base):
    u, v = u % width, v % height
    bw, bh = ((2, 2), (2, 1), (1, 1))[format]
    bx, by = u // bw, v // bh
    blocks_x = (width + bw - 1) // bw
    halfword = base // 2 + 4 * ((by // 2) * ((blocks_x + 1) // 2) + bx // 2)
    halfword += (bx & 1) + 2 * (by & 1)
    shift = (4 * ((u & 1) + 2 * (v & 1)), 8 * (u & 1), 0)[format]
    return halfword * 2, shift


def interleave_texture(levels, width, height, format):
    """Convert row-major integer texels into the physical TEX_LOAD byte stream."""
    layout = mip_layout(width, height, len(levels), format)
    size = sum(item[3] for item in layout)
    data = bytearray(size)
    for texels, (base, w, h, _) in zip(levels, layout):
        for v in range(h):
            for u in range(w):
                address, bit = texel_address(u, v, w, h, format, base)
                word = int.from_bytes(data[address:address + 2], 'little')
                word |= texels[v * w + u] << bit
                data[address:address + 2] = word.to_bytes(2, 'little')
    return bytes(data)
