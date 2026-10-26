#!/usr/bin/env python3
# File: run_spike.py; cpu-testplan 2.1; SoC spec 6.1; clock: host.
# Run the B1 reference model and stop the comparison log at the tohost store.
"""Run an ELF in the M-only B1 Spike reference configuration."""
import argparse
from pathlib import Path
import json
import re
import subprocess
import shutil

ISA = 'rv32imc_zicsr_zifencei_zicntr_zihpm'
REGIONS = json.loads((Path(__file__).resolve().parents[2] /
                      'rtl/include/soc_address_map.json').read_text())['regions']
MEMORY = ','.join(f"{region['base']}:{region['size']}" for region in REGIONS
                  if region['name'] in ('ROM', 'SRAM', 'DDR'))


def symbols(elf):
    output = subprocess.check_output(['riscv-none-elf-nm', str(elf)], text=True)
    return {parts[2]: int(parts[0], 16) for line in output.splitlines()
            if len(parts := line.split()) == 3}


def configuration_library():
    root = Path(__file__).resolve().parents[2]
    source = Path(__file__).with_name('spike_config.cc')
    library = root / 'build/cpu/spike_config.so'
    library.parent.mkdir(parents=True, exist_ok=True)
    if not library.exists() or source.stat().st_mtime > library.stat().st_mtime:
        prefix = Path(shutil.which('spike')).resolve().parents[1]
        subprocess.run(['g++', '-std=c++17', '-shared', '-fPIC',
                        '-I' + str(prefix / 'include'), str(source), '-o', str(library)],
                       check=True)
    return library


def run(elf, output, compressed=True, signature=False):
    output.mkdir(parents=True, exist_ok=True)
    names = symbols(elf)
    log = output / 'spike.log'
    args = ['spike', '--extlib=' + str(configuration_library()),
            '--extension=edrv32_config', '--triggers=0', '--isa=' + (ISA if compressed else ISA.replace('imc_', 'im_')),
            '--priv=m', '--pmpregions=0', '--no-dm', '-m' + MEMORY,
            '--pc=0', '--disable-dtb', '-l', '--log-commits', '--log=' + str(log)]
    if signature:
        args += ['+signature=' + str(output / 'reference.signature'),
                 '+signature-granularity=4']
    subprocess.run(args + [str(elf)], check=True, timeout=60)
    # HTIF polls in batches. B1 terminates at the first nonzero tohost store;
    # discard only the extra commits executed after that same endpoint by Spike.
    lines = []
    host = re.compile(r' mem 0x([0-9a-f]+) 0x([0-9a-f]+)')
    for line in log.read_text().splitlines(keepends=True):
        lines.append(line)
        match = host.search(line)
        if match and int(match[1], 16) == names['tohost'] and int(match[2], 16):
            break
    else:
        raise RuntimeError(f'{elf}: Spike did not write a nonzero tohost value')
    log.write_text(''.join(lines))
    print(f'PASS {elf.name}: {log}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('elf', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--no-c', action='store_true')
    parser.add_argument('--signature', action='store_true')
    args = parser.parse_args()
    run(args.elf.resolve(), args.output.resolve(), not args.no_c, args.signature)
