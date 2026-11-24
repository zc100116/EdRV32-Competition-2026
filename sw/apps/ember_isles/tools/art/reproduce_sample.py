#!/usr/bin/env python3
"""reproduce_sample.py — ART-2: replay the saved imagegen inputs through normalization.
Host pipeline, no clock domain. Recreating AI inputs uses the saved prompts/references.
"""
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
for script in ('normalize_atlases.py', 'texture_sample.py', 'compose_sample.py'):
    subprocess.run([sys.executable, str(HERE / script)], check=True)
