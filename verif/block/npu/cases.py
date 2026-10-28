#!/usr/bin/env python3
# File: cases.py
# Spec: npu-testplan 3.2-3.7, 5, 6.
# Description: Enumerate the exact NB test items and their directed/random variants.
# Clock domain: none (host preparation).
"""Case recipes consumed by the independent compiler, never by the DUT."""
import itertools
import random

BASES = dict(model=0x00100000, work=0x01000000, input=0x04000000,
             output=0x05000000, desc=0x00080000)
TIERS = {
    **{f'RG-{n:02}': 'full' if n == 3 else 'smoke' for n in range(1, 5)},
    **{f'OP-{n:02}': 'full' if n == 12 else 'smoke' for n in range(1, 13)},
    **{f'CP-{n:02}': 'smoke' if n == 3 else 'full' for n in range(1, 4)},
    **{f'SQ-{n:02}': 'full' if n == 3 else 'smoke' for n in range(1, 4)},
    **{f'ER-{n:02}': 'smoke' for n in range(1, 6)},
    'NET-01': 'full', 'NET-02': 'perf', 'NET-03': 'smoke',
}


def conv(**fields):
    result = dict(op='conv', in_w=8, in_h=4, cin=16, cout=32, k=1, s=1,
                  lut=False, res=False, in_c4=False, half_tail=False,
                  in_sel='work', out_sel='work', in_from='input', in_offset=0, out_offset=0x20000)
    result.update(fields)
    if result['in_from'] != 'input':
        for key in ['in_sel', 'in_offset']:
            if key not in fields:
                result.pop(key)
    result['half_tail'] = result['cout'] % 32 == 16
    return result


def chain(count=3, mixed=False):
    layers = [conv(out_offset=0x10000)]
    for n in range(1, count):
        if mixed and n == 1:
            layer = dict(op='pool', in_w=8, in_h=4, cin=32, cout=32,
                         in_from=n-1, in_sel='work', out_sel='work', out_offset=0x20000)
        else:
            layer = conv(cin=32, in_from=n-1, out_offset=(n+1)*0x10000,
                         lut=mixed, res=mixed, res_sel='output', res_offset=0x10000)
        layers.append(layer)
    layers[-1]['out_sel'] = 'output'
    layers[-1]['out_offset'] = 0
    return layers


def random_chain(seed):
    rng = random.Random(seed)
    layers = []
    width = rng.choice([16, 24, 32])
    height = rng.choice([4, 6, 8])
    channels = 16
    # Two systematically chosen flag combinations per seed cover the legal flag cross.
    for n in range(rng.randint(4, 8)):
        bits = (seed*2+n) % 32
        if n >= 2 and width <= 20 and height <= 12 and rng.randrange(4) == 0:
            layers.append(dict(op='pool', in_w=width, in_h=height, cin=channels,
                               cout=channels, in_from=n-1,
                               out_sel=rng.choice(['model', 'work', 'input', 'output']),
                               out_offset=(n+1)*0x20000))
            continue
        k = 3 if bits & 1 else 1
        stride = 2 if bits & 2 else 1
        if width % 4 or (stride == 2 and width < 8):
            layers.append(dict(op='upsample', in_w=width, in_h=height, cin=channels,
                               cout=channels, in_from=n-1,
                               out_sel=rng.choice(['model', 'work', 'input', 'output']),
                               out_offset=(n+1)*0x20000))
            width *= 2
            height *= 2
            continue
        out_c = rng.choice([16, 48, 80]) if bits & 16 else rng.choice([32, 64, 96])
        layer = conv(in_w=width, in_h=height, cin=channels, cout=out_c,
                     k=k, s=stride, lut=bool(bits & 4), res=bool(bits & 8),
                     res_sel=rng.choice(['model', 'work', 'input', 'output']),
                     res_offset=0x600000+n*0x20000, out_offset=(n+1)*0x20000,
                     out_sel=rng.choice(['model', 'work', 'input', 'output']))
        if n:
            layer['in_from'] = n-1
            layer.pop('in_sel')
            layer.pop('in_offset')
        layers.append(layer)
        width = (width+stride-1)//stride
        height = (height+stride-1)//stride
        channels = out_c
    layers[-1]['out_sel'] = 'output'
    return layers


