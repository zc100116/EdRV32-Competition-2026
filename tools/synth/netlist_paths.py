#!/usr/bin/env python3
# File: netlist_paths.py
# Spec: C-Y1; CLAUDE.md 12.
# Description: Count mapped logic levels, fanout and resources for generic LUT6/XC7 netlists.
# Clock domain: host tool; no physical timing or clock-domain constraints.
"""Analyze generic/XC7 write_json paths or unflattened generic resource ownership."""
import argparse
from collections import Counter, defaultdict
from graphlib import TopologicalSorter
import json
from html import escape
from pathlib import Path
import re


def locations(raw):
    """Keep repository RTL source spans, excluding Yosys library implementation spans."""
    result = []
    for item in raw.split('|'):
        match = re.match(r'((?:rtl|fpga)/[^:]+):(\d+)\.\d+-(\d+)\.\d+', item)
        if match:
            file, first, last = match.groups()
            value = file + ':' + first + (('-' + last) if first != last else '')
            if value not in result:
                result.append(value)
    return result


def is_ff(kind):
    return bool(re.match(r'\$_(?:DFF|SDFF)', kind)) or kind in {
        'FDRE', 'FDSE', 'FDCE', 'FDPE', 'FDRE_1', 'FDSE_1', 'FDCE_1', 'FDPE_1'}


def is_lut(kind):
    return kind == '$lut' or bool(re.fullmatch(r'LUT[1-6]', kind))


def is_mux(kind):
    return bool(re.fullmatch(r'MUXF[5-9]', kind))


def is_carry(kind):
    return kind == '$alu' or 'CARRY' in kind.upper()


def is_lutram(kind):
    return kind in {'RAM32M', 'RAM64M', 'RAM32X1S', 'RAM64X1S', 'RAM128X1S',
                    'RAM256X1S', 'RAM32X1D', 'RAM64X1D', 'RAM128X1D', 'RAM256X1D'}


def is_srl(kind):
    return kind in {'SRL16E', 'SRLC32E'}


def memory_address_ports(kind, output, connections):
    if kind in {'RAM32M', 'RAM64M'}:
        return ['ADDR' + output[-1]]
    if is_srl(kind):
        return [port for port in connections if port.startswith('A')]
    prefix = 'DPRA' if output == 'DPO' else 'A'
    return [port for port in connections if port.startswith(prefix)]


def memory_write_port(kind, port):
    if is_srl(kind):
        return port in {'D', 'CE'}
    if kind in {'RAM32M', 'RAM64M'}:
        return port.startswith('DI') or port in {'WE', 'ADDRD'}
    return port in {'D', 'WE'} or port.startswith('A')


