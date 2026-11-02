#!/usr/bin/env python3
# File: b1_stimulus.py; Spec: cpu-testplan 2.3, 3.3-3.7; Clock: host.
# Resolve directed-test ELF labels into the B1 model and observer plusargs.
import re


def address(expression, names):
    if expression.endswith(' & ~7'):
        return names[expression[:-5]] & ~7
    if '-' in expression:
        label, offset = expression.rsplit('-', 1)
        return names[label] - int(offset, 0)
    if '+' in expression:
        label, offset = expression.split('+')
        return names[label] + int(offset, 0)
    return int(expression, 0) if expression.startswith('0x') else names[expression]


def plusargs(config, names, out):
    args = ['+TEST_ID=' + config['test']]
    for symbol, argument in (('expected_instret', 'EXPECTED_INSTRET'),
                             ('expected_hpm', 'EXPECTED_HPM')):
        if symbol in names:
            args.append(f'+{argument}={names[symbol]:x}')
    if 'stores_begin' in names:
        args.append(f'+STORES_BEGIN={names["stores_begin"]:x}')
    obligations = []
    for case in config.get('cases', []):
        if 'source_stage' in case:
            field = case['consumer_slot'] * 2 + case['operand'] - 1
            source = {'E': 1, 'M': 3, 'W': 5}[case['source_stage']] + case['source_pipe']
            obligations.append((1, names[case['consumer']], names[case['producer']], field, source))
        elif 'latency' in case:
            obligations.append((2, names[case['consumer']], names[case['producer']],
                                case['latency'], case['gap']))
        elif 'pc0' in case:
            obligations.append((4 if 'pair' in case else 3,
                                address(case['pc0'], names), address(case['pc1'], names),
                                int(case.get('pair', False)), int(case.get('swap', False))))
            if config['test'] == 'p-02':
                obligations.append((9, address(case['pc0'], names),
                                    address(case['pc1'], names), 0, 0))
        elif 'redirect' in case:
            obligations.append((5 if case['stage'] == 'E' else 6,
                                names[case['redirect']], names[case['target']],
                                case['slot'], case['cause']))
        elif 'fault' in case:
            obligations.append((7, names[case['fault']], 0, case['slot'], case['cause']))
        elif 'no_request' in case:
            obligations.append((8, names[case['no_request']], 0, 0, 0))
    path = out / 'obligations.txt'
    path.write_text(''.join(f'{kind} {pc:x} {other:x} {a} {b}\n'
                            for kind, pc, other, a, b in obligations))
    if obligations:
        args.append('+OBLIGATIONS=' + str(path))
    irqs = []
    errors = []
    delays = []
    masks = dict(MEIP=1, MSIP=2, MTIP=4)
    for event in config['schedule']:
        kind = event['kind']
        if kind == 'mtime':
            args.append('+MTIME_FIXED=' + format(int(event['value'], 0), 'x'))
        elif kind == 'error':
            if event['port'] == 'ic':
                args.append('+IC_ERROR_ADDR=' + format(address(event['address'], names), 'x'))
            else:
                errors.append(names[event['pc']])
                if 'response_delay' in event:
                    delays.append((names[event['pc']], event['response_delay']))
        elif kind == 'delay':
            if event['port'] == 'ic':
                args += ['+IC_DELAY_ADDR=' + format(address(event['address'], names), 'x'),
                         '+IC_DELAY_CYCLES=' + str(event['cycles'])]
            else:
                delays.append((names[event['pc']], event['cycles']))
        elif kind == 'irq':
            when = event['when']
            if 'current_wfi_pc' in when:
                args.append('+WAKE_EVERY_WFI')
                continue
            if when == 'FENCE.I.clean':
                mode, pc = 7, names[event['pc']]
            elif when.startswith('M.pc='):
                mode, pc = 1, names[when[5:]]
            elif 'divider.pc=' in when:
                mode, pc = 2, names[when.split('divider.pc=')[1]]
            elif when.startswith('debug[26]'):
                mode, pc = 3, names[when.split('M.pc=')[1]]
            elif when.startswith('debug[28]'):
                mode, pc = 4, names[when.split('M.pc=')[1]]
            elif when.startswith('E.redirect'):
                mode, pc = 5, names[when.split('E.pc=')[1]]
            elif when.startswith('debug[29] after '):
                mode, pc = 6, names[when.split()[2]]
            else:
                raise ValueError(f'unknown IRQ condition: {when}')
            sources = event['source']
            if isinstance(sources, str):
                sources = [sources]
            clear = names[event['clear'][5:]] if event['clear'].startswith('M.pc=') else 0
            irqs.append((mode, pc, sum(masks[s] for s in sources),
                         event.get('after_cycles', 0), clear))
        elif kind == 'maintenance_delay':
            args.append('+' + event['operation'].upper() + '_DELAY=' + str(event['cycles']))
        elif kind == 'write_buffer_hold':
            args += [f'+WB_HOLD_PC={names[event["pc"]]:x}',
                     '+WB_HOLD_CYCLES=' + str(event['cycles'])]
        elif kind == 'paired_run':
            args += [f'+PREDICTOR_PC={names["probe_branch"]:x}',
                     '+PREDICTOR_FILE=' + str(out / 'predictor.txt')]
        elif kind in ('reference_write', 'event_window', 'debug_observer'):
            # These obligations are implemented by the directed observer / paired run.
            pass
        else:
            raise ValueError(kind)
    args.append('+IRQ_COUNT=' + str(len(irqs)))
    for index, (mode, pc, mask, delay, clear) in enumerate(irqs):
        args += [f'+IRQ{index}_KIND={mode}', f'+IRQ{index}_PC={pc:x}',
                 f'+IRQ{index}_MASK={mask}', f'+IRQ{index}_DELAY={delay}',
                 f'+IRQ{index}_CLEAR_PC={clear:x}']
    args.append('+DC_ERROR_COUNT=' + str(len(errors)))
    args += [f'+DC_ERROR{i}_PC={pc:x}' for i, pc in enumerate(errors)]
    args.append('+DC_DELAY_COUNT=' + str(len(delays)))
    for index, (pc, delay) in enumerate(delays):
        args += [f'+DC_DELAY{index}_PC={pc:x}', f'+DC_DELAY{index}_CYCLES={delay}']
    return args
