#!/usr/bin/env python3
# File: smoke.py
# Spec: cpu-v2-testplan 2/4 and V01 comparator acceptance.
# Description: Exercise independent known events and mutate each compared field family.
# Clock: host; tb drives retirement on clk_i.
"""Run once on the simulation host: python3 verif/unit/cpu2_trace_check/smoke.py."""
import argparse
from copy import deepcopy
import importlib.util
from pathlib import Path
import resource
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'build/cpu2_trace_check'
RFIELDS = {'pc': 32,
    'instr': 32,
    'rd': 5,
    'rd_domain': 2,
    'rd_data': 64,
    'flags': 5,
    'csr_valid': 1,
    'csr_addr': 12,
    'csr_data': 32,
    'mem_valid': 1,
    'mem_store': 1,
    'mem_addr': 32,
    'mem_data': 64,
    'mem_mask': 8}
STATE = {'fflags': 5, 'frm': 3, 'fs': 2}
TRAP = {'cause': 32, 'trap_pc': 32, 'tval': 32}
ALL = ('valid',
    'pc',
    'instr',
    'rd',
    'rd_domain',
    'rd_data',
    'flags',
    'csr_valid',
    'csr_addr',
    'csr_data',
    'mem_valid',
    'mem_store',
    'mem_addr',
    'mem_data',
    'mem_mask',
    'fflags',
    'frm',
    'fs',
    'trap',
    'cause',
    'trap_pc',
    'tval',
    'mem_effect_valid',
    'mem_effect_tag',
    'mem_effect_addr',
    'mem_effect_data',
    'mem_effect_mask',
    'redirect_valid',
    'redirect_tag',
    'redirect_pc',
    'redirect_target',
    'redirect_stage',
    'redirect_cause',
    'source0_valid',
    'source0_tag',
    'source0_domain',
    'source1_valid',
    'source1_tag',
    'source1_domain',
    'source2_valid',
    'source2_tag',
    'source2_domain',
    'source3_valid',
    'source3_tag',
    'source3_domain',
    'source4_valid',
    'source4_tag',
    'source4_domain')
BFM = ('valid', 'addr', 'data', 'mask')


def line(values):
    return ' '.join(f'{value:x}' for value in values) + '\n'


