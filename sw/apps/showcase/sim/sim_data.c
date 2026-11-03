/* sim_data.c — showcase design §4.3/5.1; deterministic scripted page data.
 * LVGL tick clock; game loader supplies names/icons without opening ROMs.
 */
#include "sim_data.h"
#include "detection.h"
#include <string.h>
extern const lv_image_dsc_t sim_street;
extern const lv_image_dsc_t sim_indoor;
static unsigned hardware = UI_ALL;
static bool paused;
static bool boxes = true;
static bool waiting;
static unsigned paused_second;
static unsigned benchmark_start;
static bool benchmarking;
static unsigned core_start;
static bool core_started;
static unsigned baud_index;
static bool hex;
static unsigned clear_tick;
static unsigned sent;
static unsigned echo_count;
void sim_data_init(void) { clear_tick = lv_tick_get(); }
void sim_data_toggle_hardware(void) { hardware ^= UI_PIX | UI_GEO; }
unsigned ui_data_hardware(void) { return hardware; }
ui_system_t ui_data_system(void)
{
    unsigned step = lv_tick_get() / 500;
    ui_system_t d = {.seconds = lv_tick_get() / 1000, .cpu = 28 + step % 9,
        .fps = 58 + step % 3, .idle = 72 - step % 9, .npu_busy = 65 + step % 13,
        .rnd_busy = 21 + step % 11, .link = true, .clock_hz = 100000000};
    for(unsigned i = 0; i < 3; ++i) d.task_cpu[i] = 12 + i * 16 + (step / 2 * 7 + i) % 19;
    for(unsigned i = 0; i < 7; ++i) {
        d.ddr_read[i] = 65 + (i * 61 + step * 13) % 350;
        d.ddr_write[i] = 20 + (i * 47 + step * 7) % 210;
    }
    return d;
}
ui_vision_t ui_data_vision(bool batch)
{
    unsigned second = paused && !batch ? paused_second : lv_tick_get() / 1000;
    ui_vision_t d = {.image = batch ? &sim_indoor : &sim_street,
        .fps = 24 + second % 2, .npu_tenths = 410 + second % 7,
        .post_tenths = 23 + second % 4, .count = batch ? 5 : 4,
        .paused = paused, .boxes = batch || boxes, .waiting = batch && waiting,
        .batch_index = 1 + second / 3 % 24, .batch_total = 24,
        .success = second / 3 % 24, .failed = 0, .roundtrip = 63 + second % 5};
    const unsigned street[]={0,1,2,2,9},indoor[]={16,57,60,41,58};
    int street_rect[5][4] = {{120, 177, 116, 300}, {338, 177, 110, 225},
        {460, 215, 155, 92}, {638, 220, 310, 143}, {770, 60, 50, 100}};
    int indoor_rect[5][4] = {{150, 285, 235, 210}, {0, 135, 368, 315},
        {400, 250, 316, 220}, {610, 253, 55, 43}, {790, 60, 165, 290}};
    for(unsigned i = 0; i < 5; ++i) {
        int *r = batch ? indoor_rect[i] : street_rect[i];
        unsigned id=batch ? indoor[i] : street[i];
        d.targets[i] = (ui_detection_t){ui_coco_names[id],
            97 - i * 3 + second % 2, r[0] + (int)(second % 3) * 2,
            r[1], r[2], r[3],id};
    }
    ui_detection_t raw[5];
    memcpy(raw,d.targets,sizeof(raw));
    ui_detection_filter(&d,raw,d.count);
    return d;
}
void ui_data_pause(void)
{
    paused = !paused;
    if(paused) paused_second = lv_tick_get() / 1000;
}
void ui_data_boxes(void) { boxes = !boxes; }
void ui_data_batch_stop(void) { waiting = true; }
const lv_image_dsc_t *ui_data_process(unsigned mode) { (void)mode; return &sim_indoor; }
/* Card 46 values supplied by coordinator. Software-off comparison is a fixed
 * estimated workload, as authorized for P2; P3 replaces it with board data. */
