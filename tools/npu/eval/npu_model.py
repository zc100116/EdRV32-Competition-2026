"""Stage model for the legacy schedule, calibrated against observed RTL phases.

SoC spec 8.9 evaluation; Python standard library only. No per-command timing
lookup: geometry and memory parameters determine every phase. W1-W8 are
explicit hypothetical schedules, not measured modified RTL.
"""

import argparse
import csv
from functools import lru_cache
import json
import math

from legacy_plan import BUILD, analysis, write_csv

BOARD_CYCLES = 14435023
MEASUREMENTS = ((0, 4.8), (30, 4.8), (100, 4.8), (30, 0.5), (30, 2.0), (94, 4.0))
STAGES = ('control', 'quant', 'weight', 'feature', 'mac', 'write_drain',
          'write_response', 'patch_pipeline', 'row_prepare', 'nonconv')


@lru_cache(maxsize=None)
def read_cycles(beats, address_mod, latency, bandwidth=4.8):
    """AR-first through final R; four outstanding, 16-beat/4KiB splits.

    The first AR is at t=0; L=0 has first R at t=1 and returns N beats in N
    cycles. New AR cannot reuse a credit freed at the same edge (legacy RTL).
    """
    queue = []
    issued = 0
    returned = 0
    time = 0
    credit = 0.0
    while returned < beats:
        credit = min(64.0, credit + 32 * bandwidth / 4.8)
        issue = issued < beats and len(queue) < 4
        take = bool(queue) and queue[0][1] <= time and credit >= 32 - 1e-9
        if take:
            queue[0][0] -= 1
            returned += 1
            credit -= 32
            if queue[0][0] == 0:
                queue.pop(0)
        if issue:
            length = min(16, beats - issued, 128 - (address_mod + issued) % 128)
            queue.append([length, time + latency + 1])
            issued += length
        time += 1
    return time - 1