def make_vectors(width, fmt):
    cycles = []
    events = []
    state = dict(fflags=0, frm=0, fs=0)

    def cycle():
        values = {key: 0 for key in ALL}
        values.update(state)
        values.update({'bfm_' + key: 0 for key in BFM})
        values['finish'] = 0
        cycles.append(values)
        return values

    def retirement(pc, instr=0x00100093, **changes):
        values = {key: 0 for key in RFIELDS}
        values.update(pc=pc, instr=instr, rd=1, rd_domain=1, rd_data=1)
        values.update(changes)
        values.update(state)
        values['next_pc'] = pc + 4
        events.append((1, values))
        return values

    def emit(values, *items):
        for slot, item in enumerate(items):
            values['valid'] |= 1 << slot
            for key, bits in RFIELDS.items():
                values[key] |= item[key] << (slot * bits)
        values.update(state)

    def effect(values, addr, data, tag=1, bfm=False, mask=15):
        prefix = 'bfm_' if bfm else 'mem_effect_'
        values.update({prefix + 'valid': 1, prefix + 'addr': addr,
                        prefix + 'data': data, prefix + 'mask': mask})
        if not bfm:
            values[prefix + 'tag'] = tag

    first = retirement(0x80000000)
    emit(cycle(), first)
    older = retirement(0x80000004, instr=0x00700113, rd=2, rd_data=7)
    if fmt != 'NONE':
        state.update(fs=3, fflags=1)
    younger = retirement(0x80000008, instr=0x1820f053 if fmt != 'NONE' else 0x00200193,
                            rd=0 if fmt != 'NONE' else 3,
                            rd_domain=2 if fmt != 'NONE' else 1,
                            rd_data=(0xffffffff3f800000 if fmt == 'FD' else
                                    (0x3f800000 if fmt == 'F' else 2)),
                            flags=0 if fmt == 'NONE' else 1)
    if width == 2:
        emit(cycle(), older, younger)
    else:
        # Older event still precedes the FP state update.
        old_cycle = cycle()
        emit(old_cycle, older)
        old_cycle.update({key: older[key] for key in STATE})
        emit(cycle(), younger)
    low = cycle()
    effect(low, 0xc0001000, 0x89abcdef)
    store = retirement(0x8000000c, instr=0x00103027 if fmt == 'FD' else 0x00102023,
                        rd_domain=0, rd=0, rd_data=0, mem_valid=1, mem_store=1,
                        mem_addr=0xc0001000, mem_data=0x0123456789abcdef if fmt == 'FD'
                        else 0x89abcdef, mem_mask=255 if fmt == 'FD' else 15)
    values = cycle()
    emit(values, store)
    effect(values, 0xc0001000, 0x89abcdef, bfm=True)
    if fmt == 'FD':
        effect(values, 0xc0001004, 0x01234567)
        effect(cycle(), 0xc0001004, 0x01234567, bfm=True)
    load = retirement(0x80000010, instr=0x00008203, rd=4, rd_data=0xffffff80,
                        mem_valid=1, mem_addr=0x1003, mem_data=0x80, mem_mask=1)
    emit(cycle(), load)
    if fmt != 'NONE':
        state.update(fflags=4, frm=2)
    csr = retirement(0x80000014, instr=0x00309073 if fmt != 'NONE' else 0x34009073,
                        rd_domain=0, csr_valid=1, csr_addr=3 if fmt != 'NONE' else 0x340,
                        csr_data=0x44 if fmt != 'NONE' else 0x123)
    emit(cycle(), csr)
    # Cacheable effects compare to Spike architectural stores, including both D beats.
    cached = retirement(0x80000100, instr=0x00103027 if fmt == 'FD' else 0x00102023,
                        rd_domain=0, mem_valid=1, mem_store=1, mem_addr=0x10000000,
                        mem_data=0x1122334455667788 if fmt == 'FD' else 0x55667788,
                        mem_mask=255 if fmt == 'FD' else 15)
    values = cycle()
    effect(values, 0x10000000, 0x55667788)
    emit(values, cached)
    if fmt == 'FD':
        effect(cycle(), 0x10000004, 0x11223344)
    byte = retirement(0x80000104, instr=0x001001a3, rd_domain=0,
                        mem_valid=1, mem_store=1, mem_addr=0x10000003,
                        mem_data=0xa5, mem_mask=1)
    values = cycle()
    emit(values, byte)
    effect(values, 0x10000003, 0xa5, mask=1)
    # Known same-edge retired branch relation; older in-flight redirects belong to V02.
    branch = retirement(0x80000018, instr=0x00000463, rd_domain=0)
    branch['next_pc'] = 0x80000020
    values = cycle()
    emit(values, branch)
    values.update(redirect_valid=1, redirect_stage=2, redirect_cause=1,
                    redirect_pc=0x80000018, redirect_target=0x80000020, redirect_tag=1)
    values = cycle()
    values.update(redirect_valid=1, redirect_stage=1, redirect_cause=3,
                    redirect_pc=0x90000000, redirect_target=0x90000004)
    # Physical maximum source ports: configured ports only are live.
    source_count = (2 * width if fmt in ('NONE', 'FD') else (3 if width == 1 else 5))
    for index in range(source_count):
        values[f'source{index}_valid'] = 1
        values[f'source{index}_tag'] = index
        values[f'source{index}_domain'] = int(fmt != 'NONE' and index == 0)
    if fmt == 'FD':
        # Low beat survives; failed high beat never appears as an effect or retirement.
        effect(cycle(), 0xc0002018, 0xdeadbeef, tag=3)
    old = retirement(0x80000020, rd=6, rd_data=9)
    values = cycle()
    emit(values, old)
    values.update(trap=1, cause=7, trap_pc=0x80000024, tval=0xc000201c)
    events.append((2, dict(cause=7, trap_pc=0x80000024, tval=0xc000201c, **state)))
    if fmt == 'FD':
        effect(values, 0xc0002018, 0xdeadbeef, tag=3, bfm=True)
    cycle()['finish'] = 1
    expected = ''
    for kind, values in events:
        fields = tuple(key for key in RFIELDS if key != 'flags') + tuple(STATE) + ('next_pc',)
        if kind == 2:
            fields = tuple(TRAP) + tuple(STATE)
        expected += line([kind] + [values[key] for key in fields])
    for values in cycles:
        if not values['valid'] and not values['trap']:
            # Frozen trace contract leaves architectural payloads unspecified on idle cycles.
            values.update(fflags=31, frm=7, fs=3)
    return cycles, expected


