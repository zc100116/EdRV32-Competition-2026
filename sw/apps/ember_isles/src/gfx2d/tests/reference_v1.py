#!/usr/bin/env python3
"""V1 acceptance: run the authorized-mechanic simulation before gfx integration at every frame.
Standard library only. Baseline sources/binary/log remain under build/.
"""
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[6]
APP = ROOT / 'sw/apps/ember_isles'
OUT = ROOT / 'build/ember_isles/v1-reference'
BASELINE = '7c3d063fd'


def main():
    paths = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', BASELINE,
                                    'sw/apps/ember_isles/src/core',
                                    'sw/apps/ember_isles/src/sim',
                                    'sw/apps/ember_isles/src/meta'], cwd=ROOT, text=True).splitlines()
    paths.append('sw/apps/ember_isles/tools/e5a_replay.c')
    for path in paths:
        content = subprocess.check_output(['git', 'show', BASELINE + ':' + path], cwd=ROOT)
        target = OUT / pathlib.Path(path).relative_to('sw/apps/ember_isles')
        target.parent.mkdir(parents=True, exist_ok=True)
        if path.endswith('/e5a_replay.c'):
            content = content.replace(b'if ((frame + 1) % 60 == 0)', b'if (1)')
        target.write_bytes(content)
    sources = [OUT / 'src' / path for path in ('core/core.c', 'core/replay.c',
               'sim/sim.c', 'sim/combat.c', 'meta/meta.c')]
    subprocess.run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror',
                    '-I' + str(OUT / 'src'), '-I' + str(ROOT / 'build/ember_isles/generated'),
                    *map(str, sources), str(OUT / 'tools/e5a_replay.c'), '-o', str(OUT / 'reference')], check=True)
    with (OUT / 'before.log').open('w') as log:
        subprocess.run([str(OUT / 'reference'), str(APP / 'assets/replays/coast.txt')],
                       stdout=log, check=True)
    print('Baseline ' + BASELINE + ': ' + str(OUT / 'before.log'))


if __name__ == '__main__':
    main()
