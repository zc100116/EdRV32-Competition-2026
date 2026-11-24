#!/usr/bin/env python3
"""profile_ember.py — P-1: 1200-frame coast replay profiling; generated files stay in build.
Host wall/CPU clocks and scheduler switch counts; no emulated clock domain.
Use --gprof for a separate call-graph run (its overhead changes phase timings).
"""
import argparse
import os
from pathlib import Path
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[4]
BUILD = ROOT / 'build/ember-perf/profile'
PREFIX = '''#include <time.h>
#include <stdint.h>
extern uint64_t profile_ns[256];
uint64_t profile_clock(void);
void profile_frame(uint64_t start);
void profile_usage(uint32_t texture, uint32_t slots, uint32_t alive);
void profile_sim(uint32_t enemies, uint32_t shots);
'''


def timed(source, call, slot):
    return source.replace(call, '{ uint64_t start = profile_clock(); ' + call
                          + f' profile_ns[{slot}] += profile_clock()-start; }}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--gprof', action='store_true')
    parser.add_argument('--revision', help='profile C sources from this git revision')
    parser.add_argument('--frames', type=int, default=1200)
    parser.add_argument('--texture-bytes', type=int, default=192 * 1024)
    args = parser.parse_args()
    global BUILD
    if args.revision:
        BUILD = ROOT / ('build/ember-perf/profile-' + args.revision)
    BUILD.mkdir(parents=True, exist_ok=True)
    sources = ['sw/apps/ember_isles/src/game.c', 'sw/bsp/pc/soc.c',
               'tools/gpu/emu/gpu_emu.c', 'sw/lib/plat/pc.c',
               'sw/apps/ember_isles/src/headless.c']
    for filename in sources:
        source = (subprocess.check_output(['git', 'show', args.revision + ':' + filename],
                                          cwd=ROOT, text=True) if args.revision
                  else (ROOT / filename).read_text())
        if filename.endswith('game.c'):
            source = timed(source, 'ember_sim_step(&simulation, keys);', 0)
            source = timed(source, 'ember_gfx_prepare(&simulation, measured_fps, &ui);', 1)
        elif filename.endswith('soc.c'):
            source = timed(source, 'audio_advance(audio_frames);', 2)
            source = timed(source, 'display_frame();', 3)
        elif filename.endswith('gpu_emu.c'):
            source = source.replace('static void command(struct gpu_emu *e,',
                                    'static void command_body(struct gpu_emu *e,')
            source = source.replace('static void reset(struct gpu_emu *e)', '''
static void command(struct gpu_emu *e, const uint8_t *data)
{
    uint64_t start = profile_clock();
    command_body(e,data);
    profile_ns[16+data[0]] += profile_clock()-start;
}
static void reset(struct gpu_emu *e)''')
        elif filename.endswith('pc.c'):
            source = source.replace('pc_soc_vsync(pc_frontend_wait());', '''
    uint64_t start = profile_clock();
    uint32_t samples = pc_frontend_wait();
    profile_ns[4] += profile_clock()-start;
    pc_soc_vsync(samples);''')
        elif filename.endswith('headless.c'):
            source = source.replace('        ember_game_frame(frame);',
                                    '        uint64_t start = profile_clock();\n'
                                    '        ember_game_frame(frame);')
            source = source.replace('        plat_wait_vsync();',
                                    '        plat_wait_vsync();\n        profile_frame(start);\n'
                                    '        profile_sim(ember_game_state()->alive_count,\n'
                                    '                    ember_game_state()->shot_count);')
            if not args.revision:
                source = source.replace('    pc_soc_destroy();', '''
    struct gpu_emu_usage usage = pc_soc_gpu_usage();
    profile_usage(usage.texture_bytes, usage.object_slots, usage.objects_alive);
    pc_soc_destroy();''')
        (BUILD / Path(filename).name).write_text(PREFIX + source)
    (BUILD / 'timing.c').write_text('''#include <time.h>
#include <sys/resource.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
uint64_t profile_ns[256];
static uint64_t frames[PROFILE_FRAMES], cpu[PROFILE_FRAMES];
static uint64_t previous_cpu;
static long voluntary[PROFILE_FRAMES], involuntary[PROFILE_FRAMES];
static struct rusage previous_usage;
static uint64_t phase_frames[PROFILE_FRAMES][5], phase_previous[5];
static uint32_t enemies_per_frame[PROFILE_FRAMES], shots_per_frame[PROFILE_FRAMES];
static unsigned count;
static uint32_t texture_bytes, object_slots, objects_alive, enemy_peak, shot_peak;
void profile_sim(uint32_t enemies, uint32_t shots)
{
    enemies_per_frame[count-1]=enemies; shots_per_frame[count-1]=shots;
    if (enemies>enemy_peak) enemy_peak=enemies;
    if (shots>shot_peak) shot_peak=shots;
}
void profile_usage(uint32_t texture, uint32_t slots, uint32_t alive)
{
    texture_bytes=texture; object_slots=slots; objects_alive=alive;
}
uint64_t profile_clock(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC,&t);
    return (uint64_t)t.tv_sec*1000000000+t.tv_nsec;
}
void profile_frame(uint64_t start)
{
    frames[count]=profile_clock()-start;
    struct rusage usage;
    getrusage(RUSAGE_SELF,&usage);
    uint64_t total_cpu=(uint64_t)(usage.ru_utime.tv_sec+usage.ru_stime.tv_sec)*1000000000
        +(uint64_t)(usage.ru_utime.tv_usec+usage.ru_stime.tv_usec)*1000;
    cpu[count]=total_cpu-previous_cpu;
    previous_cpu=total_cpu;
    voluntary[count]=usage.ru_nvcsw-previous_usage.ru_nvcsw;
    involuntary[count]=usage.ru_nivcsw-previous_usage.ru_nivcsw;
    previous_usage=usage;
    uint64_t gpu=0;
    for (unsigned i=16;i<256;++i) gpu+=profile_ns[i];
    uint64_t phase[5]={profile_ns[0],profile_ns[1],gpu,profile_ns[2],profile_ns[3]};
    for (unsigned i=0;i<5;++i) {
        phase_frames[count][i]=phase[i]-phase_previous[i];
        phase_previous[i]=phase[i];
    }
    ++count;
}
static int order(const void *a, const void *b)
{
    uint64_t x=*(const uint64_t *)a, y=*(const uint64_t *)b;
    return (x>y)-(x<y);
}
static void report(void)
{
    uint64_t sum=0;
    unsigned late=0;
    FILE *csv=fopen(PROFILE_CSV,"w");
    if (!csv) { perror(PROFILE_CSV); exit(1); }
    fputs("frame,ms,enemies,shots,sim_ms,gfx_ms,gpu_ms,audio_ms,disp_ms,"
          "cpu_ms,voluntary,involuntary\\n",csv);
    for (unsigned i=0;i<count;++i) {
        sum+=frames[i];
        late+=frames[i]>1000000000u/60u;
        fprintf(csv,"%u,%.6f,%u,%u",i+1,frames[i]/1e6,
                enemies_per_frame[i],shots_per_frame[i]);
        for (unsigned j=0;j<5;++j) fprintf(csv,",%.6f",phase_frames[i][j]/1e6);
        fprintf(csv,",%.6f,%ld,%ld\\n",cpu[i]/1e6,voluntary[i],involuntary[i]);
    }
    fclose(csv);
    qsort(frames,count,sizeof(*frames),order);
    fprintf(stderr,"FRAME count=%u mean=%.6f p50=%.6f p95=%.6f p99=%.6f max=%.6f ms late=%u\\n",
            count,sum/(count*1e6),frames[count/2]/1e6,frames[count*95/100]/1e6,
            frames[count*99/100]/1e6,frames[count-1]/1e6,late);
    fprintf(stderr,"USAGE texture_end=%u object_slots=%u objects_alive=%u enemies=%u shots=%u\\n",
            texture_bytes,object_slots,objects_alive,enemy_peak,shot_peak);
    for (int i=0;i<256;++i) if (profile_ns[i])
        fprintf(stderr,"PHASE,%d,%.6f ms/frame\\n",i,profile_ns[i]/(count*1e6));
}
__attribute__((constructor)) static void init(void)
{
    getrusage(RUSAGE_SELF,&previous_usage);
    previous_cpu=(uint64_t)(previous_usage.ru_utime.tv_sec+previous_usage.ru_stime.tv_sec)
        *1000000000
        +(uint64_t)(previous_usage.ru_utime.tv_usec+previous_usage.ru_stime.tv_usec)*1000;
    atexit(report);
}
''')
    makefile = ROOT / 'sw/apps/ember_isles/Makefile'
    if args.revision:
        makefile = BUILD / 'historical.mk'
        makefile.write_text(subprocess.check_output(
            ['git', 'show', args.revision + ':sw/apps/ember_isles/Makefile'],
            cwd=ROOT, text=True))
    dry = subprocess.check_output(['make', '-Bn', '-f', str(makefile), 'ROOT=' + str(ROOT),
                                   'linux'], cwd=ROOT, text=True).replace('\\\n', ' ')
    command = shlex.split(next(line for line in dry.splitlines() if line.startswith('gcc ')))
    for filename in sources:
        command[command.index(str(ROOT / filename))] = str(BUILD / Path(filename).name)
    if args.revision:
        for index, value in enumerate(command):
            if value.endswith('.c') and value.startswith(str(ROOT)) and value not in [
                    str(BUILD / Path(filename).name) for filename in sources]:
                filename = str(Path(value).relative_to(ROOT))
                target = BUILD / 'sources' / filename
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(subprocess.check_output(
                    ['git', 'show', args.revision + ':' + filename], cwd=ROOT, text=True))
                command[index] = str(target)
                command += ['-I' + str(Path(value).parent)]
    command[command.index('-o')+1] = str(BUILD / 'ember-profile')
    command = [value for value in command if not value.startswith('-DGPU_EMU_TEXTURE_BYTES=')]
    command += ['-D_POSIX_C_SOURCE=200809L', '-g', '-Isw/bsp/pc', str(BUILD / 'timing.c')]
    command += [f'-DPROFILE_FRAMES={args.frames}',
                f'-DPROFILE_CSV="{BUILD / "frames.csv"}"',
                f'-DGPU_EMU_TEXTURE_BYTES={args.texture_bytes}']
    if args.gprof:
        command += ['-pg']
    subprocess.run(command, cwd=ROOT, check=True)
    with (BUILD/'replay.log').open('w') as output:
        process = subprocess.Popen([str(BUILD/'ember-profile'), '--replay',
                                    'sw/apps/ember_isles/assets/replays/coast.txt',
                                    '--frames', str(args.frames)], cwd=ROOT, stdout=output,
                                   env=os.environ | {'GMON_OUT_PREFIX': str(BUILD/'gmon')})
        if process.wait():
            raise subprocess.CalledProcessError(process.returncode, process.args)
    if args.gprof:
        with (BUILD/'gprof.txt').open('w') as output:
            subprocess.run(['gprof', str(BUILD/'ember-profile'),
                            str(BUILD/f'gmon.{process.pid}')], stdout=output, check=True)


if __name__ == '__main__':
    main()
