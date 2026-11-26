#!/usr/bin/env python3
"""G-1: exercise actual headless four-button menus and all stress load levels."""
import csv
import pathlib
import subprocess

root = pathlib.Path(__file__).resolve().parents[4]
out = root / 'build/gpu_test/controls'
out.mkdir(parents=True, exist_ok=True)

def run(*args):
    result = subprocess.run([str(root/'build/gpu_test/gpu_test'), *args,
                             '--out', str(out)], check=True, text=True, capture_output=True)
    return result.stdout, list(csv.DictReader(result.stdout.splitlines()))

events = {
    1:8, 2:0, 3:16, 4:0, 5:16, 6:0, 7:16, 8:0, 9:16, 10:0,
    11:8, 12:0, 13:16, 14:0, 15:16, 16:0, 17:8, 18:0, 19:8, 20:0,
    21:16, 22:0, 23:8, 24:0, 25:16, 26:0, 27:8, 28:0, 29:16, 30:0,
    31:128, 32:0, 33:16, 34:0,
}
script = out/'input.txt'
script.write_text(''.join(f'{frame} {keys}\n' for frame, keys in events.items()))
log, rows = run('--scene', '0', '--frames', '34', '--input', str(script))
(out/'controls.csv').write_text(log)
checks = [
    (3, {'game':'2', 'mode':'0'}), (8, {'game':'2', 'mode':'1'}),
    (14, {'game':'2', 'level':'1'}), (22, {'aa':'0'}), (26, {'filter':'0'}),
    (30, {'game':'2'}), (32, {'game':'0'}), (34, {'game':'1'}),
]
for frame, expected in checks:
    for key, value in expected.items():
        assert rows[frame-1][key] == value, (frame, key, rows[frame-1][key], value)
print('PASS boot selection, mode, level, AA, filter, resume, esc, re-enter 2D')
for game in (1, 2):
    for level in range(7):
        _, rows = run('--scene', str(game), '--mode', '1', '--level', str(level),
                      '--frames', '2')
        row = rows[-1]
        if game == 1:
            expected = [1000, 2000, 5000, 10000, 20000, 50000, 100000][level]
            assert int(row['objects']) == expected, row
        else:
            assert 10000 < int(row['triangles']) < 60000, row
        print('PASS stress', game, level, row['objects'], row['triangles'])
# Toggle CPU at a frozen scene state; then resume and confirm software path executes.
script.write_text('1 16\n2 0\n3 8\n4 0\n5 8\n6 0\n7 8\n8 0\n'
                  '9 16\n10 0\n11 8\n12 0\n13 16\n14 0\n')
_, rows = run('--scene', '1', '--frames', '14', '--input', str(script))
assert rows[-1]['game'] == '1' and rows[-1]['cpu'] == '1', rows[-1]
assert int(rows[-1]['commands']) == 16, rows[-1]
print('PASS live CPU/GPU toggle retains 1500-object scene')
