#!/usr/bin/env python3
"""Run frozen RV32IMC instruction and ACT suites in scalar/dual and cached/direct modes."""
from __future__ import annotations
import argparse
import concurrent.futures
import datetime
import hashlib
import importlib.util
import json
import re
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path
from expand_filelist import expand
ROOT=Path(__file__).resolve().parents[2]
RISCV_SUITES=('rv32ui','rv32um','rv32uc','rv32mi')
ACT_SUITES=('I','M','Zca','Zicsr','Zicntr','Zifencei')
EXCLUSIONS={'rv32mi-p-breakpoint':'Debug trigger CSRs are outside the frozen profile',
            'rv32mi-p-pmpaddr':'PMP is outside the frozen M-mode-only profile'}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--mode',choices=('scalar','dual','wide','both','all'),default='both')
    p.add_argument('--memory',choices=('direct','cached','both'),default='both')
    p.add_argument('--family',choices=('riscv-tests','act','both'),default='both')
    p.add_argument('--jobs',type=int,default=2)
    p.add_argument('--timeout',type=int,default=180)
    p.add_argument('--max-cycles',type=int,default=2000000)
    p.add_argument('--output',type=Path)
    a=p.parse_args()
    compiler=shutil.which('iverilog');simulator=shutil.which('vvp')
    if not compiler or not simulator:raise RuntimeError('Icarus iverilog/vvp are required')
    stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    out=(a.output or ROOT/'sim/build/dual-isa'/stamp).resolve();out.mkdir(parents=True,exist_ok=True)
    manifest={'created_utc':stamp,'source_sha256':{},'elf_sha256':{},'archive_sha256':{},
              'builds':[],'results':[],'skipped':EXCLUSIONS,
              'profile':'RV32IMC + Zicsr + Zifencei + Zicntr, M-mode; F/D/debug-trigger/PMP excluded'}
    for name,tool in [('iverilog',compiler),('vvp',simulator)]:
        r=subprocess.run([tool,'-V'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
        manifest[name+'_version']=r.stdout.splitlines()[0]
    converter=ROOT/'sw/script/elf32_to_mem.py'
    spec=importlib.util.spec_from_file_location('elf32_to_mem',converter);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    manifest['source_sha256'][converter.relative_to(ROOT).as_posix()]=sha(converter)
    manifest['source_sha256']['sim/script/run_dual_isa.py']=sha(Path(__file__))
    manifest['source_sha256']['sim/script/expand_filelist.py']=sha(ROOT/'sim/script/expand_filelist.py')
    for path in (ROOT/'rtl/include').glob('*.vh'):manifest['source_sha256'][path.relative_to(ROOT).as_posix()]=sha(path)
    fixtures=[]
    if a.family!='act':
        for suite in RISCV_SUITES:
            files=sorted((ROOT/'sw/test/isa/riscv-tests/assets'/suite).glob('*.elf'))
            expected={'rv32ui':39,'rv32um':8,'rv32uc':1,'rv32mi':16}[suite]
            if len(files)!=expected:raise RuntimeError(f'{suite}: expected {expected} frozen ELF files, found {len(files)}')
            fixtures.extend(('riscv-tests',suite,path) for path in files if path.stem not in EXCLUSIONS)
    if a.family!='riscv-tests':
        assets=out/'assets';assets.mkdir(exist_ok=True)
        for suite in ACT_SUITES:
            if suite=='Zca':
                files=sorted((ROOT/'sw/test/isa/riscv-arch-test/assets/act4/rv32imc-zca-ilp32/xpack-gcc-15.2.0/elf').glob('*.elf'))
            else:
                archive=ROOT/'sw/test/isa/riscv-arch-test/assets/archives'/f'act4-{suite}.tar.xz'
                manifest['archive_sha256'][archive.relative_to(ROOT).as_posix()]=sha(archive)
                with tarfile.open(archive) as tar:
                    for member in tar.getmembers():
                        if not member.isfile() or not member.name.endswith('.elf'):continue
                        target=(assets/member.name).resolve()
                        if assets.resolve() not in target.parents:raise RuntimeError('invalid archive member path')
                        target.parent.mkdir(parents=True,exist_ok=True)
                        target.write_bytes(tar.extractfile(member).read())
                files=sorted((assets/'act4'/suite).glob('*.elf'))
            expected={'I':39,'M':8,'Zca':26,'Zicsr':6,'Zicntr':2,'Zifencei':1}[suite]
            if len(files)!=expected:raise RuntimeError(f'ACT {suite}: expected {expected} ELF files, found {len(files)}')
            fixtures.extend(('act',suite,path) for path in files)
    prepared=[]
    for family,suite,elf in fixtures:
        name=f'{family}/{suite}/{elf.stem}'
        entry,segments,symbols=module.parse_elf(elf)
        if 'tohost' not in symbols or entry!=0x80000000:raise RuntimeError(f'{name}: invalid entry/tohost')
        image,highest=module.build_image(segments,0x80000000)
        folder=out/'images'/family/suite;folder.mkdir(parents=True,exist_ok=True)
        hexfile=folder/(elf.stem+'.hex');module.write_hex(hexfile,image)
        metadata={'entry':entry,'symbols':{s:symbols[s] for s in ('tohost','begin_signature','end_signature') if s in symbols},'elf_sha256':sha(elf),'hex_sha256':sha(hexfile)}
        (folder/(elf.stem+'.json')).write_text(json.dumps(metadata,indent=2),encoding='utf-8')
        manifest['elf_sha256'][name]=sha(elf)
        prepared.append((family,suite,elf.stem,hexfile,symbols['tohost']))
    modes=('scalar','dual','wide') if a.mode=='all' else ('scalar','dual') if a.mode=='both' else (a.mode,)
    memories=('direct','cached') if a.memory=='both' else (a.memory,)
    work=[]
    for mode in modes:
        for memory in memories:
            for family in sorted(set(x[0] for x in prepared)):
                tb_family='riscv-arch-test' if family=='act' else family
                f=f'sim/{tb_family}/'+('files-cached.f' if memory=='cached' else 'files.f')
                options=expand(ROOT,f,set())
                for s in [f]+[s for s in options if s.endswith(('.v','.sv'))]:manifest['source_sha256'][s]=sha(ROOT/s)
                folder=out/mode/memory/family;folder.mkdir(parents=True,exist_ok=True);binary=folder/'sim.vvp'
                argv=[compiler,'-g2012','-DSIM_MODE',f'-Ptb_core_compliance.DUAL_ISSUE={int(mode in ("dual","wide"))}',
                      f'-Ptb_core_compliance.FETCH_WIDE={int(mode=="wide")}',
                      f'-Ptb_core_compliance.ACT_SELF_CHECK={int(family=="act")}','-o',str(binary),*options]
                with (folder/'compile.log').open('w',encoding='utf-8') as log:r=subprocess.run(argv,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
                manifest['builds'].append({'mode':mode,'memory':memory,'family':family,'command':argv,'returncode':r.returncode})
                if r.returncode:
                    manifest['all_passed']=False;(out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
                    print((folder/'compile.log').read_text(encoding='utf-8',errors='replace')[-6000:]);return 1
                work.extend((mode,memory,binary,folder,*fixture) for fixture in prepared if fixture[0]==family)
    def run(item):
        mode,memory,binary,folder,family,suite,name,hexfile,tohost=item
        logpath=folder/(suite+'-'+name+'.log')
        argv=[simulator,str(binary),f'+MEMFILE={hexfile}',f'+TOHOST={tohost:x}',f'+MAX_CYCLES={a.max_cycles}']
        timeout=False
        with logpath.open('w',encoding='utf-8') as log:
            try:code=subprocess.run(argv,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,timeout=a.timeout).returncode
            except subprocess.TimeoutExpired:code=-1;timeout=True
        text=logpath.read_text(encoding='utf-8',errors='replace')
        ok=code==0 and 'EDRV32_TEST_PASS' in text and not re.search(r'\b(?:FATAL|FAIL|EDRV32_TEST_FAIL)\b',text)
        counts=re.search(r'EDRV32_TEST_PASS cycles=(\d+) retires=(\d+) traps=(\d+) dual=(\d+) tohost=([0-9a-fA-F]+)',text)
        return {'mode':mode,'memory':memory,'family':family,'suite':suite,'case':name,'passed':ok,
                'returncode':code,'timed_out':timeout,'command':argv,'log':str(logpath),'log_sha256':sha(logpath),
                'counts':{k:int(v) for k,v in zip(('cycles','retires','traps','dual'),counts.groups()[:4])} if counts else None}
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as pool:
        for n,result in enumerate(pool.map(run,work),1):
            manifest['results'].append(result)
            if not result['passed']:print('FAIL',result['mode'],result['memory'],result['family'],result['case'],result['log'],flush=True)
            if n%24==0 or not result['passed']:
                (out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
                print(f'ISA progress {n}/{len(work)} passed={sum(r["passed"] for r in manifest["results"])}',flush=True)
    manifest['all_passed']=all(r['passed'] for r in manifest['results'])
    manifest['expected_run_count']=len(work)
    for mode in modes:
        for memory in memories:
            for family in sorted(set(x[0] for x in prepared)):
                results=[r for r in manifest['results'] if (r['mode'],r['memory'],r['family'])==(mode,memory,family)]
                print(mode,memory,family,sum(r['passed'] for r in results),'/',len(results),'secondary_retires',sum((r['counts'] or {}).get('dual',0) for r in results),flush=True)
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print('MANIFEST',out/'manifest.json',flush=True)
    return 0 if manifest['all_passed'] else 1
if __name__=='__main__':sys.exit(main())
