#!/usr/bin/env python3
"""Run unchanged F numeric cases and FD SoftFloat mixed-precision cases."""
import argparse
from pathlib import Path
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'verif/unit/cpu2_fpu_fma32'))
from unit_vectors import generate
sys.path.insert(0,str(ROOT/'tools'))
from regress import expand_files
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tier',choices=('smoke',))
    parser.add_argument('--softfloat-root',type=Path,default=ROOT/'build/fpu')
    args=parser.parse_args()
    unit=Path(__file__).resolve().parent.name[len('cpu2_fpu_'):]
    operations={'convert':('to_w','to_wu','from_w','from_wu','mv_x_w','mv_w_x','to_d','to_s'),
                'short':('sgnj','sgnjn','sgnjx','min','max','eq','lt','le','class')}[unit]
    out=ROOT/('build/cpu2_fpu_'+unit)
    out.mkdir(parents=True,exist_ok=True)
    vectors=out/'smoke.txt'
    generate(vectors,unit,'smoke')
    sources=expand_files(ROOT/f'verif/unit/cpu2_fpu_{unit}/files.f')
    for fmt in ('F','FD'):
        obj=out/('obj_'+fmt)
        subprocess.run(['verilator','--binary','--timing','-Wall','--top-module','tb',
                        '-DSIM_MODE','-GFPU_FORMAT="'+fmt+'"',*sources,
                        '--Mdir',str(obj),'-o','sim','-j','1'],cwd=ROOT,check=True)
        if fmt=='F':
            subprocess.run([str(obj/'sim'),'+VECTORS='+str(vectors)],cwd=ROOT,check=True)
        source=args.softfloat_root/('smoke-'+fmt.lower())
        selected=out/('softfloat-'+fmt+'.vec')
        with selected.open('w') as stream:
            for op in operations:
                if fmt=='F' and op in ('to_d','to_s'):continue
                paths=sorted(source.glob(op+'_*.vec'))
                if not paths: raise FileNotFoundError(str(source/op))
                for path in paths:stream.write(path.read_text())
        for stress in ([],['+STRESS']):
            subprocess.run([str(obj/'sim'),'+SOFTFLOAT','+VECTORS='+str(selected),*stress],
                           cwd=ROOT,check=True)
if __name__=='__main__':main()
