#!/usr/bin/env python3
"""Run exact D arithmetic, protocol stress and twelve-stage APM checks."""
import argparse
from pathlib import Path
import subprocess
import sys
from vectors import generate
ROOT = Path(__file__).resolve().parents[3]
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tier',choices=('smoke','full'))
    parser.add_argument('--softfloat-root',type=Path)
    args=parser.parse_args()
    out=ROOT/'build/cpu2_fpu_fma64'
    out.mkdir(parents=True,exist_ok=True)
    vectors=out/(args.tier+'.txt')
    generate(vectors,args.tier)
    sys.path.insert(0,str(ROOT/'tools'))
    from regress import expand_files
    sources=expand_files(ROOT/'verif/unit/cpu2_fpu_fma64/files.f')
    for top in ('apm_tb','tb'):
        obj=out/('obj_'+top)
        subprocess.run(['verilator','--binary','--timing','-Wall','--top-module',top,
                        '-DSIM_MODE',*sources,'--Mdir',str(obj),'-o','sim','-j','1'],
                       cwd=ROOT,check=True)
        commands=[[]] if top=='apm_tb' else [['+VECTORS='+str(vectors)],
                                                        ['+VECTORS='+str(vectors),'+STRESS']]
        if top=='tb' and args.softfloat_root:
            selected=out/'softfloat.vec'
            with selected.open('w') as stream:
                for op in ('add','sub','mul','madd','msub','nmadd','nmsub'):
                    paths=sorted((args.softfloat_root/'smoke-fd').glob(op+'_64_rm*.vec'))
                    if not paths: raise FileNotFoundError(op+' D vectors missing')
                    for path in paths: stream.write(path.read_text())
            commands += [['+SOFTFLOAT','+VECTORS='+str(selected)]]
        for command in commands: subprocess.run([str(obj/'sim'),*command],cwd=ROOT,check=True)
if __name__=='__main__': main()
