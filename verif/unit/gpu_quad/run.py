#!/usr/bin/env python3
# File: run.py
# Spec: gpu-spec 2.5, 2.8, 2.13.
# Description: Build and run model-driven GPU quad unit tests.
# Clock domain: none (host).
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'gpu_perspective'))
from vectors import run

if __name__ == '__main__':
    run('quad')
