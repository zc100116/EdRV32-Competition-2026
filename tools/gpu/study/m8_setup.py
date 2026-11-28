#!/usr/bin/env python3
"""M-8 setup DAG: split-width normalizers and dedicated attribute stage pipelines.
All candidates preserve M-6 source48 arithmetic and exact 60-bit relocation.
Resources are structural estimates; scheduler assumes conflict-free field banks.
"""
from collections import Counter
import heapq

import m5_setup as m5
import m6_setup as m6


def run(nodes, ports, latency, contexts=8, count=512):
    index = {n[0]: i for i, n in enumerate(nodes)}
    children = [[] for _ in nodes]
    for i, n in enumerate(nodes):
        for d in n[2]:
            children[index[d]].append(i)
    critical = [0]*len(nodes)
    for i in reversed(range(len(nodes))):
        critical[i] = latency[nodes[i][1]]+max((critical[j] for j in children[i]), default=0)
    queues = {k: [] for k in ports}
    events, pending, remaining, retired, finishes, trace = [], {}, {}, {}, [], []
    head = admitted = cycle = active = peak_active = 0
    while head < count:
        while events and events[0][0] <= cycle:
            _, tri, i = heapq.heappop(events)
            remaining[tri] -= 1
            if nodes[i][0].endswith('_write'):
                active -= 1
            for j in children[i]:
                pending[tri][j] -= 1
                if not pending[tri][j]:
                    heapq.heappush(queues[nodes[j][1]], (tri, -critical[j], j))
            if not remaining[tri]:
                retired[tri] = cycle
        while head in retired:
            finishes.append(cycle)
            del pending[head], remaining[head], retired[head]
            head += 1
        while admitted < min(count, head+contexts):
            pending[admitted] = [len(n[2]) for n in nodes]
            remaining[admitted] = len(nodes)
            for i, n in enumerate(nodes):
                if not n[2]:
                    heapq.heappush(queues[n[1]], (admitted, -critical[i], i))
            admitted += 1
        for kind, capacity in ports.items():
            for _ in range(min(capacity, len(queues[kind]))):
                tri, _, i = heapq.heappop(queues[kind])
                if nodes[i][0].endswith('_read'):
                    active += 1
                    peak_active = max(peak_active, active)
                heapq.heappush(events, (cycle+latency[kind], tri, i))
                if tri < 2:
                    trace.append((cycle, tri, nodes[i][0], kind))
        cycle += 1
    middle = finishes[count//4:count*3//4]
    gaps = [b-a for a, b in zip(middle, middle[1:])]
    work = dict(Counter(n[1] for n in nodes))
    return dict(first=finishes[0], mean=sum(gaps)/len(gaps), minimum=min(gaps),
                maximum=max(gaps), work=work, ports=ports, contexts=contexts,
                peak_active_attributes=peak_active,
                lower=max(work[k]/ports[k] for k in work), trace_first_two=trace)


def expanded(attrs, compressed=True):
    nodes = m5.dag(attrs)
    ports = dict(mul=4, add=4, norm=8, read=1, write=1)
    latency = dict(mul=7, add=3, norm=3, read=2, write=1)
    if compressed:
        # Only input48 and pack48 have a proven 48-bit shifter input. Retain all
        # 82-bit product/cancellation and intermediate normalization paths.
        nodes = [(name, 'narrow' if kind == 'norm' and
                  ('input' in name or 'pack' in name) else kind, deps, group)
                 for name, kind, deps, group in nodes]
        ports.update(norm=3, narrow=3, add=3)
        latency['narrow'] = 3
    return run(nodes, ports, latency, contexts=9 if compressed else 8)


def dedicated(attrs, groups=1):
    # One instance per named operation stage, shared across attributes. Products
    # remain full width and all M-6 rounding points remain at the same locations.
    nodes, ports, latency = [], {}, {}
    for name, kind, deps, group in m5.dag(attrs, slots=attrs):
        stage = name.split('_', 1)[1] if group >= 0 else name
        if stage == 'read':
            deps = (*deps, 'newton1y')
        nodes.append((name, stage, deps, group))
        ports[stage] = groups if group >= 0 else 1
        latency[stage] = dict(mul=7, add=3, norm=3, read=2, write=1)[kind]
    # Shared area/reciprocal front-end: one source admitted each attrs/groups
    # clocks. Explicit contexts hide its latency; output is still one attribute/clk.
    ports['read'] = ports['write'] = 1
    return run(nodes, ports, latency, contexts=16)


def resources(compressed=True, dedicated=False):
    # M-7 scratch shape: two independent x92 banks per active attribute slot.
    # Every bank has its own external 92-bit capture, no free multiport DRM.
    banks = 128 if dedicated else (72 if compressed else 64)
    storage_ff = 3*58+banks*92+128
    if dedicated:
        # 8 attribute product stages, 2 area, 4 Newton stages. Each is 49x33,
        # 6 native APM (24x16 chunks), per apm-cascade. Wide products not LUT sums.
        apm = 14*6
        norm_lut = 8*622+6*(48*6+48)+622
        add_lut = 9*656
        lut = 14*164+norm_lut+add_lut+400+450+1040+128
        ff = 14*486+15*184+9*164+storage_ff+622+16*32
        return [lut, ff, apm, 3+3+banks*2, 0]
    norm_lut = (3*622+3*(48*6+48)) if compressed else 8*622
    adders, contexts = (3, 9) if compressed else (4, 8)
    lut = 4*164+adders*656+norm_lut+400+450+1040+128
    ff = 4*486+(6 if compressed else 8)*184+adders*164+storage_ff+622+contexts*289
    return [lut, ff, 24, 3+3+banks*2, 0]


def precision():
    # Both microarchitectures retain the same exact arithmetic, so run once.
    original = m5.inverse_area
    m5.inverse_area = m6.shared_inverse
    result = m5.precision(m6.source_record, m6.relocated_evaluate, boundaries=True)
    m5.inverse_area = original
    probes = 0
    for _, vertices in m5.corpus():
        for values in ([1000, 64000, 24000], [2**30, 2**29, 2**28]):
            anchor = tuple(min(p[k] for p in vertices)//1024*64 for k in (0, 1))
            for offset in (64, 128, 192, 256, 512):
                x, y = anchor[0]+offset, anchor[1]
                a = m6.source_record(vertices, values, (x-64, y))
                b = m6.source_record(vertices, values, (x, y))
                c = m6.source_record(vertices, values, (x, y+64))
                assert a[1] == b[1] == c[1]
                assert a[0][0]+64*a[0][1] == b[0][0]
                assert b[0][0]+64*b[0][2] == c[0][0]
                probes += 2
    return dict(corpus=result, exact_boundary_probes=probes)


def study():
    candidates = []
    nodes = [(n, 'narrow' if k == 'norm' and ('input' in n or 'pack' in n) else k, d, g)
             for n, k, d, g in m5.dag(11)]
    for wide, narrow, adders, contexts in ((3, 3, 3, 8), (3, 3, 3, 9),
                                           (4, 3, 3, 8), (4, 2, 4, 8)):
        row = run(nodes, dict(mul=4, add=adders, norm=wide, narrow=narrow, read=1, write=1),
                  dict(mul=7, add=3, norm=3, narrow=3, read=2, write=1), contexts)
        candidates.append(row)
    timing = {str(a): dict(expanded=expanded(a, False), compressed=expanded(a),
                           dedicated=dedicated(a)) for a in (11, 16)}
    return dict(candidates=candidates, timing=timing,
                resources=dict(expanded=resources(False), compressed=resources(),
                               dedicated=resources(dedicated=True)), precision=precision())
