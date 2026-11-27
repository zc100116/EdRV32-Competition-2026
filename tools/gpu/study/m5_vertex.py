#!/usr/bin/env python3
"""m5_vertex.py — M-4 §3.2 / M-5 executable vertex ISA and state specialization.
Host FP32 functional model, physical-register allocation and four-context static schedule.
No RTL or hardware clock domain; SFU tables are generated once by host libm.
"""
from collections import Counter
import ctypes
from dataclasses import dataclass, replace
import math
import random
import struct


_lib = ctypes.CDLL(None)
_lib.fmaf.argtypes = (ctypes.c_float, ctypes.c_float, ctypes.c_float)
_lib.fmaf.restype = ctypes.c_float


def fp(x):
    return struct.unpack('f', struct.pack('f', x))[0]


def fma(a, b, c):
    return float(_lib.fmaf(a, b, c))


# Midpoint seeds: 1024 entries over [1,2) for RCP, [1,4) for RSQ.
RCP_TABLE = tuple(fp(1 / (1 + (i + .5) / 1024)) for i in range(1024))
RSQ_TABLE = tuple(fp(1 / math.sqrt(1 + (i + .5) * 3 / 1024)) for i in range(1024))
LOG_TABLE = tuple(fp(math.log2(.75 + i / 256)) for i in range(193))
INV_TABLE = tuple(fp(1 / (.75 + i / 256)) for i in range(193))
EXP_TABLE = tuple(fp(2 ** (i / 256)) for i in range(256))
SFU_LATENCY = dict(RCP=18, RSQ=42, LOG2=42, EXP2=40)