def analyze(design, starts=None, ends=None, end_nets=None):
    """Find longest paths between optional sets of signal/pin regular expressions.

    Selected internal start nets become cuts: their driver is excluded from the
    measured depth. Endpoint register names refer to Q, including D/enable pins.
    end_nets selects actual internal interface nets, without treating register Q
    aliases as D/enable endpoints.
    Filtering starts happens before depth propagation, not after global ranking.
    """
    top, = [name for name, module in design['modules'].items()
            if int(module.get('attributes', {}).get('top', '0'), 2)]
    module = design['modules'][top]
    cells = module['cells']
    aliases = defaultdict(list)
    for name, net in module['netnames'].items():
        for index, bit in enumerate(net['bits']):
            if isinstance(bit, int):
                offset = net.get('offset', 0)
                label = name + (f'[{index + offset}]' if len(net['bits']) > 1 else '')
                aliases[bit].append((name, label, net))

    def alias_key(item):
        name, _, net = item
        return (bool(net['hide_name']), not bool(re.search(r'_r(?:\[|$)', name)),
                -name.count('.'), len(name), name)

    def signal(bit):
        choices = sorted(aliases[bit], key=alias_key)
        if not choices:
            return {'signal': f'<net {bit}>', 'src': [], 'scope': ''}
        name, label, net = choices[0]
        return {'signal': label, 'src': locations(net['attributes'].get('src', '')),
                'scope': name.rpartition('.')[0]}

    scopes = {name: cell['attributes']['module'] for name, cell in cells.items()
              if cell['type'] == '$scopeinfo'}
    scopes[''] = top
    drivers = {}
    roots = {}
    endpoints = []
    direct_constants = 0
    graph = {}
    logic = {}
    loads = defaultdict(list)
    excluded = set()
    totals = Counter()
    by_file = defaultdict(Counter)
    by_module = defaultdict(Counter)
    missing_src = Counter()
    memories = []
    state_bit = -1

    def selected(patterns, bit, pin):
        names = [pin, pin.rsplit('[', 1)[0]] + [label for _, label, _ in aliases[bit]]
        return not patterns or any(re.search(pattern, name)
                                   for pattern in patterns for name in names)

    def endpoint(info, reference=None):
        bit = info['bit'] if reference is None else reference
        if (ends or not end_nets) and selected(ends, bit, info['pin']):
            endpoints.append(info)

    def point(bit, boundary, pin, src='', reference=None):
        info = signal(bit if reference is None else reference)
        return dict(info, bit=bit, boundary=boundary, pin=pin,
                    src=locations(src) or info['src'])

    def resource(cell, category, outputs):
        info = signal(outputs[0])
        src = locations(cell['attributes'].get('src', '')) or info['src']
        count = len(outputs) if category == 'FF' else 1
        file = src[0].rsplit(':', 1)[0] if src else '<ABC-unattributed>'
        owner = scopes.get(info['scope'], Path(file).stem) if src else '<ABC-unattributed>'
        by_file[file][category] += count
        by_module[owner][category] += count
        totals[category] += count
        if not src:
            missing_src[category] += count

    for name, port in module['ports'].items():
        for index, bit in enumerate(port['bits']):
            if not isinstance(bit, int):
                if port['direction'] == 'output':
                    direct_constants += 1
                continue
            info = point(bit, 'top', name + f'[{index}]')
            if port['direction'] == 'input':
                roots[bit] = info
                graph[bit] = set()
                drivers[bit] = info
            else:
                endpoint(info)
                loads[bit].append(info['pin'])

    for name, cell in cells.items():
        kind = cell['type']
        if kind == '$scopeinfo':
            continue
        ff = is_ff(kind)
        memory = is_lutram(kind) or is_srl(kind)
        blackbox = kind.startswith('ip_') and kind in design['modules'] and int(
            design['modules'][kind]['attributes'].get('blackbox', '0'), 2)
        output_pins = [(port, index, bit) for port, bits in cell['connections'].items()
                       if cell['port_directions'][port] == 'output'
                       for index, bit in enumerate(bits) if isinstance(bit, int)]
        outputs = [bit for _, _, bit in output_pins]
        if ff:
            resource(cell, 'FF', outputs)
        elif blackbox:
            totals['blackbox'] += 1
        elif memory:
            resource(cell, 'LUTRAM' if is_lutram(kind) else 'SRL', outputs)
            array = re.search(r'(btb_\w+_r|direction_r|registers_r|entries_r)',
                              name + ' ' + str(cell['attributes']))
            memories.append({'cell': name, 'type': kind,
                             'src': locations(cell['attributes'].get('src', '')),
                             'rtl_array': array[1] if array else '<unnamed-array>'})
        elif kind == 'DSP48E1':
            registered = {key: value for key, value in cell['parameters'].items()
                          if key.endswith('REG') and int(value, 2) != 0}
            if registered:
                raise ValueError(f'{name}: registered DSP48E1 is unsupported: {registered}')
            resource(cell, 'DSP', outputs)
        elif is_lut(kind) or is_carry(kind) or is_mux(kind) or kind == 'INV':
            category = ('LUT' if is_lut(kind) else 'carry' if is_carry(kind) else
                        'INV' if kind == 'INV' else 'MUX')
            resource(cell, category, outputs)
        else:
            raise ValueError(f'{name}: unsupported cell type {kind}')
        inputs = []
        q = cell['connections'].get('Q', outputs)
        for port, bits in cell['connections'].items():
            if cell['port_directions'][port] != 'input':
                continue
            clock = ((ff and port == 'C') or
                     ((blackbox or memory or kind == 'DSP48E1') and 'clk' in port.lower()))
            if kind == 'DSP48E1' and (port.startswith('CE') or port.startswith('RST')):
                continue
            for index, bit in enumerate(bits):
                if not isinstance(bit, int):
                    if (ff or blackbox or (memory and memory_write_port(kind, port))) and not clock:
                        direct_constants += 1
                    continue
                loads[bit].append(f'{name}.{port}[{index}]')
                if clock or (ff and port in ('R', 'S', 'CLR', 'PRE')):
                    excluded.add(bit)
                if clock:
                    continue
                inputs.append(bit)
                if ff or blackbox or (memory and memory_write_port(kind, port)):
                    reference = q[index] if ff else bit
                    endpoint(point(bit, 'FF' if ff else kind,
                                   f'{name}.{port}[{index}]',
                                   cell['attributes'].get('src', ''), reference), reference)
        for port, index, bit in output_pins:
            info = point(bit, 'FF' if ff else kind, f'{name}.{port}[{index}]',
                         cell['attributes'].get('src', ''))
            drivers[bit] = info
            if ff or blackbox:
                roots[bit] = info
                graph[bit] = set()
            elif memory:
                state = dict(info, signal=info['signal'] + ' <storage>', bit=state_bit,
                             pin=f'{name}.storage.{port}[{index}]')
                roots[state_bit] = state
                graph[state_bit] = set()
                if kind == 'SRLC32E' and port == 'Q31':
                    roots[bit] = info
                    graph[bit] = set()
                else:
                    address = memory_address_ports(kind, port, cell['connections'])
                    graph[bit] = {b for p in address for b in cell['connections'][p]
                                  if isinstance(b, int)} | {state_bit}
                    logic[bit] = (name, kind, info['src'])
                state_bit -= 1
            else:
                if kind == 'CARRY4':
                    conn = cell['connections']
                    bound = index + 1 if port == 'CO' else index
                    cone = conn['CI'] + conn['CYINIT'] + conn['DI'][:bound] + conn['S'][:bound]
                    if port == 'O':
                        cone += [conn['S'][index]]
                    graph[bit] = {b for b in cone if isinstance(b, int)}
                else:
                    graph[bit] = set(inputs)
                logic[bit] = (name, kind, info['src'])

    for bit, names in aliases.items():
        if any(re.search(r'(^|_)(clk|clock|rst|reset)(_|$)', n.rpartition('.')[2])
               for n, _, _ in names):
            excluded.add(bit)
    if starts:
        # Named internal nets may be used to measure a subcone such as hit -> D.
        cuts = {bit for bit in aliases if selected(starts, bit, '')}
        for bit in cuts - roots.keys():
            roots[bit] = point(bit, 'cut', drivers[bit]['pin'])
            graph[bit] = set()
        active_roots = {bit for bit, info in roots.items()
                        if bit in cuts or selected(starts, bit, info['pin'])}
    else:
        active_roots = set(roots)
    if end_nets:
        for bit in aliases:
            if selected(end_nets, bit, ''):
                endpoints.append(point(bit, 'net', drivers[bit]['pin']))
    # One maximal-depth predecessor per bit; ties follow ascending net number.
    depth = {}
    predecessor = {}
    for bit in TopologicalSorter(graph).static_order():
        if bit in roots:
            depth[bit] = 0 if bit in active_roots else None
        else:
            candidates = [b for b in sorted(graph[bit]) if depth[b] is not None]
            if candidates:
                prev = max(candidates, key=lambda b: depth[b])
                depth[bit] = depth[prev] + 1
                predecessor[bit] = prev
            else:
                depth[bit] = None
    reached = [end for end in endpoints if depth[end['bit']] is not None]
    histogram = Counter(depth[end['bit']] for end in reached)
    ranked = sorted(reached, key=lambda end: (-depth[end['bit']], end['pin']))
    paths = []
    for end in ranked[:50]:
        bit = end['bit']
        steps = []
        while bit in predecessor:
            name, kind, src = logic[bit]
            steps.append({'cell': name, 'type': kind, 'src': src,
                          'input_bit': predecessor[bit], 'output_bit': bit})
            bit = predecessor[bit]
        steps.reverse()
        compressed = []
        for step in steps:
            label = '|'.join(step['src']) or '<ABC:no-src>'
            if compressed and compressed[-1]['src'] == label:
                compressed[-1]['levels'] += 1
            else:
                compressed.append({'src': label, 'levels': 1})
        paths.append({'start': roots[bit], 'end': end, 'levels': len(steps),
                      'carry_levels': sum(is_carry(step['type']) for step in steps),
                      'lut_levels': sum(is_lut(step['type']) for step in steps),
                      'mux_levels': sum(is_mux(step['type']) for step in steps),
                      'dsp_levels': sum(step['type'] == 'DSP48E1' for step in steps),
                      'inv_levels': sum(step['type'] == 'INV' for step in steps),
                      'memory_levels': sum(is_lutram(step['type']) or is_srl(step['type'])
                                           for step in steps),
                      'sources': compressed, 'steps': steps})
    fanout = []
    for bit in sorted(loads, key=lambda bit: (-len(loads[bit]), bit)):
        if bit not in excluded:
            fanout.append(dict(signal(bit), bit=bit, fanout=len(loads[bit]),
                               src=drivers[bit]['src'], driver=drivers[bit]))
        if len(fanout) == 50:
            break
    return {'top': top, 'totals': dict(totals), 'max_levels': max(histogram, default=None),
            'histogram': dict(sorted(histogram.items())), 'endpoint_count': len(reached),
            'constant_endpoints': direct_constants + len(endpoints) - len(reached),
            'selected_start_bits': len(active_roots),
            'selected_endpoint_count': len(endpoints),
            'paths': paths, 'fanout': fanout,
            'by_file': dict(sorted(by_file.items())), 'by_module': dict(sorted(by_module.items())),
            'missing_src': dict(missing_src), 'memory_cells': memories}


