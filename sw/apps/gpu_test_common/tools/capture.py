#!/usr/bin/env python3
"""G-1 acceptance: sequential 180-frame PC captures, PNG sequences in ZIP files."""
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
    ('2d-normal', 1, 0, 0, 2),
    ('2d-stress-100k', 1, 1, 6, 2),
    ('2d-cpu', 1, 2, 0, 2),
    ('3d-normal', 2, 0, 0, 2),
    ('3d-stress-54k', 2, 1, 6, 2),
    ('texture-nearest', 2, 2, 0, 0),
    ('texture-bilinear', 2, 2, 0, 1),
    ('texture-trilinear', 2, 2, 0, 2),
]
for name, game, mode, level, filt in scenes:
    # Explicit G-1 host requirement: only run captures with >=2 GiB available.
    available = int(next(line.split()[1] for line in
                         pathlib.Path('/proc/meminfo').read_text().splitlines()
                         if line.startswith('MemAvailable:'))) * 1024
    if available < 2*1024**3:
        raise SystemExit(f'{name}: available RAM {available} B is below required 2 GiB')
    directory = work / name
    directory.mkdir(parents=True, exist_ok=True)
    command = [str(root / 'build/gpu_test/gpu_test'), '--scene', str(game),
               '--mode', str(mode), '--level', str(level), '--filter', str(filt),
               '--frames', '180', '--sequence', '1', '--out', str(directory)]
    print(name, flush=True)
    with (out / f'{name}.csv').open('w') as log:
        subprocess.run(command, cwd=root, stdout=log, check=True)
    shutil.copyfile(directory / 'frame0180.png', out / f'{name}.png')
    with zipfile.ZipFile(out / f'{name}-3s.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for frame in range(1, 181):
            path = directory / f'frame{frame:04}.png'
            archive.write(path, path.name)
        archive.writestr('PLAYBACK.txt', '180 consecutive frames, 60 ticks/s, 3 seconds.\n')
    # Raw generated frames stay in build; keep disk use bounded between modes.
    shutil.rmtree(directory)
shutil.copyfile(root / 'build/gpu_test/gpu_test.exe', out / 'gpu_test.exe')
with (out / 'measurements.md').open('w') as report:
    report.write('| 模式 | 对象 | 提交三角形 | 命令/帧 | PERF[4] 像素/帧范围 |\n')
    report.write('|---|---:|---:|---:|---:|\n')
    for name, *_ in scenes:
        with (out / f'{name}.csv').open() as log:
            rows = list(csv.DictReader(log))
        values = [int(row['passed_pixels']) for row in rows]
        report.write(f"| {name} | {rows[-1]['objects']} | {rows[-1]['triangles']} | "
                     f"{rows[-1]['commands']} | {min(values)}–{max(values)} |\n")