def write_stimulus(path, cycles):
    path.write_text(''.join(line([values['finish']] + [values[key] for key in ALL] +
                                [values['bfm_' + key] for key in BFM]) for values in cycles))


def run_case(binary, folder, name, cycles, diagnostic=None):
    stimulus = folder / 'stimulus.txt'
    write_stimulus(stimulus, cycles)
    result = subprocess.run([str(binary), '+TRACE_EXPECT=' + str(folder / 'expected.txt'),
                                '+STIMULUS=' + str(stimulus)], text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (folder / (name + '.log')).write_text(result.stdout)
    if diagnostic is None:
        assert result.returncode == 0 and 'PASS trace' in result.stdout, result.stdout
    else:
        assert result.returncode != 0 and 'field=' + diagnostic in result.stdout, result.stdout


def converter_tests():
    spec = importlib.util.spec_from_file_location(
        'converter', ROOT / 'tools/cpu/cpu2_spike_trace.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    log = (HERE / 'spike_commits.txt').read_text().splitlines()
    result = module.convert(log, 'FD')
    assert result == (HERE / 'spike.expected').read_text()
    # No sticky-bit subtraction: repeated fflags=8 still leaves cumulative fflags=8.
    repeated = module.convert([
        'core 0: 3 0x1000 (0x182070d3) f1 0xffffffff7f800000 c1_fflags 0x00000008',
        'core 0: 3 0x1004 (0x182070d3) f1 0xffffffff7f800000 c1_fflags 0x00000008'], 'FD')
    assert all(int(row.split()[-4], 16) == 8 for row in repeated.splitlines())
    for bad in ('core 0: 3 0x1000 (0x00002083)',
                'core 0: 3 0x1000 (0x00102023) mem 0x2000',
                'core 0: 3 0x1000 (0x30009073)',
                'core 0: exception trap_illegal_instruction, epc 0x1000',
                'core 0: 3 0x1000 (0x30101073) c769_misa 0x40000100',
                'core 0: 3 0x1000 (0xc00020f3) x1 0x123',
                'core 0: 3 0x1000 (0x003fd073) c1_fflags 0x1f'):
        try:
            module.convert([bad], 'FD')
        except ValueError:
            pass
        else:
            raise AssertionError('missing log field accepted: ' + bad)
    aliases = module.convert([
        'core 0: 3 0x1000 (0x003fd073) c1_fflags 0x1f c2_frm 0x0',
        'core 0: 3 0x1004 (0x0023d073) c2_frm 0x7',
        'core 0: 3 0x1008 (0x00105073) c1_fflags 0x0',
        'core 0: exception trap_load_access_fault, epc 0x100c',
        'core 0:           tval 0xc0001234',
        'core 0: exception interrupt #7, epc 0x100c'], 'FD')
    assert aliases.splitlines()[0].split()[6:9] == ['1', '3', '1f']
    assert aliases.splitlines()[3] == '2 5 100c c0001234 0 7 3'
    assert aliases.splitlines()[4] == '2 80000007 100c 0 0 7 3'
    raw = ['core 0: 3 0x1000 (0xf0000053) f0 0xffffffff89abcdef']
    assert module.convert(raw, 'F').split()[5] == '89abcdef'
    assert module.convert(raw, 'FD').split()[5] == 'ffffffff89abcdef'
    raw = module.convert([
        'core 0: 3 0x1000 (0x00000083) x1 0xffffff80 mem 0xc0001003',
        'core 0: 3 0x1004 (0x00103027) mem 0xc0001008 0x1122334455667788'], 'FD')
    assert raw.splitlines()[0].split()[9:14] == ['1', '0', 'c0001003', '80', '1']
    assert raw.splitlines()[1].split()[9:14] == [
        '1', '1', 'c0001008', '1122334455667788', 'ff']
    for fmt in ('NONE', 'F', 'FD'):
        assert '_zba' in module.ISA[fmt]
    print('PASS converter: real Spike fixture, sticky flags, CSR aliases, traps, missing fields')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--issue-width', type=int, choices=(1, 2))
    parser.add_argument('--format', choices=('NONE', 'F', 'FD'))
    parser.add_argument('--converter-only', action='store_true')
    args = parser.parse_args()
    if args.converter_only:
        converter_tests()
        return
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    OUT.mkdir(parents=True, exist_ok=True)
    total = 0
    widths = (args.issue_width,) if args.issue_width else (1, 2)
    formats = (args.format,) if args.format else ('NONE', 'F', 'FD')
    for width in widths:
        for fmt in formats:
            folder = OUT / f'{width}-{fmt}'
            folder.mkdir(exist_ok=True)
            obj = folder / 'obj'
            command = ['verilator', '--timing', '-Wall', '--top-module', 'tb',
                        '-GISSUE_WIDTH=' + str(width), '-GFPU_FORMAT="' + fmt + '"',
                        str(ROOT / 'verif/common/cpu2_trace/edrv32_cpu2_trace_check.sv'),
                        str(HERE / 'tb.sv')]
            for mode in (['--lint-only'], ['--binary', '-j', '1', '--Mdir', str(obj), '-o', 'sim']):
                invocation = ([str(ROOT / 'tools/check/lint.sh')] + command[1:]
                                if mode[0] == '--lint-only' else command + mode)
                result = subprocess.run(invocation, text=True, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT)
                (folder / ('lint.log' if mode[0] == '--lint-only' else 'compile.log')).write_text(
                    result.stdout)
                assert result.returncode == 0, result.stdout
            cycles, expected = make_vectors(width, fmt)
            (folder / 'expected.txt').write_text(expected)
            run_case(obj / 'sim', folder, 'good', cycles)
            total += 1
            # Payload families; every meaningful compared retirement/trap field is corrupted.
            mutations = []
            for key in RFIELDS:
                if key == 'flags':
                    continue  # Per-instruction flags belong to SoftFloat unit vectors.
                index = next(i for i, values in enumerate(cycles)
                                if values['valid'] and (key not in ('csr_addr', 'csr_data') or
                                                    values['csr_valid']) and
                                (not key.startswith('mem_') or values['mem_valid']))
                mutations.append((key, index, key, 1, key))
            mutations.append(('integer_upper_result', 0, 'rd_data', 1 << 63, 'rd_data'))
            for key in STATE:
                mutations.append((key, 0, key, 1, key))
            for key in TRAP:
                index = next(i for i, values in enumerate(cycles) if values['trap'])
                mutations.append((key, index, key, 1, key))
            index = next(i for i, values in enumerate(cycles) if values['mem_effect_valid'])
            for key in ('addr', 'data', 'mask'):
                mutations.append(('effect_' + key, index, 'mem_effect_' + key, 1,
                                    'mem_effect_' + key))
            cached = next(i for i, values in enumerate(cycles)
                            if values['mem_effect_addr'] == 0x10000000)
            for key in ('addr', 'data', 'mask'):
                mutations.append(('cache_effect_' + key, cached, 'mem_effect_' + key,
                                    1, 'cache_effect_' + key))
            index = next(i for i, values in enumerate(cycles) if values['redirect_stage'] == 1)
            mutations += [('f2_tag', index, 'redirect_tag', 1, 'redirect_tag'),
                            ('f2_cause', index, 'redirect_cause', 1, 'redirect_cause'),
                            ('redirect_stage', index, 'redirect_stage', 1, 'redirect_stage')]
            branch = next(i for i, values in enumerate(cycles) if values['redirect_stage'] == 2)
            mutations.append(('redirect_target', branch, 'redirect_target', 4, 'redirect_target'))
            source_count = (2 * width if fmt in ('NONE', 'FD') else (3 if width == 1 else 5))
            fp_ports = 0 if fmt == 'NONE' else (3 if fmt == 'F' else 2)
            for source in range(fp_ports, source_count):
                mutations.append((f'source{source}_domain', index,
                                    f'source{source}_domain', 1, f'source{source}_domain'))
            source_count = (2 * width if fmt in ('NONE', 'FD') else (3 if width == 1 else 5))
            if source_count < 5:
                mutations.append(('source_port', index, f'source{source_count}_valid', 1,
                                    f'source{source_count}_port'))
            if fmt == 'NONE':
                mutations.append(('flags_none', 0, 'flags', 1, 'flags_none'))
            if width == 2:
                dual = next(i for i, values in enumerate(cycles) if values['valid'] == 3)
                mutations.append(('valid_age_order', dual, 'valid', 1, 'valid_age_order'))
                mutations.append(('young_pc', dual, 'pc', 1 << 32, 'pc'))
                mutations.append(('young_rd', dual, 'rd', 1 << 5, 'rd'))
            if fmt == 'FD':
                fp = next(i for i, values in enumerate(cycles)
                            if values['valid'] and values['rd_domain'] in (2, 9))
                slot = int(width == 2)
                mutations.append(('fp_upper_result', fp, 'rd_data', 1 << (64*slot + 63),
                                    'rd_data'))
            for name, key, diagnostic, cached_only in [
                    ('missing_device_effect', 'mem_effect_valid', 'mem_effect_missing', False),
                    ('missing_cache_effect', 'mem_effect_valid', 'cache_effect_missing', True)]:
                bad = deepcopy(cycles)
                for values in bad:
                    cached_addr = 0x10000000 <= values['mem_effect_addr'] < 0x10010000
                    if cached_addr == cached_only:
                        values[key] = 0
                run_case(obj / 'sim', folder, name, bad, diagnostic)
                total += 1
            for name, index, key, delta, diagnostic in mutations:
                bad = deepcopy(cycles)
                bad[index][key] ^= delta
                run_case(obj / 'sim', folder, name, bad, diagnostic)
                total += 1
            for name, key, diagnostic in [('extra_retirement', 'valid', 'retire_present'),
                                            ('extra_effect', 'mem_effect_valid',
                                            'mem_effect_extra')]:
                bad = deepcopy(cycles)
                bad[-1][key] = 1
                run_case(obj / 'sim', folder, name, bad, diagnostic)
                total += 1
            for name, key, diagnostic in [('missing_trap', 'trap', 'architectural_eof'),
                                            ('missing_effect', 'mem_effect_valid',
                                            'cache_effect_missing')]:
                bad = deepcopy(cycles)
                for values in bad:
                    values[key] = 0
                run_case(obj / 'sim', folder, name, bad, diagnostic)
                total += 1
            print(f'PASS ISSUE_WIDTH={width} FPU_FORMAT={fmt}: good + {len(mutations)+6} negatives')
    print(f'PASS cpu2_trace_check smoke: {total} simulations, zero lint warnings')


if __name__ == '__main__':
    main()
