#!/usr/bin/env python3
"""compare.py — gpu-spec 8: bit-exact GT/selftest differential tests and C timings.
Host Python standard library; generated binaries and logs belong to build/gpu-emu.
"""
import argparse
import ctypes as C
import importlib.util
import json
from pathlib import Path
import random
import statistics
import struct
import subprocess
import sys
sys.dont_write_bytecode = True
import time
ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
BUILD = ROOT / 'build/gpu-emu'
sys.path[:0] = [str(ROOT), str(ROOT / 'verif/block/gpu')]
from tools.gpu.model import GPU
from tools.gpu.scene import Memory, Scene, SCHEMA, pack
from scene_support import Case
REGS = {}
for reg in SCHEMA['registers']:
    dims = reg['dimensions']
    for i in range(dims[0]['count'] if dims else 1):
        REGS[reg['name'] + (f'[{i}]' if dims else '')] = (int(reg['offset'], 0)
                                                       + (i*dims[0]['stride'] if dims else 0))


def build(threads=3):
    BUILD.mkdir(parents=True, exist_ok=True)
    flags = ['-std=c11', '-Wall', '-Wextra', '-Werror', '-O3',
             f'-DGPU_EMU_THREADS={threads}', '-pthread']
    subprocess.run(['gcc', *flags, '-shared', '-fPIC', str(HERE/'test_bridge.c'),
                    '-o', str(BUILD/'libtest.so')], check=True)
    subprocess.run(['gcc', *flags, str(HERE/'gpu_emu.c'), str(HERE/'cli.c'),
                    '-o', str(BUILD/'gpu-emu')], check=True)


def library():
    lib = C.CDLL(str(BUILD/'libtest.so'))
    ptr = C.c_void_p
    declarations = {
        'gpu_emu_create': ([ptr, C.c_uint32], ptr),
        'gpu_emu_destroy': ([ptr], None),
        'gpu_emu_write': ([ptr, C.c_uint32, C.c_uint32], None),
        'gpu_emu_read': ([ptr, C.c_uint32], C.c_uint32),
        'gpu_emu_irq': ([ptr], C.c_int),
        'test_buffer': ([ptr, C.c_int], ptr),
        'test_size': ([ptr, C.c_int, C.c_int], None),
                'test_matrix': ([ptr, ptr], None),
        'test_op': ([ptr, C.c_int, ptr, ptr], C.c_int),
        'test_sample': ([ptr,C.c_int64,C.c_int64,C.c_int,C.c_int,C.c_int,ptr],None),
        'test_planes': ([ptr,C.c_int64],ptr),
        'test_at': ([ptr,C.c_int,C.c_int,ptr],None),
        'test_free': ([ptr],None),
        'test_clip': ([ptr,C.c_int],C.c_int),
        'test_number': ([C.c_int,C.c_int64,C.c_int,C.c_int64,C.c_int,ptr],None),
    }
    for name, (args, result) in declarations.items():
        fn = getattr(lib, name)
        fn.argtypes, fn.restype = args, result
    return lib


def buffer(data):
    return C.create_string_buffer(bytes(data), max(1, len(data)))


def compare_bytes(name, actual, expected):
    if actual != expected:
        i = next((i for i, (a, b) in enumerate(zip(actual, expected)) if a != b),
                 min(len(actual), len(expected)))
        raise AssertionError(f'{name}: byte {i:#x}, C={actual[i:i+16].hex()}, '
                             f'Python={expected[i:i+16].hex()} '
                             f'(sizes {len(actual)}/{len(expected)})')


def check_regs(lib, e, gpu, name):
    for reg, offset in REGS.items():
        got = lib.gpu_emu_read(e, offset)
        assert got == gpu.regs[reg], (name, reg, got, gpu.regs[reg])
    assert lib.gpu_emu_irq(e) == bool(gpu.regs['IRQ_STAT'] & gpu.regs['IRQ_EN'])


