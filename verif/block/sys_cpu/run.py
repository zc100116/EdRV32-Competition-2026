#!/usr/bin/env python3
# File: run.py
# Spec: sys-subsys-testplan 3.6, 6; S-I2, S-I3.
# Description: Build SC software, pack ROM/SRAM images and run the integrated CPU/system bench.
#              Preserve UART, CRC, benchmark HPM and actual build/run commands.
# Clock domain: none (host tool).
"""Run sc01--sc08 or the SRAM/DDR CoreMark performance measurements."""
import argparse
import csv
from pathlib import Path
import json
import re
import shlex
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
REGIONS = {region['name']: region for region in json.loads(
    (Path(__file__).resolve().parents[3] / 'rtl/include/soc_address_map.json').read_text()
)['regions']}
sys.path.insert(0, str(ROOT))
from tools.regress import expand_files  # noqa: E402
from verif.block.sys_cpu.uart_checks import check_boot, check_monitor  # noqa: E402

HERE = Path(__file__).resolve().parent
OUT = ROOT / 'build/sys_cpu'
OPTS = {'o2': '-O2', 'tuned': '-O3 -funroll-all-loops -finline-limit=600 '
        '-falign-functions=4 -falign-jumps=4 -falign-loops=4'}


def command(args, log):
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open('w') as output:
        output.write(shlex.join(args) + '\n')
        output.flush()
        subprocess.run(args, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, check=True)


def build_program(program, name, memory='sram', opt='o2', request=False):
    out = OUT / 'sw' / name
    args = ['make', '-C', 'sw', f'PROGRAM={program}', f'OUT={out}', f'MEMORY={memory}']
    if program == 'coremark':
        flags = ('-march=rv32im_zicsr -mabi=ilp32 -std=c11 -Wall -Wextra -Werror '
                 + OPTS[opt] + ' -ffreestanding -fno-builtin -ffunction-sections '
                 '-fdata-sections -Isw/bsp/include -Isw/apps/coremark '
                 '-Ithird_party/coremark -Isw/drivers/include -DITERATIONS=10')
        # Make runs from sw/, while compilation resolves source paths from ROOT.
        flags = flags.replace('-Isw/', '-I' + str(ROOT / 'sw') + '/')
        flags = flags.replace('-Ithird_party/', '-I' + str(ROOT / 'third_party') + '/')
        args += ['ARCH=rv32im_zicsr', 'CFLAGS=' + flags,
                 'BSP=sw/bsp/start.S sw/tests/sys_cpu/host.c sw/drivers/uart.c',
                 'LDFLAGS=-nostdlib -Wl,--gc-sections -Wl,-T,sw/bsp/ld/' + memory +
                 '.ld -Wl,--wrap=main -Wl,-Map,' + str(out / 'coremark.map')]
    if request:
        args += ['PROGRAM_SOURCES=sw/tests/sys_cpu/download_request.c']
    command(args, out / 'build.log')
    elf = out / (program + '.elf')
    listing = subprocess.check_output(['riscv-none-elf-nm', str(elf)], text=True)
    symbols = {parts[2]: int(parts[0], 16) for line in listing.splitlines()
               if len(parts := line.split()) == 3}
    return out, elf, symbols


def load_segments(path):
    blob = path.read_bytes()
    header = struct.unpack_from('<16sHHIIIIIHHHHHH', blob)
    contents = {}
    for index in range(header[10]):
        kind, offset, _, addr, size, _, _, _ = struct.unpack_from(
            '<IIIIIIII', blob, header[5] + index * header[9])
        if kind == 1:
            contents.update(enumerate(blob[offset:offset + size], addr))
    return contents


def pack_image(contents, base, size, path):
    words = {}
    for address, value in contents.items():
        if base <= address < base + size:
            word = (address - base) // 8
            words[word] = words.get(word, 0) | (value << (8 * ((address - base) % 8)))
    previous = -2
    lines = []
    for address, value in sorted(words.items()):
        if address != previous + 1:
            lines.append(f'@{address:x}')
        lines.append(f'{value:016x}')
        previous = address
    path.write_text('\n'.join(lines) + '\n')
    return bool(words)


def compile_sim():
    obj = OUT / 'obj'
    args = ['verilator', '--binary', '--timing', '-Wall', '-j', '1', '-CFLAGS', '-O3',
            '+define+SIM_MODE',
            '--top-module', 'edrv32_sys_cpu_tb', '--Mdir', str(obj), '-o', 'sim']
    command(args + expand_files(HERE / 'files.f'), OUT / 'compile.log')
    return obj / 'sim'