def endpoint_text(point):
    src = ','.join(point['src']) or '无 src'
    return f"`{point['signal']}` ({src}; {point['boundary']}; `{point['pin']}`)"


def path_sources(path):
    return ' → '.join(f"{entry['src']} ×{entry['levels']}" for entry in path['sources'])


def markdown(result, limit=50):
    lines = [f"### {result['top']}", '',
             f"资源：{result['totals']}；最大级数：{result['max_levels']}。", '',
             '| 组合级数 | 终点 bit 数 |', '|---:|---:|']
    lines += [f'| {level} | {count} |' for level, count in result['histogram'].items()]
    lines += ['', f"计入 {result['endpoint_count']} 个终点；"
              f"无起点可达的常量终点 {result['constant_endpoints']} 个。", '',
              '| # | 起点 | 终点 | 总级数 | LUT | carry | MUX | INV | DSP | RAM/SRL | 源位置序列（相邻相同位置压缩） |',
              '|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---|']
    table_text = lambda value: escape(str(value), quote=False).replace('|', '&#124;')
    for index, path in enumerate(result['paths'][:limit], 1):
        lines.append('| ' + ' | '.join(map(table_text, [index, endpoint_text(path['start']),
                     endpoint_text(path['end']), path['levels'], path['lut_levels'],
                     path['carry_levels'], path['mux_levels'], path['inv_levels'],
                     path['dsp_levels'],
                     path['memory_levels'],
                     path_sources(path)])) + ' |')
    lines += ['', '| # | 驱动 RTL 信号/映射网络 | 源位置 | 扇出（负载 pin/bit） |', '|---:|---|---|---:|']
    for index, net in enumerate(result['fanout'][:limit], 1):
        lines.append(f"| {index} | `{table_text(net['signal'])}` | "
                     f"{table_text(','.join(net['src']) or '无 src')} | {net['fanout']} |")
    if result['memory_cells']:
        counts = Counter((item['type'], item['rtl_array'], ','.join(item['src']))
                         for item in result['memory_cells'])
        lines += ['', '| 存储单元 | RTL 阵列 | 源属性 | 数量 |', '|---|---|---|---:|']
        for (kind, array, src), count in sorted(counts.items()):
            values = [kind, array, src or '无 src', count]
            lines.append('| ' + ' | '.join(map(table_text, values)) + ' |')
    for field, title in [('by_file', '源文件'), ('by_module', '模块')]:
        lines += ['', f'| {title} | LUT | FF | carry |', '|---|---:|---:|---:|']
        for name, counts in result[field].items():
            lines.append(f"| {escape(name, quote=False)} | {counts.get('LUT', 0)} | "
                         f"{counts.get('FF', 0)} | "
                         f"{counts.get('carry', 0)} |")
    return '\n'.join(lines) + '\n'


