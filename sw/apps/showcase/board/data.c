/* data.c — showcase 4.3/4.5; measured CPU and bus counters, exclusive benchmarks.
 * Statistics use runtime CLK_SYS_HZ and snapshot CLK_MEM cycles; clk_sys. */
#include "board.h"
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
static uint64_t report_time,previous_busy[3],previous_idle;
static uint32_t previous_frames;
static ui_coremark_t core;
static unsigned pending_core, pending_benchmark, benchmark_pass, progress;
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
void showcase_cpu_report(void)
{
    uint64_t now=platform_ticks(),elapsed=now-report_time;
    if(elapsed<platform_clock_hz()) return;
    struct sched_task *tasks[]={&communication_task,&application_task,&gui_task};
    uint64_t idle=sched_idle_ticks();
    system_data.seconds=platform_milliseconds()/1000;
    system_data.idle=(unsigned)((idle-previous_idle)*100/elapsed);
    system_data.cpu=100-system_data.idle;
    uint32_t frames=showcase_gui_frames();
    system_data.fps=(unsigned)((uint64_t)(frames-previous_frames)*platform_clock_hz()/elapsed);
    system_data.link=showcase_network_link()>0;
    platform_puts("CPU%/max_us");
    for(unsigned i=0;i<3;++i) {
        system_data.task_cpu[i]=(unsigned)((tasks[i]->busy_ticks-previous_busy[i])*100/elapsed);
        system_data.task_max_us[i]=(unsigned)(tasks[i]->max_step_ticks*1000000/platform_clock_hz());
        previous_busy[i]=tasks[i]->busy_ticks;
        platform_puts(" "); platform_put_u32(system_data.task_cpu[i]);
        platform_puts("/"); platform_put_u32(system_data.task_max_us[i]);
    }
    platform_puts("\r\n"); previous_frames=frames; previous_idle=idle; report_time=now;
}
void board_memory_sample(const struct mem_xbar_stats *m)
{
    static uint64_t cycles,read[7],write[7];
    cycles+=m->window_cycles;
    for(unsigned i=0;i<7;++i) { read[i]+=m->port[i].rd_beat; write[i]+=m->port[i].wr_beat; }
    static uint64_t previous;
    uint64_t now=platform_ticks();
    if(now-previous<platform_clock_hz()) return;
    uint64_t elapsed=now-previous;
    for(unsigned i=0;i<7;++i) {
        system_data.ddr_read[i]=(unsigned)(read[i]*32*platform_clock_hz()/elapsed/1000000);
        system_data.ddr_write[i]=(unsigned)(write[i]*32*platform_clock_hz()/elapsed/1000000);
        read[i]=write[i]=0;
    }
    static uint64_t rnd_before,npu_before;
    uint64_t rnd=board_rnd_cycles(),npu=board_npu_cycles();
    /* RND clk_mem=125 MHz; NPU clk_npu=150 MHz, specified engine clocks. */
    system_data.rnd_busy=(unsigned)((rnd-rnd_before)*100*platform_clock_hz()/elapsed/125000000);
    system_data.npu_busy=(unsigned)((npu-npu_before)*100*platform_clock_hz()/elapsed/150000000);
    rnd_before=rnd; npu_before=npu; previous=now;
    cycles=0;
}
const ui_benchmark_t *ui_data_benchmark(void) { return rows; }
unsigned ui_data_benchmark_progress(void) { return progress; }
void ui_data_benchmark_start(void)
{
    if(ui_tab==2) {
        extern const struct app board_layers_app;
        ui_hint("图层演示：按返回键退出"); board_request(&board_layers_app); return;
    }
    ui_hint("正在运行 LVGL benchmark 场景序列");
    pending_benchmark=1; action_frame=showcase_gui_frames(); progress=0;
    app_wake_at(platform_ticks()+platform_clock_hz()/30);
}
void board_benchmark_result(unsigned scene,uint64_t ticks,unsigned frames)
{
    unsigned ms=frames ? (unsigned)(ticks*10000/platform_clock_hz()/frames) : 0;
    if(benchmark_pass) rows[scene].software_tenths=ms;
    else { rows[scene].ms_tenths=ms; rows[scene].fps_tenths=ms ? 100000/ms : 0; }
    progress=scene+1;
}
void board_benchmark_end(void)
{
    pending_benchmark=benchmark_pass ? 3 : 2;
    app_wake_at(platform_ticks());
}
ui_coremark_t ui_data_coremark(void) { return core; }
void ui_data_coremark_start(void)
{
    core.running=true; core.progress=0; pending_core=1;
    action_frame=showcase_gui_frames(); app_wake_at(platform_ticks()+platform_clock_hz()/30);
}
extern const uint8_t __coremark_stack_top[];
void board_coremark_stack(void (*run)(void),const void *top);
static uint64_t core_elapsed;
static void __attribute__((section(".text.coremark_run"))) run_coremark(void)
{
    core_results result;
    monitor_core_init(&result,5000);
    uint64_t start=platform_ticks();
    iterate(&result);
    core_elapsed=platform_ticks()-start;
}
void board_init(void) {}
void board_step(void)
{
    extern void board_prof_step(void);
    board_prof_step();
    if(pending_core && showcase_gui_frames()!=action_frame) {
        board_coremark_stack(run_coremark,__coremark_stack_top);
        core.score_tenths=(unsigned)(5000ull*platform_clock_hz()*10/core_elapsed);
        core.per_mhz_thousandths=(unsigned)(5000ull*1000000000/core_elapsed);
        core.progress=100; core.running=false; pending_core=0; ui_refresh();
    }
    if(pending_benchmark==1 && showcase_gui_frames()!=action_frame) {
        pending_benchmark=0; benchmark_pass=0; ui_suspend(true);
        showcase_draw_rnd_enable((platform_hardware()&APP_HW_RND)!=0);
        showcase_lvgl_start_benchmark();
    } else if(pending_benchmark==2) {
        pending_benchmark=0; benchmark_pass=1;
        showcase_draw_rnd_enable(false); showcase_lvgl_start_benchmark();
    } else if(pending_benchmark==3) {
        pending_benchmark=0; showcase_lvgl_stop_demo();
        showcase_draw_rnd_enable((platform_hardware()&APP_HW_RND)!=0);
        ui_open(4); ui_suspend(false);
    }
    if(pending_core || pending_benchmark)
        app_wake_at(platform_ticks()+platform_clock_hz()/30);
}
static void layer_exit(void) { layers_exit(); }
const struct app board_layers_app={"layers",0,APP_HW_RND,1,layers_enter,layers_step,layer_exit};
