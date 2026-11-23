"""replay.py — S-0b frame-150 GPU input replay against the bit-exact Python model.
Host-only verification; compare DDR and functional PERF from register-level capture.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))
from tools.gpu.scene import Memory
from tools.gpu.model import GPU

out = Path(sys.argv[1])
initial = (out / 'frame150-input.bin').read_bytes()
memory = Memory(0, initial)
gpu = GPU(memory)
writes = [tuple(map(int, line.split()))
          for line in (out / 'frame150-writes.txt').read_text().splitlines()]
gpu.execute(writes)
expected = (out / 'frame150-output.bin').read_bytes()
if memory.data != expected:
    first = next(i for i, (a, b) in enumerate(zip(memory.data, expected)) if a != b)
    raise AssertionError(f'DDR differs at {first:#x}: Python={memory.data[first]:#x}, '
                         f'PC={expected[first]:#x}')
perf = list(map(int, (out / 'frame150-perf.txt').read_text().splitlines()))
for index, value in enumerate(perf):
    assert gpu.regs[f'PERF[{index}]'] == value, (index, gpu.regs[f'PERF[{index}]'], value)
print(f'PASS frame 150: {len(initial)} DDR bytes, {len(writes)} register writes, '
      f'{len(perf)} PERF counters bit-exact')
