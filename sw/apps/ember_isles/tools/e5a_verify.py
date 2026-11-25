#!/usr/bin/env python3
# File: e5a_verify.py; tech 6: serial E5a acceptance.
# Description: Reproduce measurements with logs in build/.
# Clock domain: fixed 60 Hz simulation and host measurement.
"""G-2.5a: serial builds, directed tests, complete replays and real stress measurements.

Run after sourcing ~/.local/opt/edrv32/env.sh; all logs/products stay in build/.
"""
import contextlib
from pathlib import Path
import subprocess

from compare_replay import compare

ROOT = Path(__file__).resolve().parents[4]
APP = ROOT / 'sw/apps/ember_isles'
OUT = ROOT / 'build/ember_isles'
SPIKE = ['spike', '--isa=rv32im_zicsr_zicntr', '--priv=m', '--pmpregions=0',
         '--no-dm', '--disable-dtb', '-m0x80000000:0x40000000', '--pc=0x80000000']


def run(command, name):
    with (OUT / name).open('w') as log:
        subprocess.run(list(map(str, command)), cwd=ROOT, stdout=log,
                       stderr=subprocess.STDOUT, check=True)
    print(f'PASS {name}', flush=True)


def make(*targets):
    return ['make', '-C', APP, *targets, '-j1']


def measurements(name):
    pc, spike = OUT / f'e5a-{name}-pc.log', OUT / f'e5a-{name}-spike.log'
    with (OUT / f'e5a-{name}-measure.txt').open('w') as report:
        with contextlib.redirect_stdout(report):
            compare(pc, spike)
            rows = [list(map(int, line.split(',')[1:])) for line in spike.read_text().splitlines()
                    if line.startswith('INST,') and not line.startswith('INST,frame')]
            for stage in range(3):
                subset = [row for row in rows if row[6] == stage]
                if subset:
                    print(f'stage={stage}; frames={len(subset)}; sim/gfx/audio/total mean,max: ' +
                          '; '.join(f'{sum(r[c] for r in subset) / len(subset):.2f},'
                                    f'{max(r[c] for r in subset)}' for c in range(1, 5)))
            state = next(line for line in reversed(pc.read_text().splitlines())
                         if line.startswith('STATE,'))
            print('actual per-stage enemy/shot/pickup/summon peaks: ' +
                  state.split(' peaks=')[1].split()[0])
    print((OUT / f'e5a-{name}-measure.txt').read_text(), flush=True)


def main():
    tests = ['e5a-grid-test', 'e5a-upgrade-test', 'e5a-content-test', 'e4-content-test',
             'e5a-replay', 'e5a-stress']
    run(make('all', 'test', *(OUT / name for name in tests)), 'e5a-build-tests.log')
    for name in tests[:4]:
        run([OUT / name], f'{name}.log')
    # Leave the final generated header and ordinary Spike executable on arena.
    for name in ['route', 'arena']:
        replay = APP / f'assets/replays/{name}.txt'
        run([OUT / 'e5a-replay', replay], f'e5a-{name}-pc.log')
        run(['python3', APP / 'tools/replay_convert.py', replay], f'e5a-{name}-convert.log')
        run(make('spike'), f'e5a-{name}-build.log')
        run([*SPIKE, OUT / 'ember_isles-spike.elf'], f'e5a-{name}-spike.log')
        measurements(name)
    run(['python3', APP / 'tools/e5a_profile.py'], 'e5a-profile-measure.txt')
    run(make(OUT / 'ember_isles-stress-spike.elf'), 'e5a-stress-build.log')
    run([OUT / 'e5a-stress'], 'e5a-stress-pc.log')
    run([*SPIKE, OUT / 'ember_isles-stress-spike.elf'], 'e5a-stress-spike.log')
    measurements('stress')


if __name__ == '__main__':
    main()
