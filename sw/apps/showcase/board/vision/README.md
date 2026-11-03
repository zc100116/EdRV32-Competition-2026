# Showcase vision backend

Implements design 4.3/4.5: camera VIN CH0 + CH2 → NPU → sliced integer YOLO,
CPU CH2 adaptation for uploaded RGB565 images, and seven PIX/GEO processing modes.
The camera path runs on VRN without accessing PIX/GEO. The image application requires
NPU + ETH and does not require VIN. No application callback waits for hardware.

## BOARD integration

Include `board/vision/program.mk`, remove the integration-only vision stub, and register:

| Application table object | Required hardware | Exclusive display |
|---|---|---|
| `vision_app_camera` | VIN + NPU | no |
| `vision_app_image` | NPU + ETH | no |
| `vision_app_process` | VIN + PIX + GEO | no |

The objects provide enter/step/exit. BOARD selects the corresponding UI page.
Call `vision_init()` once before starting the scheduler, after the platform clock and
hardware probes are available. This is the only entry point that performs blocking
OV5640 I2C initialization. Initial NPU configuration uses the demo's 68-descriptor
preloaded model; subsequent EDNM uploads replace it.

BOARD owns interrupt registration and calls `vision_irq(event, context)`, with
`context = (void *)(uintptr_t)ENGINE_*`, then wakes the application task:

| Engine | Enabled IRQ masks |
|---|---|
| VIN | `ERROR`, `FRAME`, `CH2_FRAME` |
| NPU | `ERROR`, `DONE` |
| PIX, when present | `ERROR` |
| GEO, when present | `ERROR`, `DONE` |

These names refer to the generated `EDRV32_<engine>_IRQ_EN_<name>_MASK` constants.
The callback only latches flags/errors. ETH remains owned entirely by BOARD.
Call `vision_service()` in application-task context, including after a page has exited,
until it returns zero. A nonzero return requests another application-task slice; do not
run it in the communication task. Camera frame IRQs wake it again after it becomes idle.

`vision_bulk_done(kind, base, bytes)` returns `uint32_t`: 0 accepts asynchronous work,
1 reports a length error, 2 reports an EDNM format error. Kinds 1/2 mean model/image.
EDNM retains offsets 0 / 0x1000 / 0x100000; transmitted gaps are zero filled and total
length is `0x100000 + model_bytes`. Only the old demo header fields are validated;
NPU reports invalid operators and shapes. `vision_camera()` requests a source switch.
BOARD keeps BULK window 0 closed and defers successful EDSC DONE until vision invokes
`board_bulk_complete(kind)` after model loading or the entire image result transmission.
Only one BULK may be outstanding, as specified by the EDSC protocol.

BOARD supplies `int board_eth_send(uint32_t descriptors, uint32_t count)` and
`void board_bulk_complete(unsigned kind)` in `board.h`. Send returns 0 while another
batch owns ETH and 1 after accepting this batch. Its busy flag must remain set until
**all** descriptors complete. Image replies retain the demo/yolo.py order:
CH2 on window 0, OUTPUT on window 1, then EDDT on window 2 with NOTIFY.
Each accepted image retains its receive base/length until TX completes and reopens that
specific window configuration; there is no global `image_window`.

## GUI and DDR ownership

`ui_data_vision(bool)` and `ui_data_process(unsigned mode)` return persistent RGB565
LVGL descriptors with 1280×720 dimensions and 2560-byte stride, backed by uncached DDR.
The shared UI scales these images to 960×540 and draws the first five detections;
the total count and the five category counts cover all detections. Box coordinates
are converted to the 960×540 viewport.

BOARD calls `vision_frame_presented()` after LVGL `LV_EVENT_RENDER_READY`, when all
RND source reads have completed. A displayed slot remains busy until a newer descriptor
has been returned and a subsequent presented callback has occurred. Exit retires the
old page's source until the replacement page has rendered. Ready, inference, GEO and
GUI consumers retain separate reference bits; VIN receives their combined busy mask.
The GUI must refresh the processing image periodically using the selected mode.

The inherited frame/model/workspace allocations are in `memory.h`. Private TX storage
starts at physical `0x0a180000`: descriptors at +0, EDDT at +0x200, GEO descriptor at
+0x700. BOARD's own TX/monitor allocation ends at `0x0a17ffff`.

## Validation

Host tests and commands are in `sw/tests/showcase/vision/README.md`. All four production
C files pass RV32 C11 `-Wall -Wextra -Werror -fsyntax-only`. No UI source is changed here;
validation uses BOARD's concurrently updated `ui_data_process(unsigned)` contract.

Decode slices contain at most eight anchors within a single head row. Heap construction
and extraction process one root per slice; NMS processes sixteen comparisons per slice.
CPU CH2 handles one 640-pixel output row per slice. Image/model copies handle 1024 bytes
per slice. Host tests prove exact numerical equivalence and ownership transitions;
actual maximum step duration, including the ≤5 ms target, still requires FPGA measurement
using the scheduler's maximum-step counters.