def core_bypass_cone(module):
    """Union of mapped LUTs between named bypass outputs and the agreed signal cuts."""
    names = module['netnames']
    outputs = [f'd_operand_w[{index}]' for index in range(4)]
    cut_pattern = (r'(?:d_register_w|d_source_w|[emw]_result_w)\[\d+\]|'
                   r'[emw]_(?:valid_r|write_r|rd_r|class_r)(?:\[\d+\])?')
    cut_names = sorted(name for name in names if re.fullmatch(cut_pattern, name))
    cuts = {bit for name in cut_names for bit in names[name]['bits'] if isinstance(bit, int)}
    boundaries = {bit for port in module['ports'].values() if port['direction'] == 'input'
                  for bit in port['bits'] if isinstance(bit, int)}
    drivers = {}
    for name, cell in module['cells'].items():
        outputs_bits = [bit for port, bits in cell['connections'].items()
                        if cell['port_directions'][port] == 'output'
                        for bit in bits if isinstance(bit, int)]
        if cell['type'] == '$lut':
            for bit in outputs_bits:
                drivers[bit] = name
        else:
            boundaries.update(outputs_bits)
    pending = {bit for name in outputs for bit in names[name]['bits'] if isinstance(bit, int)}
    seen_bits = set()
    lut_cells = set()
    hit_cuts = set()
    while pending:
        bit = pending.pop()
        if bit in seen_bits:
            continue
        seen_bits.add(bit)
        if bit in cuts:
            hit_cuts.add(bit)
            continue
        if bit in boundaries:
            continue
        name = drivers[bit]
        lut_cells.add(name)
        cell = module['cells'][name]
        pending.update(bit for port, bits in cell['connections'].items()
                       if cell['port_directions'][port] == 'input'
                       for bit in bits if isinstance(bit, int))
    return {'LUT': len(lut_cells), 'output_signals': outputs, 'cut_signals': cut_names,
            'reached_cut_bits': len(hit_cuts), 'lut_cells': sorted(lut_cells)}


