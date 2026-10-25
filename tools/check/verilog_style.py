#!/usr/bin/env python3
# File: verilog_style.py
# Spec: CLAUDE.md 5-7; infra-plan I-04
# Description: Report mechanically recognizable Verilog language and style violations.
#              Structural synthesis checks remain with Verilator lint.
# Clock domain: none (host tool).
"""Check mechanically recognizable CLAUDE.md sections 5–7 rules."""
import argparse
from pathlib import Path
import re
import sys


def without_comments(text):
    return re.sub(r'/\*.*?\*/|//[^\n]*', lambda m: re.sub(r'[^\n]', ' ', m[0]),
                  text, flags=re.S)


def top_commas(text):
    depth = 0
    count = 0
    for char in text:
        if char in '([{':
            depth += 1
        elif char in ')]}':
            depth -= 1
        elif char == ',' and depth == 0:
            count += 1
    return count


def check(path):
    text = path.read_text()
    clean = without_comments(text)
    errors = []

    def report(line, message):
        errors.append(f'{path}:{line}: {message}')

    header = '\n'.join(text.splitlines()[:12])
    build_header = path.name == 'edrv32_build_mode.vh'
    for label in ('File', 'Spec', 'Description', 'Clock'):
        if label.lower() not in header.lower() and not (build_header and label == 'Clock'):
            report(1, f'file header missing {label}')
    for number, (raw, line) in enumerate(zip(text.splitlines(), clean.splitlines()), 1):
        if '\t' in raw:
            report(number, 'Tab character')
        if line.strip() and len(raw.rstrip()) > 100:
            report(number, 'code line exceeds 100 columns')
        if line.strip() and (len(line) - len(line.lstrip())) % 4:
            report(number, 'indentation must use multiples of four spaces')
        if re.search(r'`(?:ifdef|ifndef|elsif|else|endif)\b', line):
            if 'tech' not in path.parts and not build_header:
                report(number, 'conditional compilation is only allowed in rtl/tech/')
        declaration = re.match(r'\s*(?:input|output|inout|wire|reg|integer)\b(.*)', line)
        if declaration and (top_commas(declaration[1].rstrip().rstrip(','))
                            or re.search(r';\s*(?:wire|reg|input|output|inout)\b', line)):
            report(number, 'declare one signal per line')
        port = re.match(r'\s*(input|output|inout)\b(.*)', line)
        if port:
            names = re.findall(r'\b[A-Za-z_]\w*\b', port[2].split('=')[0])
            name = names[-1] if names else ''
            suffixes = ('_i',) if port[1] == 'input' else ('_o', '_oe')
            if not name.endswith(suffixes):
                report(number, f'{port[1]} port {name} requires direction suffix')
        forbidden = r'\b(logic|bit|int|byte|shortint|longint|string|struct|union|class|program|modport|clocking|unique|priority|timeunit|timeprecision|always_comb|always_ff|always_latch|typedef|struct|enum|interface|package|endpackage|casex|force|release|fork|join)\b'
        match = re.search(forbidden, line)
        if match:
            report(number, f'forbidden syntax {match[0]}')
        if re.search(r'\binitial\b', line) and 'tech' not in path.parts:
            report(number, 'initial block is forbidden in RTL')
        if re.search(r'#\s*(?:\d|\.)', line):
            report(number, 'delay is forbidden in RTL')
        if re.match(r'\s*(and|nand|or|nor|xor|xnor|buf|not|tran|pullup|pulldown)\b', line):
            report(number, 'gate primitive is forbidden')
        if len(re.findall(r'\.\w+\s*\(', line)) > 1:
            report(number, 'connect one port per line')
    if path.suffix == '.v':
        modules = re.findall(r'\bmodule\s+(\w+)', clean)
        if modules != [path.stem] or not re.fullmatch(r'edrv32_[a-z0-9_]+', path.stem):
            report(1, 'one edrv32_ module per file, matching the filename')
    # Module instantiations have a type, optional parameter block, and instance name.
    pattern = r'\b(\w+)\s+(?:#\s*\((?:[^()]|\([^()]*\))*\)\s*)?(\w+)\s*\('
    for match in re.finditer(pattern, clean):
        if match[1] in ('module', 'function', 'task', 'if', 'else', 'case',
                        'begin', 'end', 'generate', 'for', 'while', 'always'):
            continue
        start = match.end()
        depth = 1
        end = start
        while depth:
            char = clean[end]
            depth += (char == '(') - (char == ')')
            end += 1
        connections = clean[start:end - 1].strip()
        if connections and not connections.startswith('.'):
            report(clean[:start].count('\n') + 1, 'use named port connections')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('paths', nargs='+', type=Path)
    args = parser.parse_args()
    paths = set()
    for path in args.paths:
        if path.is_dir():
            paths.update(p for p in path.rglob('*') if p.suffix in ('.v', '.vh'))
        else:
            paths.add(path)
    errors = [error for path in sorted(paths) for error in check(path)]
    for error in errors:
        print(error)
    print(f'Style: {len(paths)} files, {len(errors)} warnings')
    return bool(errors)


if __name__ == '__main__':
    sys.exit(main())
