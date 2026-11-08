#!/usr/bin/env python3
# File: check_retained_jal.py; Spec: cpu-spec 4.2, 4.4; Clock: host.
# Reproduce the retained-JAL mapping defect with v0.17 RTL and the directed unit test.
# Run under flock /tmp/edrv32-sim.lock; generated snapshots stay in build/.
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.regress import expand_files  # noqa: E402


def main():
    out = ROOT / 'build/cpu-n-tour/v017-negative'
    out.mkdir(parents=True, exist_ok=True)
    sources = expand_files(ROOT / 'verif/unit/cpu_v3s/files.f')
    for name in ('core', 'frontend', 'ib', 'predictor'):
        filename = f'edrv32_cpu_{name}.v'
        target = out / filename
        target.write_text(subprocess.check_output(
            ['git', 'show', f'6413d119:rtl/cpu/{filename}'], text=True, cwd=ROOT))
        sources = [str(target) if x.endswith('/' + filename) else x for x in sources]
    with (out / 'compile.log').open('w') as log:
        subprocess.run(['verilator', '--binary', '--timing', '-j', '1', '--top-module',
                        'tb', '--Mdir', str(out / 'obj'), '-o', 'sim', '+define+SIM_MODE',
                        *sources], stdout=log, stderr=log, check=True, cwd=ROOT)
    with (out / 'run.log').open('w') as log:
        result = subprocess.run([str(out / 'obj/sim')], stdout=log, stderr=log)
    expected = 'FAIL retained slot0 JAL swapped with unissued load'
    assert result.returncode != 0 and expected in (out / 'run.log').read_text(), (
        f'Expected v0.17 retained-JAL failure; see {out}/run.log')
    print('PASS negative reproduction: v0.17 core fails retained-JAL scenario 21')


if __name__ == '__main__':
    main()
