#!/usr/bin/env python3
# File: prepare.py
# Spec: npu-testplan 2.4 and 3.2-3.7; npu-spec 4.1-4.3.
# Description: Invoke independent tools and apply specified error/boundary stimuli.
#              Only generated files under build/npu are modified.
# Clock domain: none (host preparation).
"""Generate NB cases; the public interchange format is the only tool interface."""
import json
import os
from pathlib import Path
import shutil
import subprocess

from cases import BASES, recipes

ROOT = Path(__file__).resolve().parents[3]
BUILD = ROOT / 'build/npu'
PYTHON = Path.home() / '.local/opt/edrv32-py/bin/python'
GEN = ROOT / 'tools/npu/gen_case.py'
REF = ROOT / 'tools/npu/ref/npu_ref.py'


def command(*args):
    subprocess.run([str(arg) for arg in args], cwd=ROOT, check=True,
                   env={**os.environ, 'OPENBLAS_NUM_THREADS': '1', 'OMP_NUM_THREADS': '1',
                        'PYTHONPATH': str(ROOT/'third_party/ultralytics')})


def regs(path):
    return {name: int(value, 16) for name, value in
            (line.split() for line in (path / 'regs.txt').read_text().splitlines())}


def write_regs(path, values):
    (path / 'regs.txt').write_text(''.join(f'{k} {v:08x}\n' for k, v in values.items()))


class Image:
    """Sparse bytes with readmemh beat addressing, used solely to prepare stimuli."""
    def __init__(self, path):
        self.data = {}
        for file in sorted(path.glob('mem_*.hex')):
            addr = 0
            for word in file.read_text().split():
                if word.startswith('@'):
                    addr = int(word[1:], 16)*32
                else:
                    self.data.update(enumerate(bytes.fromhex(word)[::-1], addr))
                    addr += 32

    def word(self, addr):
        return int.from_bytes(bytes(self.data.get(addr+n, 0) for n in range(4)), 'little')

    def put_word(self, addr, value):
        self.data.update(enumerate((value & 0xffffffff).to_bytes(4, 'little'), addr))

    def save(self, path):
        for file in path.glob('mem_*.hex'):
            file.unlink()
        write_hex(path / 'mem_state.hex', self.data)


