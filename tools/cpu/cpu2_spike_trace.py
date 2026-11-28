#!/usr/bin/env python3
# File: cpu2_spike_trace.py
# Spec: cpu-v2-testplan 2/4, fpu-testplan 4 (V01 clarification).
# Description: Convert Spike commit records into ordered retirement/trap expectations.
# Clock: host; instruction order only, no cycle or implementation-tag oracle.
"""Convert Spike 1.1.1-dev --log-commits -l output; see cpu2_trace/README.md."""
import argparse
from pathlib import Path
import re

RETIRE_FIELDS = ('pc', 'instr', 'rd', 'rd_domain', 'rd_data', 'csr_valid', 'csr_addr',
                    'csr_data', 'mem_valid', 'mem_store', 'mem_addr', 'mem_data', 'mem_mask',
                    'fflags', 'frm', 'fs', 'next_pc')
TRAP_FIELDS = ('cause', 'trap_pc', 'tval', 'fflags', 'frm', 'fs')
ISA = {fmt: 'rv32im' + {'NONE': '', 'F': 'f', 'FD': 'fd'}[fmt] +
        '_zicsr_zicntr_zifencei_zba' for fmt in ('NONE', 'F', 'FD')}
COMMIT = re.compile(r'^core\s+0:\s+3\s+0x([\da-f]+)\s+\(0x([\da-f]+)\)(.*)$')
REG = re.compile(r'\b([xf])(\d+)\s+0x([\da-f]+)')
CSR = re.compile(r'\bc(\d+)_\w+\s+0x([\da-f]+)')
MEM = re.compile(r'\bmem\s+0x([\da-f]+)(?:\s+0x([\da-f]+))?')
TRAP = re.compile(r'exception (trap_\w+|interrupt #\d+), epc 0x([\da-f]+)'
                    r'(?:, tval 0x([\da-f]+))?')
CAUSES = {'instruction_address_misaligned': 0, 'instruction_access_fault': 1,
            'illegal_instruction': 2, 'breakpoint': 3, 'load_address_misaligned': 4,
            'load_access_fault': 5, 'store_address_misaligned': 6, 'store_access_fault': 7,
            'machine_ecall': 11}


def encode(kind, values):
    fields = RETIRE_FIELDS if kind == 1 else TRAP_FIELDS
    return ' '.join(f'{v:x}' for v in (kind, *(values[key] for key in fields))) + '\n'


