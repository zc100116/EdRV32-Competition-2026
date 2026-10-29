#!/usr/bin/env python3
# File: run.py
# Spec: soc-testplan SC-01, 2.
# Description: Run the shared SoC environment for the boot/download scenario.
# Clock domain: host.
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'common'))
from run import run
run(Path(__file__).resolve().parent, 1)
