# Showcase vision backend

Implements P5 design 3.1–3.4 and 8.1–8.6. VIN CH0 supplies full-screen L0 camera frames;
CH2 supplies NPU inputs. Uploaded RGB565 images use VIN's DDR input path for CH2
and are scanned directly from the upload slot. There is no CPU CH2 or video BLIT.
The camera application requires VIN + NPU, image recognition VIN + NPU + ETH,
and processing VIN + PIX + GEO. NPU/CH2 and TX wait cooperatively; CPU sorting/NMS remains sliced.

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
all three image TX descriptors: CH2 / candidates / EDDT. The EDSC single-BULK contract
retains the source until processing and transmission finish; cancellation after CH2 releases
its JOB/READY references immediately, while DISP ownership still waits for SWITCH.

`ui_data_process_config/set/defaults` expose PIX brightness, contrast Q8, gamma,
two 3×3 stages, grayscale/binary/invert, and GEO rotation, scale, translation and
mirrors. Gamma is computed one sample per CPU slice, then written into the inactive bank. Matrices use
`sw/lib/geo_matrix.c`; scale is displayed as output/input (50–400%). PIX shadow
registers apply at SOF; GEO descriptors retain their matrix for the submitted job.
Original view bypasses both engines, and the L1 parameter panel can be collapsed.

P5 sessions retain per-application results and image metadata; the shared pipeline
owns capture, inference, postprocessing and display references. Session callbacks
poll STARTING, PAUSED and STOPPING completion. Pausing drains the current NPU job
and freezes L0; stopping waits for VIN/PIX/GEO and L0 release. An image cancellation
does not interrupt NPU, and a following upload can wait for the cancelled job to drain.
EDDT offset 12 carries the image BULK_BEGIN sequence. Every image is preceded by
IMAGE_INFO; board image navigation emits IMAGE_STEP only outside receiving/detecting.

Each processing stage uses its own `enabled` bit. Disabling preserves parameters;
`ui_data_process_defaults(stages)` resets selected parameters, with ALL also clearing
the enable mask. PROCESS completion while RUNNING waits for a captured frame with the new revision;
in other states parameters are saved and acknowledged immediately. DETECT completes
after a GUI-consumed configuration reaches the next L1 SWITCH when recognition runs.
NPU runs class selection, thresholds and DFL. Candidate buffers at 0x05100000 and
0x05120000 each reserve 120960 B. Before DOORBELL, BSP cleans the whole selected
buffer; after successful DONE, CPU invalidates ceil(POST_COUNT*24/32)*32 B.
The saved count/input/frame belong to that buffer until sorting/NMS finishes.
UI threshold 0.50 and class whitelist filter presentation copies only.

The once-per-second `vision` record uses P5 8.6 field names and recent-window averages:
`fps npu wait decode sort nms post_span gui e2e cpu_comm cpu_app cpu_gui`.
`decode` now means candidate cache acquisition, optional pre-NMS TX snapshot and
CPU handoff, not class selection/DFL. `npu` includes hardware postprocessing and
the final candidate write response. EDTM NPU/post fields keep their wire offsets;
post CPU time now covers candidate processing, sorting/NMS and mapping.
VIN and NPU completion timestamps come from IRQs. GUI completion is the first L1
SWITCH after `ui_data_vision()` consumes new boxes, as agreed with the coordinator;
gui includes the wait before consumption. UART emission shares the existing CPU report.

On F CPU125 hardware, check post-processing ≤35 ms and upload completion to DONE
≤300 ms. Host numerical/ownership tests cannot establish FPGA timing.
The working-memory allocation is in `memory.h`; BOARD/vision TX partitions are in
`../ddr_map.h`. Initial NPU configuration retains the demo's preloaded 68-descriptor
model, and EDNM uploads preserve sparse offsets 0 / 0x1000 / 0x100000.

Run `make -C sw/tests/showcase/vision test runtime` for numerical and runtime tests.

Candidates are sorted by Q24 probability descending and anchor ascending, then
class-aware NMS uses unclipped Q8 boxes and strict IoU >0.45, retaining at most 100.
Letterbox mapping/clipping follows suppression. Previous-frame CPU work overlaps
the next NPU frame using the other candidate buffer; completed hardware results
wait for the CPU job to release its buffer. No 725760 B RND COPY or POST raw buffer
remains. `copy=` stays zero and `period=` still measures consecutive NPU starts.

Image-check channel 1 sends little-endian u32 count followed by count*24 B records,
without NOTIFY, from a pre-sort snapshot at 0x05140000. This snapshot is uncached
CPU/TX storage and stays owned through final TX DONE. Channel 0 remains CH2 and
channel 2 remains complete EDDT. Raw box/debug OUTPUT layout offsets remain fixed;
normal POST_CTRL=1 disables raw cls, which software never reads.

The embedded model is regenerated with POST labels/LUTs by the compile_yolo.py
--model-source build rule. Upload the same build/npu/software_model directory.
