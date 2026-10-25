#!/usr/bin/env python3
"""Sum cache-testplan section 5 counters from simulation logs into a text report."""
import collections
import pathlib
import re
import sys

counts = collections.Counter()
for name in sys.argv[1:]:
    for line in pathlib.Path(name).read_text().splitlines():
        match = re.fullmatch(r"COVER (.+)=(\d+)", line)
        if match:
            counts[match[1]] += int(match[2])
for name, value in sorted(counts.items()):
    print(f"{name}: {value} {'covered' if value else 'uncovered'}")