def sfu(op, x, rsq_iterations=2):
    if op == 'RCP':
        if x == 0:
            return math.copysign(math.inf, x)
        m, e = math.frexp(abs(x))
        m *= 2
        e -= 1
        y = RCP_TABLE[int((m - 1) * 1024)]
        y = fma(y, fma(-m, y, 1.), y)
        return fp(math.copysign(math.ldexp(y, -e), x))
    if op == 'RSQ':
        if x == 0:
            return math.inf
        m, e = math.frexp(x)
        m *= 2
        e -= 1
        if e & 1:
            m *= 2
            e -= 1
        y = RSQ_TABLE[int((m - 1) * 1024 / 3)]
        for _ in range(rsq_iterations):
            yy = fp(y * y)
            y = fp(y * fma(-.5 * m, yy, 1.5))
        return fp(math.ldexp(y, -e // 2))
    if op == 'LOG2':
        if x == 0:
            return -math.inf
        m, e = math.frexp(x)
        if m < .75:
            m *= 2
            e -= 1
        i = round((m - .75) * 256)
        r = fp(fp(m - (.75 + i / 256)) * INV_TABLE[i])
        p = fma(r, fp(1 / 3), -.5)
        p = fma(r, p, 1.)
        return fma(fp(r * p), fp(1 / math.log(2)), fp(e + LOG_TABLE[i]))
    if op == 'EXP2':
        if x == -math.inf:
            return 0.
        e = math.floor(x)
        i = int((x - e) * 256)
        r = fp((x - e - i / 256) * fp(math.log(2)))
        p = fma(r, fp(1 / 6), .5)
        p = fma(r, p, 1.)
        p = fma(r, p, 1.)
        return fp(math.ldexp(fp(EXP_TABLE[i] * p), e))
    raise ValueError(op)


@dataclass(frozen=True)
class Source:
    reg: str
    swizzle: str = 'xyzw'
    negate: bool = False
    absolute: bool = False


def src(reg, swizzle='xyzw', negate=False, absolute=False):
    return Source(reg, swizzle, negate, absolute)


@dataclass
class Instruction:
    op: str
    dst: str = ''
    args: tuple = ()
    mask: str = 'xyzw'
    key: str = ''
    count: int = 0
    body: tuple = ()


def expanded(program):
    for ins in program:
        if ins.op == 'LOOP':
            for _ in range(ins.count):
                yield from expanded(ins.body)
        else:
            yield ins


class Builder:
    def __init__(self):
        self.code = []
        self.number = 0

    def emit(self, op, *args, mask='xyzw', key=''):
        name = f'v{self.number}'
        self.number += 1
        self.code.append(Instruction(op, name, tuple(
            src(a) if isinstance(a, str) else a for a in args), mask, key))
        return name

    def load(self, key, attr=False):
        return self.emit('LOAD_ATTR' if attr else 'LOAD_CONST', key=key)

    def store(self, key, value):
        self.code.append(Instruction('STORE_VERTEX', args=(src(value),), key=key,
                                     mask='x' if key in ('clip', 'fog') else 'xyzw'))

    def dot(self, a, b, n=3):
        value = self.emit('MUL', replace(a, swizzle='xxxx'),
                          replace(b, swizzle='xxxx'), mask='x')
        for c in 'yzw'[:n-1]:
            value = self.emit('FMA', replace(a, swizzle=c*4),
                              replace(b, swizzle=c*4), src(value, 'xxxx'), mask='x')
        return value

    def matrix(self, value, key, n=4):
        result = self.emit('MUL', src(value, 'xxxx'), self.load(key+'0'))
        for i in range(1, n):
            result = self.emit('FMA', src(value, 'xyzw'[i]*4),
                               self.load(key+str(i)), result)
        return result

    def normal(self, value):
        square = self.dot(src(value), src(value))
        inverse = self.emit('RSQ', src(square, 'xxxx'), mask='x')
        return self.emit('MUL', value, src(inverse, 'xxxx'))

    def power(self, value, exponent):
        log = self.emit('LOG2', src(value, 'xxxx'), mask='x')
        product = self.emit('MUL', src(log, 'xxxx'), exponent, mask='x')
        return self.emit('EXP2', src(product, 'xxxx'), mask='x')


@dataclass(frozen=True)
class State:
    lights: int = 0
    generic: bool = False
    two_side: bool = False
    clip: bool = False
    texture: bool = False
    tex_matrix: bool = False
    texgen: bool = False
    fog: str = ''


VARIANTS = {
    'position': State(), 'D1': State(lights=1), 'D8': State(lights=8),
    'G1': State(lights=1, generic=True), 'G8': State(lights=8, generic=True),
    'two_side': State(lights=1, two_side=True), 'clip1': State(clip=True),
    'tex_identity': State(texture=True), 'tex_matrix': State(texture=True, tex_matrix=True),
    'object_linear': State(texture=True, texgen=True),
    **{f'fog_{f}': State(fog=f) for f in ('LINEAR', 'EXP', 'EXP2')},
    'combined': State(8, True, True, True, True, True, True, 'EXP2'),
}


def compile_state(state):
    b = Builder()
    p = b.load('position', True)
    clip = b.matrix(p, 'mvp')
    b.store('position', clip)
    needs_eye = state.generic or state.clip or bool(state.fog)
    eye = b.matrix(p, 'mv') if needs_eye else None
    if state.lights:
        n = b.normal(b.matrix(b.load('normal', True), 'normal', 3))
        zero, one = b.load('zero'), b.load('one')
        cart = None
        if state.generic:
            invw = b.emit('RCP', src(eye, 'wwww'), mask='x')
            cart = b.emit('MUL', eye, src(invw, 'xxxx'))
        for side in range(2 if state.two_side else 1):
            normal = src(n, negate=bool(side))
            color = b.load('base')
            for light in range(state.lights):
                prefix = f'l{light}_'
                if state.generic:
                    # Lighting uses Cartesian eye position; we may not assume eye.w=1.
                    delta = b.emit('ADD', b.load(prefix+'position'), src(cart, negate=True))
                    d2 = b.dot(src(delta), src(delta))
                    invd = b.emit('RSQ', src(d2, 'xxxx'), mask='x')
                    direction = b.emit('MUL', delta, src(invd, 'xxxx'))
                    distance = b.emit('MUL', src(d2, 'xxxx'), src(invd, 'xxxx'), mask='x')
                    atten = b.load(prefix+'atten')
                    denom = b.emit('FMA', src(distance, 'xxxx'), src(atten, 'yyyy'),
                                   src(atten, 'xxxx'), mask='x')
                    denom = b.emit('FMA', src(d2, 'xxxx'), src(atten, 'zzzz'),
                                   src(denom, 'xxxx'), mask='x')
                    factor = b.emit('RCP', src(denom, 'xxxx'), mask='x')
                    spot = b.dot(src(direction, negate=True), src(b.load(prefix+'spot')))
                    cutoff = b.emit('ADD', src(spot, 'xxxx'),
                                    src(b.load(prefix+'cutoff'), negate=True), mask='x')
                    spot = b.emit('MAX', src(spot, 'xxxx'), zero, mask='x')
                    power = b.power(spot, b.load(prefix+'spot_exp'))
                    power = b.emit('SELECT', src(cutoff, 'xxxx'), src(power, 'xxxx'),
                                   zero, mask='x')
                    factor = b.emit('MUL', src(factor, 'xxxx'), src(power, 'xxxx'), mask='x')
                else:
                    direction = b.load(prefix+'direction')
                diffuse = b.dot(normal, src(direction))
                diffuse = b.emit('MAX', src(diffuse, 'xxxx'), zero, mask='x')
                if not state.generic:
                    color = b.emit('FMA', src(diffuse, 'xxxx'), b.load(prefix+'diffuse'), color)
                    continue
                contribution = b.emit('FMA', src(diffuse, 'xxxx'), b.load(prefix+'diffuse'),
                                      b.load(prefix+'ambient'))
                half = b.normal(b.emit('ADD', direction, b.load('viewer')))
                shine = b.dot(normal, src(half))
                shine = b.emit('MAX', src(shine, 'xxxx'), zero, mask='x')
                shine = b.power(shine, b.load('shininess'))
                # fi=0 when diffuse=0, SELECT's condition is >=0.
                condition = b.emit('CMP', src(diffuse, 'xxxx'), zero, mask='x')
                shine = b.emit('SELECT', src(condition, 'xxxx'), src(shine, 'xxxx'),
                               zero, mask='x')
                contribution = b.emit('FMA', src(shine, 'xxxx'),
                                      b.load(prefix+'specular'), contribution)
                contribution = b.emit('MUL', contribution, src(factor, 'xxxx'))
                color = b.emit('ADD', color, contribution)
            color = b.emit('MAX', color, zero)
            color = b.emit('MIN', color, one)
            # A write mask preserves RGB, and lighting alpha is diffuse material alpha.
            color = b.emit('MOV', color, b.load('alpha'), mask='w')
            b.store('back' if side else 'color', color)
    if state.clip:
        plane = b.dot(src(eye), src(b.load('clip')), 4)
        b.store('clip', plane)
    if state.texture:
        for unit in range(2):
            # OBJECT_LINEAR generates all four components in this variant.
            tex = (b.matrix(p, f'object{unit}_') if state.texgen
                   else b.load(f'tex{unit}', True))
            if state.tex_matrix:
                tex = b.matrix(tex, f'texmat{unit}_')
            b.store(f'tex{unit}', tex)
    if state.fog:
        z = src(eye, 'zzzz', absolute=True)
        if state.fog == 'LINEAR':
            fog = b.emit('FMA', z, b.load('fog_scale'), b.load('fog_bias'), mask='x')
        else:
            density = b.emit('MUL', z, b.load('density'), mask='x')
            if state.fog == 'EXP2':
                density = b.emit('MUL', src(density, 'xxxx'),
                                 src(density, 'xxxx'), mask='x')
            exponent = b.emit('MUL', src(density, 'xxxx'), b.load('minus_log2e'), mask='x')
            fog = b.emit('EXP2', src(exponent, 'xxxx'), mask='x')
        fog = b.emit('MAX', src(fog, 'xxxx'), b.load('zero'), mask='x')
        fog = b.emit('MIN', src(fog, 'xxxx'), b.load('one'), mask='x')
        b.store('fog', fog)
    b.code.append(Instruction('END', mask=''))
    return b.code


def execute(program, inputs):
    registers = {i.dst: [0.]*4 for i in expanded(program) if i.dst}
    outputs = {}
    for ins in expanded(program):
        args = []
        for a in ins.args:
            v = [registers[a.reg]['xyzw'.index(c)] for c in a.swizzle]
            args.append([(-1 if a.negate else 1) * (abs(x) if a.absolute else x) for x in v])
        op = ins.op
        if op in ('LOAD_ATTR', 'LOAD_CONST'):
            value = list(map(fp, inputs[ins.key]))
        elif op == 'STORE_VERTEX':
            outputs[ins.key] = [args[0][i] if c in ins.mask else 0.
                                for i, c in enumerate('xyzw')]
            continue
        elif op == 'END':
            continue
        elif op == 'MOV':
            value = args[-1]
        elif op in SFU_LATENCY:
            value = [sfu(op, args[0][0])] * 4
        else:
            value = []
            for i in range(4):
                a, c = args[0][i], args[1][i]
                if op == 'ADD':
                    result = fp(a + c)
                elif op == 'MUL':
                    result = fp(a * c)
                elif op == 'FMA':
                    result = fma(a, c, args[2][i])
                elif op == 'MIN':
                    result = min(a, c)
                elif op == 'MAX':
                    result = max(a, c)
                elif op == 'CMP':
                    result = 1. if a > c else -1.
                elif op == 'SELECT':
                    result = c if a >= 0 else args[2][i]
                else:
                    raise ValueError(op)
                value.append(result)
        # Two-source MOV is the SSA representation of an in-place masked write.
        old = args[0][:] if op == 'MOV' and len(args) == 2 else registers[ins.dst][:]
        for c in ins.mask:
            old['xyzw'.index(c)] = value['xyzw'.index(c)]
        registers[ins.dst] = old
    return outputs


def allocate(program):
    """Linear-scan 32 vec4/context; emitted listing uses physical register indices."""
    code = list(expanded(program))
    last = {a.reg: i for i, ins in enumerate(code) for a in ins.args}
    live, free, result = {}, list(range(32)), []
    peak = 0
    for i, ins in enumerate(code):
        args = tuple(replace(a, reg=f'r{live[a.reg]}') for a in ins.args)
        tied = live[ins.args[0].reg] if ins.op == 'MOV' and len(ins.args) == 2 else None
        if tied is not None:
            args = args[1:]
        # Sources are captured before the destination writes, allowing last-use aliasing.
        for reg in list(live):
            if last.get(reg, -1) == i:
                free.append(live.pop(reg))
        dst = ''
        if ins.dst:
            index = tied if tied is not None else min(free)
            free.remove(index)
            live[ins.dst] = index
            dst = f'r{index}'
        peak = max(peak, len(live))
        result.append(replace(ins, dst=dst, args=args))
    return result, peak


def schedule(program, width, latency, sfu_ii=4):
    """Static four-context round-robin batch, repeated without data-dependent timing.
    For each instruction all four contexts issue in order; literal idle slots wait
    for operands. Sources are captured before a destination can alias its last use.
    The emitted timestamps are the scheduling artifact, not a hardware scoreboard.
    """
    ready = [{} for _ in range(4)]
    cycle, scalar_free = 0, 0
    trace = []
    idle = 0
    for pc, ins in enumerate(expanded(program)):
        for ctx in range(4):
            available = max((ready[ctx].get(a.reg, 0) for a in ins.args), default=0)
            if ins.op in SFU_LATENCY:
                available = max(available, scalar_free)
            start = max(cycle, available)
            idle += start-cycle
            beats = math.ceil(len(ins.mask)/width) if ins.op != 'END' else 1
            if ins.op in SFU_LATENCY:
                beats, delay = 1, SFU_LATENCY[ins.op]
                scalar_free = start+sfu_ii
            elif ins.op in ('LOAD_ATTR', 'LOAD_CONST', 'MOV', 'MIN', 'MAX', 'CMP', 'SELECT'):
                delay = beats+1
            else:
                delay = beats+latency
            if ins.dst:
                ready[ctx][ins.dst] = start+delay
            trace.append((start, ctx, pc))
            cycle = start+beats
    return dict(cycles=cycle/4, first_four_cycles=cycle,
                idle_cycles_per_four=idle, trace=trace)


def dot(a, b):
    return sum(x*y for x, y in zip(a[:3], b[:3]))


def unit(v):
    norm = math.sqrt(dot(v, v))
    return [x / norm for x in v[:3]] + [0.]


def matrix(v, inputs, prefix, n=4):
    return [sum(v[j] * inputs[prefix+str(j)][i] for j in range(n)) for i in range(4)]


def reference(state, u):
    p = u['position']
    out = {'position': matrix(p, u, 'mvp')}
    eye = matrix(p, u, 'mv')
    if state.lights:
        n = unit(matrix(u['normal'], u, 'normal', 3))
        for side in range(2 if state.two_side else 1):
            nn = [-x for x in n] if side else n
            color = u['base'][:]
            if not state.generic:
                color = [color[j] + sum(u[f'l{i}_ambient'][j] for i in range(state.lights))
                         for j in range(4)]
            for i in range(state.lights):
                k = f'l{i}_'
                if state.generic:
                    delta = [u[k+'position'][j] - eye[j]/eye[3] for j in range(3)]
                    d2 = dot(delta, delta)
                    distance = math.sqrt(d2)
                    direction = unit(delta)
                    atten = u[k+'atten']
                    factor = 1 / (atten[0]+atten[1]*distance+atten[2]*d2)
                    spot = max(0., dot([-x for x in direction], u[k+'spot']))
                    factor *= spot**u[k+'spot_exp'][0] if spot >= u[k+'cutoff'][0] else 0.
                else:
                    direction, factor = u[k+'direction'], 1.
                diffuse = max(0., dot(nn, direction))
                shine = 0.
                if state.generic and diffuse > 0:
                    half = unit([direction[j]+u['viewer'][j] for j in range(3)])
                    shine = max(0., dot(nn, half))**u['shininess'][0]
                for j in range(3):
                    ambient = u[k+'ambient'][j] if state.generic else 0.
                    color[j] += factor * (ambient+diffuse*u[k+'diffuse'][j]
                                          +shine*u[k+'specular'][j])
            out['back' if side else 'color'] = [min(1., max(0., x)) for x in color[:3]]
            out['back' if side else 'color'].append(u['alpha'][0])
    if state.clip:
        out['clip'] = [sum(x*y for x, y in zip(eye, u['clip'])), 0., 0., 0.]
    if state.texture:
        for i in range(2):
            tex = matrix(p, u, f'object{i}_') if state.texgen else u[f'tex{i}']
            if state.tex_matrix:
                tex = matrix(tex, u, f'texmat{i}_')
            out[f'tex{i}'] = tex
    if state.fog:
        d = abs(eye[2])
        if state.fog == 'LINEAR':
            f = d*u['fog_scale'][0] + u['fog_bias'][0]
        elif state.fog == 'EXP':
            f = math.exp(-d*u['density'][0])
        else:
            f = math.exp(-(d*u['density'][0])**2)
        out['fog'] = [min(1., max(0., f)), 0., 0., 0.]
    return out


def random_inputs(rng):
    u = dict(zero=[0.]*4, one=[1.]*4, viewer=[0., 0., 1., 0.])
    for name in ('mvp', 'mv', 'normal', 'object0_', 'object1_', 'texmat0_', 'texmat1_'):
        for j in range(4):
            u[name+str(j)] = [rng.uniform(-.3, .3) + (1. if i == j else 0.)
                              for i in range(4)]
    # Affine MV preserves positive eye w; projective texture matrices remain arbitrary.
    for j in range(4):
        u['mv'+str(j)][3] = float(j == 3)
        u['normal'+str(j)][3] = 0.
    u['position'] = [rng.uniform(-4, 4) for _ in range(3)] + [rng.uniform(.5, 2)]
    u['normal'] = [rng.uniform(-2, 2) for _ in range(3)] + [0.]
    for key in ('base', 'tex0', 'tex1', 'clip'):
        u[key] = [rng.uniform(.01, .2) for _ in range(4)]
    u.update(alpha=[rng.random()]*4, shininess=[rng.uniform(.25, 127.75)]*4,
             fog_scale=[-.2]*4, fog_bias=[1.2]*4,
             density=[rng.uniform(.01, 1)]*4, minus_log2e=[-math.log2(math.e)]*4)
    for i in range(8):
        k = f'l{i}_'
        u[k+'position'] = [rng.uniform(-6, 6) for _ in range(3)] + [1.]
        u[k+'direction'] = unit([rng.uniform(-1, 1) for _ in range(3)])
        u[k+'spot'] = unit([rng.uniform(-1, 1) for _ in range(3)])
        u[k+'atten'] = [rng.uniform(.1, 1), rng.random(), rng.random(), 0.]
        u[k+'cutoff'] = [rng.uniform(0, .8)]*4
        u[k+'spot_exp'] = [rng.uniform(.25, 127.75)]*4
        for key in ('diffuse', 'ambient', 'specular'):
            u[k+key] = [rng.uniform(.001, .15) for _ in range(4)]
    return {k: list(map(fp, v)) for k, v in u.items()}


def error_summary(pairs):
    pairs = list(pairs)
    absolute = [abs(a-b) for a, b in pairs]
    relative = [abs(a-b)/abs(b) for a, b in pairs if b != 0]
    return dict(n=len(pairs), max_abs=max(absolute),
                rms=math.sqrt(sum(x*x for x in absolute)/len(pairs)),
                max_rel=max(relative), above_1e5=sum(x > 1e-5 for x in relative))


def study():
    rng = random.Random(20261127)
    result, programs = {}, {}
    for name, state in VARIANTS.items():
        code = compile_state(state)
        physical, peak = allocate(code)
        pairs = []
        groups = {}
        for sample in range(128):
            u = random_inputs(rng)
            if state.generic and sample >= 96:
                # Exercise visible noninteger spotlight/specular terms, avoiding a mostly
                # rejected spotlight corpus. Also alternate back-facing normals.
                for j in range(4):
                    u['normal'+str(j)] = [float(i == j and i < 3) for i in range(4)]
                eye = matrix(u['position'], u, 'mv')
                direction = unit([.5, .25, 2.])
                half = unit([direction[j]+u['viewer'][j] for j in range(3)])
                sign = -1 if state.two_side and sample & 1 else 1
                u['normal'] = [fp(sign*x) for x in half]
                u['base'] = [.01]*4
                for i in range(state.lights):
                    k = f'l{i}_'
                    u[k+'position'] = [fp(eye[j]/eye[3]+direction[j]*3) for j in range(3)]
                    u[k+'position'].append(1.)
                    u[k+'spot'] = [fp(-x) for x in direction]
                    u[k+'cutoff'] = [.5]*4
                    u[k+'atten'] = [1., 0., 0., 0.]
                    u[k+'diffuse'] = [.01/state.lights]*4
                    u[k+'ambient'] = [0.]*4
                    u[k+'specular'] = [.75/state.lights]*4
            u = {k: list(map(fp, v)) for k, v in u.items()}
            if state.lights and not state.generic:
                # Driver folds all directional ambient contributions into a single constant.
                u['base'] = [fp(u['base'][j] + sum(
                    u[f'l{i}_ambient'][j] for i in range(state.lights))) for j in range(4)]
                ideal_inputs = dict(u)
                for i in range(state.lights):
                    ideal_inputs[f'l{i}_ambient'] = [0.]*4
            else:
                ideal_inputs = u
            actual, ideal = execute(code, u), reference(state, ideal_inputs)
            pairs.extend((a, b) for key in ideal for a, b in zip(actual[key], ideal[key]))
            for key in ideal:
                groups.setdefault(key, []).extend(zip(actual[key], ideal[key]))
            assert execute(physical, u) == actual, name
        counts = Counter(i.op for i in code)
        timings = {f'W{w}L{l}': schedule(code, w, l)['cycles']
                   for w in (1, 2, 4) for l in (8, 10, 12)}
        result[name] = dict(words=len(code),
                            constant_words=len({i.key for i in code if i.op == 'LOAD_CONST'}),
                            arithmetic=sum(v for k, v in counts.items()
                             if k not in ('LOAD_ATTR', 'LOAD_CONST', 'STORE_VERTEX', 'END')),
                            opcodes=dict(counts), peak_regs=peak, cycles=timings,
                            errors=error_summary(pairs),
                            output_errors={k: error_summary(v) for k, v in groups.items()},
                            sfu_serial_W2L10=schedule(code, 2, 10, 42)['cycles'])
        result[name]['schedule_W2L10'] = schedule(code, 2, 10)
        programs[name] = [dict(op=i.op, dst=i.dst, mask=i.mask, key=i.key,
                               args=[a.__dict__ for a in i.args]) for i in physical]
    special = {}
    for op in SFU_LATENCY:
        pairs = []
        for _ in range(20000):
            x = fp(rng.uniform(-100, 32) if op == 'EXP2' else 2**rng.uniform(-32, 32))
            target = dict(RCP=lambda: 1/x, RSQ=lambda: 1/math.sqrt(x),
                          LOG2=lambda: math.log2(x), EXP2=lambda: 2**x)[op]()
            pairs.append((sfu(op, x), target))
        if op == 'LOG2':
            for j in range(1, 128):
                for x in (fp(1+j*2**-23), fp(1-j*2**-24)):
                    pairs.append((sfu(op, x), math.log2(x)))
        special[op] = error_summary(pairs)
    special['RSQ_one_newton'] = error_summary(
        (sfu('RSQ', x, 1), 1/math.sqrt(x))
        for x in (fp(2**rng.uniform(-32, 32)) for _ in range(20000)))
    pairs = []
    for _ in range(20000):
        x, y = fp(2**rng.uniform(-.8, 0)), fp(rng.uniform(.25, 127.75))
        actual = sfu('EXP2', fp(sfu('LOG2', x)*y))
        pairs.append((actual, x**y))
    special['pow'] = error_summary(pairs)
    broad = []
    underflow = 0
    for _ in range(20000):
        x, y = fp(2**rng.uniform(-8, 0)), fp(rng.uniform(.25, 127.75))
        target = x**y
        actual = sfu('EXP2', fp(sfu('LOG2', x)*y))
        if target < 2**-126:
            underflow += 1
        else:
            broad.append((actual, target))
    special['pow_broad_normal'] = error_summary(broad)
    special['pow_broad_underflow_count'] = underflow
    # ISA-directed exercise: real LOOP, mask preservation, swizzle, abs/negate and SELECT.
    loop = [Instruction('LOAD_ATTR', 'a', key='position'),
            Instruction('LOAD_CONST', 'one', key='one'),
            Instruction('LOOP', count=3, body=(Instruction(
                'ADD', 'a', (src('a', 'wzyx', True, True), src('one'))),)),
            Instruction('STORE_VERTEX', args=(src('a'),), key='position')]
    got = execute(loop, dict(position=[-1., 2., -3., 4.], one=[1.]*4))['position']
    assert got == [-1., 0., 1., 0.], got
    return dict(variants=result, programs=programs, sfu_errors=special,
                seed=20261127, vertices_per_variant=128,
                sfu_samples_each=20000, loop_result=got,
                sfu_table_bits=32*sum(map(len, (RCP_TABLE, RSQ_TABLE, LOG_TABLE,
                                              INV_TABLE, EXP_TABLE))))
