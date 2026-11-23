#!/usr/bin/env python3
# File: run.py
# Spec: gpu-spec 2.4, 2.12 and section 7; R-2 unit verification.
# Description: Reference transform/clip/project vectors with ordered output and throughput checks.
# Clock domain: host tool.
from pathlib import Path
import random
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from tools.gpu.model import GPU
from tools.gpu.model.arithmetic import edge, reciprocal_seed
from tools.gpu.scene import pack


def bits(values, width):
    return sum((v & ((1 << width)-1)) << (i*width) for i,v in enumerate(values))


def vectors():
    rng = random.Random(0x523247)
    identity = [65536 if i//4 == i%4 else 0 for i in range(16)]
    light = dict(LX=0, LY=0, LZ=16384, DIR_RGB=0xffffff, AMB_RGB=0x404040)
    target = dict(VP_X0=-10, VP_Y0=3, VP_W=640, VP_H=180)

    def vertex(x,y,z):
        return dict(X=x,Y=y,Z=z,NX=rng.randrange(-128,128),NY=rng.randrange(-128,128),
                    NZ=rng.randrange(-128,128), U=rng.randrange(65536),V=rng.randrange(65536),
                    COLOR=rng.randrange(65536))

    triangle = [vertex(-1,-1,1),vertex(1,-1,1),vertex(0,1,1)]
    cases = [(identity, light, target, 0, triangle*64, 1)]
    for cull in (0,1,2):
        cases += [(identity,light,target,cull,triangle,0),
                  (identity,light,target,cull,[triangle[0],triangle[2],triangle[1]],0)]
    near = identity.copy()
    near[0] = near[5] = 1024
    near[10], near[11], near[14], near[15] = 0,2048,65536,0
    cases += [(near,light,target,0,[vertex(-1,-1,z0),vertex(1,-1,z1),vertex(0,1,1)],0)
              for z0,z1 in ((0,1),(0,0),(-1,1),(-1,-1))]
    for coords in (((-6,-1,1),(1,-1,1),(0,1,1)),
                   ((-6,-6,1),(6,-6,1),(0,6,1)),
                   ((5,-1,1),(6,0,1),(5,1,1)),
                   ((0,0,1),(0,0,1),(0,0,1))):
        cases.append((identity,light,target,0,[vertex(*v) for v in coords],0))
    outside = identity.copy()
    outside[15] = 0
    cases.append((outside,light,target,0,triangle,0))
    # Negative and overbright dot products, saturated input coordinates, and extreme viewport.
    for direction in (-32768,32767):
        strong = dict(LX=direction,LY=direction,LZ=direction,
                      DIR_RGB=0xffffff,AMB_RGB=0xffffff)
        verts = [dict(v,NX=127,NY=127,NZ=127,COLOR=0xffff) for v in triangle]
        cases.append((identity,strong,target,0,verts,0))
    large = [0x7fffffff]*16
    cases.append((large,light,target,0,[vertex(32767,32767,32767),
                  vertex(-32768,32767,32767),vertex(32767,-32768,32767)],0))
    saturated = [1<<27,0,0,0, 0,1<<27,0,0, 0,0,0,32768,
                 0,0,0x7fffffff,65536]
    cases.append((saturated,light,target,0,[vertex(-10000,-10000,32767),
                  vertex(10000,-10000,32767),vertex(0,10000,32767)],0))
    huge_side = identity.copy()
    huge_side[0] = 0x7fffffff
    cases.append((huge_side,light,target,0,[vertex(-32768,-1,1),
                  vertex(0,-1,1),vertex(32767,1,1)],0))
    extreme = dict(VP_X0=-32768,VP_Y0=32767,VP_W=65535,VP_H=65535)
    cases.append((identity,light,extreme,0,triangle,0))
    for _ in range(40):
        matrix = [rng.randrange(-65536,65537) for _ in range(12)]
        matrix += [rng.randrange(-4096,4097) for _ in range(3)] + [rng.randrange(32768,131073)]
        illumination = dict(LX=rng.randrange(-32768,32768),LY=rng.randrange(-32768,32768),
                            LZ=rng.randrange(-32768,32768),DIR_RGB=rng.randrange(1<<24),
                            AMB_RGB=rng.randrange(1<<24))
        vertices = [vertex(*(rng.randrange(-3,4) for _ in range(3))) for _ in range(9)]
        cases.append((matrix,illumination,target,rng.randrange(3),vertices,0))
    cases.append((identity,light,target,0,[],0))
    lines = [f'{len(cases)}\n']
    triangle_count = 0
    for matrix, illumination, viewport, cull, vertices, throughput in cases:
        gpu = GPU(None, (1,1))
        gpu.matrix, gpu.light, gpu.target = matrix,illumination,viewport
        output = []
        for start in range(0,len(vertices),3):
            polygon = gpu.clip([gpu.transform(v) for v in vertices[start:start+3]])
            screen = [gpu.project(v) for v in polygon]
            for i in range(1,len(screen)-1):
                tri = [screen[0],screen[i],screen[i+1]]
                area = edge(tri[0],tri[1],*tri[2][:2])
                if area == 0 or (cull==1 and area>0) or (cull==2 and area<0):
                    continue
                if area < 0:
                    tri[1],tri[2] = tri[2],tri[1]
                value,offset = 0,0
                for channel,width in enumerate((17,17,16,35,51,51)):
                    value |= bits([v[channel] for v in tri],width) << offset
                    offset += 3*width
                value |= bits([v[c] for v in tri for c in (6,7,8)],24) << offset
                output.append(value)
        triangle_count += len(output)
        matrix_raw = bits(matrix,32)
        light_raw = bits([illumination[n] for n in ('LX','LY','LZ')],16)
        light_raw |= illumination['DIR_RGB'] << 48 | illumination['AMB_RGB'] << 72
        target_raw = int.from_bytes(pack('CMD_SET_TARGET',**viewport),'little')
        pixel_raw = int.from_bytes(pack('CMD_SET_PIXEL',CULL=cull),'little')
        lines.append(f'{len(vertices)} {len(output)} {throughput}\n')
        lines.append(f'{matrix_raw:x} {light_raw:x} {target_raw:x} {pixel_raw:x}\n')
        lines += [f'{int.from_bytes(pack("VERTEX",**v),"little"):032x}\n' for v in vertices]
        lines += [f'{v:0195x}\n' for v in output]
    out = ROOT / 'build/gpu_geometry'
    out.mkdir(parents=True,exist_ok=True)
    (out / 'vectors.txt').write_text(''.join(lines))
    (out / 'seeds.hex').write_text(''.join(
        f'{reciprocal_seed((1<<30)+(i<<20)+(1<<19)):08x}\n' for i in range(1024)))
    print(f'Model vectors: {len(cases)} draws, {triangle_count} screen triangles',flush=True)


def main():
    vectors()
    out = ROOT / 'build/gpu_geometry'
    subprocess.run(['verilator', '-DSIM_MODE','--binary','--timing','-j','1',
                    '--top-module','tb_gpu_geometry','--Mdir',str(out / 'obj'),
                    '-o','sim','-f','files.f'],cwd=Path(__file__).resolve().parent,check=True)
    subprocess.run([str(out / 'obj/sim')],cwd=ROOT,check=True)


if __name__ == '__main__':
    main()
