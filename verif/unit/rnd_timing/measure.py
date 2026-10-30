#!/usr/bin/env python3
# File: measure.py
# Spec: T-RND1/T-RND2; rnd-spec 5/7.
# Description: Preserve variable multipliers as hard boundaries before LUT6 mapping;
#              inspect their immediate register connections in the pre-techmap netlist.
# Clock domain: host tool; all RTL data paths measured belong to clk_mem.
import collections
import json
from pathlib import Path
import subprocess,sys
from tools.synth.yosys_synth import read_filelist

def retain_multipliers(out):
    p=out;d=json.loads((p/'coarse.json').read_text());top=d['modules']['edrv32_rnd'];rows=[]
    for n,c in top['cells'].items():
     if c['type']!='$mul' or any(all(isinstance(b,str) for b in c['connections'][port]) for port in ['A','B']):continue
     typ='ip_hard_mul_'+str(len(rows));ports={};nets={};idx=2
     for port in ['A','B','Y']:
      bits=list(range(idx,idx+len(c['connections'][port])));idx+=len(bits)
      ports[port]={'direction':'output' if port=='Y' else 'input','bits':bits}
      nets[port]={'hide_name':0,'bits':bits,'attributes':{}}
     d['modules'][typ]={'attributes':{'blackbox':'1'},'parameter_default_values':{},'ports':ports,'cells':{},'netnames':nets}
     rows.append({'cell':n,'type':typ,'parameters':c['parameters'],'widths':{k:len(v) for k,v in c['connections'].items()},'src':c.get('attributes',{}).get('src','')});c['type']=typ;c['parameters']={}
    (p/'hardmul.json').write_text(json.dumps(d));(p/'multipliers.json').write_text(json.dumps(rows,indent=2))
    (p/'hardmul.ys').write_text(f'read_json {p}/hardmul.json\nsynth -top edrv32_rnd -flatten -noabc\nabc -lut 6 -dress\nopt_clean\nwrite_json {p}/hardnet.json\nstat\n')
    print('hard multipliers:',len(rows))

def check_registers(out):
    p=out;d=json.loads((p/'coarse.json').read_text());m=d['modules']['edrv32_rnd']
    regs={b for c in m['cells'].values() if 'dff' in c['type'].lower() for b in c['connections']['Q']}
    loads=collections.defaultdict(list)
    for n,c in m['cells'].items():
     for port,bs in c['connections'].items():
      if c['port_directions'][port]=='input':
       for b in bs:
        if isinstance(b,int):loads[b].append((n,c['type'],port))
    rows=[];constants=[]
    for n,c in m['cells'].items():
     if c['type']!='$mul':continue
     consts={port:bits for port,bits in c['connections'].items() if port in ['A','B'] and all(b in ('0','1') for b in bits)}
     if consts:
      constants.append({'cell':n,'constants':{port:int(''.join(bits[::-1]),2) for port,bits in consts.items()},'widths':{k:len(v) for k,v in c['connections'].items()},'src':c['attributes'].get('src')});continue
     pre={port:sum(isinstance(b,int) and b not in regs for b in c['connections'][port]) for port in ['A','B']}
     post=sorted({typ for b in c['connections']['Y'] for _,typ,_ in loads[b] if 'dff' not in typ.lower()})
     rows.append({'cell':n,'input_non_ff_bits':pre,'output_non_ff_load_types':post,'src':c['attributes'].get('src'),'widths':{k:len(v) for k,v in c['connections'].items()}})
    result={'variable_multipliers':rows,'constant_multipliers':constants,'violations':[r for r in rows if any(r['input_non_ff_bits'].values()) or r['output_non_ff_load_types']]}
    (p/'structure.json').write_text(json.dumps(result,indent=2));print(p,'variable',len(rows),'constant',len(constants),'violations',len(result['violations']))

root=Path.cwd();out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
files=[];includes=set();read_filelist(root/'rtl/filelists/rnd.f',files,includes)
(out/'stubs.v').write_text('''(* blackbox *) module ip_ram_rnd_line (
input wr_clk,wr_en,input [8:0] wr_addr,input [255:0] wr_data,
input [31:0] wr_byte_en,input wr_rst,rd_clk,rd_clk_en,rd_rst,
input [8:0] rd_addr,output [255:0] rd_data); endmodule
(* blackbox *) module ip_ram_rnd_palette (
input wr_clk,wr_en,input [8:0] wr_addr,input [31:0] wr_data,
input wr_rst,rd_clk,rd_clk_en,rd_rst,input [8:0] rd_addr,
output [31:0] rd_data); endmodule
''')
read='read_verilog -D FPGA_MODE '+' '.join('-I'+v for v in sorted(includes))+' '+' '.join(files)+f' {out}/stubs.v'
(out/'coarse.ys').write_text(read+'\nhierarchy -top edrv32_rnd\nproc\nflatten\nopt\nwreduce\nopt_clean\n'+f'write_json {out}/coarse.json\n')
subprocess.run(['flock','/tmp/edrv32-sim.lock','yosys','-Q','-T','-l',str(out/'coarse.log'),'-s',str(out/'coarse.ys')],stdout=(out/'coarse.stdout').open('w'),check=True)
retain_multipliers(out)
check_registers(out)
subprocess.run(['flock','/tmp/edrv32-sim.lock','yosys','-Q','-T','-l',str(out/'hardnet.log'),'-s',str(out/'hardmul.ys')],stdout=(out/'hardnet.stdout').open('w'),check=True)
subprocess.run([sys.executable,'tools/synth/netlist_paths.py',str(out/'hardnet.json')],check=True)
