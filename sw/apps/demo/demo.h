/* File: demo.h
 * Spec: design 2026-10-29-b2-software 3.3–3.5a.
 * Description: B2 DDR allocation and host-testable menu/wire contracts.
 * Clock domain: none (pure software).
 */
#ifndef EDRV32_DEMO_H
#define EDRV32_DEMO_H
#include <stddef.h>
#include <stdint.h>
#include "mem_xbar.h"
#include "yolo_post.h"

#define DEMO_DESC_BASE 0x00080000u
#define DEMO_DESC_SIZE 0x00010000u
#define DEMO_MODEL_BASE 0x00100000u
#define DEMO_MODEL_SIZE 0x00400000u
#define DEMO_WORK_BASE 0x01000000u
#define DEMO_WORK_SIZE 0x00800000u
#define DEMO_INPUT_BASE 0x04000000u
#define DEMO_INPUT_SPACING 0x00100000u
#define DEMO_INPUT_COUNT 3u
#define DEMO_INPUT_BYTES 983040u
#define DEMO_OUTPUT_BASE 0x05000000u
#define DEMO_OUTPUT_SPACING 0x00100000u
#define DEMO_OUTPUT_COUNT 2u
#define DEMO_OUTPUT_BYTES 725760u
#define DEMO_IMAGE_BASE 0x06000000u
#define DEMO_IMAGE_SPACING 0x00200000u
#define DEMO_IMAGE_COUNT 4u
#define DEMO_GEO_BASE 0x07000000u
#define DEMO_GEO_COUNT 2u
#define DEMO_WINDOW_BASE 0x08000000u
#define DEMO_WINDOW_SIZE 0x00200000u
#define DEMO_MODEL_WINDOW 0x09000000u
#define DEMO_MODEL_WINDOW_SIZE 0x01000000u
#define DEMO_COMMAND_WINDOW 0x0a000000u
#define DEMO_COMMAND_WINDOW_SIZE 0x00010000u
#define DEMO_SEND_BASE 0x0a100000u
#define DEMO_SEND_SIZE 0x00400000u
#define DEMO_WIDTH 1280u
#define DEMO_HEIGHT 720u
#define DEMO_STRIDE 2560u
#define DEMO_IMAGE_BYTES 1843200u
#define DEMO_MONITOR_BYTES 320u
#define DEMO_VIDEO_BYTES 32u
#define DEMO_MAX_BOXES 100u
#define DEMO_DETECTION_BYTES (16u + 12u * DEMO_MAX_BOXES)
#define DEMO_NPU_HZ 150000000u
#define DEMO_CAMERA_FPS 30u

/* Design 3.3 leaves 0x01800000..0x03ffffff unallocated, outside TX storage. */
#define DEMO_WORKSPACE 0x01800000u
#define DEMO_WORKSPACE_BYTES (YOLO_ANCHORS * sizeof(yolo_candidate))
#define DEMO_TX_DESCRIPTORS DEMO_SEND_BASE
#define DEMO_TX_VIDEO (DEMO_SEND_BASE + 0x100u)
#define DEMO_TX_DETECTIONS (DEMO_SEND_BASE + 0x200u)
#define DEMO_TX_MONITOR (DEMO_SEND_BASE + 0x800u)
#define DEMO_MONITOR_RING (DEMO_SEND_BASE + 0x2000u)
#define DEMO_MONITOR_CAPACITY 1024u
#define DEMO_GEO_DESCRIPTOR (DEMO_SEND_BASE + 0x700u)

struct demo_monitor {
    uint32_t sequence;
    uint32_t scene;
    uint64_t time;
    struct mem_xbar_stats memory;
    uint32_t vin[4];
    uint32_t disp[2];
    uint32_t npu[4];
    uint32_t eth[2];
    uint32_t idle_cycles;
    uint32_t system_hz;
    uint32_t video_skips;
};
enum demo_command_kind {
    DEMO_HELP, DEMO_SCENE, DEMO_PIX, DEMO_GEO, DEMO_OUTPUT,
    DEMO_FPS, DEMO_SAMPLE, DEMO_STATUS
};
struct demo_command {
    enum demo_command_kind kind;
    unsigned int value;
};
enum demo_output { DEMO_HDMI, DEMO_ETHERNET, DEMO_BOTH };

/* UART boundary: exact commands listed in README; invalid input returns -1. */
int demo_parse(const char *line, struct demo_command *command);
unsigned int demo_frame_divisor(unsigned int source_fps, unsigned int requested_fps);
int demo_frame_due(uint32_t frame_id, unsigned int divisor);
void demo_monitor_pack(uint8_t out[DEMO_MONITOR_BYTES], const struct demo_monitor *record);
void demo_video_pack(uint8_t out[DEMO_VIDEO_BYTES], uint32_t frame_id,
                     uint64_t time, uint32_t scene);
size_t demo_detection_pack(uint8_t *out, const yolo_detection *boxes,
                           unsigned int count, uint32_t frame_id);
uint32_t demo_read32(const uint8_t *bytes);
/* EDNM header/length/layout validation required by design 3.5a. */
const char *demo_model_header(const uint8_t *header, uint32_t received_bytes);
#endif
