"""Extract preserved PIX FFs and routed primitive-pin fanout from PDS netlists."""
from collections import Counter,defaultdict
from pathlib import Path
import re

REPO=Path(__file__).resolve().parents[4]
TASK=REPO/"tasks/win/20261029-01-media-r4"
BUILD=REPO/"build/win/20261029-01-media-r4"
ROOT=REPO.parent/"EdRV32-FPGA/EdRV32-MEDIA"
LIB=Path("G:/Program/pango/PDS_2022.2-SP6.1/arch/vendor/pango/verilog/bsim")
CELL=re.compile(r'(V_\w+)\s*/\*\s*(.*?)\s*\*/\s*(?:#\((.*?)\)\s*)?(\\\S+|\w+)\s*\((.*?)\);',re.S)
PIN=re.compile(r'\.(\w+)\s*\(([^()]*)\)')


def main():
    flat=(BUILD/"flat_netlist/generate_netlist/edrv32_fpga_media_top_sim.v").read_text()
    widths={}
    for hi,lo,name in re.findall(r'\bwire\s+(?:\[(\d+):(\d+)\]\s+)?(\\\S+|\w+)\s*;',flat):
        if hi:
            widths[name.lstrip('\\')]=(int(hi),int(lo))
    def nets(expr):
        expr=re.sub(r"\b\d+'[sS]?[bBdDhHoO][0-9a-fA-F_xXzZ?]+","",expr)
        result=[]
        for name,sel in re.findall(r'(\\[^\s]+|[A-Za-z_]\w*)(?:\s*(\[[0-9:]+\]))?',expr):
            name=name.lstrip('\\')
            if sel:
                span=sel[1:-1].split(':')
                if len(span)==1:
                    result.append(name+sel)
                    continue
                hi,lo=map(int,span)
            elif name in widths:
                hi,lo=widths[name]
            else:
                result.append(name)
                continue
            result.extend(name+f'[{i}]' for i in range(min(hi,lo),max(hi,lo)+1))
        return result
    cells=list(CELL.finditer(flat))
    directions={}
    for kind in {m[1] for m in cells}:
        text=(LIB/(kind+'.v')).read_text(errors='replace')
        text=re.sub(r'//[^\n]*|/\*.*?\*/','',text,flags=re.S)
        header=text[text.index('module '):text.index(');',text.index('module '))+2]
        pins={}
        for direction,decl in re.findall(r'\b(input|output|inout)\s+(.*?)(?=\b(?:input|output|inout)\b|\)\s*;)',header,re.S):
            decl=re.sub(r'\[[^]]+\]|\b(?:wire|reg|signed)\b','',decl)
            for pin in re.findall(r'\b[A-Za-z_]\w*\b',decl):
                pins[pin]=direction
        directions[kind]=pins
    loads=Counter();drivers={};ff=[]
    for m in cells:
        kind,logical,_,physical,pins=m.groups()
        ports=dict(PIN.findall(pins))
        for pin,expr in ports.items():
            direction=directions[kind][pin]
            for net in nets(expr):
                if direction=='input':
                    loads[net]+=1
                elif direction=='output':
                    drivers[net]=(kind,logical,physical.lstrip('\\'),pin)
        if kind in ('V_FFSYN','V_FFASYN') and logical.startswith('u_pix/'):
            ff.append((logical,kind,nets(ports['Q'])[0],physical.lstrip('\\')))
    expected={'advance_input_r':1,'advance_point1_r':7,'advance_point2_r':3,
              'advance_filter1_r':4,'advance_filter2_r':4,'advance_kernel10_r':21,
              'advance_kernel11_r':21,'advance_kernel20_r':21,'advance_kernel21_r':21}
    syn=(ROOT/'synthesize/edrv32_fpga_media_top_syn.vm').read_text()
    modules={name:body for name,body in re.findall(r'^module (\w+)\b(.*?)^endmodule',syn,re.M|re.S)}
    module_paths={'edrv32_pix':'u_pix','edrv32_pix_kernel':'u_pix/u_stage1/u_kernel0',
                  'edrv32_pix_kernel_unq8':'u_pix/u_stage1/u_kernel1',
                  'edrv32_pix_kernel_unq10':'u_pix/u_stage2/u_kernel0',
                  'edrv32_pix_kernel_unq12':'u_pix/u_stage2/u_kernel1'}
    syn_bits=defaultdict(list);preserved=Counter()
    for module,prefix in module_paths.items():
        for attrs,kind,orig in re.findall(r'(\(\*[^\n]*\*\)\s*)?(GTP_DFF\w*)\s*/\*\s*(.*?)\s*\*/',modules[module]):
            orig=orig.strip().lstrip('\\')
            if module=='edrv32_pix' and not orig.startswith('advance_'):
                continue
            if module!='edrv32_pix' and not re.search(r'op_(?:spatial|result|color)_r',orig):
                continue
            path=prefix+'/'+orig
            base=re.sub(r'\[\d+\]$','',path)
            syn_bits[base].append(path)
            preserved[base]+=int('PAP_PRESERVE="TRUE"' in attrs)
    rows=['register\trtl_bits\tsynthesis_bits\tPAP_PRESERVE_bits\trouted_logical_bits\trouted_physical_FFs']
    detail=['register_bit\tphysical_FF\tdriver_type\tQ_net\tQ_fanout_input_pins']
    groups={('u_pix/'+name):bits for name,bits in expected.items()}
    for prefix in list(module_paths.values())[1:]:
        groups.update({prefix+'/op_spatial_r':3,prefix+'/op_result_r':3})
        groups.update({prefix+f'/g_color[{i}].op_color_r':3 for i in range(3)})
    for base,bits in groups.items():
        found=[r for r in ff if r[0].split('/opit_',1)[0] in syn_bits[base]]
        logicals={r[0].split('/opit_',1)[0] for r in found}
        rows.append(f'{base}\t{bits}\t{len(syn_bits[base])}\t{preserved[base]}\t{len(logicals)}\t{len(found)}')
        for logical,kind,net,physical in found:
            detail.append(f'{logical.split("/opit_",1)[0]}\t{physical}\t{kind}\t{net}\t{loads[net]}')
    top=sorted([(net,loads[net],*driver) for net,driver in drivers.items()
                if net.startswith('u_pix/') or driver[1].startswith('u_pix/')],key=lambda r:r[1],reverse=True)[:10]
    messages=[]
    for stage in ('compile','synthesize'):
        log=(ROOT/stage/'run.log').read_text(errors='replace')
        messages += [f'SOURCE {stage}/run.log']+[l for l in log.splitlines() if
                    'syn_preserve' in l or 'PAP_PRESERVE' in l or
                    ('Removed inst' in l and ('advance_' in l or 'op_color_r' in l or 'op_spatial_r' in l or 'op_result_r' in l))]
    out=TASK/'artifacts';out.mkdir(parents=True,exist_ok=True)
    (out/'replication_registers.tsv').write_text('\n'.join(rows)+'\n',encoding='utf-8')
    (out/'replication_fanout.tsv').write_text('\n'.join(detail)+'\n',encoding='utf-8')
    lines=['PIX replication: synthesis VM plus flattened post-PnR functional netlist.',
           'Fanout = number of primitive input pins on each physical FF Q net; counted from vendor VOP pin directions.',
           'This is post-route physical fanout, not DMR pre-route logical fanout. Packing/replication may produce more physical FFs per RTL bit.',
           'Advance expected bits=103; opcode expected bits=60 (4 kernels * (3+3+3*3)).',
           'Synthesis PAP_PRESERVE retained advance bits='+str(sum(preserved['u_pix/'+name] for name in expected)),
           '',*rows,'','Per-bit Q fanout: replication_fanout.tsv (all physical FFs).','',
           'u_pix top10 driven networks (post-PnR; net name may be renamed by packing):',
           'net\tfanout_input_pins\tdriver_type\tlogical_driver\tphysical_driver\toutput_pin']
    lines += ['\t'.join(map(str,r)) for r in top]+['','Original attribute messages:',*messages]
    (out/'replication_check.txt').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print('\n'.join(rows),flush=True)
    print('Top10',top,flush=True)


if __name__=='__main__':
    main()
