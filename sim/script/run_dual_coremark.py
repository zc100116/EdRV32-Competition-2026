#!/usr/bin/env python3
"""Fixed-image CoreMark checks for scalar and paired frontend configurations."""
from __future__ import annotations
import argparse
import concurrent.futures
import datetime
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path
from expand_filelist import expand

ROOT=Path(__file__).resolve().parents[2]
CASE=ROOT/'sim/soc/dual-frontend-coremark'

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--mode',choices=['scalar','paired','dual','wide','both','all'],default='both')
    p.add_argument('--opt',choices=['o2','o3','both'],default='both')
    p.add_argument('--output',type=Path)
    p.add_argument('--jobs',type=int,default=4)
    p.add_argument('--timeout',type=int,default=900)
    a=p.parse_args()
    for name in ('verilator','make'):
        if not shutil.which(name):raise RuntimeError(f'{name} required; run this suite in the Linux VM')
    stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    out=(a.output or ROOT/'sim/build/dual-coremark'/stamp).resolve();out.mkdir(parents=True,exist_ok=True)
    modes=['scalar','paired','dual','wide'] if a.mode=='all' else ['scalar','paired'] if a.mode=='both' else [a.mode]
    opts=['o2','o3'] if a.opt=='both' else [a.opt]
    flat=expand(ROOT,'sim/soc/dual-frontend-coremark/files.f',set())
    flags=[];sources=[];i=0
    while i<len(flat):
        if flat[i]=='-s':i+=2;continue
        if flat[i]=='-I':flags.append('-I'+flat[i+1]);i+=2;continue
        if flat[i].endswith(('.v','.sv')):sources.append(flat[i])
        else:flags.append(flat[i])
        i+=1
    versions=subprocess.run(['verilator','--version'],stdout=subprocess.PIPE,text=True,check=True).stdout.strip()
    manifest={'created_utc':stamp,'verilator_version':versions,'results':[],
        'scope':'Selectable scalar, paired frontend or independent ALU dual issue/retirement; simulation UART model.',
        'source_sha256':{s:digest(ROOT/s) for s in sources},'builds':[]}
    for path in (ROOT/'rtl/include').glob('*.vh'):
        manifest['source_sha256'][path.relative_to(ROOT).as_posix()]=digest(path)
    manifest['source_sha256']['sim/soc/dual-frontend-coremark/sim_main.cpp']=digest(CASE/'sim_main.cpp')
    for mode in modes:
        folder=out/mode;folder.mkdir(exist_ok=True);obj=folder/'obj_dir'
        command=['verilator','--cc','--exe','-O3','-Wno-fatal','--top-module','tb_soc',
            '--Mdir',str(obj),'-DSIM_MODE',f'-GFRONTEND_DUAL_WINDOW={int(mode=="paired")}',f'-GDUAL_ISSUE={int(mode in ("dual","wide"))}',f'-GFETCH_WIDE={int(mode=="wide")}',
            '-CFLAGS','-O3',*flags,*sources,str(CASE/'sim_main.cpp')]
        for argv,name in [(command,'verilator.log'),
                          (['make','-C',str(obj),'-f','Vtb_soc.mk',f'-j{a.jobs}'],'build.log')]:
            with (folder/name).open('w',encoding='utf-8') as log:
                result=subprocess.run(argv,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
            if result.returncode:
                manifest['all_passed']=False
                manifest['build_failure']={'mode':mode,'command':argv,'returncode':result.returncode,'log':str(folder/name)}
                (out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
                print((folder/name).read_text(encoding='utf-8',errors='replace')[-6000:]);return 1
        manifest['builds'].append({'mode':mode,'command':command,'binary_sha256':digest(obj/'Vtb_soc')})
        print('BUILT',mode,flush=True)

    def run(item):
        mode,opt=item;image=ROOT/'sim/fixtures/coremark'/f'{opt}-i10'
        log_path=out/mode/f'{opt}.log'
        command=[str(out/mode/'obj_dir/Vtb_soc'),f'+ROMFILE={image}/bootrom_32.hex',
                 f'+SRAMFILE={image}/sram_32.hex','+WATCHDOG=3000000','+CYCLE_LIMIT=30000000']
        with log_path.open('w',encoding='utf-8') as log:
            try:
                result=subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,timeout=a.timeout)
                returncode=result.returncode
                timed_out=False
            except subprocess.TimeoutExpired:
                returncode=-1
                timed_out=True
        text=log_path.read_text(encoding='utf-8',errors='replace')
        counts=re.findall(r'HPM cycles=(\d+) instret=(\d+)',text)
        expected_instret={'o2':2899049,'o3':2944145}[opt]
        ok=returncode==0 and len(counts)==3 and 'SIM_ALL_ROUNDS_COMPLETE' in text
        for field,expected in [('crclist','e3c1'),('crcmatrix','0747'),('crcstate','8d84'),('crcfinal','c64e')]:
            ok &= re.findall(field+r'\s*:\s*0x([0-9a-f]+)',text)==[expected]*3
        ok &= all(int(instret)==expected_instret for cycles,instret in counts)
        if mode=='scalar' and len(counts)==3:
            ok &= int(counts[1][0])=={'o2':3487221,'o3':3523737}[opt]
        data={'mode':mode,'optimization':opt,'passed':bool(ok),'run_command':command,
              'returncode':returncode,'timed_out':timed_out,
              'rounds':[{'cycles':int(c),'instret':int(n)} for c,n in counts],
              'log':str(log_path),'log_sha256':digest(log_path),
              'firmware_sha256':{p.name:digest(p) for p in (image/'bootrom_32.hex',image/'sram_32.hex')}}
        print(mode,opt,'PASS' if ok else 'FAIL',counts,flush=True)
        return data
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        manifest['results']=list(pool.map(run,[(m,o) for m in modes for o in opts]))
    manifest['all_passed']=all(r['passed'] for r in manifest['results'])
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print('MANIFEST',out/'manifest.json',flush=True)
    return 0 if manifest['all_passed'] else 1

if __name__=='__main__':sys.exit(main())
