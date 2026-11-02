/* File: status.c
 * Design: showcase 4.2.
 * Description: Measured service CPU share, GUI FPS and communication status.
 * Clock domain: clk_sys; performance counters in clk_eth.
 */
#include "apps.h"
#include "platform.h"
#include "runtime.h"
#include "eth_monitor.h"
#include "uart.h"
#include "eth.h"
static lv_obj_t *statistics;
static uint64_t previous_time;
static uint64_t previous_busy[3];
static uint64_t previous_idle;
static uint32_t previous_frames;
void status_enter(void)
{
    lv_obj_t *screen = lv_screen_active();
    lv_obj_set_style_bg_color(screen, lv_color_hex(0x0b1725), 0);
    lv_obj_set_style_bg_opa(screen, LV_OPA_COVER, 0);
    lv_obj_set_style_text_color(screen, lv_color_hex(0xf2f7fc), 0);
    statistics = lv_label_create(screen);
    lv_obj_set_pos(statistics, 72, 80);
    previous_time = platform_ticks();
    previous_busy[0] = communication_task.busy_ticks;
    previous_busy[1] = application_task.busy_ticks;
    previous_busy[2] = gui_task.busy_ticks;
    previous_idle = sched_idle_ticks();
    previous_frames = showcase_gui_frames();
    lv_label_set_text(statistics, "系统状态\n正在采样……\n按键 4 返回");
    app_wake_at(previous_time + platform_clock_hz());
}
void status_step(void)
{
    uint64_t now = platform_ticks();
    if (now - previous_time < platform_clock_hz()) return;
    uint64_t elapsed = now - previous_time;
    struct sched_task *tasks[] = {&communication_task, &application_task, &gui_task};
    uint32_t share[3];
    for (unsigned i = 0; i < 3; ++i) {
        share[i] = (uint32_t)((tasks[i]->busy_ticks - previous_busy[i]) * 100u / elapsed);
        previous_busy[i] = tasks[i]->busy_ticks;
    }
    uint64_t idle = sched_idle_ticks();
    uint32_t idle_percent = (uint32_t)((idle - previous_idle) * 100u / elapsed);
    uint32_t frames = showcase_gui_frames();
    uint32_t fps = (uint32_t)((uint64_t)(frames - previous_frames) *
                            platform_clock_hz() / elapsed);
    int link = -1;
    uint32_t peer = 0;
    uint32_t rx = 0;
    uint32_t tx = 0;
    if (platform_hardware() & APP_HW_ETH) {
        link = showcase_network_link();
        peer = eth_monitor_peer_known();
        rx = engine_perf(ENGINE_ETH, 1);
        tx = showcase_network_tx_packets();
    }
    uint32_t divisor = mmio_read32(EDRV32_UART0_BASE + UART_BAUD_DIV);
    uint32_t baud = (uint32_t)((uint64_t)platform_clock_hz() * 16u / divisor);
    lv_label_set_text_fmt(statistics,
        "系统状态\n\n通信服务 CPU  %u %%\n当前应用 CPU  %u %%\n图形界面 CPU  %u %%\n"
        "空闲率  %u %%\nGUI 帧率  %u fps\n\n网口 link  %s    PEER  %s\n"
        "接收包数  %u    发送包数  %u\n串口波特率  %u\n虚拟输入  %s\n\n按键 4 返回",
        (unsigned)share[0], (unsigned)share[1], (unsigned)share[2],
        (unsigned)idle_percent, (unsigned)fps,
        link < 0 ? "未检测到 PHY" : (link ? "UP" : "DOWN"), peer ? "已连接" : "未连接",
        (unsigned)rx, (unsigned)tx, (unsigned)baud,
        platform_input_source() == 2 ? "网口" :
        (platform_input_source() == 1 ? "串口" : "尚无输入"));
    previous_time = now;
    previous_idle = idle;
    previous_frames = frames;
    app_wake_at(now + platform_clock_hz());
    sched_signal(&gui_task, 1);
}

/* UART sampling belongs to the communication service, independent of the page. */
static uint64_t report_time;
static uint64_t report_busy[3];
static uint64_t report_idle;
static uint32_t report_frames;
void showcase_cpu_report_init(void)
{
    report_time = platform_ticks();
    report_busy[0] = communication_task.busy_ticks;
    report_busy[1] = application_task.busy_ticks;
    report_busy[2] = gui_task.busy_ticks;
    report_idle = sched_idle_ticks();
    report_frames = showcase_gui_frames();
}
void showcase_cpu_report(void)
{
    uint64_t now = platform_ticks();
    uint64_t elapsed = now - report_time;
    if (elapsed < platform_clock_hz()) return;
    struct sched_task *tasks[] = {&communication_task, &application_task, &gui_task};
    const char *const names[] = {"% comm=", "% app=", "% gui="};
    uint64_t idle = sched_idle_ticks();
    uint32_t frames = showcase_gui_frames();
    platform_puts("Showcase CPU idle=");
    platform_put_u32((uint32_t)((idle - report_idle) * 100u / elapsed));
    for (unsigned i = 0; i < 3; ++i) {
        platform_puts(names[i]);
        platform_put_u32((uint32_t)((tasks[i]->busy_ticks - report_busy[i]) * 100u / elapsed));
        report_busy[i] = tasks[i]->busy_ticks;
    }
    platform_puts("% GUI fps=");
    platform_put_u32((uint32_t)((uint64_t)(frames - report_frames) *
                              platform_clock_hz() / elapsed));
    platform_puts("\r\n");
    report_time = now;
    report_idle = idle;
    report_frames = frames;
}
