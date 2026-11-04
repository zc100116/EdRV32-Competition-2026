#!/usr/bin/env python3
"""vision_frame.py — npu-spec 2.2; one real-image fixed-model OUTPUT, host clock."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools/npu'))
sys.path.insert(0, str(ROOT / 'third_party/ultralytics'))
from input_pack import pack
from ref.npu_ref import load_case, execute

image = Path(sys.argv[1])
destination = Path(sys.argv[2])
model = ROOT / 'tasks/win/20261029-09-b3-software/src/npu'
memory, registers = load_case(model)
memory.write(registers['INPUT_BASE'], pack(image))
execute(memory, registers)
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_bytes(memory.read(registers['OUTPUT_BASE'], 725760))
print(f'{image}: {destination} (725760 bytes)', flush=True)