def execute(sim, case, boot, program, name, *, memory='sram', opt='o2', latency=20,
            scratch=False):
    program_out, elf, symbols = build_program(program, name, memory, opt)
    app_elf = elf
    out = OUT / name
    out.mkdir(parents=True, exist_ok=True)
    contents = load_segments(boot)
    if case == 4:
        if scratch:
            _, app_elf, _ = build_program('sc04', 'download_request', request=True)
            contents.update(load_segments(app_elf))
    else:
        contents.update(load_segments(elf))
    if memory == 'ddr':
        entry = struct.unpack_from('<I', elf.read_bytes(), 24)[0]
        boot_jump = struct.pack('<II', (((entry + 0x800) >> 12) << 12) | 0x2b7,
                               ((entry & 0xfff) << 20) | 0x28067)
        contents.update(enumerate(boot_jump, 0x10000000))
    rom = out / 'rom64.hex'
    sram = out / 'sram64.hex'
    pack_image(contents, 0, 0x4000, rom)
    has_sram = pack_image(contents, int(REGIONS['SRAM']['base'], 0),
                          int(REGIONS['SRAM']['size'], 0), sram)
    args = [str(sim), f'+CASE_ID={case}', f'+ROM_HEX={rom}',
            f'+DDR_LATENCY={latency}', '+TIMEOUT=100000000',
            f'+APP_ENTRY={struct.unpack_from("<I", elf.read_bytes(), 24)[0]:x}']
    if has_sram:
        args.append(f'+SRAM_HEX={sram}')
    if memory == 'ddr':
        args.append(f'+DDR_HEX={program_out / "ddr.hex"}')
    if case == 4:
        raw = elf.with_suffix('.bin')
        command(['riscv-none-elf-objcopy', '-O', 'binary', str(elf), str(raw)],
                out / 'objcopy.log')
        args += [f'+DOWNLOAD_BIN={raw}', f'+DOWNLOAD_LENGTH={raw.stat().st_size}',
                 f'+SCRATCH_DOWNLOAD={int(scratch)}']
    if case == 7:
        args += [f'+PERF_BEGIN={symbols["start_time"]:x}',
                 f'+PERF_END={symbols["stop_time"]:x}']
    command(args, out / 'run.log')
    output = (out / 'run.log').read_text()
    if f'PASS sys_cpu SC-{case:02}' not in output:
        raise RuntimeError(f'{out}/run.log: missing completion')
    for text in (['EdRV32 Boot ROM'] if case == 4 else ['EdRV32 Boot ROM', 'Boot SRAM']):
        if text not in output:
            raise RuntimeError(f'{out}/run.log: missing UART {text!r}')
    if case in (1, 8):
        commit = subprocess.check_output(['git', 'rev-parse', '--short', 'HEAD'],
                                         cwd=ROOT, text=True).strip()
        compiler = 'GCC ' + subprocess.check_output(
            ['riscv-none-elf-gcc', '-dumpfullversion'], text=True).strip()
        check_boot(output.split('Boot SRAM\n')[0], commit, compiler)
        if case == 8:
            check_monitor(output, commit, compiler)
    if case == 4:
        for text in ['BIOS: EdRV32', 'BIOS menu: 1=UART load 2=ETH load 3=Run 4=Baud',
                     'UART load ready',
                     f'Load bytes: {raw.stat().st_size} segments: 1',
                     'Load result: PASS']:
            if text not in output:
                raise RuntimeError(f'{out}/run.log: missing UART {text!r}')
    metrics = {'name': name, 'memory': memory, 'opt': opt, 'latency': latency}
    if case == 7:
        crc = [re.search(r'\[0\]crc' + kind + r'\s*:\s*0x([0-9a-f]+)', output)
               for kind in ('list', 'matrix', 'state')]
        if not all(crc) or [int(m[1], 16) for m in crc] != [0xe714, 0x1fd7, 0x8e3a]:
            raise RuntimeError(f'{out}/run.log: CoreMark algorithm CRC mismatch')
        ticks = int(re.search(r'Total ticks\s*:\s*(\d+)', output)[1])
        metrics.update(cycles=ticks, score=10000000 / ticks)
        for event, count in re.findall(r'SC_HPM window=0 event=(\d+) count=(\d+)', output):
            metrics['hpm' + event] = int(count)
        for channel, count, service in re.findall(
                r'SC_FILL channel=(\d+) count=(\d+) service_cycles=(\d+)', output):
            metrics['fill' + channel] = int(count)
            metrics['service' + channel] = int(service)
        for channel, cycles in re.findall(r'SC_MISSWAIT channel=(\d+) cycles=(\d+)', output):
            metrics['wait' + channel] = int(cycles)
        metrics['boot_cycles'] = int(re.search(r'SC_BOOT cycles=(\d+)', output)[1])
        print(f'PASS {name} CRC cycles={ticks} CoreMark/MHz={metrics["score"]:.6f}', flush=True)
    else:
        print(f'PASS {name}: {out / "run.log"}', flush=True)
    return metrics


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('test', choices=[f'sc{n:02}' for n in range(1, 9)] + ['perf'])
    args = parser.parse_args()
    _, boot, _ = build_program('bootloader', 'bootloader', 'rom')
    sim = compile_sim()
    if args.test == 'perf':
        metrics = []
        for opt in ('o2', 'tuned'):
            metrics.append(execute(sim, 7, boot, 'coremark', 'coremark_sram_' + opt, opt=opt))
        for latency in (20, 60):
            metrics.append(execute(sim, 7, boot, 'coremark', f'coremark_ddr_o2_l{latency}',
                                   memory='ddr', latency=latency))
        with (OUT / 'coremark.csv').open('w') as output:
            writer = csv.DictWriter(output, fieldnames=list(metrics[0]))
            writer.writeheader()
            writer.writerows(metrics)
    else:
        case = int(args.test[2:])
        program = 'coremark' if case == 7 else ('monitor' if case == 8 else args.test)
        execute(sim, case, boot, program, args.test)
        if case == 4:
            execute(sim, case, boot, args.test, 'sc04_scratch', scratch=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())
