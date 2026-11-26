#!/usr/bin/env python3
"""G-4: four-entry boot menu and short/long-confirm scene control regression."""
import csv
import pathlib
import subprocess
import sys
binary=pathlib.Path(sys.argv[1] if len(sys.argv)>1 else 'build/gpu_test/gpu_test').resolve()
out=pathlib.Path('build/g4/controls');out.mkdir(parents=True,exist_ok=True)
def run(scene,events,frames):
    script=out/'input.txt'
    script.write_text(''.join(f'{frame} {keys}\n'for frame,keys in events))
    result=subprocess.run([str(binary),'--scene',str(scene),'--frames',str(frames),
        '--input',str(script),'--out',str(out)],check=True,text=True,capture_output=True)
    return list(csv.DictReader(result.stdout.splitlines()))[-1]
for game in range(1,5):
    keys=[8,0]*(game-1)+[16,0]
    row=run(0,list(enumerate(keys,1)),len(keys))
    assert int(row['game'])==game,row
for game in (3,4):
    row=run(game,[(1,16),(31,0)],31)
    assert int(row['game'])==game+8,row
    row=run(game,[(1,16),(31,0),(32,16),(33,0)],33)
    assert int(row['game'])==game and row['mode']=='1',row
    row=run(game,[(1,16),(2,0),(3,128),(4,0)],4)
    assert row['game']=='0',row
    events=[(1,16),(31,0),(32,128),(33,0),(34,16),(35,0),(36,16),(37,0)]
    for frame in (38,40,42,44):events.extend([(frame,8),(frame+1,0)])
    events.extend([(46,16),(47,0)])
    row=run(game,events,47)
    assert row['game']=='1' and row['weapon']=='1',row
print('PASS four boot entries, long-confirm controls, modes, Esc and new-to-original menu roundtrip')