def write_hex(path, data):
    beats = sorted({addr//32 for addr in data})
    lines = []
    previous = -2
    for beat in beats:
        if beat != previous+1:
            lines.append(f'@{beat:x}')
        value = bytes(data.get(beat*32+b, 0) for b in range(32))
        lines.append(value[::-1].hex())
        previous = beat
    path.write_text('\n'.join(lines)+'\n')


def patch_case(path, kind):
    image = Image(path)
    r = regs(path)
    desc = r['DESC_BASE']
    flags = image.word(desc)
    bases = [r[k] for k in ['MODEL_BASE', 'WORK_BASE', 'INPUT_BASE', 'OUTPUT_BASE']]
    if kind in ['negative', 'positive_input']:
        addr = bases[(flags >> 12) & 3]+image.word(desc+4)
        shape = image.word(desc+32)
        planes = image.word(desc+40) & 63
        stride = image.word(desc+8)
        size = (shape & 4095)*((shape >> 16) & 4095)*16
        for plane in range(planes):
            for n in range(size):
                image.data[addr+plane*stride+n] = (128+((n+plane*17) % 128)
                    if kind == 'negative' else 127)
    elif kind == 'lut':
        quant = r['MODEL_BASE']+image.word(desc+28)
        blocks = (image.word(desc+40) >> 8) & 15
        for block in range(blocks):
            for n in range(256):
                image.data[quant+block*512+256+n] = (n*73+19) & 255
    else:
        field, value = kind
        if field == 'op':
            image.put_word(desc, (flags & ~15) | value)
        elif field == 'row':
            image.put_word(desc+44, (image.word(desc+44) & ~2047) | value)
        elif field == 'cout':
            image.put_word(desc+40, (image.word(desc+40) & ~0xf00) | (value << 8))
        elif field == 'weight':
            image.put_word(desc+48, value)
        else:
            raise ValueError(kind)
    image.save(path)


def manual_selftest():
    """A hand-built format fixture, independent of unfinished compiler/model tools."""
    path = BUILD / 'selftest'
    path.mkdir(parents=True, exist_ok=True)
    r = {key.upper()+'_BASE': value for key, value in BASES.items()}
    r['DESC_COUNT'] = 1
    write_regs(path, r)
    for index, name in enumerate(['model', 'desc', 'input', 'work', 'output']):
        address = BASES[name]
        data = {address+b: (b*7+index*31) & 255 for b in range(64)}
        write_hex(path / f'mem_{name}.hex', data)
    output = BASES['output']
    # Sparse second interval and unequal high/low bytes expose reversed packing.
    ref = {output+b: (b*11+3) & 255 for b in range(64)}
    ref.update({output+0x1000+b: (255-b*5) & 255 for b in range(32)})
    write_hex(path / 'ref_out.hex', ref)
    (path / 'check.txt').write_text(f'head0 {output:08x} 40\nhead1 {output+4096:08x} 20\n')
    return path


def second_frame(path):
    result = path.parent / (path.name+'_frame2')
    if result.exists():
        shutil.rmtree(result)
    shutil.copytree(path, result)
    image = Image(result)
    r = regs(result)
    old_in = r['INPUT_BASE']
    old_out = r['OUTPUT_BASE']
    new_in = old_in+0x100000
    new_out = old_out+0x100000
    moved = {}
    for addr in list(image.data):
        if old_in <= addr < old_in+0x100000:
            byte = image.data.pop(addr)
            moved[addr-old_in+new_in] = 0 if addr % 4 == 3 else (byte+37) & 255
        elif old_out <= addr < old_out+0x100000:
            moved[addr-old_out+new_out] = image.data.pop(addr)
    image.data.update(moved)
    image.save(result)
    r['INPUT_BASE'] = new_in
    r['OUTPUT_BASE'] = new_out
    write_regs(result, r)
    checks = []
    for line in (result / 'check.txt').read_text().splitlines():
        name, address, length = line.split()
        address = int(address, 16)
        if old_out <= address < old_out+0x100000:
            address += new_out-old_out
        checks.append(f'{name} {address:08x} {length}')
    (result / 'check.txt').write_text('\n'.join(checks)+'\n')
    command(PYTHON, REF, result)
    return result


def error_options(path, options):
    r = regs(path)
    image = Image(path)
    desc = r['DESC_BASE']+options['error_desc']*64
    flags = image.word(desc)
    bases = [r[k] for k in ['MODEL_BASE', 'WORK_BASE', 'INPUT_BASE', 'OUTPUT_BASE']]
    write = options['error'] == 2
    address = bases[(flags >> (14 if write else 12)) & 3]
    address += image.word(desc+(12 if write else 4))
    prefix = 'MEM_WERR' if write else 'MEM_RERR'
    return [f'+{prefix}_FIRST={address:08x}', f'+{prefix}_LAST={address+31:08x}']


def prepare_small(test):
    prepared = []
    for name, config, options, patch in recipes(test):
        path = BUILD / test.lower().replace('-', '_') / name
        if path.exists():
            shutil.rmtree(path)
        path.mkdir(parents=True)
        config_path = path / 'config.json'
        config_path.write_text(json.dumps(config, indent=2)+'\n')
        command(PYTHON, GEN, '--config', config_path, '--seed', options.get('seed', 1),
                '--out', path)
        args = [f'+TEST_ID={test}', '+MEM_MODE=bw', '+MEM_MHZ=125',
                f'+MEM_B_DELAY={options.get("b_delay", 1)}']
        if options.get('error'):
            args += [f'+EXPECT_ERR={options["error"]}',
                     f'+EXPECT_DESC={options["error_desc"]}']
            if options['error'] <= 2:
                args += error_options(path, options)
        if isinstance(patch, tuple):
            recovery = path.parent / (name+'_recovery')
            if recovery.exists():
                shutil.rmtree(recovery)
            shutil.copytree(path, recovery)
            command(PYTHON, REF, recovery)
            args.append(f'+RECOVERY_DIR={recovery}')
        if patch:
            patch_case(path, patch)
        if not isinstance(patch, tuple):
            command(PYTHON, REF, path)
        if options.get('frame2'):
            args.append(f'+FRAME2_DIR={second_frame(path)}')
        if options.get('repeat'):
            args.append(f'+FRAME2_DIR={path}')
        if options.get('abort'):
            args.append(f'+ABORT_PHASE={options["abort"]}')
        if options.get('npu_mhz'):
            args.append(f'+NPU_MHZ={options["npu_mhz"]}')
        prepared.append((path, args))
    return prepared


def prepare_network(test):
    path = BUILD / 'yolo'
    image = next(iter(sorted((Path.home()/'.local/share/edrv32/npu/coco128').rglob('*.jpg'))))
    command(PYTHON, ROOT/'tools/npu/compile_yolo.py', '--image', image, '--out', path)
    command(PYTHON, REF, path)
    count = regs(path)['DESC_COUNT']
    if count != 68:
        raise ValueError(f'NET expected 68 descriptors, actual {count}')
    if test == 'NET-01':
        return [(path, ['+TEST_ID=NET-01', '+MEM_MODE=bw'])]
    if test == 'NET-02':
        return [(path, ['+TEST_ID=NET-02', f'+MEM_MODE={mode}'])
                for mode in ['zero', 'latency', 'bw']]
    r = regs(path)
    memory = Image(path)
    descriptors = [r['DESC_BASE']+n*64 for n in range(r['DESC_COUNT'])]
    convs = [n for n, addr in enumerate(descriptors) if memory.word(addr) & 15 == 0]
    chosen = {
        'L0': next(n for n in convs if memory.word(descriptors[n]) & 256),
        'L7': max(convs, key=lambda n: memory.word(descriptors[n]+48)*
                  ((memory.word(descriptors[n]+40) >> 8) & 15)),
        'L15_split': next(n for n in convs
                          if memory.word(descriptors[n]+32) == (48 << 16 | 80)
                          and memory.word(descriptors[n]+40) & 63 == 12
                          and (memory.word(descriptors[n]+40) >> 8) & 15 == 2),
        'SPPF_pool': next(n for n, addr in enumerate(descriptors) if memory.word(addr) & 15 == 1),
        'upsample': next(n for n, addr in enumerate(descriptors) if memory.word(addr) & 15 == 2),
        'head': next(n for n in reversed(convs) if (memory.word(descriptors[n]) >> 14) & 3 == 3),
    }
    prepared = []
    for name, n in chosen.items():
        target = BUILD / 'net_03' / name
        if target.exists():
            shutil.rmtree(target)
        command(PYTHON, REF, path, '--split-at', n, '--out', target)
        command(PYTHON, REF, target)
        prepared.append((target, ['+TEST_ID=NET-03', '+MEM_MODE=bw']))
    return prepared