def frontend_shift_sources(module):
    """Count retained source spans covering the three measured frontend shift statements."""
    lines = (231, 267, 382)
    net_sources = defaultdict(list)
    for net in module['netnames'].values():
        for bit in net['bits']:
            if isinstance(bit, int):
                net_sources[bit].append(net['attributes'].get('src', ''))
    total = 0
    attributed = 0
    union = 0
    by_line = Counter({line: 0 for line in lines})
    for cell in module['cells'].values():
        if cell['type'] != '$lut':
            continue
        total += 1
        raw = [cell['attributes'].get('src', '')]
        for port, bits in cell['connections'].items():
            if cell['port_directions'][port] == 'output':
                for bit in bits:
                    raw.extend(net_sources[bit])
        spans = re.findall(r'rtl/cpu/edrv32_cpu_frontend.v:(\d+)\.\d+-(\d+)\.\d+',
                           '|'.join(raw))
        attributed += bool(spans)
        hits = [line for line in lines if any(int(first) <= line <= int(last)
                                              for first, last in spans)]
        by_line.update(hits)
        union += bool(hits)
    return {'frontend_LUT': total, 'with_frontend_src_LUT': attributed,
            'by_source_line_LUT': dict(by_line), 'source_union_LUT': union}


def hierarchy_resources(design):
    """Count owned cells once per hierarchical instance, without flattening."""
    top, = [name for name, module in design['modules'].items()
            if int(module.get('attributes', {}).get('top', '0'), 2)]
    totals = Counter()
    by_file = defaultdict(Counter)
    by_module = defaultdict(Counter)
    instances = {}
    bypass = {}
    frontend_sources = {}

    def visit(kind, path):
        module = design['modules'][kind]
        source = locations(module['attributes'].get('src', ''))
        file = source[0].rsplit(':', 1)[0] if source else '<generated-wrapper>'
        owner = Path(file).stem if source else kind
        if file == 'rtl/cpu/edrv32_cpu_core.v':
            bypass[path] = core_bypass_cone(module)
        if file == 'rtl/cpu/edrv32_cpu_frontend.v':
            frontend_sources[path] = frontend_shift_sources(module)
        own = Counter()
        for name, cell in module['cells'].items():
            typ = cell['type']
            if typ in design['modules']:
                if int(design['modules'][typ]['attributes'].get('blackbox', '0'), 2):
                    own['blackbox'] += 1
                else:
                    visit(typ, path + '.' + name)
            elif typ == '$lut':
                own['LUT'] += 1
            elif is_ff(typ):
                own['FF'] += len(cell['connections']['Q'])
            elif is_carry(typ):
                own['carry'] += 1
            elif typ != '$scopeinfo':
                raise ValueError(f'{path}.{name}: unsupported cell type {typ}')
        totals.update(own)
        by_file[file].update(own)
        by_module[owner].update(own)
        instances[path] = {'module': kind, 'src': source, 'own_cells': dict(own)}

    visit(top, top)
    return {'top': top, 'totals': dict(totals), 'by_file': dict(sorted(by_file.items())),
            'by_module': dict(sorted(by_module.items())), 'instances': instances,
            'bypass_cones': bypass, 'frontend_shift_sources': frontend_sources}


