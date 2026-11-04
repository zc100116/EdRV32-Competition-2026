#!/usr/bin/env python3
"""vision_profile.py — npu-spec 2.2; instrument production post.c and run each ELF once.

Run after sourcing ~/.local/opt/edrv32/env.sh, under the requested shared flock.
Clock domain: host orchestration; Spike minstret is an instruction count only.
"""
from pathlib import Path
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import yolo_post_ref as reference

ROOT = Path(__file__).resolve().parents[3]
build = ROOT / 'build/vision-latency'
build.mkdir(parents=True, exist_ok=True)
source = (ROOT / 'sw/apps/showcase/board/vision/post.c').read_text()
start = source.index('            for (uint32_t plane = 0; plane < 5; ++plane) {')
end = source.index('            stats->class_comparisons', start)
source = source[:start] + '            best = scan(classes, head, &class_id);\n' + source[end:]
source = source.replace('static uint32_t distance_q8(', 'static uint32_t distance_impl(')
point = source.index('static int better(')
wrapper = '''static uint32_t distance_q8(const int8_t *bins, const yolo_head *head,
                            yolo_post_stats *stats)
{
    uint32_t start = instructions();
    uint32_t value = distance_impl(bins, head, stats);
    dfl += instructions() - start;
    return value;
}

'''
(build / 'post_profile.inc').write_text(source[:point] + wrapper + source[point:])
(build / 'start.S').write_text('''.section .text.init
.globl _start
_start:
    la sp, stack_top
    call run
.section .rodata
.balign 64
.globl frame
frame:
    .incbin "build/vision-latency/output.bin"
.section .bss
.balign 16
    .space 16384
stack_top:
''')
(build / 'link.ld').write_text('''ENTRY(_start)
SECTIONS {
    . = 0x80000000;
    .text : { *(.text.init) *(.text*) }
    .rodata : { *(.rodata*) }
    .data : { *(.data*) *(.sdata*) }
    . = ALIGN(4096);
    .tohost : { *(.tohost) }
    .bss : { *(.bss*) *(.sbss*) *(COMMON) }
}
''')
results = []
for variant in ('baseline', 'packed'):
    elf = build / f'{variant}.elf'
    command = ['riscv-none-elf-gcc', '-O3', '-march=rv32im_zicsr', '-mabi=ilp32',
               '-fno-strict-aliasing', '-msmall-data-limit=0', '-nostartfiles',
               '-T', str(build / 'link.ld'), '-I', str(build), '-I', str(ROOT / 'sw/lib'),
               '-I', str(ROOT / 'sw/apps/showcase/board/vision')]
    if variant == 'packed':
        command += ['-DPACKED_FILTER']
    command += ['tools/npu/eval/vision_profile.c', 'sw/lib/yolo_tables.c',
                str(build / 'start.S'), '-o', str(elf)]
    subprocess.run(command, cwd=ROOT, check=True)
    result = subprocess.run(['spike', '--isa=RV32IM_Zicsr', '-m32', str(elf)],
                            cwd=ROOT, capture_output=True, text=True)
    (build / f'{variant}.txt').write_text(result.stdout + result.stderr)
    result.check_returncode()
    values = [int(line) for line in (result.stdout + result.stderr).splitlines()]
    results.append(values)
    print(variant, values[:12], flush=True)
assert results[0][12:] == results[1][12:], 'EDDT detections differ'
assert results[0][8:] == results[1][8:], 'candidate or operation counts differ'
print('PASS: identical candidates, sort/IoU counts and all EDDT detections')

expected, _ = reference.postprocess((build / 'output.bin').read_bytes(), reference.load_heads())
assert results[0][12:] == [value for row in expected for value in row], 'Python EDDT differs'
print('PASS: independent Python reference EDDT')
