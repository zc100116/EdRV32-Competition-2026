#!/usr/bin/env python3
"""Reproducible dual-issue development regression, without changing build inputs."""
from __future__ import annotations
import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

from expand_filelist import expand

ROOT=Path(__file__).resolve().parents[2]
BASELINE=[
    'mul-low1','mdu-low1','mdu-pango-low1','ex-mul-stable','mul-low2',
    'foundation','operand-resolve','core-mdu-waw-load','core-mdu-raw-irq',
    'core-mdu-raw-irq-high','decode-stage','hpm-attribution','ex-stage',
    'lsu-equality-load','lsu-control-load','lsu-decoupled-load','load-queue',
    'mem2-response-bypass','uncached-load-use','hpm-attribution-cached','mdu',
    'mdu-pango','mdu-legacy','mdu-pango-legacy','mdu-commit','core-mdu',
    'core-smoke','cached-core-smoke','core-csr-trap','core-pma-trap',
    'core-irq-fencei','irq-store-commit','cached-irq-store',
    'mul-equivalence','div-equivalence','mul-pango-equivalence',
    'frontend','frontend-early-redirect',
]
FRONTEND=['wide-prediction','wide-mdu-irq','wide-cache','wide-predictor','wide-frontend','if2-dual-missing','dual-align','dual-frontend','if2-dual-prediction','core-dual-frontend',
          'core-dual-csr-trap','core-dual-irq-fencei','core-dual-mdu-raw-irq']

EXTRA=['align-stage','alu-equivalence','axi-single-outstanding-route','axi-single-outstanding-write-route',
       'branch-predictor','cache-array-equivalence','cache-blocking','hpm-csr','lsu-early-lookup',
       'lsu-throughput','mem-req-flow','pma-classifier','rvc-decompress','sram-axi-boundary','store-queue']
BACKEND=['ex-second-resident','dual-memory-alu','dual-memory-precise','dual-memory-cached-precise','dual-pair-irq','dual-regfile','dual-hpm-csr','dual-alu','dual-operand-resolve','dual-alu-csr-trap','dual-alu-irq-fencei','dual-alu-mdu-raw-irq']

def tool(name,override):
    found=override or shutil.which(name)
    if not found:
        raise RuntimeError(f'{name} is unavailable; install Icarus or pass --{name} PATH')
    return str(Path(found).resolve())

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite',choices=['frontend','backend','baseline','all'],default='all')
    parser.add_argument('--case',action='append',dest='cases',help='Case name, repeatable')
    parser.add_argument('--seed',action='append',type=int,dest='seeds')
    parser.add_argument('--iverilog')
    parser.add_argument('--vvp')
    parser.add_argument('--wave',action='store_true',help='New frontend cases support VCD')
    parser.add_argument('--output',type=Path)
    parser.add_argument('--timeout',type=int,default=180)
    args=parser.parse_args()
    compiler=tool('iverilog',args.iverilog);simulator=tool('vvp',args.vvp)
    cases=args.cases or (FRONTEND if args.suite=='frontend' else BACKEND if args.suite=='backend' else BASELINE if args.suite=='baseline' else BASELINE+EXTRA+FRONTEND+BACKEND)
    seeds=args.seeds or [1,7,20261006]
    stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    output=(args.output or ROOT/'sim/build/dual-issue'/stamp).resolve()
    output.mkdir(parents=True,exist_ok=True)
    manifest={'created_utc':stamp,'root':str(ROOT),'suite':args.suite,
              'compiler':compiler,'simulator':simulator,'seed_list':seeds,
              'results':[],'source_sha256':{},'functional_scope':'Paired frontend and selectable independent ALU dual issue/retirement'}
    for name,path in [('iverilog',compiler),('vvp',simulator)]:
        version=subprocess.run([path,'-V'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
        manifest[name+'_version']=version.stdout.splitlines()[0] if version.stdout else ''
    git=subprocess.run(['git','rev-parse','HEAD'],cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
    manifest['git_head']=git.stdout.strip() if git.returncode==0 else None
    for path in (ROOT/'rtl/include').glob('*.vh'):
        manifest['source_sha256'][path.relative_to(ROOT).as_posix()]=hashlib.sha256(path.read_bytes()).hexdigest()
    passed=True
    for case in cases:
        filelist=f'sim/cases/cpu/{case}/files.f'
        options=expand(ROOT,filelist,set())
        source_names=[s for s in options if s.endswith(('.v','.sv'))]
        for s in source_names:
            manifest['source_sha256'][s]=hashlib.sha256((ROOT/s).read_bytes()).hexdigest()
        manifest['source_sha256'][filelist]=hashlib.sha256((ROOT/filelist).read_bytes()).hexdigest()
        folder=output/case;folder.mkdir(parents=True,exist_ok=True)
        binary=folder/'case.vvp'
        command=[compiler,'-g2012','-DSIM_MODE','-o',str(binary),*options]
        with (folder/'compile.log').open('w',encoding='utf-8') as log:
            compile_result=subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
        case_variants={'lsu-throughput':8,'dual-memory-precise':6,'dual-memory-cached-precise':6}
        run_seeds=list(range(case_variants[case])) if case in case_variants else seeds if case in ('dual-align','dual-frontend','dual-alu','dual-memory-alu','wide-frontend') else [None]
        for seed in run_seeds:
            log_path=folder/(f'seed-{seed}.log' if seed is not None else 'run.log')
            run_command=[simulator,str(binary)]
            if seed is not None:run_command.append(f'+{"CASEID" if case in case_variants else "SEED"}={seed}')
            if args.wave:
                run_command.extend(['+WAVE',f'+WAVEFILE={folder}/seed-{seed}.vcd'])
            returncode=compile_result.returncode
            timeout=False
            with log_path.open('w',encoding='utf-8') as log:
                if compile_result.returncode==0:
                    try:
                        returncode=subprocess.run(run_command,cwd=ROOT,stdout=log,
                            stderr=subprocess.STDOUT,timeout=args.timeout).returncode
                    except subprocess.TimeoutExpired:
                        returncode=-1;timeout=True
            text=log_path.read_text(encoding='utf-8',errors='replace')
            ok=compile_result.returncode==0 and returncode==0 and 'PASS' in text and not re.search(r'\b(?:FAIL|FATAL)\b',text)
            passed &= ok
            manifest['results'].append({'case':case,'seed':None if case in case_variants else seed,
                'case_id':seed if case in case_variants else None,'passed':ok,
                'compile_command':command,'run_command':run_command,
                'returncode':returncode,'timed_out':timeout,
                'compile_log':str(folder/'compile.log'),'run_log':str(log_path)})
            (output/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
            print(f'{case} seed={seed}: {"PASS" if ok else "FAIL"}',flush=True)
            if not ok:
                print((folder/'compile.log').read_text(errors='replace')[-2500:] if compile_result.returncode else text[-2500:],flush=True)
    manifest['all_passed']=passed
    manifest['result_count']=len(manifest['results'])
    (output/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print('MANIFEST',output/'manifest.json',flush=True)
    return 0 if passed else 1

if __name__=='__main__':
    sys.exit(main())
