#!/usr/bin/env python3
# host_test.py — npu-testplan 3.10 PP-SW-01/02 host preparation checks.
# Compare production candidate C path with the official oracle before SoC integration.
# Clock domain: host CPU.
import ctypes as ct
from pathlib import Path
import subprocess
import prepare

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'build/npu/post_sw'
subprocess.run(['gcc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2',
                '-fsanitize=undefined', '-fno-sanitize-recover=all', '-shared', '-fPIC',
                str(ROOT / 'sw/lib/yolo_post.c'), '-o', str(OUT / 'candidates.so')], check=True)
lib = ct.CDLL(str(OUT / 'candidates.so'))


class Candidate(ct.Structure):
    _fields_ = [('box', ct.c_int32 * 4), ('probability', ct.c_uint32),
                ('category', ct.c_uint16), ('anchor', ct.c_uint16)]


lib.yolo_post_candidates.argtypes = [ct.POINTER(Candidate), ct.c_uint32,
                                     ct.c_void_p, ct.c_void_p]
for address, data in prepare.segments:
    if address not in (0x08600000, 0x08610000, 0x08620000, 0x08800000):
        continue
    items = (Candidate * (len(data) // 24)).from_buffer_copy(data)
    expected_address = {0x08600000: 0x08700000, 0x08610000: 0x08710000,
                        0x08620000: 0x08720000, 0x08800000: 0x08900000}[address]
    expected = dict(prepare.segments)[expected_address]
    detections = ct.create_string_buffer(1200)
    stats = (ct.c_uint32 * 7)()
    kept = lib.yolo_post_candidates(items, len(items), detections, stats)
    assert kept * 12 == len(expected)
    assert detections.raw[:kept * 12] == expected
    assert list(stats[:4]) == [0, len(items), 0, 0]
    print(f'PASS oracle address={address:08x} candidates={len(items)} EDDT={kept}')
command = ['gcc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2',
           '-I' + str(ROOT / 'sw/bsp/include'), '-I' + str(ROOT / 'sw/drivers/include'),
           '-include', str(ROOT / 'sw/tests/npu_post/host_mmio.h'),
           str(ROOT / 'sw/drivers/npu.c'), str(ROOT / 'sw/tests/npu_post/driver_test.c'),
           '-o', str(OUT / 'driver_test')]
subprocess.run(command, check=True)
subprocess.run([str(OUT / 'driver_test')], check=True)

# The NPU interpreter verifies the six identity-head descriptors and folded weights.
# This is software reference execution, not an RTL simulation.
import sys
sys.path.insert(0, str(ROOT / 'tools/npu'))
from ref.npu_ref import Memory, execute
for frame in range(2):
    memory = Memory()
    memory.write(0x00100000, prepare.model)
    memory.write(0x00080000, prepare.descriptors)
    raw = dict(prepare.segments)[0x08000000 + frame * 0x100000]
    memory.write(0x04000000, raw)
    execute(memory, dict(MODEL_BASE=0x00100000, WORK_BASE=0x01000000,
                         INPUT_BASE=0x04000000, OUTPUT_BASE=0x05000000,
                         DESC_BASE=0x00080000, DESC_COUNT=6))
    assert memory.read(0x05000000, len(raw)) == raw
    print(f'PASS identity detection-head fixture frame={frame}')
