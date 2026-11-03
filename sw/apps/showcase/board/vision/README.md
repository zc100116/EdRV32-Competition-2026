# Showcase vision backend

Implements design 4.6.1–4.6.2. VIN CH0 supplies full-screen L0 camera frames;
CH2 supplies NPU inputs. Uploaded RGB565 images use VIN's DDR input path for CH2
and are scanned directly from the upload slot. There is no CPU CH2 or video BLIT.
The camera application requires VIN + NPU, image recognition VIN + NPU + ETH,
and processing VIN + PIX + GEO. Application callbacks never wait for hardware.

`vision_irq` latches accelerator flags, while `vision_display_irq` latches DISP flags.
`vision_service` runs in application-task context, including after page exit.
L0 submissions occur after FRAME; only SWITCH / REL_BASE (or stopped DISP IDLE)
release scanned surfaces. VIN pairing, inference, ready, display and GEO retain
separate reference bits. LVGL only draws ARGB8888 L1 and detection objects at native
1280×720 coordinates; GUI rendering does not retain or release video slots.

`vision_upload_base()` returns a free 2 MiB upload slot at `0x08000000` or `0x08200000`,
or zero when both remain owned. BOARD reserves this address at BULK_BEGIN and replies
DONE(status 3) if neither is free. `vision_bulk_done` returns 0 for asynchronous work,
1 for a length error, 2 for invalid EDNM. Successful DONE follows model loading or
all three image TX descriptors: CH2 / OUTPUT / EDDT. The EDSC single-BULK contract
retains the source until processing and transmission finish.

`ui_data_process_config/set/defaults` expose PIX brightness, contrast Q8, gamma,
two 3×3 stages, grayscale/binary/invert, and GEO rotation, scale, translation and
mirrors. Gamma is computed on CPU into the inactive bank. Matrices use
`sw/lib/geo_matrix.c`; scale is displayed as output/input (50–400%). PIX shadow
registers apply at SOF; GEO descriptors retain their matrix for the submitted job.
Original view bypasses both engines, and the L1 parameter panel can be collapsed.

Serial records use the runtime system clock:

- `vision npu_ms=... post_ms=... display_fps=...` once per second of results;
- `image receive_ms=... ch2_ms=... npu_ms=... post_ms=... return_ms=...
  upload_to_done_ms=...` for each image.

On F CPU125 hardware, check post-processing ≤35 ms and upload completion to DONE
≤300 ms. Host numerical/ownership tests cannot establish FPGA timing.
The working-memory allocation is in `memory.h`; BOARD/vision TX partitions are in
`../ddr_map.h`. Initial NPU configuration retains the demo's preloaded 68-descriptor
model, and EDNM uploads preserve sparse offsets 0 / 0x1000 / 0x100000.

Run `make -C sw/tests/showcase/vision test runtime` for numerical and runtime tests.
