#!/usr/bin/env python3
# File: virtual_input_host_s3.py
# Spec: sys-subsys 2.5/2.6; Task T-S3IN.
# Description: Compile production S3 UART reception against host hardware mocks.
# Clock domain: deterministic host microseconds.
"""T-S3IN: real S3 platform/parser with finite UART and mocked CPU CSR entry.

Optional argument selects a baseline s3_platform.c. CSR instructions alone are
replaced for the host; UART configuration, ISR dispatch and snapshots stay real.
"""
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/s3-input-host'
OUT.mkdir(parents=True, exist_ok=True)
source = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'sw/apps/s3/s3_platform.c'
text = source.read_text().replace('__attribute__((interrupt("machine"), aligned(4)))', '')
text = text.replace('static void  s3_interrupt', 'void s3_interrupt')
text = re.sub(r'^#define CSR_WRITE.*$', '#define CSR_WRITE(csr, value) ((void)(value))',
              text, flags=re.M)
text = re.sub(r'^#define CSR_READ.*$', '#define CSR_READ(csr, value) ((value) = 0)',
              text, flags=re.M)
# Model CSR reads and interrupt enable; unused performance counters read as zero.
def csr(match):
    instruction = match.group(0)
    output = re.search(r'"=r"\((\w+)\)', instruction)
    if 'mcause' in instruction:
        return 'cause = host_cause;'
    if 'mepc' in instruction:
        return 'pc = 0x1234u;'
    if output:
        name = output.group(1)
        if 'csrrci' in instruction:
            return f'{name} = virtual_input_lock();'
        return f'{name} = 0;'
    if 'csrci mstatus' in instruction:
        return '(void)virtual_input_lock();'
    if 'csrsi mstatus' in instruction:
        return 'virtual_input_unlock(8u);'
    if 'csrw mtvec' in instruction:
        return '(void)handler;'
    if 'wfi' in instruction:
        return 'host_stopped();'
    return '(void)0;'
text = re.sub(r'__asm__ volatile\s*\(.*?\);', csr, text, flags=re.S)
text = ('#include "virtual_input_uart.h"\nextern unsigned host_cause;\n'
        'void host_stopped(void);\n' + text)
(OUT / 'platform.c').write_text(text)
flags = ['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror',
         '-ffunction-sections', '-fdata-sections', '-Isw/apps/s3', '-Isw/lib',
         '-Isw/drivers/include', '-Isw/bsp/include',
         '-include', 'sw/apps/nes/tests/input_mmio.h']
subprocess.run(flags + [str(OUT / 'platform.c'), 'tools/s3/virtual_input_host_s3.c',
                       'sw/lib/virtual_input.c', 'sw/lib/virtual_input_uart.c',
                       '-Wl,--gc-sections', '-o', str(OUT / 'input')], cwd=ROOT, check=True)
subprocess.run([str(OUT / 'input')], cwd=ROOT, check=True)
