#!/usr/bin/env python3
# run.py — npu-testplan 3.10 PP-SW; independent SoC software integration.
# Build images and run the shared postprocessing bench; host clock domain.
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'pp_sw_01'))
from run_common import run
run(Path(__file__).resolve().parent)
