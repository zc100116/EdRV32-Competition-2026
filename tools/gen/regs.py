#!/usr/bin/env python3
# File: regs.py
# Spec: edrv32-soc-spec 7.1; engine specifications section 4.
# Description: Generate C and Verilog constants from engine JSON tables.
#              Preserve table order and keep generated headers reproducible.
# Clock domain: none (host tool).
"""Generate engine C and Verilog headers from rtl/include/regs/*.json."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def constant(lines, name, value):
    lines.append(f'#define {name} 0x{value:08X}u')


def field_constants(lines, prefix, field):
    name = prefix + '_' + field['name']
    lines.append(f'/* {field["spec"]} */')
    constant(lines, name + '_POS', field['lsb'])
    constant(lines, name + '_WIDTH', field['width'])
    mask = ((1 << field['width']) - 1) << field['lsb']
    constant(lines, name + '_MASK', mask)


def register_constants(lines, prefix, register):
    name = prefix + '_' + register['name']
    lines.append(f'/* {register["spec"]}; {register["access"]}; '
                 f'reset: {json.dumps(register["reset"])}. */')
    if 'reset_status' in register:
        lines.append(f'/* Reset metadata: {register["reset_status"]}. */')
    if 'note' in register:
        lines.append(f'/* {register["note"]} */')
    dimensions = register['dimensions']
    offset = int(register['offset'], 0)
    if dimensions:
        arguments = ', '.join(dimension['index'] for dimension in dimensions)
        expression = f'0x{offset:08X}u'
        for dimension in dimensions:
            index = dimension['index']
            stride = dimension['stride']
            expression += f' + 0x{stride:08X}u * ({index})'
            constant(lines, name + '_' + index.upper() + '_COUNT', dimension['count'])
        lines.append(f'#define {name}_OFFSET({arguments}) \\')
        lines.append(f'    ({expression})')
    else:
        constant(lines, name + '_OFFSET', offset)
    reset = register['reset']
    if isinstance(reset, int):
        constant(lines, name + '_RESET', reset)
    elif isinstance(reset, list):
        for index, value in enumerate(reset):
            if value is not None:
                constant(lines, name + f'_RESET_{index}', value)
    for field in register['fields']:
        field_constants(lines, name, field)
    lines.append('')


def generate():
    output = ROOT / 'sw/bsp/include/regs'
    output.mkdir(parents=True, exist_ok=True)
    for source in sorted((ROOT / 'rtl/include/regs').glob('*.json')):
        data = json.loads(source.read_text(encoding='utf-8'))
        module = data['module']
        prefix = 'EDRV32_' + module.upper()
        guard = prefix + '_REGS_H'
        lines = [f'/* File: {module}_regs.h', f' * Spec: {data["spec"]}',
                 ' * Description: Engine register offsets, fields and descriptor layouts.',
                 ' * Clock domain: none (constants).', ' */',
                 '// 由 tools/gen/regs.py 从 rtl/include/regs/*.json 生成，不要手改。',
                 f'#ifndef {guard}', f'#define {guard}', '', f'/* {data["note"]} */', '']
        for register in data['registers']:
            register_constants(lines, prefix, register)
        for layout in data['layouts']:
            name = prefix + '_' + layout['name']
            lines.append(f'/* {layout["spec"]}; {layout["byte_order"]}. */')
            constant(lines, name + '_SIZE', layout['size'])
            if 'note' in layout:
                lines.append(f'/* {layout["note"]} */')
            for field in layout['fields']:
                constant(lines, name + '_' + field['name'] + '_OFFSET',
                         int(field['offset'], 0))
                field_constants(lines, name, field)
            lines.append('')
        lines.append('#endif')
        (output / f'{module}_regs.h').write_text('\n'.join(lines) + '\n', encoding='utf-8')
        generate_verilog(data)


def generate_verilog(data):
    module = data['module']
    filename = f'edrv32_{module}_regs.vh'
    prefix = 'EDRV32_' + module.upper()
    lines = [f'// File: {filename}', f'// Spec: {data["spec"]}',
             '// Description: Generated register offsets, fields and descriptor layouts.',
             '//              Include inside a module; regenerate with tools/gen/regs.py.',
             '// Clock domain: none (constants).']

    def emit(name, value):
        lines.append(f'localparam [31:0] {name} = 32\'h{value:08X};')

    def fields(name, field):
        stem = name + '_' + field['name']
        emit(stem + '_POS', field['lsb'])
        emit(stem + '_WIDTH', field['width'])
        emit(stem + '_MASK', ((1 << field['width']) - 1) << field['lsb'])

    for register in data['registers']:
        name = prefix + '_' + register['name']
        emit(name + '_OFFSET', int(register['offset'], 0))
        for dimension in register['dimensions']:
            stem = name + '_' + dimension['index'].upper()
            emit(stem + '_COUNT', dimension['count'])
            emit(stem + '_STRIDE', dimension['stride'])
        for field in register['fields']:
            fields(name, field)
    for layout in data['layouts']:
        name = prefix + '_' + layout['name']
        emit(name + '_SIZE', layout['size'])
        for field in layout['fields']:
            emit(name + '_' + field['name'] + '_OFFSET', int(field['offset'], 0))
            fields(name, field)
    (ROOT / 'rtl/include/regs' / filename).write_text('\n'.join(lines) + '\n', encoding='utf-8')


if __name__ == '__main__':
    generate()
