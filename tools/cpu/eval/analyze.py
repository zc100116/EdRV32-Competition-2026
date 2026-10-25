#!/usr/bin/env python3
# File: analyze.py; Spec: cpu-spec 4.2/4.4, cpu-plan C-E1/E2/E3; Clock: host.
# Extract the timed CoreMark instruction stream and measure ISA, pairing and prediction.
"""Analyze build/cpu/eval after run_coremark.py; write numeric results as CSV."""
import csv
from dataclasses import dataclass
from itertools import product
from pathlib import Path
import re
import subprocess

from run_coremark import OUTPUT, VARIANTS

COMMIT = re.compile(r'^core\s+\d+:\s+3\s+0x([0-9a-f]+)\s+\(0x([0-9a-f]+)\)')
DISASM = re.compile(r'^\s*([0-9a-f]+):\s+([0-9a-f]+)\s+(\S+)\s*(.*)$')
CONTROL = {'branch', 'jal', 'jalr'}


@dataclass(frozen=True)
class Instruction:
    pc: int
    bits: int
    size: int
    kind: str
    rd: int
    sources: tuple
    target: int
    pop: bool
    push: bool


def decode(pc, bits, mnemonic, operands):
    """Use GNU's numeric, no-alias disassembly for explicit and compressed operands."""
    regs = tuple(int(value) for value in re.findall(r'\bx(\d+)\b', operands.split('#')[0]))
    size = 4 if bits & 3 == 3 else 2
    rd = 0
    sources = regs
    target = 0
    pop = push = False
    base = mnemonic.removeprefix('c.')
    if base in {'beq', 'bne', 'blt', 'bge', 'bltu', 'bgeu', 'beqz', 'bnez'}:
        kind = 'branch'
        target = int(operands.split(',')[-1].split()[0], 16)
    elif base in {'j', 'jal', 'jr', 'jalr'}:
        kind = 'jalr' if base in {'jr', 'jalr'} else 'jal'
        if mnemonic.startswith('c.'):
            rd = 1 if base in {'jal', 'jalr'} else 0
        else:
            rd, sources = regs[0], regs[1:]
        if kind == 'jal':
            target = int(operands.split(',')[-1].split()[0], 16)
            sources = ()
        push = rd in {1, 5}
        if kind == 'jalr':
            rs1 = sources[0]
            pop = rs1 in {1, 5} and (not push or rd != rs1)
    elif base in {'sb', 'sh', 'sw'}:
        kind = 'store'
    elif base in {'lb', 'lbu', 'lh', 'lhu', 'lw', 'lwsp'}:
        kind = 'load'
        rd, sources = regs[0], regs[1:]
    elif base in {'swsp'}:
        kind = 'store'
    elif (bits & 0x7f in {0x0f, 0x73} and size == 4) or base == 'ebreak':
        kind = 'serial'
    else:
        kind = 'muldiv' if size == 4 and bits & 0x7f == 0x33 and bits >> 25 == 1 else 'alu'
        if regs:
            rd, sources = regs[0], regs[1:]
            if mnemonic.startswith('c.') and base in {
                    'addi', 'addi16sp', 'slli', 'srli', 'srai', 'andi', 'add',
                    'sub', 'xor', 'or', 'and'}:
                sources = regs
    return Instruction(pc, bits, size, kind, rd, sources, target, pop, push)


def load_program(out):
    elf = out / 'coremark.elf'
    disasm = subprocess.check_output(
        ['riscv-none-elf-objdump', '-d', '-M', 'no-aliases,numeric', str(elf)], text=True)
    (out / 'numeric.dis').write_text(disasm)
    program = {}
    for line in disasm.splitlines():
        if match := DISASM.match(line):
            pc, bits = int(match[1], 16), int(match[2], 16)
            program[pc] = decode(pc, bits, match[3], match[4])
    names = subprocess.check_output(['riscv-none-elf-nm', str(elf)], text=True)
    symbols = {parts[2]: int(parts[0], 16) for line in names.splitlines()
               if len(parts := line.split()) == 3}
    sizes = subprocess.check_output(['riscv-none-elf-size', '-A', str(elf)], text=True)
    (out / 'sections.txt').write_text(sizes)
    text_size = next(int(line.split()[1]) for line in sizes.splitlines()
                     if line.startswith('.text '))
    return program, symbols, text_size


