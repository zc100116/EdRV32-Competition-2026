/* ui_data.h — showcase design §4.3/5.1; displayed data and user actions.
 * Shared UI/backend contract; LVGL tick clock, no hardware ownership here.
 */
#ifndef UI_DATA_H
#define UI_DATA_H
#include "lvgl.h"
enum { UI_PIX = 1, UI_GEO = 2, UI_VIN = 4, UI_NPU = 8, UI_ETH = 16,
       UI_RND = 32, UI_DISP = 64, UI_ALL = 127 };
typedef struct {
    unsigned seconds, cpu, fps, idle, npu_busy, rnd_busy, clock_hz;
    unsigned task_max_us[3];
    unsigned task_cpu[3], ddr_read[7], ddr_write[7];
    bool link;
} ui_system_t;
typedef struct {
    const char *category;
    unsigned confidence;
    int x, y, width, height;
} ui_detection_t;
typedef struct {
    const lv_image_dsc_t *image;
    unsigned fps, npu_tenths, post_tenths, count;
    ui_detection_t targets[5];
    unsigned category_count[5];
    bool paused, boxes, waiting;
    unsigned batch_index, batch_total, success, failed, roundtrip;
} ui_vision_t;
typedef struct { const char *name; unsigned ms_tenths, fps_tenths, software_tenths; }
    ui_benchmark_t;
typedef struct { const char *name; const char *initial; const lv_image_dsc_t *cover; } ui_game_t;
typedef struct { unsigned progress, score_tenths, per_mhz_thousandths; bool running; }
    ui_coremark_t;
typedef struct {
    const char *uart_text, *uart_hex, *udp_text, *peer;
    unsigned baud, uart_rx, uart_tx, rx_packets, tx_packets, rx_bytes, tx_bytes;
    unsigned echo_count, echo_replies;
    bool hex, link;
} ui_debug_t;
/* Return the modules available to this hardware configuration. */
unsigned ui_data_hardware(void);
/* Return status, task occupancy and seven DDR port counters. */
ui_system_t ui_data_system(void);
/* Return the current camera or batch image and detection results. */
ui_vision_t ui_data_vision(bool batch);
/* Toggle camera capture pause. */
void ui_data_pause(void);
/* Toggle detection box visibility. */
void ui_data_boxes(void);
/* Stop the image batch and wait for the next PC upload. */
void ui_data_batch_stop(void);
/* Return the image used for the processing mode preview. */
const lv_image_dsc_t *ui_data_process(unsigned mode);
/* Return all sixteen benchmark rows. */
const ui_benchmark_t *ui_data_benchmark(void);
/* Start the fixed benchmark sequence. */
void ui_data_benchmark_start(void);
/* Return the number of completed benchmark scenes. */
unsigned ui_data_benchmark_progress(void);
/* Return the build-time game names, initial characters and optional covers. */
const ui_game_t *ui_data_games(unsigned *count);
const lv_image_dsc_t *ui_data_game_name(unsigned index);
const lv_image_dsc_t *ui_data_game_initial(unsigned index);
/* Return CoreMark progress and the completed score. */
ui_coremark_t ui_data_coremark(void);
/* Start a CoreMark run. */
void ui_data_coremark_start(void);
/* Return UART and Ethernet display data. */
ui_debug_t ui_data_debug(void);
/* Toggle UART text versus hexadecimal display. */
void ui_data_debug_format(void);
/* Select the next specified UART baud rate. */
void ui_data_debug_baud(void);
/* Send the preset UART test string. */
void ui_data_debug_send(void);
/* Clear UART display and byte counters. */
void ui_data_debug_clear(void);
/* Run the Ethernet loopback sequence. */
void ui_data_debug_echo(void);
#endif