def run_case(lib, name, scene, repeats=5, command_timing=False):
    writes = scene.finish()
    if command_timing:
        base, count = writes[-3][1], writes[-2][1]
        writes = writes[:-3]
        for i in range(count):
            writes.extend([['IRQ_STAT',3],['DESC_BASE',base+32*i],
                           ['DESC_COUNT',1],['DOORBELL',1]])
    # The core takes DDR physical addresses from zero; preserve all encoded addresses.
    raw = bytes(scene.memory.data)
    data = (C.c_ubyte * (scene.memory.base + len(raw)))()
    C.memmove(C.addressof(data)+scene.memory.base, raw, len(raw))
    e = lib.gpu_emu_create(data, len(data))
    assert e
    gpu = GPU(Memory(scene.memory.base, raw)).execute(writes)
    durations = []
    for _ in range(repeats):
        C.memmove(C.addressof(data)+scene.memory.base, raw, len(raw))
        lib.gpu_emu_write(e, REGS['CTRL'], 8)
        start = time.perf_counter_ns()
        for reg, value in writes:
            lib.gpu_emu_write(e, REGS[reg] if isinstance(reg, str) else reg, value)
        durations.append((time.perf_counter_ns()-start)/1e6)
    compare_bytes(name+' DDR', C.string_at(C.addressof(data)+scene.memory.base, len(raw)),
                  bytes(gpu.memory.data))
    check_regs(lib, e, gpu, name)
    for kind, values, fmt in [(0,gpu.color,'H'), (1,gpu.depth,'H'), (2,gpu.stencil,'B')]:
        expected = struct.pack('<'+str(len(values))+fmt,*values)
        compare_bytes(name+f' target{kind}',
                      C.string_at(lib.test_buffer(e,kind),len(expected)),expected)
    lib.gpu_emu_destroy(e)
    return statistics.median(durations)


