#!/usr/bin/env python3
"""M-6 host setup DAG throughput and exact integer tile relocation study.
Uses the M-5 operations/latencies with explicitly bounded triangle contexts.
No RTL clock domain; resource numbers are structural planning estimates.
"""
from collections import Counter
import heapq
import math

import m5_setup as m5
from m5_setup import BF, dag, coefficients, precision, resources
from m5_setup import divide, shift
from m6_sfu import RCP


def pipeline(attributes, pools, contexts, normals=2, adders=2, count=512):
    nodes = dag(attributes)
    index = {n: i for i, (n, _, _, _) in enumerate(nodes)}
    children = [[] for _ in nodes]
    for i, (_, _, deps, _) in enumerate(nodes):
        for dep in deps:
            children[index[dep]].append(i)
    critical = [0]*len(nodes)
    latency = dict(mul=6, add=2, norm=2, read=1, write=1)
    for i in range(len(nodes)-1, -1, -1):
        critical[i] = latency[nodes[i][1]] + max(
            (critical[j] for j in children[i]), default=0)
    ports = dict(mul=pools, add=adders, norm=normals, read=1, write=1)
    queues = {k: [] for k in ports}
    events, pending, remaining, retired = [], {}, {}, {}
    next_triangle, head, t = 0, 0, 0
    finishes, trace = [], []

    def admit(triangle):
        pending[triangle] = [len(n[2]) for n in nodes]
        remaining[triangle] = len(nodes)
        for i, n in enumerate(nodes):
            if not n[2]:
                heapq.heappush(queues[n[1]], (triangle, -critical[i], i))

    while head < count:
        while events and events[0][0] <= t:
            _, triangle, i = heapq.heappop(events)
            remaining[triangle] -= 1
            for j in children[i]:
                pending[triangle][j] -= 1
                if pending[triangle][j] == 0:
                    heapq.heappush(queues[nodes[j][1]], (triangle, -critical[j], j))
            if remaining[triangle] == 0:
                retired[triangle] = t
        while head in retired:
            finishes.append(t)
            del pending[head], remaining[head], retired[head]
            head += 1
        while next_triangle < min(count, head+contexts):
            admit(next_triangle)
            next_triangle += 1
        for kind, capacity in ports.items():
            for _ in range(min(capacity, len(queues[kind]))):
                triangle, _, i = heapq.heappop(queues[kind])
                heapq.heappush(events, (t+latency[kind], triangle, i))
                if triangle < 2:
                    trace.append((t, triangle, nodes[i][0], kind))
        t += 1
    middle = finishes[count//4:3*count//4]
    intervals = [b-a for a, b in zip(middle, middle[1:])]
    work = Counter(n[1] for n in nodes)
    return dict(attributes=attributes, pools=pools, contexts=contexts, ports=ports,
                first_latency=finishes[0], interval=(middle[-1]-middle[0])/(len(middle)-1),
                interval_min=min(intervals), interval_max=max(intervals),
                work=dict(work), resource_lower_bound=max(work[k]/ports[k] for k in work),
                makespan=finishes[-1], triangles=count, trace_first_two=trace)


def shared_inverse(area):
    exponent = area.bit_length()-1
    mantissa = shift(area, exponent-31)
    if mantissa == 1 << 32:
        mantissa >>= 1
        exponent += 1
    index = (mantissa-(1 << 31)) >> 25
    y = round(RCP[index]*(1 << 31))
    for _ in range(2):
        y = shift(y*((2 << 31)-shift(mantissa*y, 31)), 31)
    return BF(y, -31-exponent)


def source_record(vertices, values, origin, bits=32):
    # One canonical anchor per source triangle, irrespective of requesting tile.
    anchor = tuple(min(p[k] for p in vertices)//1024*64 for k in (0, 1))
    fields, exponent = coefficients(vertices, values, anchor, 48)
    s, gx, gy = fields
    relocated = s+(origin[0]-anchor[0])*gx+(origin[1]-anchor[1])*gy
    assert -(1 << 59) <= relocated < (1 << 59)
    return (relocated, gx, gy), exponent


def relocated_evaluate(record, origin, x, y, bits=32):
    # S is retained at full width; no per-tile repack or renormalization.
    (s, gx, gy), exponent = record
    value = s+(x-origin[0])*gx+(y-origin[1])*gy
    assert -(1 << 59) <= value < (1 << 59)
    return math.ldexp(value, exponent)


def resource_estimate(pools=4, contexts=4, normals=2, adders=2):
    base = resources()['vector']
    # Replicate M-5 banks rather than claiming free multiport RAM.
    lutram = base[4]-512+(contexts-1)*(174+736)
    lut = base[0]+(pools-4)*164+(normals-2)*622+(adders-2)*656
    lut += lutram-base[4]
    ff = base[1]+(pools-4)*(246+144+96)+(contexts-1)*289
    ff += (normals-2)*184+(adders-2)*164
    # Relocation: eight-term balanced 60-bit tree, seven adders and term muxes.
    lut += 2*7*60+200
    ff += 7*60+154+48
    return [lut, ff, pools*6, 3, lutram]


def study():
    rows = []
    for attrs in (11, 16):
        for pools in (4, 6, 8):
            for contexts in (1, 2, 4, 8):
                rows.append(pipeline(attrs, pools, contexts))
            rows.append(pipeline(attrs, pools, 8, 8, 4))
    # Run the original corpus and added 64-pixel boundary +/-1/helper probes.
    before = precision(boundaries=True)
    original_inverse = m5.inverse_area
    m5.inverse_area = shared_inverse
    after = precision(source_record, relocated_evaluate, boundaries=True)
    m5.inverse_area = original_inverse
    sections = [after[k] for k in ('aggregate', 'quantized',
                                  'bounded_coordinate_quantized', 'common_covered_quantized')]
    sections.extend(after['per_case'].values())
    for section in sections:
        section['source48'] = section.pop('block32')
        del section['block24']
    after['max_boundary_relative_jump'] = {'48': after['max_boundary_relative_jump'][32]}
    for row in after['max_boundary_relative_jump'].values():
        assert row == 0, row
    integer_probes = 0
    for _, vertices in m5.corpus():
        for values in ([1000, 64000, 24000], [2**30, 2**29, 2**28]):
            anchor = tuple(min(p[k] for p in vertices)//1024*64 for k in (0, 1))
            for offset in (64, 128, 192, 256, 512):
                x, y = anchor[0]+offset, anchor[1]
                a = source_record(vertices, values, (x-64, y))
                b = source_record(vertices, values, (x, y))
                assert a[1] == b[1] and a[0][0]+64*a[0][1] == b[0][0]
                c = source_record(vertices, values, (x, y+64))
                assert b[1] == c[1] and b[0][0]+64*b[0][2] == c[0][0]
                integer_probes += 2
    return dict(integer_boundary_probes=integer_probes, pipeline=rows,
                per_tile_precision=before, source_once_precision=after,
                candidate_resources={f'P{p}C{c}N{n}': resource_estimate(p, c, n, a)
                                     for p, c, n, a in ((4, 4, 2, 2), (4, 8, 8, 4),
                                                       (6, 8, 8, 4), (8, 8, 8, 4))},
                record_bytes={str(a): math.ceil((64+20*a)/32)*32 for a in (11, 16)})