def bursts(beats, address):
    result = 0
    while beats:
        n = min(beats, 16, 128 - (address // 32) % 128)
        beats -= n
        address += n * 32
        result += 1
    return result


@lru_cache(maxsize=None)
def writer_timing(k, pairs, tile, planes, addr0, addr1, latency, bandwidth):
    """Two 16-pair banks, per-plane bursts and four B credits.

    Quantized pair availability follows the measured tile issue spacing.
    Backpressure shifts later pairs; payload and B events are cycle scheduled.
    Returns producer stalls, post-acceptance W drain and B drain cycles.
    """
    full = [False, False]
    length = [0, 0]
    fill_bank = drain_bank = fill_count = accepted = 0
    state = plane = index = 0
    pending = []
    outstanding = 0
    time = 0
    credit = 64.0
    stalled = 0
    last_accept = None
    data_done = None
    while True:
        credit = min(64.0, credit + 32*bandwidth/4.8)
        response = bool(pending) and pending[0] <= time
        ready = (accepted < pairs and not full[fill_bank] and
                 not (state != 0 and fill_bank == drain_bank))
        arrival = (accepted+1)*k + min(pairs, tile)*k + 10*(accepted//tile+1) + 13
        valid = accepted < pairs and time >= arrival + stalled
        take = ready and valid
        aw = state == 1 and outstanding < 4
        wr = state == 2 and credit >= 32-1e-9
        if last_accept is not None and not any(full) and state == 0 and data_done is None:
            data_done = time
        if last_accept is not None and not any(full) and state == 0 and outstanding == 0:
            return stalled, data_done-last_accept-1, time-data_done+2
        if valid and not ready:
            stalled += 1
        old_state = state
        old_full = list(full)
        if response:
            pending.pop(0)
            outstanding -= 1
        if old_state == 0 and old_full[drain_bank]:
            plane = index = 0
            state = 1
        elif aw:
            outstanding += 1
            state = 2
        elif wr:
            credit -= 32
            index += 1
            if index == length[drain_bank]:
                index = 0
                pending.append(time+latency+1)
                if plane or planes == 1:
                    full[drain_bank] = False
                    drain_bank = 1-drain_bank
                    state = 0
                else:
                    plane = 1
                    state = 1
        if take:
            if fill_count == 0:
                limit = min(16, 128-(addr0+accepted)%128,
                            128-(addr1+accepted)%128)
            fill_count += 1
            accepted += 1
            if fill_count == limit or accepted == pairs:
                length[fill_bank] = fill_count
                full[fill_bank] = True
                fill_bank = 1-fill_bank
                fill_count = 0
            if accepted == pairs:
                last_accept = time
        time += 1


def operator_cycles(c, latency, bandwidth=4.8):
    """Serial DMA stages: read, arithmetic/sample, AW/W/B, then next chunk."""
    beat_time = 4.8 / bandwidth
    if c['kind'] == 'add':
        count = c['beat_count']
        chunks = math.ceil(count / 16)
        return 3 * count * beat_time + chunks * (10 + 3 * latency) + 4
    w = c['input_width'] // 2
    h = c['input_height']
    planes = c['cin_blocks']
    if c['kind'] == 'pool':
        # Current RTL has SAMPLE_ADDR -> SAMPLE_REQ -> SAMPLE_USE: 3 cycles.
        sample = w * 2 * h * planes * 25 * 3
        read = sum(read_cycles(w * h, ((c['input_base'] +
                   p * c['input_plane_stride']) // 32) % 128, latency, bandwidth)
                   for p in range(planes))
        wb = sum(bursts(w, c['output_base'] + p * c['output_plane_stride'] + y*w*32)
                 for p in range(planes) for y in range(h))
        return sample + read + planes * 4 + w*h*planes*beat_time + wb*(latency+2) + 8
    total = 4
    for p in range(planes):
        for y in range(h):
            addr = c['input_base'] + p*c['input_plane_stride'] + y*w*32
            rd = read_cycles(w, (addr // 32) % 128, latency, bandwidth)
            out = c['output_base'] + p*c['output_plane_stride'] + y*w*128
            total += rd + 3 + w*4*beat_time + bursts(w*4, out)*(latency+2)
    return total


def conv_stages(c, latency, bandwidth=4.8, macs=512, first_c3=False):
    b = c['output_blocks']
    h = c['output_height']
    pairs = c['output_width_pairs']
    tiles = math.ceil(pairs / c['tile_pairs'])
    k = c['cin_blocks'] * 2 * (9 if c['kernel3'] else 1)
    if first_c3:
        k = 9
    stages = {s: 0.0 for s in STAGES}
    stages['control'] = b * 3 + 3
    quant_cost = read_cycles(16, (c['quant_base']//32) % 128, latency, bandwidth)
    stages['quant'] = b * (quant_cost + 37 + 257*c['lut_enable'])
    stages['weight'] = sum(read_cycles(8*k,
        ((c['weight_base'] + block*c['weight_block_stride'])//32) % 128,
        latency, bandwidth) + 5 for block in range(b))
    for block in range(b):
        for y in range(c['input_height']):
            row = 1
            for p in range(c['cin_blocks']):
                addr = c['input_base'] + p*c['input_plane_stride'] + y*c['input_width']*16
                count = c['input_width'] // 2
                if first_c3:
                    count = c['input_width'] * 3 // 32
                    addr = c['input_base'] + y*count*32
                row += read_cycles(count, (addr//32) % 128, latency, bandwidth) + 3
            stages['feature'] += row
    stages['mac'] = b * h * pairs * k * 512 / macs
    stages['row_prepare'] = b * h * (4 if c['kernel3'] else 2)
    # Two activation halves: patch fill and MAC overlap in steady state.
    # Envelope for a faster MAC keeps the old patch generator's one-row/clock limit.
    first_chunk = min(pairs, c['tile_pairs']) * k
    last_chunk = (pairs - (tiles-1)*c['tile_pairs']) * k
    stream = max(pairs*k*512/macs + first_chunk,
                 pairs*k + last_chunk*512/macs)
    stages['patch_pipeline'] = b*h*(stream - pairs*k*512/macs + 10*tiles + 14)
    for block in range(b):
        planes = 1 if c['last_c16_only'] and block == b-1 else 2
        for y in range(h):
            addr0 = c['output_base'] + 2*block*c['output_plane_stride'] + y*pairs*32
            addr1 = addr0 + c['output_plane_stride']
            stalls, tail, response = writer_timing(
                k, pairs, c['tile_pairs'], planes, (addr0//32)%128,
                (addr1//32)%128, latency, bandwidth)
            stages['patch_pipeline'] += stalls
            stages['write_drain'] += tail
            stages['write_response'] += response
    return stages


def command(c, latency, bandwidth=4.8, changes=(), macs=512):
    result = {'index': c['index'], 'name': c['name'], 'kind': c['kind']}
    traffic = c['ddr_bytes']
    if c['kind'] != 'conv':
        phase = {s: 0.0 for s in STAGES}
        phase['nonconv'] = operator_cycles(c, latency, bandwidth)
        if 'W6' in changes and c['kind'] == 'add':
            # Fuse quantized residual addition into producer writeback: keep
            # the shortcut operand read, remove temporary result read+write.
            phase['nonconv'] = 0
            traffic -= c['operator_write'] * 2
        return result | phase | {'cycles': sum(phase.values()), 'ddr_bytes': traffic}
    phase = conv_stages(c, latency, bandwidth, macs, 'W5' in changes and c['index'] == 0)
    b, h = c['output_blocks'], c['output_height']
    if 'W5' in changes and c['index'] == 0:
        traffic -= c['feature_read'] * 13/16 + c['weight_read']/2
    copies = b
    if 'W4a' in changes:
        copies = 1
    if 'W4b' in changes:
        copies = 1
    if 'W4group' in changes:
        blocks_per_group = 131072 // c['weight_block_stride']
        copies = math.ceil(b / blocks_per_group)
    if copies < b:
        phase['feature'] *= copies/b
        traffic -= c['feature_read'] * (b-copies)/b
    # Compute the available row execution time before removing serial costs.
    row_execution = sum(phase[k] for k in ('mac', 'patch_pipeline', 'write_drain'))
    if 'W1' in changes:
        # Retain initial 2 rows (3x3) or 1 row (1x1) of every input pass.
        initial = (2 if c['kernel3'] else 1) / c['input_height']
        hideable = phase['feature'] * (1-initial)
        available = row_execution * (h-1)/h
        if 'W4a' in changes:
            available /= b
        phase['feature'] -= min(hideable, available)
    if 'W2' in changes:
        # The 3-cycle local drain bookkeeping remains; only external B delay
        # moves to the command boundary. Last command response still drains.
        phase['write_response'] -= max(0, b*h-1)*latency
    if 'W3' in changes:
        phase['quant'] /= b
        phase['weight'] /= b
    cycles = sum(phase.values())
    # Payload lower bound for shared R/W service, including overlapped stages.
    cycles = max(cycles, traffic / (bandwidth*1e9/150e6))
    return result | phase | {'cycles': cycles, 'ddr_bytes': traffic}


def network(rows, latency, bandwidth=4.8, changes=(), macs=512):
    output = [command(c, latency, bandwidth, changes, macs) for c in rows]
    if 'W6' in changes:
        # Residual fusion reads the shortcut while the conv producer writes.
        # Keep a conservative serialized service charge for the retained reads.
        for i, c in enumerate(rows):
            if c['kind'] == 'add':
                before = output[i-1]
                charge = c['operator_write'] / 32 * 4.8/bandwidth
                charge += math.ceil(c['beat_count']/16)*latency
                before['feature'] += charge
                before['cycles'] += charge
                before['ddr_bytes'] += output[i]['ddr_bytes']
                output[i]['ddr_bytes'] = 0
                before['cycles'] = max(before['cycles'], before['ddr_bytes'] /
                                       (bandwidth*1e9/150e6))
    return output


def total(rows):
    return sum(r['cycles'] for r in rows)


def equivalent_latency(rows, bandwidth=4.8):
    low, high = 0, 200
    while low < high:
        middle = (low+high)//2
        if total(network(rows, middle, bandwidth)) < BOARD_CYCLES:
            low = middle+1
        else:
            high = middle
    return low


def validate(rows):
    errors = []
    for latency, bandwidth in MEASUREMENTS:
        path = BUILD / f'l{latency}_b{bandwidth:g}.csv'
        measured = list(csv.DictReader(path.open()))
        modeled = network(rows, latency, bandwidth)
        for c, m, p in zip(rows, measured, modeled):
            cy = int(m['CY'])
            errors.append({'latency': latency, 'bandwidth': bandwidth,
                           'index': c['index'], 'name': c['name'],
                           'measured': cy, 'modeled': round(p['cycles'], 3),
                           'error_pct': (p['cycles']/cy-1)*100})
    write_csv(BUILD / 'calibration.csv', errors)
    return errors


def scenarios(rows, latency, base_bandwidth=4.8):
    cases = [('baseline', (), 512, 150, base_bandwidth)]
    cases += [(w, (w,), 512, 150, base_bandwidth) for w in
              ('W1', 'W2', 'W3', 'W4a', 'W4b', 'W4group', 'W5', 'W6')]
    cases += [(f'W7_{mhz}MHz_{macs}', (), macs, mhz, base_bandwidth)
              for mhz in (125, 150) for macs in (512, 1024)]
    combo = ('W1', 'W2', 'W3', 'W4a')
    cases += [(f'W1-W4_{macs}MAC', combo, macs, 150, base_bandwidth)
              for macs in (512, 1024)]
    cases += [(f'W1-W4b_{macs}MAC', ('W1', 'W2', 'W3', 'W4b'),
               macs, 150, base_bandwidth) for macs in (512, 1024)]
    cases += [('W1-W6', combo+('W5', 'W6'), 512, 150, base_bandwidth),
              ('W1-W7', combo+('W5', 'W6'), 1024, 150, base_bandwidth)]
    cases += [(f'W8_{bw}GBps', (), 512, 150, bw) for bw in (0.5, 1.0, 1.5, 2.0)]
    cases += [(f'W1-W7_BW{bw}GBps', combo+('W5', 'W6'), 1024, 150, bw)
              for bw in (0.5, 1.0, 1.5, 2.0)]
    result = []
    for name, changes, macs, mhz, bandwidth in cases:
        model = network(rows, latency, bandwidth, changes, macs)
        cycles = total(model)
        seconds = cycles/(mhz*1e6)
        traffic = sum(r['ddr_bytes'] for r in model)
        result.append({'case': name, 'latency': latency, 'macs': macs, 'mhz': mhz,
                       'cycles': round(cycles), 'ms': seconds*1000, 'fps': 1/seconds,
                       'post_ms': 4.15, 'fps_with_post': 1/(seconds+0.00415),
                       'ddr_bytes': round(traffic), 'avg_GBps': traffic/seconds/1e9,
                       'max_command_avg_GBps': max(r['ddr_bytes']/r['cycles']*mhz/1000
                                                   for r in model if r['cycles']),
                       'peak_limit_GBps': min(bandwidth, 4.8)*mhz/150})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--latency', type=int)
    parser.add_argument('--bandwidth-gbps', type=float, default=4.0)
    args = parser.parse_args()
    rows = analysis()
    errors = validate(rows)
    for latency, bandwidth in MEASUREMENTS:
        e = [r for r in errors if r['latency'] == latency and r['bandwidth'] == bandwidth]
        measured = sum(r['measured'] for r in e)
        modeled = sum(r['modeled'] for r in e)
        print(f'L={latency}, B={bandwidth}: RTL={measured}, model={modeled:.0f}, '
              f'error={(modeled/measured-1)*100:.3f}%, '
              f'max-command-error={max(abs(r["error_pct"]) for r in e):.3f}%')
    latency = (equivalent_latency(rows, args.bandwidth_gbps)
               if args.latency is None else args.latency)
    modeled = network(rows, latency, args.bandwidth_gbps)
    write_csv(BUILD / 'model_commands.csv', modeled)
    write_csv(BUILD / 'scenarios.csv', scenarios(rows, latency, args.bandwidth_gbps))
    phase = {s: sum(r[s] for r in modeled) for s in STAGES}
    summary = {'equivalent_latency': latency, 'bandwidth_gbps': args.bandwidth_gbps,
               'board_cycles': BOARD_CYCLES,
               'modeled_cycles': total(modeled), 'phases': phase,
               'latency_at_4_8GBps': equivalent_latency(rows, 4.8),
               'latency_at_2_6GBps': equivalent_latency(rows, 2.6)}
    (BUILD / 'model_summary.json').write_text(json.dumps(summary, indent=2)+'\n')
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