def recipes(test):
    """Each yield is (variant name, compiler config, simulation options, patch kind)."""
    entries = []

    def add(name, layers, options=None, patch=None, bases=None):
        entries.append((name, dict(layers=layers,
            bases={key.upper()+'_BASE': value for key, value in (bases or BASES).items()}),
            options or {}, patch))

    if test == 'RG-01':
        # Exercise MAC and non-CONV counters, and leave CUR_DESC nonzero before SOFT_RST.
        add('registers', [conv(in_w=4, in_h=1, cout=16),
                          dict(op='pool', in_w=4, in_h=1, cin=16, cout=16,
                               in_from=0, out_sel='output', out_offset=0)])
    elif test == 'RG-02':
        layers = chain(3)
        for layer in layers:
            layer.update(in_w=32, in_h=8)
        add('three_desc', layers)
    elif test == 'RG-03':
        add('perf', chain(4, mixed=True), {'repeat': True})
    elif test == 'RG-04':
        layers = chain(4)
        layers[0] = conv(in_w=16, in_h=8, cin=3, in_c4=True, k=3, s=2,
                         in_sel='input', out_offset=0x10000)
        add('frame_a', layers, {'frame2': True})
    elif test == 'OP-01':
        for cin, cout in itertools.product([16, 32, 48], [32, 64, 96]):
            add(f'c{cin}_{cout}', [conv(cin=cin, cout=cout)])
    elif test == 'OP-02':
        for width in [4, 8, 12]:
            add(f'w{width}', [conv(k=3, in_w=width, in_h=6)])
    elif test == 'OP-03':
        for height in [4, 5, 6, 7]:
            add(f'h{height}', [conv(k=3, s=2, in_w=12, in_h=height)])
    elif test == 'OP-04':
        for cout, lut, res in itertools.product([32, 16], [False, True], [False, True]):
            add(f'c4_cout{cout}_lut{int(lut)}_res{int(res)}',
                [conv(k=3, s=2, in_c4=True, cin=3, cout=cout, lut=lut, res=res,
                      res_sel='output', res_offset=0x40000)])
    elif test == 'OP-05':
        for lut in [False, True]:
            add(f'lut{int(lut)}', [conv(lut=lut)], patch='lut')
    elif test == 'OP-06':
        for select in ['work', 'output']:
            add(select, [conv(res=True, res_sel=select, res_offset=0x40000)])
    elif test == 'OP-07':
        for cout in [16, 80]:
            add(f'cout{cout}', [conv(cout=cout, cin=48, k=3)])
    elif test == 'OP-08':
        for shift, mult, bias in itertools.product([0, 47], [32767, -32768],
                                                  [2147483647, -2147483648]):
            layer = conv(k=3, cin=32, weights='max' if bias > 0 else 'min',
                         quant=dict(bias=bias, mult=mult, shift=shift, out_zp=-7))
            add(f's{shift}_m{mult}_b{bias}', [layer], patch='positive_input')
        for zp in [0, 127, -128, -1]:
            add(f'lut_index_{zp & 255}', [conv(lut=True,
                quant=dict(bias=0, mult=0, shift=0, out_zp=zp))], patch='lut')
    elif test == 'OP-09':
        for channels in [16, 48]:
            add(f'negative_c{channels}', [dict(op='pool', in_w=20, in_h=12,
                cin=channels, cout=channels, in_sel='work', out_sel='output',
                in_offset=0, out_offset=0)], patch='negative')
    elif test == 'OP-10':
        for width in range(2, 41, 2):
            add(f'w{width}', [dict(op='upsample', in_w=width, in_h=3, cin=32,
                cout=32, in_sel='work', out_sel='output', in_offset=0, out_offset=0)])
    elif test == 'OP-11':
        for index, select in enumerate(['model', 'work', 'input', 'output']):
            add(select, [conv(in_sel=select, out_sel=select, res_sel=select, res=True,
                in_offset=0x1000, out_offset=0x4000, res_offset=0x8000,
                in_plane_stride=0x400, out_plane_stride=0x600)])
        add('concat', [conv(cout=16, out_offset=0x10000),
                       conv(cout=16, out_offset=0x10200),
                       conv(cin=32, in_from=[0, 1], in_offset=0x10000,
                            out_sel='output', out_offset=0)])
    elif test == 'OP-12':
        for seed in range(20):
            add(f'seed{seed:02}', random_chain(seed), {'seed': seed})
    elif test == 'CP-01':
        add('L7', [conv(in_w=40, in_h=24, cin=128, cout=256, k=3, s=2)])
    elif test == 'CP-02':
        add('k3_1020', [conv(in_w=16, cin=816, k=3, cout=16)])
        add('k1_1024', [conv(in_w=128, cin=256, k=1, cout=16)])
        # Output region must not overlap this layer's 720 KiB input (npu-spec 2.4).
        add('L15_split', [conv(in_w=80, in_h=48, cin=192, cout=64, out_offset=0x200000)])
    elif test == 'CP-03':
        add('blocks8', [conv(cout=256)])
    elif test in ['SQ-01', 'SQ-02']:
        add('dependent', chain(3), {'b_delay': 200})
    elif test == 'SQ-03':
        for freq in [150, 125, 100]:
            add(f'npu{freq}', random_chain(0), {'npu_mhz': freq, 'seed': 0})
    elif test in ['ER-01', 'ER-02']:
        add('response', chain(3), {'error': 1 if test == 'ER-01' else 2,
                                 'error_desc': 1})
    elif test == 'ER-03':
        for op in [3, 15]:
            add(f'op{op}', [conv()], {'error': 3, 'error_desc': 0}, ('op', op))
    elif test == 'ER-04':
        for field, value, layer in [('row', 205, conv(k=3)),
                                    ('row', 513, conv(k=1)),
                                    ('cout', 9, conv()),
                                    ('weight', 294913, conv())]:
            add(f'{field}{value}', [layer], {'error': 4, 'error_desc': 0}, (field, value))
        add('equal_weight', [conv(in_w=40, in_h=24, cin=128, cout=256, k=3, s=2)])
        add('equal_rows_k3', [conv(in_w=16, cin=816, k=3, cout=16)])
        add('equal_rows_k1', [conv(in_w=128, cin=256, cout=16)])
        add('equal_cout', [conv(cout=256)])
    elif test == 'ER-05':
        for phase in [1, 2, 3]:
            add(f'phase{phase}', chain(3), {'abort': phase, 'b_delay': 200})
    else:
        raise ValueError(f'No small-case recipes for {test}')
    return entries