def extract(out, program, symbols):
    trace = []
    previous_pc = None
    start_return = None
    active = False
    with (out / 'spike.log').open() as log, (out / 'roi.trace').open('w') as raw:
        for line in log:
            if not (match := COMMIT.match(line)):
                continue
            pc = int(match[1], 16)
            if pc == symbols['start_time']:
                start_return = previous_pc + program[previous_pc].size
            if pc == start_return:
                active = True
            if active and pc == symbols['stop_time']:
                break
            if active:
                instruction = program[pc]
                trace.append(instruction)
                raw.write(f'{pc:08x} {instruction.bits:08x}\n')
            previous_pc = pc
    return trace, symbols['stop_time']


def successors(trace, final_pc):
    for index, instruction in enumerate(trace):
        yield instruction, trace[index + 1].pc if index + 1 < len(trace) else final_pc


def fetch_groups(trace, final_pc):
    count = 0
    previous_group = None
    for instruction, next_pc in successors(trace, final_pc):
        first = instruction.pc >> 3
        last = (instruction.pc + instruction.size - 1) >> 3
        count += (first != previous_group) + (last != first)
        # A taken transfer starts a fresh fetch even when its target is in this group.
        previous_group = last if next_pc == instruction.pc + instruction.size else None
    return count


def pairing(trace, branch_support):
    result = dict(pairs=0, raw=0, structural=0, slot1_type=0, only_one=0)
    index = 0
    while index < len(trace):
        older = trace[index]
        if (index + 1 == len(trace) or older.kind in {'jal', 'jalr'}
                or trace[index + 1].pc != older.pc + older.size):
            reason = 'only_one'
        else:
            younger = trace[index + 1]
            if older.rd and older.rd in younger.sources:
                reason = 'raw'
            elif older.kind == 'serial':
                reason = 'structural'
            elif younger.kind != 'alu' and not (branch_support and younger.kind == 'branch'):
                reason = 'slot1_type'
            else:
                reason = 'pairs'
        result[reason] += 1
        index += 2 if reason == 'pairs' else 1
    result['issue_groups'] = sum(result.values())
    result['paired_instruction_pct'] = 200 * result['pairs'] / len(trace)
    result['dual_group_pct'] = 100 * result['pairs'] / result['issue_groups']
    result['sequence_ipc'] = len(trace) / result['issue_groups']
    return result


def ras_update(stack, instruction, depth):
    if instruction.pop and stack:
        stack.pop()
    if instruction.push:
        stack.append(instruction.pc + instruction.size)
        if len(stack) > depth:
            del stack[0]


def prediction_events(trace, final_pc):
    """Retain group entry addresses and controls; ALUs cannot change predictor state."""
    events = []
    group = None
    serial = 0
    start = None
    for instruction, next_pc in successors(trace, final_pc):
        if instruction.pc >> 3 != group:
            group = instruction.pc >> 3
            serial += 1
            start = instruction.pc
        if instruction.kind in CONTROL:
            events.append((instruction, next_pc, serial, start))
            if instruction.kind != 'branch' or next_pc != instruction.pc + instruction.size:
                group = None
    return events


