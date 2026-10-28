#!/usr/bin/env python3
# File: run.py
# Spec: eth-spec 2.5; Task V-R8, registered ARP decision at a UDP frame boundary.
# Description: Exercise public RX/TX packet ordering with the independent ETH harness.
#              An ARP received at the first UDP completion must precede UDP number two.
# Clock domain: host; three asynchronous clocks in the reused port-level harness.
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
sys.path.insert(0, str(ROOT / 'verif/block/eth'))
from regress import expand_files
from cases import Case
from eth_ref import arp

OUT = ROOT / 'build/media-r3/eth_priority'


def generate(delay):
    case = Case(OUT, f'delay-{delay}')
    case.configure()
    packets = case.descriptors([3000])
    case.w(0x28, 1)
    case.cmd('H', 2)
    case.cmd('D', delay)
    case.tx.append(packets[0][:-4])
    case.send(arp())
    case.wait_rx(0)
    case.tx.extend(packet[:-4] for packet in packets[1:])
    case.ref.arp_sent()
    case.finish_tx(1)
    case.snapshot()
    return case.save()[1]


def compile_sim():
    OUT.mkdir(parents=True, exist_ok=True)
    obj = OUT / 'obj'
    with (OUT / 'compile.log').open('w') as log:
        subprocess.run(['verilator', '--binary', '--timing', '-Wall', '-j', '1',
                        '+define+SIM_MODE', '--top-module', 'edrv32_eth_tb',
                        '--Mdir', str(obj), '-o', 'sim',
                        *expand_files(ROOT / 'verif/block/eth/files.f')], cwd=ROOT,
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    return obj / 'sim'


def main():
    sim = compile_sim()
    # The port-level clocks place delay=1002 at the last eligible ARP/UDP boundary.
    # Include both a normal pending request and the preceding arrival cycle.
    for delay in [0, 1001, 1002]:
        directory = generate(delay)
        with (directory / 'run.log').open('w') as log:
            subprocess.run([str(sim), f'+SCRIPT={directory / "script.txt"}',
                            f'+VECTORS={directory}'], cwd=ROOT,
                           stdout=log, stderr=subprocess.STDOUT, check=True)
        print(f'PASS ARP priority delay={delay}', flush=True)


if __name__ == '__main__':
    main()