static const ui_benchmark_t benchmark[] = {
    {"Empty screen", 60, 600, 100},
    {"Moving wallpaper", 194, 290, 450},
    {"Single rectangle", 9, 581, 24},
    {"Multiple rectangles", 66, 576, 148},
    {"Multiple RGB images", 177, 290, 380},
    {"Multiple ARGB images", 177, 290, 390},
    {"Rotated ARGB images", 1603, 58, 1650},
    {"Multiple labels", 410, 189, 620},
    {"Screen sized text", 1149, 78, 1600},
    {"Multiple arcs", 458, 169, 490},
    {"Containers", 552, 144, 730},
    {"Containers with overlay", 661, 122, 980},
    {"Containers with opa", 595, 136, 850},
    {"Containers with opa_layer", 1436, 63, 1940},
    {"Containers with scrolling", 919, 81, 1260},
    {"Widgets demo", 943, 83, 1240}
};
const ui_benchmark_t *ui_data_benchmark(void) { return benchmark; }
void ui_data_benchmark_start(void) { benchmark_start = lv_tick_get(); benchmarking = true; }
unsigned ui_data_benchmark_progress(void)
{
    if(!benchmarking) return 0;
    unsigned n = (lv_tick_get() - benchmark_start) / 500 + 1;
    return n > 16 ? 16 : n;
}
extern const ui_game_t sim_games[];
extern const unsigned sim_game_count;
const ui_game_t *ui_data_games(unsigned *count)
{
    *count = sim_game_count;
    return sim_games;
}
void ui_data_coremark_start(void) { core_start = lv_tick_get(); core_started = true; }
ui_coremark_t ui_data_coremark(void)
{
    unsigned p = core_started ? (lv_tick_get() - core_start) / 50 : 0;
    bool done = p >= 100;
    return (ui_coremark_t){done ? 100 : p, done ? 4354 : 0, done ? 4354 : 0,
        core_started && !done};
}
ui_debug_t ui_data_debug(void)
{
    unsigned step = (lv_tick_get() - clear_tick) / 500;
    unsigned baud[] = {115200, 921600, 2000000};
    bool received = step > 0;
    ui_debug_t d = {
        .uart_text = received ? "RX  EdRV32 ready\nRX  Link established\n"
            "RX  Vision pipeline active" : "",
        .uart_hex = received ? "RX  45 64 52 56 33 32 20 72 65 61 64 79\n"
            "RX  4C 69 6E 6B 20 65 73 74 61 62 6C 69 73 68 65 64" : "",
        .udp_text = "192.168.1.2:6000\n\nEDRV32 / telemetry\n"
            "frame=0248  targets=04\nstatus=ready",
        .peer = "192.168.1.2:6000", .baud = baud[baud_index],
        .uart_rx = step * 24, .uart_tx = sent * 15,
        .rx_packets = 248 + step * 3, .tx_packets = 232 + step * 2,
        .rx_bytes = 31744 + step * 384, .tx_bytes = 29696 + step * 256,
        .echo_count = echo_count, .echo_replies = echo_count, .hex = hex, .link = true};
    if(sent && !hex) d.uart_text = "TX  Hello EdRV32!\nRX  EdRV32 ready\nRX  Link established";
    if(sent && hex) d.uart_hex =
        "TX  48 65 6C 6C 6F 20 45 64 52 56 33 32 21 0D 0A\n"
        "RX  45 64 52 56 33 32 20 72 65 61 64 79";
    return d;
}
void ui_data_debug_format(void) { hex = !hex; }
void ui_data_debug_baud(void) { baud_index = (baud_index + 1) % 3; }
void ui_data_debug_send(void) { ++sent; }
void ui_data_debug_clear(void) { clear_tick = lv_tick_get(); sent = 0; }
void ui_data_debug_echo(void) { echo_count += 10; }

const lv_image_dsc_t *ui_data_game_name(unsigned index) { (void)index; return NULL; }

const lv_image_dsc_t *ui_data_game_initial(unsigned index) { (void)index; return NULL; }