def predictor(events, btb_size, pht_size, ras_depth, branch_file=None):
    btb = [None] * btb_size
    counters = [1] * pht_size
    history = 0
    stack = []
    group = None
    prediction = None
    predicted_taken = False
    predicted_target = 0
    checkpoint = []
    previous_serial = None
    previous_next_pc = None
    result = dict(controls=0, conditional=0, direction_wrong=0, target_wrong=0,
                  btb_miss=0, redirects=0, calls=0, returns=0, ras_empty=0)
    for instruction, next_pc, serial, start in events:
        pc = instruction.pc
        if serial != group:
            group = serial
            lookup_pc = previous_next_pc if serial == previous_serial else start
            entry = btb[(pc >> 3) & (btb_size - 1)]
            prediction = entry if entry and entry[0].pc >> 3 == pc >> 3 else None
            if prediction and prediction[0].pc < lookup_pc:
                prediction = None
            checkpoint = stack.copy()
            if prediction:
                predicted, predicted_target = prediction
                pht_index = ((predicted.pc >> 1) ^ history) & (pht_size - 1)
                predicted_taken = predicted.kind != 'branch' or counters[pht_index] >= 2
                if predicted_taken:
                    if predicted.pop and stack:
                        predicted_target = stack[-1]
                    ras_update(stack, predicted, ras_depth)
        result['controls'] += 1
        actual_taken = instruction.kind != 'branch' or next_pc != pc + instruction.size
        hit = prediction is not None and prediction[0].pc == pc
        taken = hit and predicted_taken
        target = instruction.target if instruction.kind != 'jalr' else next_pc
        direction_wrong = instruction.kind == 'branch' and taken != actual_taken
        target_wrong = hit and taken and actual_taken and predicted_target != next_pc
        redirect = taken != actual_taken or target_wrong
        result['conditional'] += instruction.kind == 'branch'
        result['direction_wrong'] += direction_wrong
        result['target_wrong'] += target_wrong
        result['btb_miss'] += not hit
        result['redirects'] += redirect
        result['calls'] += instruction.push
        result['returns'] += instruction.pop
        result['ras_empty'] += instruction.pop and not checkpoint
        if branch_file:
            branch_file.write(f'{pc:08x},{instruction.kind},{int(actual_taken)},'
                              f'{target:08x},{int(instruction.push)},'
                              f'{int(instruction.pop)}\n')
        if redirect:
            stack = checkpoint.copy()
            ras_update(stack, instruction, ras_depth)
        if instruction.kind == 'branch':
            pht_index = ((pc >> 1) ^ history) & (pht_size - 1)
            delta = 1 if actual_taken else -1
            counters[pht_index] = min(3, max(0, counters[pht_index] + delta))
            history = ((history << 1) | actual_taken) & (pht_size - 1)
        btb[(pc >> 3) & (btb_size - 1)] = (instruction, target)
        if redirect or actual_taken:
            group = None
        previous_serial = serial
        previous_next_pc = next_pc
    return result


def write_csv(path, rows):
    with path.open('w') as output:
        writer = csv.DictWriter(output, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main():
    isa_rows, pairing_rows, predictor_rows = [], [], []
    for variant in VARIANTS:
        out = OUTPUT / variant
        program, symbols, text_size = load_program(out)
        trace, final_pc = extract(out, program, symbols)
        groups = fetch_groups(trace, final_pc)
        isa_rows.append(dict(isa=variant, instructions=len(trace), text_bytes=text_size,
                             instruction_bytes=sum(item.size for item in trace),
                             fetch_groups=groups, fetch_bytes=8 * groups))
        for support in (False, True):
            pairing_rows.append(dict(isa=variant, slot1_branch=int(support),
                                     **pairing(trace, support)))
        with (out / 'branches.csv').open('w') as branches:
            branches.write('pc,kind,taken,target,call,return\n')
            events = prediction_events(trace, final_pc)
            for btb, pht, ras in product((16, 32, 64), (256, 512, 1024), (2, 4, 8)):
                raw = branches if (btb, pht, ras) == (32, 512, 4) else None
                result = predictor(events, btb, pht, ras, raw)
                result['direction_pct_conditional'] = (
                    100 * result['direction_wrong'] / result['conditional'])
                for field in ('target_wrong', 'btb_miss', 'redirects'):
                    result[field + '_pct_control'] = 100 * result[field] / result['controls']
                predictor_rows.append(dict(isa=variant, btb=btb, gshare=pht, ras=ras, **result))
        print(f'Analyzed {variant}: {len(trace)} instructions', flush=True)
    write_csv(OUTPUT / 'isa.csv', isa_rows)
    write_csv(OUTPUT / 'pairing.csv', pairing_rows)
    write_csv(OUTPUT / 'predictor.csv', predictor_rows)


if __name__ == '__main__':
    main()
