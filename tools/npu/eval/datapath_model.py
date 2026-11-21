"""N-E2 512-MAC stage estimates; no RTL implementation or synthesis.

SoC spec 8.9 and task N-E2. See the accompanying report for the explicitly
conditional overlap and physical RAM mapping assumptions. Legacy W schedules
remain in npu_model; this module changes only the D2/D3 stage envelope.
"""

import math

from npu_model import STAGES, command as legacy_command, conv_stages, writer_timing

C0 = ('W1', 'W2', 'W3', 'W4b', 'W5', 'W6')
COMBINATIONS = (('C0', C0), ('C0+D2', C0+('D2',)),
                ('C0+D3a', C0+('D3a',)), ('C0+D3b', C0+('D3b',)),
                ('C0+D2+D3a', C0+('D2', 'D3a')),
                ('C0+D2+D3b', C0+('D2', 'D3b')))
CASES = [('baseline', ())] + [(w, (w,)) for w in
         ('W1', 'W2', 'W3', 'W4b', 'W5', 'W6', 'D2', 'D3a', 'D3b')]
CASES += list(COMBINATIONS)


def datapath_stages(c, latency, bandwidth=4.0, changes=()):
    """Reissue MAC/patch/writer phases with the proposed activation geometry.

    D2 pairs two C8 halves of the same C16 and adds one merge pipeline clock
    per chunk (per row for direct feed). First C3 stays under W5's model.
    D3a needs W1, keeps the initial fill of each C32 pass, and hides only the
    next first chunk that fits in the previous last chunk's MAC window.
    D3b replaces materialized patches with registered direct reads, keeping
    14 row pipeline clocks, quantizer throughput, writer stalls and drains.
    """
    first_c3 = 'W5' in changes and c['index'] == 0
    phase = conv_stages(c, latency, bandwidth, first_c3=first_c3)
    b, h = c['output_blocks'], c['output_height']
    pairs, tile = c['output_width_pairs'], c['tile_pairs']
    tiles = math.ceil(pairs/tile)
    k = 9 if first_c3 else c['cin_blocks']*2*(9 if c['kernel3'] else 1)
    direct = 'D3b' in changes
    quant_pair_cycles = 2 if 'Q32' in changes else 4
    for key in ('mac', 'patch_pipeline', 'write_drain', 'write_response'):
        phase[key] = 0.0
    for block in range(b):
        half = ('D2' in changes and c['index'] != 0 and
                c['last_c16_only'] and block == b-1)
        block_k = k//2 if half else k
        merge = int(half)
        phase['mac'] += h*pairs*block_k
        first = min(pairs, tile)*block_k
        last = (pairs-(tiles-1)*tile)*block_k
        if direct:
            phase['patch_pipeline'] += h*(
                14+merge+pairs*max(0, quant_pair_cycles-block_k))
        else:
            phase['patch_pipeline'] += h*(first+(10+merge)*tiles+14)
            if 'D3a' in changes and 'W1' in changes:
                phase['patch_pipeline'] -= (h-1)*min(first, last)
        planes = 1 if c['last_c16_only'] and block == b-1 else 2
        for y in range(h):
            addr0 = c['output_base']+2*block*c['output_plane_stride']+y*pairs*32
            addr1 = addr0+c['output_plane_stride']
            stalls, tail, response = writer_timing(
                block_k, pairs, tile, planes, (addr0//32)%128, (addr1//32)%128,
                latency, bandwidth, direct=direct, merge=merge,
                quant_pair_cycles=quant_pair_cycles)
            phase['patch_pipeline'] += stalls
            phase['write_drain'] += tail
            phase['write_response'] += response
    return phase


def close_budget(r, bandwidth):
    """Expose shared R/W payload enforcement as a mutually exclusive phase."""
    r['schedule_cycles'] = sum(r[s] for s in STAGES)
    r['payload_cycles'] = r['ddr_bytes']/(bandwidth*1e9/150e6)
    r['payload_wait'] = max(0, r['payload_cycles']-r['schedule_cycles'])
    r['cycles'] = r['schedule_cycles']+r['payload_wait']
    r['demand_GBps'] = (r['ddr_bytes']/r['schedule_cycles']*0.15
                         if r['schedule_cycles'] else 0.0)
    r['payload_limited'] = r['payload_wait'] > 0
    return r


def command(c, latency=94, bandwidth=4.0, changes=()):
    has_datapath = any(d in changes for d in ('D2', 'D3a', 'D3b'))
    inherited = tuple(w for w in changes if not (has_datapath and w == 'W1'))
    r = legacy_command(c, latency, bandwidth, inherited)
    if has_datapath and c['kind'] == 'conv':
        d = datapath_stages(c, latency, bandwidth, changes)
        for key in ('mac', 'patch_pipeline', 'write_drain', 'write_response'):
            r[key] = d[key]
        if 'W2' in changes:
            r['write_response'] -= (c['output_blocks']*c['output_height']-1)*latency
        if 'W1' in changes:
            initial = (2 if c['kernel3'] else 1)/c['input_height']
            window = sum(r[s] for s in ('mac', 'patch_pipeline', 'write_drain'))
            window *= (c['output_height']-1)/c['output_height']
            r['feature'] -= min(r['feature']*(1-initial), window)
    # Track read and write separately, including W6's operand-only add.
    writes = c['ddr_write']
    if 'W6' in changes and c['kind'] == 'add':
        writes = 0
    r['ddr_write'] = writes
    r['ddr_read'] = r['ddr_bytes']-writes
    return close_budget(r, bandwidth)


def network(rows, latency=94, bandwidth=4.0, changes=()):
    result = [command(c, latency, bandwidth, changes) for c in rows]
    if 'W6' in changes:
        for i, c in enumerate(rows):
            if c['kind'] == 'add':
                before, add = result[i-1], result[i]
                charge = c['operator_write']/32*4.8/bandwidth
                charge += math.ceil(c['beat_count']/16)*latency
                before['feature'] += charge
                for key in ('ddr_bytes', 'ddr_read', 'ddr_write'):
                    before[key] += add[key]
                    add[key] = 0
                close_budget(before, bandwidth)
                close_budget(add, bandwidth)
    return result


def summarize(name, model, bandwidth):
    cycles = sum(r['cycles'] for r in model)
    traffic = sum(r['ddr_bytes'] for r in model)
    seconds = cycles/150e6
    return dict(case=name, bandwidth=bandwidth, cycles=cycles, ms=seconds*1000,
                fps=1/seconds, fps_with_post=1/(seconds+0.00415),
                ddr_read=sum(r['ddr_read'] for r in model),
                ddr_write=sum(r['ddr_write'] for r in model), ddr_bytes=traffic,
                avg_GBps=traffic/seconds/1e9,
                max_command_avg_GBps=max(r['ddr_bytes']/r['cycles']*0.15
                                         for r in model if r['cycles']))


def breakdown(rows, model):
    useful = sum(c['real_mac'] for c in rows)/512
    phases = {'useful_mac': useful,
              'padding_mac': sum(r['mac'] for r in model)-useful}
    phases.update({s: sum(r[s] for r in model) for s in STAGES if s != 'mac'})
    phases['payload_wait'] = sum(r['payload_wait'] for r in model)
    return phases


def resident_weights(rows):
    """Eight 256-bit weight banks, each built from 512x64 SDP slices.

    No byte-capacity-only division: bank depth and width both round up.
    Quant parameters and 512-byte DMA records retain the legacy FF layout.
    Sixteen independently addressed LUT copies use sixteen 4Kx8 slices.
    """
    result = []
    for c in rows:
        if c['kind'] != 'conv':
            continue
        # One full K row spans all eight banks, irrespective of output block.
        depth_per_bank = c['weight_read']//256
        result.append(dict(index=c['index'], name=c['name'], blocks=c['output_blocks'],
                           weight_bytes=c['weight_read'], bank_depth=depth_per_bank,
                           weight_drm=8*4*math.ceil(depth_per_bank/512),
                           params_bytes=c['output_blocks']*256,
                           lut_bytes=c['output_blocks']*4096,
                           records_bytes=c['output_blocks']*512))
    return result
