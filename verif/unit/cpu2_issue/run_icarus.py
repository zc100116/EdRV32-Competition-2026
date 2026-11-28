# File: run_icarus.py
# Spec: cpu-v2-testplan CV02-CV05; control reset and X-propagation supplement.
# Description: Run the same public-interface unit benches under four-state simulation.
# Clock domain: host test runner.
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.regress import expand_files

os.chdir(ROOT)
out=Path('build/i02_icarus');out.mkdir(exist_ok=True)
for module in ('rf','id_agu','alu','branch','issue'):
 for width in (1,2):
  formats=('NONE',) if module=='rf' else ('NONE','F','FD')
  for fmt in formats:
   name=f'{module}-{width}-{fmt}'
   dest=out/name;dest.mkdir(exist_ok=True)
   args=['flock','/tmp/edrv32-sim.lock','iverilog','-g2012','-s','tb','-DSIM_MODE',f'-Ptb.ISSUE_WIDTH={width}','-o',str(dest/'sim')]
   if module!='rf':args+=[f'-Ptb.FPU_FORMAT="{fmt}"']
   for token in expand_files(Path('verif/unit/cpu2_'+module+'/files.f').resolve()):
    if token.startswith('+incdir+'):
     args += ['-I'+p for p in token[8:].split('+')]
    else:args.append(token)
   with (dest/'compile.log').open('w') as log:
    rc=subprocess.run(args,stdout=log,stderr=subprocess.STDOUT,timeout=180).returncode
   if rc:raise SystemExit(f'FAIL {name} compile: {dest}/compile.log')
   with (dest/'run.log').open('w') as log:
    rc=subprocess.run(['flock','/tmp/edrv32-sim.lock','vvp','-n',str(dest/'sim')],stdout=log,stderr=subprocess.STDOUT,timeout=180).returncode
   if rc or 'PASS' not in (dest/'run.log').read_text():raise SystemExit(f'FAIL {name}: {dest}/run.log')
   print('PASS Icarus '+name,flush=True)

print('PASS all 26 I02 Icarus control/configuration cases', flush=True)
