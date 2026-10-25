#!/usr/bin/env python3
# File: coverage.py
# Spec: sys-subsys-testplan 5 (allocated sources and reachable contention only).
# Description: Sum observed functional bins from SB simulation logs.
# Clock domain: none (host tool).
"""Print covered/uncovered bins; stub results do not claim DUT coverage closure."""
from collections import Counter
from pathlib import Path
import re
import sys

bins = []
for master in range(2):
    for slave in range(7):
        bins.append(f'route.m{master}.s{slave}.read')
        if master == 1:
            bins.append(f'route.m1.s{slave}.write')
bins += [f'contention.s{s}' for s in (0, 1, 6)]
bins += [f'isolation.s{s}' for s in range(2, 6)]
bins += [f'response.{direction}.{resp}' for direction in ('read', 'write')
         for resp in (0, 2, 3)]
for domain, slots in [('sys', (0, 1, 4, 5, 6)), ('media', range(10))]:
    bins += [f'apb.{domain}.slot{s}.{direction}' for s in slots
             for direction in ('read', 'write')]
bins += ['apb.reserved', 'apb.timeout', 'apb.pslverr']
bins += [f'plic.claim.{s}' for s in (1, 2, 5, 6, *range(8, 16))]
bins += ['plic.tie']
bins += [f'uart.baud.{r}' for r in range(3)]
bins += ['uart.overrun', 'uart.frame_error']
bins += [f'uart.irq.{n}' for n in range(4)]
bins += ['i2c.port.0', 'i2c.port.1', 'i2c.read', 'i2c.write', 'i2c.nack',
         'i2c.speed.0', 'i2c.speed.1', 'reset.power', 'reset.media', 'reset.soc']
counts = Counter()
for argument in sys.argv[1:]:
    for name, count in re.findall(r'^COVER (\S+)=(\d+)$', Path(argument).read_text(), re.M):
        counts[name] += int(count)
for name in bins:
    print(f'{name}: {counts[name]} {"covered" if counts[name] else "uncovered"}')
print(f'Total: {sum(counts[name] != 0 for name in bins)}/{len(bins)} bins covered')
