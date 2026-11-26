#!/usr/bin/env python3
"""G-2 acceptance: all-mode screenshots; 180 consecutive frames for normal/CPU scenes."""
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
    directory = work / name
    directory.mkdir(parents=True, exist_ok=True)
    frames = 180 if name in ('2d-normal','2d-cpu','3d-normal') else 3
    command = [str(root / 'build/gpu_test/gpu_test'), '--scene', str(game),
               '--mode', str(mode), '--level', str(level), '--filter', str(filt),
               '--frames', str(frames), '--sequence', str(int(frames == 180)),
               '--out', str(directory)]
    print(name, flush=True)
    with (out / f'{name}.csv').open('w') as log:
        subprocess.run(command, cwd=root, stdout=log, check=True)
    preview = 20 if name == '3d-normal' else frames
    shutil.copyfile(directory / f'frame{preview:04}.png', out / f'{name}.png')
    if name == '2d-normal':
        for target in ['2d-explosion', '2d-boss', '2d-weapon-spread']:
            shutil.copyfile(directory/'frame0020.png', out/f'{target}.png')
    if name == '3d-normal':
        shutil.copyfile(directory/'frame0045.png', out/'3d-drone.png')
        shutil.copyfile(directory/'frame0096.png', out/'3d-ring-effect.png')
        shutil.copyfile(directory/'frame0105.png', out/'3d-hit.png')
    if frames == 180:
        with zipfile.ZipFile(out / f'{name}-3s.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
            for frame in range(1, 181):
                path = directory / f'frame{frame:04}.png'
                archive.write(path, path.name)
            archive.writestr('PLAYBACK.txt', '180 consecutive frames, 60 ticks/s, 3 seconds.\n')
    else:
        # G-1 archived all modes; G-2 only publishes continuous play/CPU captures.
        (out/f'{name}-3s.zip').unlink(missing_ok=True)
    # Raw generated frames stay in build; keep disk use bounded between modes.
    shutil.rmtree(directory)
# Replay the actual four-button menu to choose laser, homing missile and checker.
for name, game, switches in [('2d-weapon-laser',1,1), ('2d-weapon-missile',1,2),
                             ('texture-checker',2,1)]:
    keys = ([16,0]+[8,0]*4+[16,0])*switches
    script = work/'weapon-input.txt'
    script.write_text(''.join(f'{i+1} {k}\n' for i,k in enumerate(keys)))
    directory = work/name
    directory.mkdir(parents=True, exist_ok=True)
    command = [str(root/'build/gpu_test/gpu_test'), '--scene',str(game),
               '--mode', '2' if game==2 else '0', '--input', str(script),
               '--frames','100', '--out',str(directory)]
    with (out/f'{name}.csv').open('w') as log:
        subprocess.run(command,cwd=root,stdout=log,check=True)
    shutil.copyfile(directory/'frame0100.png',out/f'{name}.png')
    shutil.rmtree(directory)
for name, frames in [('2d-spiral',241),('2d-wave',481)]:
    directory=work/name
    directory.mkdir(parents=True,exist_ok=True)
    with (out/f'{name}.csv').open('w') as log:
        subprocess.run([str(root/'build/gpu_test/gpu_test'),'--scene','1',
                        '--frames',str(frames),'--out',str(directory)],stdout=log,check=True)
    shutil.copyfile(directory/f'frame{frames:04}.png',out/f'{name}.png')
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
