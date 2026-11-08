/* data.c — showcase 4.3/4.5; measured CPU and bus counters, exclusive benchmarks.
 * Statistics use runtime CLK_SYS_HZ and snapshot CLK_MEM cycles; clk_sys. */
#include "board.h"
#include "vision_hooks.h"
#include "input.h"
#include "hpm.h"
#include "fabric.h"
#include "latency.h"
#include "overlay.h"
#include "../ui/coremark.h"
#include "../nes/nes_port.h"
#include "../apps.h"
#include "../platform.h"
#include "../runtime.h"
#include "../ui/theme.h"
#include "../lvgl/showcase_lvgl.h"
#include "../lvgl/draw_rnd.h"
#include "mem_xbar.h"
#include "sysctrl.h"
#include "monitor.h"
#include "uart.h"
#include <string.h>
static ui_system_t system_data;
static char report_line[768];
static unsigned report_length;
static uint64_t report_time,previous_busy[3],previous_idle;
static uint32_t previous_frames,previous_display,previous_nes;
static ui_coremark_t core;
static unsigned pending_core, pending_benchmark;
static uint32_t action_frame;
static ui_benchmark_t rows[16]={
    {"Empty screen",0,0,0},{"Moving wallpaper",0,0,0},{"Single rectangle",0,0,0},
    {"Multiple rectangles",0,0,0},{"Multiple RGB images",0,0,0},
    {"Multiple ARGB images",0,0,0},{"Rotated ARGB images",0,0,0},
    {"Multiple labels",0,0,0},{"Screen sized text",0,0,0},{"Multiple arcs",0,0,0},
    {"Containers",0,0,0},{"Containers with overlay",0,0,0},
    {"Containers with opa",0,0,0},{"Containers with opa_layer",0,0,0},
    {"Containers with scrolling",0,0,0},{"Widgets demo",0,0,0}
};
unsigned ui_data_hardware(void)
{
    unsigned h=platform_hardware(),r=UI_DISP;
    if(h&APP_HW_RND) r|=UI_RND;
    if(h&APP_HW_NPU) r|=UI_NPU;
    if(h&APP_HW_VIN) r|=UI_VIN;
    if(h&APP_HW_PIX) r|=UI_PIX;
    if(h&APP_HW_GEO) r|=UI_GEO;
    if(h&APP_HW_ETH) r|=UI_ETH;
    return r;
}
ui_system_t ui_data_system(void)
{
    system_data.clock_hz=platform_clock_hz();
    return system_data;
}
void showcase_cpu_report_init(void) { report_time=platform_ticks(); }
extern unsigned board_eth_rering;
void showcase_cpu_report(void)
{
    uint64_t now=platform_ticks(),elapsed=now-report_time;
    if(elapsed<platform_clock_hz()/2) return;
    struct sched_task *tasks[]={&communication_task,&application_task,&gui_task};
    uint64_t idle=sched_idle_ticks();
    system_data.seconds=platform_milliseconds()/1000;
    system_data.idle=(unsigned)((idle-previous_idle)*100/elapsed);
    system_data.cpu=100-system_data.idle;
    uint32_t frames=showcase_gui_frames();
    uint32_t display=platform_frames();
    system_data.display_fps=(unsigned)((uint64_t)(display-previous_display)*
        platform_clock_hz()/elapsed);
    unsigned rendered=showcase_gui_paused() ? nes_shown-previous_nes : frames-previous_frames;
    previous_nes=nes_shown; previous_display=display;
    system_data.fps=(unsigned)((uint64_t)rendered*platform_clock_hz()/elapsed);
    system_data.link=showcase_network_link()>0;
    for(unsigned i=0;i<3;++i) {
        system_data.task_cpu[i]=(unsigned)((tasks[i]->busy_ticks-previous_busy[i])*100/elapsed);
        system_data.task_max_us[i]=(unsigned)(tasks[i]->max_step_ticks*1000000/platform_clock_hz());
        previous_busy[i]=tasks[i]->busy_ticks;
    }
    previous_frames=frames; previous_idle=idle; report_time=now;
    static uint64_t last_log;
    if(now-last_log<platform_clock_hz()) return;
    uint64_t log_elapsed=now-last_log;
    last_log=now;
    static uint64_t overlay_before;
    uint64_t overlay=board_overlay_ticks();
    unsigned overlay_percent=(unsigned)((overlay-overlay_before)*10000/log_elapsed);
    overlay_before=overlay;
    unsigned eth_max,eth_avg;
    board_nes_latency(2,&eth_max,&eth_avg);
    report_length=(unsigned)lv_snprintf(report_line,sizeof(report_line),
        "CPU%%/max_us %u/%u %u/%u %u/%u overlay_cpu=%u.%02u%% max_us=%u rering=%u\r\n"
        "NES input ETH max_ms=%u.%03u avg_ms=%u.%03u\r\n",
        system_data.task_cpu[0],system_data.task_max_us[0],
        system_data.task_cpu[1],system_data.task_max_us[1],
        system_data.task_cpu[2],system_data.task_max_us[2],overlay_percent/100,overlay_percent%100,
        board_overlay_max_us(),board_eth_rering,
        eth_max/1000,eth_max%1000,eth_avg/1000,eth_avg%1000);
    const char *vision = vision_report();
    unsigned length = (unsigned)strlen(vision);
    memcpy(report_line + report_length, vision, length + 1);
    report_length += length;
    platform_puts(report_line);
}
void board_memory_sample(const struct mem_xbar_stats *m)
{
    board_fabric_sample(m);
    static uint64_t cycles,read[7],write[7];
    cycles+=m->window_cycles;
    for(unsigned i=0;i<7;++i) { read[i]+=m->port[i].rd_beat; write[i]+=m->port[i].wr_beat; }
    static uint64_t previous;
    uint64_t now=platform_ticks();
    if(now-previous<platform_clock_hz()/2) return;
    uint64_t elapsed=now-previous;
    for(unsigned i=0;i<7;++i) {
        system_data.ddr_read[i]=(unsigned)(read[i]*32*platform_clock_hz()/elapsed/1000000);
        system_data.ddr_write[i]=(unsigned)(write[i]*32*platform_clock_hz()/elapsed/1000000);
        read[i]=write[i]=0;
    }
    static uint64_t rnd_before,npu_before;
    uint64_t rnd=board_rnd_cycles(),npu=board_npu_cycles();
    /* RND clk_mem=125 MHz; NPU clk_npu=180 MHz, specified engine clocks. */
    system_data.rnd_busy=(unsigned)((rnd-rnd_before)*100*platform_clock_hz()/elapsed/125000000);
    system_data.npu_busy=(unsigned)((npu-npu_before)*100*platform_clock_hz()/elapsed/180000000);
    rnd_before=rnd; npu_before=npu; previous=now;
    cycles=0;
}
const ui_benchmark_t *ui_data_benchmark(void) { return rows; }
void board_benchmark_result(unsigned scene,uint64_t ticks,unsigned frames)
{
    (void)ticks; (void)frames;
    const struct showcase_benchmark_scene *scenes;
    showcase_benchmark_result(&scenes);
    rows[scene].name=scenes[scene].name;
    rows[scene].ms_tenths=scenes[scene].ms_tenths;
    rows[scene].fps_tenths=scenes[scene].fps_tenths;
}
void board_benchmark_end(void) { app_wake_at(platform_ticks()); }
unsigned ui_data_benchmark_progress(void)
{
    const struct showcase_benchmark_scene *scenes;
    return showcase_benchmark_result(&scenes);
}
bool ui_data_benchmark_running(void)
{ return pending_benchmark==1 || showcase_benchmark_running(); }
void ui_data_benchmark_stop(void)
{
    if(pending_benchmark==2) ui_benchmark_controls(false);
    showcase_benchmark_stop(); pending_benchmark=0;
    showcase_input_owner(INPUT_GUI);
    ui_suspend(false); ui_open(4);
}
void ui_data_benchmark_start(void)
{
    ui_data_app_open(UI_APP_GRAPHICS,0);
    for(unsigned i=0;i<16;++i) rows[i].ms_tenths=rows[i].fps_tenths=0;
    ui_hint("正在运行 LVGL benchmark 场景序列");
    pending_benchmark=1; action_frame=showcase_gui_frames();
    app_wake_at(platform_ticks()+platform_clock_hz()/30);
}
ui_coremark_t ui_data_coremark(void) { return core; }
void ui_data_coremark_start(void) { ui_data_app_open(UI_APP_COREMARK,0); }
void board_coremark_begin(void)
{
    core.running=true; core.progress=0; pending_core=1;
    action_frame=showcase_gui_frames(); app_wake_at(platform_ticks()+platform_clock_hz()/30);
}
extern const uint8_t __coremark_stack_top[];
void board_coremark_stack(void (*run)(void),const void *top);
static unsigned core_round;
static void __attribute__((section(".text.coremark_run"))) run_coremark(void)
{
    core_results result;
    monitor_core_init(&result,5000);
    board_hpm_prepare(core_round);
    board_hpm_start();
    iterate(&result);
    board_hpm_stop();
    uint64_t counters[8];
    board_hpm_read(&core.cycles[core_round],&core.instructions[core_round],counters);
    ui_hpm_store(core.events,core_round,counters);
    board_hpm_release();
}
void board_init(void) { platform_puts("Showcase: EdRV32 showcase v2\r\n"); }
void board_step(void)
{
    extern void board_prof_step(void);
    board_prof_step();
    extern void board_render_step(void);
    ui_session_t session=ui_data_session();
    if(session.app==UI_APP_GRAPHICS && session.state==UI_STATE_RUNNING) board_render_step();
    if(pending_core && showcase_gui_frames()!=action_frame) {
        for(core_round=0;core_round<2;++core_round)
            board_coremark_stack(run_coremark,__coremark_stack_top);
        core.compiler_flags="g15-tuned -O3 -funroll-all-loops -finline-limit=600 "
            "-falign-functions=4 -falign-jumps=4 -falign-loops=4 "
            "-fstrict-aliasing -march=rv32im_zicsr_zifencei; SRAM";
        core.score_tenths=(unsigned)(5000ull*platform_clock_hz()*10/core.cycles[0]);
        core.per_mhz_thousandths=(unsigned)(5000ull*1000000000/core.cycles[0]);
        core.progress=100; core.running=false; pending_core=0; app_return(); ui_refresh();
    }
    if(pending_benchmark==1 && session.app==UI_APP_GRAPHICS &&
       session.state==UI_STATE_RUNNING && showcase_gui_frames()!=action_frame) {
        pending_benchmark=2; showcase_input_owner(INPUT_APP);
        ui_suspend(true); showcase_benchmark_start();
        ui_benchmark_controls(true);
    } else if(pending_benchmark==2 && !showcase_benchmark_running()) {
        pending_benchmark=0; ui_benchmark_controls(false);
        showcase_benchmark_stop(); showcase_input_owner(INPUT_GUI);
        ui_suspend(false); ui_open(4);
    }
    if(pending_core || pending_benchmark)
        app_wake_at(platform_ticks()+platform_clock_hz()/30);
}
static void layer_exit(void) { layers_exit(); }
const struct app board_layers_app={"layers",0,APP_HW_RND,1,layers_enter,layers_step,layer_exit};

void board_coremark_stop(void) { pending_core=0; core.running=false; }
void board_graphics_stop(void)
{
    if(pending_benchmark==2) ui_benchmark_controls(false);
    showcase_benchmark_stop(); pending_benchmark=0;
    showcase_input_owner(INPUT_GUI); ui_suspend(false);
    extern void board_render_stop(void);
    board_render_stop();
}