def convert(lines, fmt):
    """State is reconstructed from explicit commit writes, never sticky-bit subtraction."""
    state = dict(fflags=0, frm=0, fs=0)
    events = []
    records = []
    for line in lines:
        if match := re.search(r'^core\s+0:\s+tval 0x([\da-f]+)', line):
            records[-1] += ', tval 0x' + match[1]
        else:
            records.append(line)
    for number, line in enumerate(records, 1):
        if match := TRAP.search(line):
            name, pc, tval = match.groups()
            if name.startswith('interrupt #'):
                cause = 0x80000000 | int(name.split('#')[1])
            else:
                name = name[5:]
                cause = CAUSES[name]
            if tval is None and cause < 0x80000000 and name != 'machine_ecall':
                raise ValueError(f'line {number}: trap {name} lacks required tval')
            events.append((2, dict(cause=cause, trap_pc=int(pc, 16),
                                    tval=int(tval, 16) if tval else 0, **state)))
            continue
        match = COMMIT.match(line)
        if not match:
            if re.match(r'^core\s+\d+:\s+[0123]\s+0x', line):
                raise ValueError(f'line {number}: expected single-hart M-mode commit')
            continue
        pc, instr, effects = match.groups()
        pc, instr = int(pc, 16), int(instr, 16)
        item = {key: 0 for key in RETIRE_FIELDS}
        item.update(pc=pc, instr=instr)
        registers = REG.findall(effects)
        if len(registers) > 1:
            raise ValueError(f'line {number}: multiple register destinations')
        if registers:
            domain, rd, value = registers[0]
            item.update(rd=int(rd), rd_domain=1 if domain == 'x' else 2,
                        rd_data=int(value, 16) & ((1 << (64 if fmt == 'FD' else 32)) - 1))
            if domain == 'x':
                item['rd_data'] &= 0xffffffff
                if int(rd) == 0:
                    item.update(rd=0, rd_domain=0, rd_data=0)
            else:
                state['fs'] = 3
        writes = {int(addr): int(value, 16) for addr, value in CSR.findall(effects)}
        opcode = instr & 0x7f
        funct3 = (instr >> 12) & 7
        # Explicit CSR writes are distinct from implicit fflags/mstatus side effects.
        if opcode == 0x73 and funct3:
            addr = instr >> 20
            source = (instr >> 15) & 31
            write = funct3 in (1, 5) or source != 0
            reads = funct3 not in (1, 5) or ((instr >> 7) & 31) != 0
            if addr == 0x301 and write:
                raise ValueError(f'line {number}: misa write differs from CPU v2; use CV10 '
                                    'dedicated CSR tests, not Spike comparison')
            counter = (addr in (0xb00, 0xb80, 0xb02, 0xb82, 0xc00, 0xc80,
                                0xc01, 0xc81, 0xc02, 0xc82) or
                        0xb03 <= addr <= 0xb1f or 0xb83 <= addr <= 0xb9f or
                        0xc03 <= addr <= 0xc1f or 0xc83 <= addr <= 0xc9f)
            if counter and reads:
                raise ValueError(f'line {number}: counter CSR {addr:03x} read differs from '
                                    'CPU timing; use CV10 dedicated CSR tests')
            if write:
                if addr == 3:
                    # Spike fcsr is a composite CSR: only its two constituent writes log.
                    if 1 not in writes or 2 not in writes:
                        raise ValueError(f'line {number}: fcsr constituent write missing')
                    item.update(csr_valid=1, csr_addr=3,
                                csr_data=(writes[2] & 7) << 5 | (writes[1] & 31))
                elif addr not in writes:
                    raise ValueError(f'line {number}: CSR {addr:03x} write value missing')
                else:
                    item.update(csr_valid=1, csr_addr=addr,
                                csr_data=writes[addr] & 0xffffffff)
                if addr in (1, 2, 3):
                    state['fs'] = 3
        for addr, value in writes.items():
            if addr == 1:
                state['fflags'] = value & 31
                # Spike emits this write for raised flags even when already sticky.
                if opcode != 0x73:
                    state['fs'] = 3
            elif addr == 2:
                state['frm'] = value & 7
            elif addr == 3:
                state.update(fflags=value & 31, frm=(value >> 5) & 7)
            elif addr == 0x300:
                state['fs'] = (value >> 13) & 3
        is_memory = opcode in (0x03, 0x07, 0x23, 0x27)
        if is_memory:
            memory = MEM.search(effects)
            if memory is None:
                raise ValueError(f'line {number}: memory address missing')
            store = opcode in (0x23, 0x27)
            size = (1 << (funct3 & 3)) if opcode in (0x03, 0x23) else (1 << funct3)
            mask = (1 << size) - 1
            data_mask = (1 << (8 * size)) - 1
            if store:
                if memory[2] is None:
                    raise ValueError(f'line {number}: store data missing')
                data = int(memory[2], 16)
            else:
                if not registers or item['rd_domain'] == 0:
                    raise ValueError(f'line {number}: load raw value unavailable (including x0)')
                data = item['rd_data']
            item.update(mem_valid=1, mem_store=int(store), mem_addr=int(memory[1], 16),
                        mem_data=data & data_mask, mem_mask=mask)
        # A writing instruction must have its architectural destination in the log.
        writes_rd = opcode in (0x03, 0x07, 0x13, 0x17, 0x33, 0x37, 0x43, 0x47,
                                0x4b, 0x4f, 0x53, 0x67, 0x6f) or (opcode == 0x73 and funct3)
        fp_integer_dest = opcode == 0x53 and (instr >> 25) in (
            0x50, 0x51, 0x60, 0x61, 0x70, 0x71)
        fp_dest = (opcode in (0x07, 0x43, 0x47, 0x4b, 0x4f) or
                    (opcode == 0x53 and not fp_integer_dest))
        if writes_rd and not registers and (((instr >> 7) & 31) or fp_dest):
            raise ValueError(f'line {number}: destination result missing')
        item.update(state)
        events.append((1, item))
    if not events:
        raise ValueError('no Spike architectural events')
    for index, (kind, item) in enumerate(events):
        if kind == 1:
            if index + 1 < len(events):
                next_kind, next_item = events[index + 1]
                item['next_pc'] = next_item['pc' if next_kind == 1 else 'trap_pc']
            elif item['instr'] & 0x7f in (0x63, 0x67, 0x6f):
                raise ValueError('last control instruction requires its successor in the log')
            else:
                item['next_pc'] = (item['pc'] + 4) & 0xffffffff
    return ''.join(encode(kind, item) for kind, item in events)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--format', choices=tuple(ISA), required=True)
    args = parser.parse_args()
    args.output.write_text(convert(args.log.read_text().splitlines(), args.format))


if __name__ == '__main__':
    main()
