#!/usr/bin/env python3
# File: randgen.py
# Spec: cpu-spec 2, 4.2, 4.3; cpu-testplan 2.4, P-09, 4; cpu-plan C-V3.
# Description: Generate seeded, exception-free random programs and run Spike batches.
# Clock domain: host; generated instructions execute in clk_sys.
"""Seeded CPU random streams; all generated artifacts go to build/cpu/rand/."""
import argparse
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
import random
import subprocess
import sys

from run_spike import ISA, run, symbols
from trace_compare import spike_events

ROOT = Path(__file__).resolve().parents[2]
ENV = ROOT / 'verif/block/cpu/env'
OUT = ROOT / 'build/cpu/rand'
REGS = tuple(reg for reg in range(1, 31) if reg != 8)
CATEGORIES = ('alu', 'load', 'store', 'mul', 'div', 'branch', 'csr', 'fence')
DISTANCES = ('1', '2', '3', '4-8', '9+', 'entry')

# Category weights sum to 100. Distance weights apply per bucket, then a source
# is chosen uniformly among registers in that bucket. "entry" means no producer
# in the body yet. Branch distances count forward generation slots (1-3 insns).
# No command-line tuning: configurations are the reproducible workload contract.
CONFIGS = {
    'high-dep': {
        'mix': (55, 12, 8, 10, 4, 5, 4, 2),
        'distance': (76, 14, 5, 3, 1, 1),
        'memory': (0, 256), 'branch_distance': (1, 2, 3, 4),
        'slots': 1024, 'compressed_percent': 25, 'waw_percent': 20,
    },
    'low-dep': {
        'mix': (78, 5, 4, 4, 2, 4, 2, 1),
        'distance': (0, 0, 0, 10, 80, 10),
        'memory': (0, 1024), 'branch_distance': (1, 2, 4, 8),
        'slots': 1024, 'compressed_percent': 25, 'waw_percent': 20,
    },
    'memory': {
        'mix': (18, 34, 34, 4, 2, 4, 2, 2),
        'distance': (40, 25, 15, 10, 8, 2),
        'memory': (0, 2048), 'branch_distance': (1, 2, 4, 8),
        'slots': 1024, 'compressed_percent': 25, 'waw_percent': 20,
    },
    'branch': {
        'mix': (37, 8, 6, 4, 2, 38, 3, 2),
        'distance': (35, 25, 15, 15, 8, 2),
        'memory': (0, 512), 'branch_distance': (1, 2, 4, 8, 16, 32),
        'slots': 1024, 'compressed_percent': 25, 'waw_percent': 20,
    },
}


@dataclass
class Instruction:
    asm: str
    category: str
    sources: tuple = ()
    dest: int = 0
    size: int = 4


def distance_bucket(distance):
    if distance <= 3:
        return str(distance)
    return '4-8' if distance <= 8 else '9+'


class Statistics:
    """Count actual emitted instructions and mutable-register RAW distances."""

    def __init__(self):
        self.categories = Counter()
        self.distances = Counter()
        self.compressed = 0
        self.last_write = {}
        self.count = 0

    def add(self, instruction):
        self.categories[instruction.category] += 1
        self.compressed += instruction.size == 2
        for reg in instruction.sources:
            if reg in REGS:
                bucket = (distance_bucket(self.count - self.last_write[reg])
                          if reg in self.last_write else 'entry')
                self.distances[bucket] += 1
        if instruction.dest in REGS:
            self.last_write[instruction.dest] = self.count
        self.count += 1

    def merge(self, other):
        self.categories.update(other.categories)
        self.distances.update(other.distances)
        self.compressed += other.compressed
        self.count += other.count


