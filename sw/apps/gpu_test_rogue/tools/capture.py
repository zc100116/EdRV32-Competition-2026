#!/usr/bin/env python3
"""G-4 real GPU-reference captures; run rogue before world, one process at a time."""
import argparse
import pathlib
import shutil
import subprocess
import zipfile
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('demo',choices=['rogue','world'])
p.add_argument('--binary',type=pathlib.Path,default=pathlib.Path('build/gpu_test/gpu_test'))
a=p.parse_args()
out=pathlib.Path('outputs/gpu-test-games-20261126');out.mkdir(parents=True,exist_ok=True)
scene=3 if a.demo=='rogue' else 4
shots= [('combat',60),('slash',2),('boss',45),('choice',1),('minimap',1),('stress',10)] if scene==3 else [
    ('day',1),('dusk',1),('coast',1),('landmark',1),('lod',1),('stress',1)]
for name,frames in shots:
    target=pathlib.Path('build/g4/captures')/f'{a.demo}-{name}'
    target.mkdir(parents=True,exist_ok=True)
    command=[str(a.binary.resolve()),'--scene',str(scene),'--frames',str(frames),'--out',str(target)]
    if name=='stress': command+=['--mode','1','--level','2']
    else:command+=['--shot',name]
    with (out/f'{a.demo}-{name}.csv').open('w') as log:subprocess.run(command,stdout=log,check=True)
    shutil.copyfile(target/f'frame{frames:04}.png',out/f'{a.demo}-{name}.png')
target=pathlib.Path('build/g4/captures')/f'{a.demo}-sequence'
target.mkdir(parents=True,exist_ok=True)
command=[str(a.binary.resolve()),'--scene',str(scene),'--frames','180','--sequence','1',
         '--out',str(target)]
if scene==3:command+=['--shot','combat']
with (out/f'{a.demo}-3s.csv').open('w') as log:subprocess.run(command,stdout=log,check=True)
with zipfile.ZipFile(out/f'{a.demo}-3s.zip','w',zipfile.ZIP_DEFLATED) as archive:
    for i in range(1,181):archive.write(target/f'frame{i:04}.png',f'frame{i:04}.png')
print(f'{a.demo}: six independent-state screenshots and 180 consecutive ticks saved in {out}')
