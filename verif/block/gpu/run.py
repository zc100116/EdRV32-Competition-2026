#!/usr/bin/env python3
"""run.py: gpu-testplan 2, 4, 6; generate, export, compare and run block cases.
Host Python, no clock domain. Generated files live under build/gpu/block.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import random
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(ROOT), str(HERE)]
from tools.gpu.model import GPU
from tools.gpu.scene import BusError, Memory, SCHEMA
from scene_support import Case

REGISTERS = {}
RESETS = {}
for register in SCHEMA['registers']:
    dimensions = register['dimensions']
    count = dimensions[0]['count'] if dimensions else 1
    stride = dimensions[0]['stride'] if dimensions else 0
    for index in range(count):
        name = register['name'] + (f'[{index}]' if dimensions else '')
        REGISTERS[name] = int(register['offset'], 0) + index*stride
        RESETS[name] = register['reset']
CHECKED = ['STATUS', 'IRQ_STAT', 'ERR_CODE', 'DONE_COUNT', 'OBJ_HIT_COUNT',
           'OBJ_FREE_COUNT', 'OBJ_ALIVE_COUNT', 'OBJ_STAT'] + [f'PERF[{i}]' for i in range(1, 5)]
SAMPLED = CHECKED + [f'PERF[{i}]' for i in (0, 5, 6, 7, 8)]


def metadata(test):
    return dict(line.split(':', 1) for line in (HERE/test/'test.yaml').read_text().splitlines()
                if ':' in line and not line.lstrip().startswith('#'))


class TestMemory(Memory):
    """Apply specified address-range errors; nth AXI errors use a model access address."""
    def __init__(self, original, errors):
        super().__init__(original.base, original.data)
        self.errors = errors

    def fault(self, channel, address, size):
        if channel in self.errors:
            fault = self.errors[channel]
            if 'nth' in fault:
                first = last = fault['model_address']
            else:
                first, last = fault['first'], fault['last']
            if address <= last and first < address+size:
                raise BusError(f'{channel} response error at {address:#x}')

    def read(self, address, size):
        self.fault('read', address, size)
        return super().read(address, size)

    def write(self, address, data):
        self.fault('write', address, len(data))
        super().write(address, data)


def execute_model(out, writes, base, config):
    gpu = GPU(TestMemory(Memory.read_hex(out/'initial.hex', base), config['axi_errors']))
    if config['abort'] is not None:
        # Mid-command target contents and timing are outside the functional model.
        gpu.execute([write for write in writes if write[0] != REGISTERS['DOORBELL']])
        gpu.write_register('CTRL', 5)
    else:
        gpu.execute(writes)
    gpu.memory.errors = {}
    return gpu


def model_export(out):
    # Consume the bench control file, including its integer/hex conventions.
    records = (out/'control.txt').read_text().splitlines()
    origin, words, write_count, sample_count = records[0].split()
    base = int(origin, 16)
    writes = [[int(a, 16), int(v, 16)] for a, v in
              (line.split() for line in records[1:1+int(write_count)])]
    offsets = [int(line, 16) for line in records[1+int(write_count):]]
    assert len(offsets) == int(sample_count)
    config = json.loads((out/'config.json').read_text())
    reset_gpu = GPU(Memory.read_hex(out/'initial.hex', base))
    (out/'actual.reset.txt').write_text(''.join(
        f'{REGISTERS[name]:03x} {reset_gpu.regs[name]:08x}\n'
        for name in config['reset_registers']))
    gpu = execute_model(out, writes, base, config)
    # Export numeric little-endian words exactly as the DDR BFM's dump task does.
    (out/'actual.ddr.hex').write_text(''.join(
        f'{int.from_bytes(gpu.memory.read(base+index*4, 4), "little"):08x}\n'
        for index in range(int(words))))
    names = {offset: name for name, offset in REGISTERS.items()}
    (out/'actual.regs.txt').write_text(''.join(
        f'{offset:03x} {gpu.regs[names[offset]]:08x}\n' for offset in offsets))


def generate(test, out):
    seed = int(metadata(test)['seed'])
    spec = importlib.util.spec_from_file_location(test, HERE/test/'scene.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    case = Case()
    module.build(case, random.Random(seed))
    outputs = [out] + [out/f'run{index:02d}' for index in range(1, len(case.runs)+1)]
    for item, directory in zip([case] + case.runs, outputs):
        generate_case(item, directory)
    (out/'runs.json').write_text(json.dumps([str(p.relative_to(out)) for p in outputs]) + '\n')
    return outputs


def generate_case(case, out):
    out.mkdir(parents=True, exist_ok=True)
    writes = case.scene.export(out/'initial.hex', out/'writes.json')
    if case.command_timing:
        base_name, base = writes[-3]
        count = writes[-2][1]
        writes = list(writes[:-3])
        for index in range(count):
            writes.extend([['IRQ_STAT', 3], [base_name, base+index*32],
                           ['DESC_COUNT', 1], ['DOORBELL', 1]])
    writes = [[REGISTERS[name], value] for name, value in writes]
    checked = CHECKED if case.checked_registers is None else case.checked_registers
    checked = list(dict.fromkeys(checked + case.sample_registers +
                                 list(case.expected_registers)))
    sampled = list(dict.fromkeys(checked + SAMPLED + case.sample_registers))
    config = dict(axi_errors=case.axi_errors, abort=case.abort,
                  compare_ddr=case.compare_ddr, checked=checked,
                  reset_registers=case.reset_registers, clock_mhz=case.clock_mhz)
    (out/'config.json').write_text(json.dumps(config, indent=2) + '\n')
    (out/'reset.txt').write_text(str(len(case.reset_registers)) + '\n' + ''.join(
        f'{REGISTERS[name]:03x} {RESETS[name]:08x}\n' for name in case.reset_registers))
    gpu = execute_model(out, writes, case.scene.memory.base, config)
    for check in case.checks:
        check(gpu)
    gpu.memory.write_hex(out/'expected.ddr.hex')
    expected = {name: gpu.regs[name] for name in checked}
    expected.update(case.expected_registers)
    (out/'expected.regs.json').write_text(json.dumps(expected, indent=2) + '\n')
    (out/'regions.json').write_text(json.dumps(dict(surfaces=case.surfaces,
                                                  regions=case.regions), indent=2) + '\n')
    for index, region in enumerate(case.surfaces + case.regions):
        (out/f'expected.region{index}.bin').write_bytes(
            gpu.memory.read(region['address'], region['size']))
    (out/'commands.bin').write_bytes(b''.join(case.scene.commands))
    words = len((out/'initial.hex').read_text().splitlines())
    header = f'{case.scene.memory.base:08x} {words:d} {len(writes):d} {len(sampled):d}\n'
    (out/'control.txt').write_text(header + ''.join(f'{a:03x} {v:08x}\n' for a, v in writes)
                                  + ''.join(f'{REGISTERS[n]:03x}\n' for n in sampled))
    # Expected IRQ_STAT selects normal completion or the specified command error path.
    (out/'completion.txt').write_text(f'{expected.get("IRQ_STAT", gpu.regs["IRQ_STAT"]):08x}\n')
    abort = case.abort
    values = (-1, 0, 0) if abort is None else (
        abort.get('cycle', -1), abort.get('command', 0), abort.get('after', 0))
    kind, first, last = 0, 0, 0
    if abort is not None:
        if 'read_address' in abort:
            kind, (first, last) = 1, abort['read_address']
        elif 'write_address' in abort:
            kind, (first, last) = 2, abort['write_address']
    (out/'events.txt').write_text(('%d %d %d %d %08x %08x\n') %
                                  (*values, kind, first, last))
    arguments = [f'+CLOCK_MHZ={case.clock_mhz}']
    for channel, fault in case.axi_errors.items():
        tag = 'R' if channel == 'read' else 'W'
        if 'nth' in fault:
            arguments.append(f'+MEM_{tag}ERR_NTH={fault["nth"]}')
        else:
            arguments.extend([f'+MEM_{tag}ERR={fault["first"]:x}',
                              f'+MEM_{tag}ERR_LAST={fault["last"]:x}'])
    (out/'sim_args.json').write_text(json.dumps(arguments) + '\n')


def compare(out):
    base = int((out/'control.txt').read_text().split()[0], 16)
    expected = (out/'expected.ddr.hex').read_text().splitlines()
    actual = (out/'actual.ddr.hex').read_text().splitlines()
    if len(expected) != len(actual):
        raise AssertionError(f'DDR words expected={len(expected)} actual={len(actual)}')
    config = json.loads((out/'config.json').read_text())
    expected_reset = (out/'reset.txt').read_text().splitlines()[1:]
    actual_reset = (out/'actual.reset.txt').read_text().splitlines()
    if expected_reset != actual_reset:
        raise AssertionError(f'reset expected={expected_reset} actual={actual_reset}')
    pairs = zip(expected, actual) if config['compare_ddr'] else []
    for index, (left, right) in enumerate(pairs):
        if int(left, 16) != int(right, 16):
            want = int(left, 16).to_bytes(4, 'little')
            got = int(right, 16).to_bytes(4, 'little')
            byte = next(n for n in range(4) if want[n] != got[n])
            raise AssertionError(f'DDR address={base+index*4+byte:#x} '
                                 f'expected={want[byte]:#04x} actual={got[byte]:#04x}')
    registers = {int(a, 16): int(v, 16) for a, v in
                 (line.split() for line in (out/'actual.regs.txt').read_text().splitlines())}
    for name, value in json.loads((out/'expected.regs.json').read_text()).items():
        observed = registers[REGISTERS[name]]
        if value != observed:
            raise AssertionError(f'{name} expected={value:#x} actual={observed:#x}')
    regions = json.loads((out/'regions.json').read_text())
    memory = Memory.read_hex(out/'actual.ddr.hex', base)
    for index, region in enumerate(regions['surfaces'] + regions['regions']):
        (out/f'actual.region{index}.bin').write_bytes(
            memory.read(region['address'], region['size']))
    register_count = len(json.loads((out/"expected.regs.json").read_text()))
    print(f'PASS {out.name}: DDR={len(expected)*4} bytes, registers={register_count}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['generate', 'compare', 'model', 'rtl'])
    parser.add_argument('tests', nargs='*', default=[])
    args = parser.parse_args()
    tests = args.tests or [f'gt{i:02d}' for i in range(1, 9)]
    for test in tests:
        root = ROOT/'build/gpu/block'/test
        if args.mode == 'compare':
            outputs = [root/item for item in json.loads((root/'runs.json').read_text())]
        else:
            outputs = generate(test, root)
        if args.mode == 'generate':
            continue
        for out in outputs:
            if args.mode == 'model':
                model_export(out)
            elif args.mode == 'rtl':
                from tools.regress import expand_files
                obj = ROOT/'build/gpu/block/obj'
                subprocess.run(['verilator', '--binary', '--timing', '-Wall', '-j', '1',
                                '--top-module', 'edrv32_gpu_tb', '--Mdir', str(obj), '-o', 'sim',
                                '+define+SIM_MODE', *expand_files(HERE/test/'files.f')],
                               cwd=ROOT, check=True)
                arguments = json.loads((out/'sim_args.json').read_text())
                subprocess.run([str(obj/'sim'), f'+CASE_DIR={out}',
                                f'+SEED={int(metadata(test)["seed"])}', *arguments],
                               cwd=ROOT, check=True)
            compare(out)


if __name__ == '__main__':
    main()
