"""GT-17: gpu-spec 2.6, 6; immediate load consumers and errors 3/4 stop the list."""
from scene_support import Case


def build(c,rng):
    c.ready()
    source,count = c.scene.texture([[1]*64], format=0, width=8, height=8)
    c.scene.command('TEX_LOAD', SRC=source, DST=0, BYTES=count)
    c.scene.command('SET_TEX', OFFSET=0, LOG2_W=3, LOG2_H=3, FORMAT=0, LEVELS=1)
    for color in [0xf800,0x07e0]:
        address=c.scene.records('PAL_ENTRY',[dict(
            RGB565=color if index == 1 else (0x001f if index == 2 else 0), A4=15)
            for index in range(16)])
        c.scene.command('PAL_LOAD',SRC=address,GROUP=0,ENTRIES=16)
        c.quad()
        c.resolve()
    source,count = c.scene.texture([[2 if x%2 else 0 for y in range(8) for x in range(8)]],
                                   format=0,width=8,height=8)
    c.scene.command('TEX_LOAD',SRC=source,DST=0,BYTES=count)
    c.quad()
    c.resolve()
    # Exactly at the RAM end is valid for both the load and padded I4 descriptor.
    c.scene.command('TEX_LOAD',SRC=source,DST=192*1024-32,BYTES=count)
    c.scene.command('SET_TEX',OFFSET=192*1024-32,LOG2_W=3,LOG2_H=3,FORMAT=0,LEVELS=1)
    c.quad()
    c.resolve()
    for error in [3,4]:
        run=Case()
        run.ready()
        if error == 3:
            run.scene.command('SET_TEX',OFFSET=192*1024-32,LOG2_W=3,LOG2_H=3,
                              FORMAT=2,LEVELS=1)
        else:
            source=run.scene.blob(bytes(64))
            run.scene.command('TEX_LOAD',SRC=source,DST=192*1024-32,BYTES=64)
        run.clear(0x001f)
        run.resolve()
        run.checks.append(lambda gpu, code=error: check_error(gpu,code))
        c.runs.append(run)


def check_error(gpu,code):
    assert gpu.regs['ERR_CODE'] == code
    assert gpu.regs['IRQ_STAT'] == 2 and gpu.regs['DONE_COUNT'] == 0