def resource_markdown(result):
    lines = [f"### 保留层次资源：{result['top']}", '', f"总数：{result['totals']}。", '']
    for field, title in [('by_file', '源文件'), ('by_module', '模块')]:
        lines += [f'| {title} | LUT | FF | 黑盒 |', '|---|---:|---:|---:|']
        for name, counts in result[field].items():
            lines.append(f"| {escape(name, quote=False)} | {counts.get('LUT', 0)} | "
                         f"{counts.get('FF', 0)} | "
                         f"{counts.get('blackbox', 0)} |")
        lines.append('')
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('netlist', type=Path)
    parser.add_argument('--hierarchical', action='store_true',
                        help='count resources per instance in an unflattened generic netlist')
    parser.add_argument('--start', action='append', help='start signal/pin regex; repeat for a set')
    parser.add_argument('--end', action='append', help='endpoint signal/pin regex; repeat for a set')
    parser.add_argument('--end-net', action='append', help='internal net regex; repeat for a set')
    args = parser.parse_args()
    if args.hierarchical:
        result = hierarchy_resources(json.loads(args.netlist.read_text()))
        args.netlist.with_name('resources.json').write_text(json.dumps(result, indent=2) + '\n')
        args.netlist.with_name('resources.md').write_text(resource_markdown(result))
        print(f"{result['top']}: hierarchical {result['totals']}")
        return
    result = analyze(json.loads(args.netlist.read_text()), args.start, args.end, args.end_net)
    prefix = 'xc7_paths' if args.netlist.stem == 'xc7' else 'paths'
    if args.start or args.end or args.end_net:
        prefix = 'filtered_' + prefix
    args.netlist.with_name(prefix + '.json').write_text(json.dumps(result, indent=2) + '\n')
    args.netlist.with_name(prefix + '.md').write_text(markdown(result))
    print(f"{result['top']}: {result['totals']}; max={result['max_levels']}")


if __name__ == '__main__':
    main()
