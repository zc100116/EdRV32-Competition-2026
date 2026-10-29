#!/usr/bin/env python3
# File: run.py
# Spec: soc-testplan SC-06, 2.
# Description: Run this scenario through the shared SoC environment.
# Clock domain: host.
from pathlib import Path
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'common'))
from run import run
run(Path(__file__).resolve().parent, 6)
