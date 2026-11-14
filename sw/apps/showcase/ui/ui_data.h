/* ui_data.h — showcase design §4.3/5.1, P5 replan 8.7; displayed data and user actions.
 * Shared UI/backend contract; LVGL tick clock, no hardware ownership here.
 */
#ifndef UI_DATA_H
#define UI_DATA_H
#include "lvgl.h"
enum { UI_PIX = 1, UI_GEO = 2, UI_VIN = 4, UI_NPU = 8, UI_ETH = 16,
       UI_RND = 32, UI_DISP = 64, UI_ALL = 127 };
typedef struct {
    unsigned seconds, cpu, fps, idle, npu_busy, rnd_busy, clock_hz;
    unsigned display_fps;
    unsigned task_max_us[3];
    unsigned task_cpu[3], ddr_read[7], ddr_write[7];
    bool link;
} ui_system_t;
typedef struct {
    const char *category;
    unsigned confidence;
    int x, y, width, height;
    unsigned class_id;
} ui_detection_t;
typedef struct { unsigned threshold; uint32_t classes[3]; } ui_detection_config_t;
/* Media applications and session states: design 2026-11-03-showcase-p5-replan 8.1.
 * Values equal the EDSC `app` and `state` fields. */
typedef enum { UI_APP_NONE, UI_APP_PIPELINE, UI_APP_IMAGE, UI_APP_PROCESS,
               UI_APP_GRAPHICS, UI_APP_GAME, UI_APP_COREMARK } ui_app_t;
typedef enum { UI_STATE_IDLE, UI_STATE_STARTING, UI_STATE_RUNNING, UI_STATE_PAUSED,
               UI_STATE_STOPPING, UI_STATE_FAILED } ui_state_t;
typedef struct {
    ui_app_t app;
    ui_state_t state;
    const char *error;      /* reason text in FAILED, NULL otherwise */
    bool peer;              /* PC connected (HELLO sent, virtual input available) */
} ui_session_t;
typedef enum { UI_IMAGE_WAITING, UI_IMAGE_RECEIVING, UI_IMAGE_DETECTING, UI_IMAGE_DONE,
               UI_IMAGE_FAILED } ui_image_status_t;
typedef struct {
    const lv_image_dsc_t *image;
    unsigned fps, npu_tenths, post_tenths, latency_tenths, count;
    ui_detection_t targets[5];
    unsigned category_count[5];
    unsigned category_id[5];
    unsigned category_used;
    bool boxes;
    /* Image recognition (app 2): current PC image, design 8.2 IMAGE_INFO. */
    const char *image_name;
    unsigned image_index, image_total, roundtrip_ms;
    ui_image_status_t image_status;
} ui_vision_t;
typedef struct { const char *name; unsigned ms_tenths, fps_tenths, software_tenths; }
    ui_benchmark_t;
typedef struct { const char *name; const char *initial; const lv_image_dsc_t *cover; } ui_game_t;
typedef struct {
    unsigned progress, score_tenths, per_mhz_thousandths;
    bool running;
    uint64_t cycles[2], instructions[2], events[16];
    const char *compiler_flags;
} ui_coremark_t;
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
/* Current media session; the shell shows state and FAILED reasons from here. */
ui_session_t ui_data_session(void);
/* Open the media application of the page being entered (UI_APP_NONE when leaving
 * such a page). The board stops the previous application first (design 3.2, Q4).
 * arg is the game index for UI_APP_GAME and 0 otherwise. */
void ui_data_app_open(ui_app_t app, unsigned arg);
/* Pause or resume the camera/process application (design Q2). */
void ui_data_app_pause(bool paused);
/* Restart the current application after FAILED. */
void ui_data_app_retry(void);
/* Implemented by the UI: open the page for app after a PC APP request. */
void ui_show_app(ui_app_t app, unsigned arg);
/* Return the current camera or PC image and detection results. */
ui_vision_t ui_data_vision(void);
/* Ask the PC for the previous (-1) or next (+1) image of its list (EDSC IMAGE_STEP). */
void ui_data_image_step(int direction);
ui_detection_config_t ui_data_detection_config(void);
void ui_data_detection_threshold(unsigned percent);
void ui_data_detection_class(unsigned class_id,bool enabled);
void ui_data_detection_all(bool enabled);
/* Toggle detection box visibility. */
void ui_data_boxes(void);
/* Image processing stages in pipeline order, design 8.3. A cleared bit bypasses the
 * stage in hardware and keeps its parameters. */