def gt_cases(lib):
    results, skipped = [], []
    for number in range(1, 26):
        name = f'gt{number:02}'
        path = ROOT/'verif/block/gpu'/name
        seed = int(next(line.split(':')[1] for line in (path/'test.yaml').read_text().splitlines()
                        if line.startswith('seed:')))
        spec = importlib.util.spec_from_file_location(name,path/'scene.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        case = Case()
        module.build(case,random.Random(seed))
        for i, c in enumerate([case]+case.runs):
            label = name + (f'/run{i:02}' if i else '')
            if c.axi_errors:
                reason = 'injected read_errors/write_errors AXI responses are outside C API'
                skipped.append((label,reason))
                print(f'{label}: SKIP {reason}',flush=True)
                continue
            # ABORT cases run the complete list: neither synchronous functional model can
            # receive the RTL bench's mid-command ABORT. Keep these as functional cases.
            elapsed = run_case(lib,label,c.scene,command_timing=c.command_timing)
            results.append((label,elapsed))
            print(f'{label}: PASS {elapsed:.3f} ms'+(' (full list; mid-command ABORT not modeled)'
                                                    if c.abort else ''),flush=True)
    return results, skipped


def selftests(lib):
    from tools.gpu.model import selftest as st
    class DifferentialGPU(GPU):
        nesting = 0
        def replay(self, method, args, kwargs):
            if self.nesting:
                return getattr(super(),method)(*args,**kwargs)
            if self.memory.read_errors or self.memory.write_errors:
                skipped.append((test_name, 'injected read_errors/write_errors AXI responses'))
                self.nesting += 1
                try:
                    return getattr(super(),method)(*args,**kwargs)
                finally:
                    self.nesting -= 1
            # Populate a private native instance from the unit scenario's explicit
            # internal setup, then compare the public model operation's effects.
            raw = bytes(self.memory.data)
            data = (C.c_ubyte*(self.memory.base+len(raw)))()
            C.memmove(C.addressof(data)+self.memory.base,raw,len(raw))
            e = lib.gpu_emu_create(data,len(data))
            lib.test_size(e,self.width,self.height)
            for name, layout in [('light','CMD_SET_LIGHT'), ('target','CMD_SET_TARGET'),
                                 ('pixel_state','CMD_SET_PIXEL')]:
                if hasattr(self,name):
                    assert not lib.test_op(e,0,buffer(pack(layout,**getattr(self,name))),None)
            if hasattr(self,'texture'):
                assert not lib.test_op(e,0,buffer(pack('CMD_SET_TEX',**self.texture.desc)),None)
            if hasattr(self,'matrix'):
                lib.test_matrix(e,buffer(struct.pack('<16i',*self.matrix)))
            for kind, values, fmt in [(0,self.color,'H'),(1,self.depth,'H'),(2,self.stencil,'B'),
                                      (3,self.ram,'B'),
                                      (4,[v for p in self.palettes for v in p],'I')]:
                encoded = struct.pack('<'+str(len(values))+fmt,*values)
                C.memmove(lib.test_buffer(e,kind),encoded,len(encoded))
            regs = (C.c_uint32*128).from_address(lib.test_buffer(e,5))
            for reg, offset in REGS.items(): regs[offset//4] = self.regs[reg]
            native_result = None
            def op(number, encoded=b'', values=()):
                v = (C.c_int64*max(27,len(values)))(*values)
                code = lib.test_op(e,number,buffer(encoded),v)
                return code, list(v)
            if method in ('run','execute','write_register'):
                if method == 'run':
                    commands = args[0] if args else kwargs.get('commands')
                    if commands is None:
                        lib.gpu_emu_write(e,REGS['DOORBELL'],1)
                    else:
                        regs[REGS['STATUS']//4] = 1
                        code = 0
                        for command in commands:
                            code, _ = op(0,command)
                            if code: break
                        if code:
                            regs[REGS['STATUS']//4] = 6
                            regs[REGS['ERR_CODE']//4] = code
                            regs[REGS['IRQ_STAT']//4] |= 2
                        else:
                            regs[REGS['STATUS']//4] = 2
                            regs[REGS['DONE_COUNT']//4] += 1
                            regs[REGS['IRQ_STAT']//4] |= 1
                else:
                    writes = args[0] if method == 'execute' else [args]
                    for reg, value in writes:
                        lib.gpu_emu_write(e,REGS[reg] if isinstance(reg,str) else reg,value)
            elif method == 'command':
                code, _ = op(0,args[0]); assert not code
            elif method == 'quad': op(1,pack('QUAD',**args[0]))
            elif method == 'triangle': op(2,values=[v for vertex in args[0] for v in vertex])
            elif method == 'draw_triangle': op(3,b''.join(pack('VERTEX',**v) for v in args[0]))
            elif method == 'objects': op(4,pack('CMD_OBJ_STEP',**args[0]))
            elif method == 'resolve': op(5,pack('CMD_RESOLVE',**args[0]))
            elif method == 'pixel':
                x,y,depth,rgba = args[:4]
                transparent = args[4] if len(args)>4 else kwargs.get('transparent',False)
                op(6,values=[x,y,depth,*rgba,int(transparent)])
            elif method == 'stencil_op': op(7,values=args)
            elif method == 'transform': _, native_result = op(8,pack('VERTEX',**args[0]))
            elif method == 'project': _, native_result = op(9,values=args[0])
            elif method == 'clip':
                values = [x for vertex in args[0] for x in vertex]
                v = (C.c_int64*144)(*values)
                n = lib.test_clip(v,len(args[0]))
                native_result = [list(v[i*9:(i+1)*9]) for i in range(n)]
            elif method == 'sample':
                u,v,lod = args[:3]
                group = args[3] if len(args)>3 else kwargs.get('group')
                if group is None: group = self.texture.desc['PAL_GROUP']
                nearest = args[4] if len(args)>4 else kwargs.get('nearest',False)
                out = (C.c_int64*4)()
                lib.test_sample(e,u,v,lod,group,nearest,out)
                native_result = list(out)
            self.nesting += 1
            try:
                result = (self.texture.sample(*args,**kwargs) if method == 'sample'
                          else getattr(super(),method)(*args,**kwargs))
            finally:
                self.nesting -= 1
            if hasattr(self,'texture'): self.texture.owner = self
            if native_result is not None:
                assert native_result[:len(result)] == list(result), (method,native_result,result)
            compare_bytes(test_name+' '+method+' DDR',
                          C.string_at(C.addressof(data)+self.memory.base,len(raw)),
                          bytes(self.memory.data))
            check_regs(lib,e,self,test_name+' '+method)
            for kind, values, fmt in [(0,self.color,'H'),(1,self.depth,'H'),
                                      (2,self.stencil,'B'),(3,self.ram,'B'),
                                      (4,[v for p in self.palettes for v in p],'I')]:
                encoded = struct.pack('<'+str(len(values))+fmt,*values)
                compare_bytes(test_name+' '+method+f' target{kind}',
                              C.string_at(lib.test_buffer(e,kind),len(encoded)),encoded)
            lib.gpu_emu_destroy(e)
            counts[test_name] = counts.get(test_name,0)+1
            return result
    methods = ['command','write_register','run','execute','quad','triangle','draw_triangle',
               'objects','resolve','pixel','stencil_op','transform','project','clip']
    for method in methods:
        def wrapper(self,*args,_method=method,**kwargs): return self.replay(_method,args,kwargs)
        setattr(DifferentialGPU,method,wrapper)
    counts, skipped = {}, []
    st.GPU = DifferentialGPU
    from tools.gpu.model import renderer
    from tools.gpu.model.texture import Texture
    class DifferentialTexture(Texture):
        def sample(self,*args,**kwargs):
            if hasattr(self,'owner') and not self.owner.nesting:
                return self.owner.replay('sample',args,kwargs)
            return super().sample(*args,**kwargs)
    renderer.Texture = DifferentialTexture
    class DifferentialPlanes(st.PixelArithmetic):
        def __init__(self,vertices,area):
            super().__init__(vertices,area)
            self.native = lib.test_planes((C.c_int64*27)(*(x for v in vertices for x in v)),area)
        def __del__(self): lib.test_free(self.native)
        def at(self,x,y):
            result = super().at(x,y)
            data = C.create_string_buffer(112)
            lib.test_at(self.native,x,y,data)
            actual = [int.from_bytes(data.raw[i:i+16],'little',signed=True)
                      for i in range(0,112,16)]
            assert result == actual, (x,y,result,actual)
            counts[test_name] = counts.get(test_name,0)+1
            return result
        def normal(self,value,exponent=0):
            result = super().normal(value,exponent)
            # Plane accumulators may exceed int64; their normalization is covered
            # by full triangle comparisons. Direct numeric selftests fit int64.
            if -(1<<63) <= value < (1<<63):
                out = (C.c_int64*2)()
                lib.test_number(0,value,exponent,0,0,out)
                assert tuple(out) == result
            return result
        def multiply(self,a,b):
            result = super().multiply(a,b)
            out = (C.c_int64*2)()
            lib.test_number(1,*a,*b,out)
            assert tuple(out) == result
            return result
        def inverse(self,a):
            result = super().inverse(a)
            out = (C.c_int64*2)()
            lib.test_number(3,*a,0,0,out)
            assert tuple(out) == result
            return result
    st.PixelArithmetic = DifferentialPlanes
    # Unit scenes default to a high RTL BFM origin. Zero is the core's DDR origin;
    # change scene construction only, retaining every relative address and byte.
    for test_name in [n for n in vars(st) if n.startswith('test_')]:
        getattr(st,test_name)()
        print(f'{test_name}: PASS ({counts.get(test_name,0)} native operations)',flush=True)
    return counts, skipped


def object_writeback_case(lib):
    # Spec 2.9.5 preserves the record read before list writes, even when a list
    # shares DDR storage with that record.
    c = Case()
    c.ready()
    s = c.scene
    table = s.records('OBJ',[dict(ALIVE=1,PX=10*256,PY=10*256,VX=1,
                                  TGT_MASK=1,COL_HW=2,COL_HH=2,W=4,H=4,ALPHA=255)])
    s.memory.data[table-s.memory.base] |= 0x80
    for reg,value in [('OBJ_LIVE_RECT1',64 | (64<<16)),('OBJ_TGT0[0]',0),
                      ('OBJ_TGT1[0]',64 | (64<<16)),('OBJ_HIT_BASE',table),
                      ('OBJ_HIT_MAX',1)]: s.reg(reg,value)
    s.command('OBJ_STEP',ADDR=table,COUNT=1,STEP=1,DRAW=1)
    c.resolve()
    run_case(lib,'object writeback preserves read record',s)
    print('Object writeback preserves read record across list writes: PASS',flush=True)


def cli_case():
    c = Case()
    c.scene = Scene(base=0x1000)
    c.ready()
    c.quad(X=-3,Y=7,W=12,H=9)
    c.resolve()
    output = BUILD/'cli'
    output.mkdir(exist_ok=True)
    writes = c.scene.export(output/'input.hex',output/'writes.json')
    # Check both accepted JSON register forms against the model CLI contract.
    for numeric in (False,True):
        encoded = [[REGS[n],v] for n,v in writes] if numeric else writes
        (output/'writes.json').write_text(json.dumps(encoded))
        subprocess.run([str(BUILD/'gpu-emu'),str(output/'input.hex'),
                        str(output/'writes.json'),str(output),'--base','0x1000'],check=True)
        gpu = GPU(Memory(c.scene.memory.base,c.scene.memory.data)).execute(encoded)
        actual = Memory.read_hex(output/'ddr.hex',c.scene.memory.base)
        compare_bytes('CLI DDR',bytes(actual.data),bytes(gpu.memory.data))
        assert json.loads((output/'registers.json').read_text()) == gpu.regs
    print('CLI named/numeric writes and nonzero image base: PASS',flush=True)


def profile(lib, scene):
    data = buffer(scene.memory.data)
    e = lib.gpu_emu_create(data,len(scene.memory.data))
    for reg, value in scene.registers: lib.gpu_emu_write(e,REGS[reg],value)
    phases = {}
    names = {16:'clear',32:'triangles',33:'quads',34:'objects',64:'resolve'}
    for command in scene.commands:
        start = time.perf_counter_ns()
        assert not lib.test_op(e,0,buffer(command),None)
        elapsed = (time.perf_counter_ns()-start)/1e6
        key = names.get(command[0],'setup/load')
        phases[key] = phases.get(key,0)+elapsed
    lib.gpu_emu_destroy(e)
    return phases


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--gt-only',action='store_true')
    parser.add_argument('--selftest-only',action='store_true')
    parser.add_argument('--threads',type=int,default=3)
    args = parser.parse_args()
    build(args.threads)
    # Set the test allocator origin before importing scene builders or selftests.
    original_init = Scene.__init__
    def physical_init(self,base=0): original_init(self,base)
    Scene.__init__ = physical_init
    lib = library()
    cli_case()
    object_writeback_case(lib)
    results, skipped = ([], []) if args.selftest_only else gt_cases(lib)
    counts, unit_skips = ({},[]) if args.gt_only else selftests(lib)
    from stress import scene as stress_scene
    stress = stress_scene()
    elapsed = run_case(lib,'stress',stress,11)
    phases = profile(lib,stress)
    print(f'stress: PASS {elapsed:.3f} ms; phases {phases}',flush=True)
    results = dict(stress_ms=elapsed,phases=phases,gt=results,skipped=skipped,
                   selftest_operations=counts,selftest_skips=unit_skips)
    print(json.dumps(results,indent=2))
    (BUILD/'results.json').write_text(json.dumps(results,indent=2)+'\n')

if __name__ == '__main__': main()
