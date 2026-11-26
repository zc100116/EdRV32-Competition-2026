#!/usr/bin/env python3
"""G-3: distinct deterministic screenshots and actual consecutive gameplay frames."""
import csv
import pathlib
import shutil
import subprocess
import zipfile

root = pathlib.Path(__file__).resolve().parents[4]
out = root / 'outputs/gpu-test-games-20261126'
work = root / 'build/gpu_test/captures'
out.mkdir(parents=True, exist_ok=True)
scenes = [
    ('2d-normal', 1, 0, 0, 2, 26, ['--shot', 'boss']),
    ('2d-boss', 1, 0, 0, 2, 29, ['--shot', 'boss', '--tick', '120']),
    ('2d-explosion', 1, 0, 0, 2, 36, ['--shot', 'explosion']),
    ('2d-spiral', 1, 0, 0, 2, 36, ['--tick', '240']),
    ('2d-wave', 1, 0, 0, 2, 36, ['--tick', '480']),
    ('2d-weapon-spread', 1, 0, 0, 2, 42, ['--weapon', '0']),
    ('2d-weapon-laser', 1, 0, 0, 2, 42, ['--weapon', '1']),
    ('2d-weapon-missile', 1, 0, 0, 2, 42, ['--weapon', '2']),
    ('2d-stress-100k', 1, 1, 6, 2, 3, []),
    ('2d-cpu', 1, 2, 0, 2, 26, ['--shot', 'boss']),
    ('3d-normal', 2, 0, 0, 2, 20, []),
    ('3d-drone', 2, 0, 0, 2, 26, ['--shot', 'drone']),
    ('3d-ring-effect', 2, 0, 0, 2, 27, ['--shot', 'ring']),
    ('3d-hit', 2, 0, 0, 2, 24, ['--shot', 'hit']),
    ('3d-stress-54k', 2, 1, 6, 2, 3, []),
    ('texture-nearest', 2, 2, 0, 0, 3, []),
    ('texture-bilinear', 2, 2, 0, 1, 3, []),
    ('texture-trilinear', 2, 2, 0, 2, 3, []),
    ('texture-checker', 2, 2, 0, 2, 16, ['--input', str(work/'checker-input.txt')]),
]
work.mkdir(parents=True, exist_ok=True)
keys = [16, 0]+[8, 0]*4+[16, 0]
(work/'checker-input.txt').write_text(''.join(f'{i+1} {k}\n' for i, k in enumerate(keys)))
for name, game, mode, level, filt, frames, extra in scenes:
    directory = work/name
    directory.mkdir(parents=True, exist_ok=True)
    print(name, flush=True)
    command = [str(root/'build/gpu_test/gpu_test'), '--scene', str(game),
               '--mode', str(mode), '--level', str(level), '--filter', str(filt),
               '--frames', str(frames), '--out', str(directory), *extra]
    with (out/f'{name}.csv').open('w') as log:
        subprocess.run(command, cwd=root, stdout=log, check=True)
    shutil.copyfile(directory/f'frame{frames:04}.png', out/f'{name}.png')
    shutil.rmtree(directory)

for name, game, mode in [('2d-normal', 1, 0), ('2d-cpu', 1, 2), ('3d-normal', 2, 0)]:
    directory = work/(name+'-sequence')
    directory.mkdir(parents=True, exist_ok=True)
    print(name+' consecutive sequence', flush=True)
    with (out/f'{name}-sequence.csv').open('w') as log:
        subprocess.run([str(root/'build/gpu_test/gpu_test'), '--scene', str(game),
                        '--mode', str(mode), '--frames', '180', '--sequence', '1',
                        '--out', str(directory)], cwd=root, stdout=log, check=True)
    with zipfile.ZipFile(out/f'{name}-3s.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for frame in range(1, 181):
            path = directory/f'frame{frame:04}.png'
            archive.write(path, path.name)
        archive.writestr('PLAYBACK.txt', '180 consecutive gameplay frames; 60 ticks/s; 3 seconds.\n')
    shutil.rmtree(directory)

shutil.copyfile(root/'build/gpu_test/gpu_test.exe', out/'gpu_test.exe')
with (out/'measurements.md').open('w') as report:
    report.write('| 模式 | 对象 | 提交三角形 | 命令/帧 | PERF[4] 像素/帧范围 |\n')
    report.write('|---|---:|---:|---:|---:|\n')
    for name, *_ in scenes:
        with (out/f'{name}.csv').open() as log:
            rows = list(csv.DictReader(log))
        pixels = [int(row['passed_pixels']) for row in rows]
        report.write(f"| {name} | {rows[-1]['objects']} | {rows[-1]['triangles']} | "
                     f"{rows[-1]['commands']} | {min(pixels)}–{max(pixels)} |\n")