class Generator:
    def __init__(self, config, seed, compressed):
        self.config = CONFIGS[config]
        self.rng = random.Random(seed)
        self.compressed = compressed
        self.stats = Statistics()
        self.instructions = []
        self.lines = []
        self.previous_dest = 1

    def emit(self, asm, category, sources=(), dest=0, size=4):
        instruction = Instruction(asm, category, sources, dest, size)
        self.instructions.append(instruction)
        self.stats.add(instruction)
        if size == 2:
            self.lines.extend(['    .option rvc', '    ' + asm, '    .option norvc'])
        else:
            self.lines.append('    ' + asm)
        if dest in REGS:
            self.previous_dest = dest

    def source(self):
        buckets = {bucket: [] for bucket in DISTANCES}
        for reg in REGS:
            bucket = (distance_bucket(self.stats.count - self.stats.last_write[reg])
                      if reg in self.stats.last_write else 'entry')
            buckets[bucket].append(reg)
        # Empty buckets carry no weight; low-dep always has registers older than
        # three instructions, since each instruction writes at most one GPR.
        weights = [weight if buckets[bucket] else 0
                   for bucket, weight in zip(DISTANCES, self.config['distance'])]
        bucket = self.rng.choices(DISTANCES, weights)[0]
        return self.rng.choice(buckets[bucket])

    def dest(self):
        if self.rng.randrange(100) < self.config['waw_percent']:
            return self.previous_dest
        return self.rng.choice((0,) + REGS)

    def alu(self, compressed):
        rng = self.rng
        src = self.source()
        if compressed:
            op = rng.choice(('c.add', 'c.mv', 'c.addi', 'c.li'))
            # These encodings require nonzero rd; reuse a source as rd for
            # read-modify-write forms so the requested dependency is retained.
            if op == 'c.add':
                rhs = self.source()
                self.emit(f'{op} x{src}, x{rhs}', 'alu', (src, rhs), src, 2)
            elif op == 'c.addi':
                imm = rng.choice(tuple(range(-32, 0)) + tuple(range(1, 32)))
                self.emit(f'{op} x{src}, {imm}', 'alu', (src,), src, 2)
            else:
                dest = rng.choice(REGS)
                operand = f'x{src}' if op == 'c.mv' else str(rng.randint(-32, 31))
                sources = (src,) if op == 'c.mv' else ()
                self.emit(f'{op} x{dest}, {operand}', 'alu', sources, dest, 2)
            return
        dest = self.dest()
        form = rng.randrange(4)
        if form == 0:
            op = rng.choice(('lui', 'auipc'))
            self.emit(f'{op} x{dest}, {rng.randrange(1 << 20)}', 'alu', dest=dest)
        elif form == 1:
            op = rng.choice(('addi', 'slti', 'sltiu', 'xori', 'ori', 'andi'))
            self.emit(f'{op} x{dest}, x{src}, {rng.randint(-2048, 2047)}',
                      'alu', (src,), dest)
        elif form == 2:
            op = rng.choice(('slli', 'srli', 'srai'))
            self.emit(f'{op} x{dest}, x{src}, {rng.randrange(32)}', 'alu', (src,), dest)
        else:
            op = rng.choice(('add', 'sub', 'sll', 'slt', 'sltu', 'xor',
                             'srl', 'sra', 'or', 'and'))
            rhs = self.source()
            self.emit(f'{op} x{dest}, x{src}, x{rhs}', 'alu', (src, rhs), dest)

    def memory(self, category):
        load = category == 'load'
        op, width = self.rng.choice((('lb', 1), ('lbu', 1), ('lh', 2),
                                    ('lhu', 2), ('lw', 4)) if load else
                                   (('sb', 1), ('sh', 2), ('sw', 4)))
        low, high = self.config['memory']
        offset = self.rng.randrange(low // width, high // width) * width
        reg = self.dest() if load else self.source()
        self.emit(f'{op} x{reg}, {offset}(x8)', category,
                  (8,) if load else (8, reg), reg if load else 0)

    def branch(self, slot):
        rng = self.rng
        target = min(slot + rng.choice(self.config['branch_distance']), self.config['slots'])
        label = f'rand_slot_{target}'
        form = rng.randrange(10)
        if form == 0:
            # A reserved target register prevents arbitrary data from becoming
            # an address. Explicit AUIPC/ADDI retain a one-instruction metadata map.
            anchor = f'rand_target_{slot}'
            self.lines.append(anchor + ':')
            self.emit(f'auipc x31, %pcrel_hi({label})', 'alu', dest=31)
            self.emit(f'addi x31, x31, %pcrel_lo({anchor})', 'alu', (31,), 31)
            dest = self.dest()
            self.emit(f'jalr x{dest}, 0(x31)', 'branch', (31,), dest)
        elif form <= 2:
            dest = self.dest()
            self.emit(f'jal x{dest}, {label}', 'branch', dest=dest)
        else:
            lhs = self.source()
            rhs = self.source()
            op = rng.choice(('beq', 'bne', 'blt', 'bge', 'bltu', 'bgeu'))
            self.emit(f'{op} x{lhs}, x{rhs}, {label}', 'branch', (lhs, rhs))

    def generate(self):
        for slot in range(self.config['slots']):
            self.lines.append(f'rand_slot_{slot}:')
            category = self.rng.choices(CATEGORIES, self.config['mix'])[0]
            compressed = (self.compressed and
                          self.rng.randrange(100) < self.config['compressed_percent'])
            if category == 'alu':
                self.alu(compressed)
            elif category in ('load', 'store'):
                self.memory(category)
            elif category in ('mul', 'div'):
                op = self.rng.choice(('mul', 'mulh', 'mulhsu', 'mulhu') if category == 'mul'
                                     else ('div', 'divu', 'rem', 'remu'))
                lhs, rhs, dest = self.source(), self.source(), self.dest()
                self.emit(f'{op} x{dest}, x{lhs}, x{rhs}', category, (lhs, rhs), dest)
            elif category == 'branch':
                self.branch(slot)
            elif category == 'csr':
                dest = self.dest()
                if self.rng.randrange(2):
                    src = self.source()
                    op = self.rng.choice(('csrrw', 'csrrs', 'csrrc'))
                    self.emit(f'{op} x{dest}, mscratch, x{src}', 'csr', (src,), dest)
                else:
                    op = self.rng.choice(('csrrwi', 'csrrsi', 'csrrci'))
                    self.emit(f'{op} x{dest}, mscratch, {self.rng.randrange(32)}',
                              'csr', dest=dest)
            else:
                self.emit(self.rng.choice(('fence rw, rw', 'fence.i')), 'fence')
        self.lines.append(f"rand_slot_{self.config['slots']}:")
        return self.lines


def write_program(config, seed, compressed):
    out = OUT / config / ('c' if compressed else 'no-c') / f'seed-{seed}'
    out.mkdir(parents=True, exist_ok=True)
    generator = Generator(config, seed, compressed)
    body = generator.generate()
    # All source GPRs and all bytes in the data region have defined entry values.
    init = [f'    li x{reg}, {generator.rng.randint(-2048, 2047)}' for reg in REGS]
    data = [f'    .word 0x{generator.rng.getrandbits(32):08x}'
            for _ in range(generator.config['memory'][1] // 4)]
    lines = [
        '# File: program.S; cpu-spec 2, 4.2, 4.3; clock: clk_sys.',
        f'# Configuration: {config}; seed: {seed}; C: {compressed}.',
        '.option norvc', '.option norelax', '.section .text.init,"ax",@progbits',
        '.globl _start', '_start:', *init, '    la x8, rand_data',
        '    csrrwi x0, mscratch, 0', '.globl rand_body', 'rand_body:', *body,
        '.globl rand_end', 'rand_end:', '    la x31, tohost', '    addi x1, x0, 1',
        '    sw x1, 0(x31)', '1:  jal x0, 1b',
        '.section .tohost,"aw",@progbits', '.balign 64', '.globl tohost',
        'tohost: .dword 0', '.globl fromhost', 'fromhost: .dword 0',
        '.section .data,"aw",@progbits', '.balign 16', 'rand_data:', *data,
    ]
    source = out / 'program.S'
    source.write_text('\n'.join(lines) + '\n')
    return out, source, generator


def build_run(out, source, generator, compressed):
    elf = out / 'program.elf'
    isa = ISA if compressed else ISA.replace('imc_', 'im_')
    args = ['riscv-none-elf-gcc', '-march=' + isa, '-mabi=ilp32', '-mcmodel=medany',
            '-nostdlib', '-nostartfiles', '-static', '-Wl,--no-relax', '-DTEST_ENTRY=_start',
            '-T' + str(ENV / 'link.ld'), str(ENV / 'boot.S'), str(source), '-o', str(elf)]
    with (out / 'build.log').open('w') as log:
        subprocess.run(args, stdout=log, stderr=subprocess.STDOUT, check=True)
    with (out / 'program.dis').open('w') as listing:
        subprocess.run(['riscv-none-elf-objdump', '-d', '-M', 'no-aliases', str(elf)],
                       stdout=listing, check=True)
    subprocess.run([sys.executable, str(ROOT / 'tools/elf2mem.py'), str(elf), str(out)],
                   check=True)
    image = []
    for region, base in (('rom', 0), ('sram', 0x10000000), ('ddr', 0x80000000)):
        for line in (out / (region + '.hex')).read_text().splitlines():
            image.append(f'@{int(line[1:], 16) + base:08x}' if line.startswith('@') else line)
    (out / 'mem.hex').write_text('\n'.join(image) + '\n')
    run(elf, out, compressed=compressed)
    pc = symbols(elf)['rand_body']
    instructions = {}
    for instruction in generator.instructions:
        instructions[pc] = instruction
        pc += instruction.size
    retired = Statistics()
    for event in spike_events(out / 'spike.log'):
        if event.cause is not None:
            raise RuntimeError(f'{elf}: unexpected Spike trap {event.cause:#x}')
        if event.pc in instructions:
            retired.add(instructions[event.pc])
    return retired


def format_statistics(title, stats):
    lines = [title, f'body instructions: {stats.count}; compressed: {stats.compressed}']
    for label, keys, counts in (('category', CATEGORIES, stats.categories),
                                ('RAW distance', DISTANCES, stats.distances)):
        total = sum(counts.values())
        lines.append(label + ': ' + ', '.join(
            f'{key}={counts[key]} ({counts[key] / total:.2%})' for key in keys))
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest='mode', required=True)
    for mode in ('generate', 'batch'):
        sub = modes.add_parser(mode)
        sub.add_argument('config', choices=CONFIGS)
        if mode == 'generate':
            sub.add_argument('seed', type=int)
        else:
            sub.add_argument('first_seed', type=int)
            sub.add_argument('stop_seed', type=int, help='exclusive upper bound')
        sub.add_argument('--c', action='store_true', help='include compressed ALU instructions')
    args = parser.parse_args()
    seeds = ([args.seed] if args.mode == 'generate'
             else range(args.first_seed, args.stop_seed))
    generated = Statistics()
    retired = Statistics()
    for seed in seeds:
        out, source, generator = write_program(args.config, seed, args.c)
        generated.merge(generator.stats)
        if args.mode == 'batch':
            retired.merge(build_run(out, source, generator, args.c))
        else:
            print(source)
    report = [f'config={args.config}; C={args.c}; seeds={seeds}',
              format_statistics('Generated (static)', generated)]
    if args.mode == 'batch':
        report.append(format_statistics('Spike retired (dynamic)', retired))
    text = '\n\n'.join(report) + '\n'
    report_dir = OUT / args.config / ('c' if args.c else 'no-c')
    name = (f'seed-{args.seed}/statistics.txt' if args.mode == 'generate' else
            f'statistics-{args.first_seed}-{args.stop_seed}.txt')
    (report_dir / name).write_text(text)
    print(text)


if __name__ == '__main__':
    main()
