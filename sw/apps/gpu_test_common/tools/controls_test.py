#!/usr/bin/env python3
"""G-2: exercise real four-button controls, weapons, texture view and stress tiers."""
import csv
import pathlib
import subprocess

root = pathlib.Path(__file__).resolve().parents[4]
out = root / 'build/gpu_test/controls'
out.mkdir(parents=True, exist_ok=True)

def run(*args):
    result = subprocess.run([str(root/'build/gpu_test/gpu_test'), *args,
                             '--out', str(out)], check=True, text=True, capture_output=True)
    return list(csv.DictReader(result.stdout.splitlines()))

def menu(item, repeats=1):
    keys = [16,0]+[8,0]*item+[16,0]
    if repeats > 1:
        keys = keys*repeats
    script = out/'input.txt'
    script.write_text(''.join(f'{i+1} {k}\n' for i,k in enumerate(keys)))
    return ['--input',str(script),'--frames',str(len(keys)+1)]

for game in (1,2):
    for level in range(7):
        row = run('--scene',str(game),'--mode','1','--level',str(level),'--frames','2')[-1]
        if game == 1:
            assert int(row['objects']) == [1000,2000,5000,10000,20000,50000,100000][level], row
        else:
            assert 10000 < int(row['triangles']) < 60000, row
        print('PASS stress',game,level,row['objects'],row['triangles'])
    row = run('--scene',str(game),*menu(0))[-1]
    assert row['mode'] == '1' and row['game'] == str(game), row
    row = run('--scene',str(game),*menu(1))[-1]
    assert row['level'] == '1', row
    row = run('--scene',str(game),*menu(2))[-1]
    assert row['aa'] == '0', row
    row = run('--scene',str(game),*menu(3))[-1]
    assert row['cpu' if game == 1 else 'filter'] == ('1' if game == 1 else '0'), row
    for count in (1,2,3):
        row = run('--scene',str(game),*menu(4,count))[-1]
        assert row['game'] == str(game), row
        assert row['weapon' if game == 1 else 'checker'] == str(count%(3 if game==1 else 2)),row
    row = run('--scene',str(game),*menu(5))[-1]
    assert row['game'] == str(game),row
print('PASS mode, load, AA, CPU/filter, all three weapons, both texture views and resume')
script=out/'input.txt'
script.write_text('1 128\n2 0\n3 8\n4 0\n5 16\n6 0\n')
row=run('--scene','1','--frames','6','--input',str(script))[-1]
assert row['game']=='2',row
print('PASS Esc -> boot menu -> 3D selection')