enum {
    UI_PROC_LEVEL = 1u << 0, UI_PROC_GAMMA = 1u << 1, UI_PROC_S1 = 1u << 2,
    UI_PROC_S2 = 1u << 3, UI_PROC_GRAY = 1u << 4, UI_PROC_BINARY = 1u << 5,
    UI_PROC_INVERT = 1u << 6, UI_PROC_ROTATE = 1u << 7, UI_PROC_SCALE = 1u << 8,
    UI_PROC_TRANSLATE = 1u << 9, UI_PROC_MIRROR_X = 1u << 10, UI_PROC_MIRROR_Y = 1u << 11,
    UI_PROC_ALL = (1u << 12) - 1
};
typedef struct {
    uint32_t enabled;
    int brightness, contrast, gamma_tenths, stage1, stage2, threshold;
    int angle, scale_percent, translate_x, translate_y;
    bool original;
} ui_process_config_t;
ui_process_config_t ui_data_process_config(void);
void ui_data_process_set(const ui_process_config_t *config);
/* Restore the parameters of the given stages to design 8.3 defaults.
 * UI_PROC_ALL also clears every enable bit ("全部恢复默认", design Q3). */
void ui_data_process_defaults(uint32_t stages);
/* Return the image used for the processing mode preview. */
const lv_image_dsc_t *ui_data_process(unsigned mode);
/* Vision pipeline page, design 2026-11-14-showcase-vision-pipeline section 7.
 * The ui_process_* interface above is removed when the pipeline page is integrated. */
enum { UI_BLOCK_MAX = 8 };
enum { UI_BLOCK_NONE, UI_BLOCK_LEVEL, UI_BLOCK_GAMMA, UI_BLOCK_FILTER, UI_BLOCK_GRAY,
       UI_BLOCK_BINARY, UI_BLOCK_INVERT, UI_BLOCK_GEO, UI_BLOCK_DETECT, UI_BLOCK_OVERLAY };
enum { UI_SOURCE_CAMERA, UI_SOURCE_PC_IMAGE, UI_SOURCE_TEST_IMAGE };
enum { UI_VIEW_FINAL = 0xff };
typedef struct { uint8_t type, flags; int16_t p[5]; } ui_block_t;
typedef struct {
    uint8_t source, count, view, preset;
    ui_block_t block[UI_BLOCK_MAX];
} ui_chain_t;
ui_chain_t ui_data_chain(void);
/* 0 = accepted, else design 8.1 error code; a rejected chain leaves the current one. */
unsigned ui_data_chain_set(const ui_chain_t *chain);
/* Load preset 1..8 (design 4.1 table order). */
void ui_data_chain_preset(unsigned preset);
enum { UI_HOP_CAM_PIX, UI_HOP_CAM_RAW, UI_HOP_MEM_PIX, UI_HOP_MEM_NPU, UI_HOP_GEO,
       UI_HOP_RND };
typedef struct {
    uint8_t engine;       /* UI_HOP_* */
    uint8_t first, last;  /* block range served by this hop */
    uint32_t us;          /* average duration over the last second */
} ui_hop_t;
enum { UI_HOP_MAX = 12 };
typedef struct {
    unsigned hop_count;
    ui_hop_t hop[UI_HOP_MAX];
    unsigned fps, e2e_us, box_lag_us, npu_us;
    unsigned ddr_mbps, ddr_limit_mbps;
} ui_pipe_stats_t;
ui_pipe_stats_t ui_data_pipe_stats(void);
/* 160x90 RGB565 thumbnail of block k's output (5 fps); UI_VIEW_FINAL is the source. */
const lv_image_dsc_t *ui_data_thumb(unsigned block);
/* Return all sixteen benchmark rows. */
const ui_benchmark_t *ui_data_benchmark(void);
/* Start the fixed benchmark sequence. */
void ui_data_benchmark_start(void);
/* Return the number of completed benchmark scenes. */
unsigned ui_data_benchmark_progress(void);
void ui_data_benchmark_stop(void);
bool ui_data_benchmark_running(void);
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
