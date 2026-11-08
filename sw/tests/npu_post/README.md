# PP-SW-01/02

`prepare.py` generates build/npu/post_sw/data/ddr.hex and data.h using
`tools/npu/yolo_post_ref.py`. Two INPUT tensors feed six fixed-shape identity CONV
heads, with normal exp/probability LUTs and descriptor POST_KIND/HEAD_ID labels.
The two synthetic frames have 126 hardware candidates and 100 expected detections;
the real COCO frame from board_npu has 37 candidates and five detections. Complete
pre-NMS candidates and EDDT header/entries are compared, associating candidates by
anchor because hardware enqueue order is independent of oracle traversal.

PP-SW-01 also tests 128 directed Q8 records: strict IoU .45 and one Q8 unit either
side, different classes at identical boxes, probability/anchor ties, negative
coordinates and the 100-box cap. They enter the same production CPU candidate
API; only the identity-head frames exercise NPU generation. UI 0.50/whitelist
presentation filtering also runs against the real frame in PP-SW-01.

PP-SW-02 dirties both entire candidate regions, transfers ownership using BSP,
processes frame zero while frame one runs, and reuses the sorted dirty first
region. The SoC bench observes cache maintenance address/size, clean before
DOORBELL, full-line invalidation after DONE, and CPU candidate requests including
cache hits; CPU access during DMA ownership fails the simulation.

```sh
. ~/.local/opt/edrv32/env.sh
make -C sw PROGRAM=board_npu -j 1
python3 sw/tests/npu_post/host_test.py
make -C sw PROGRAM=pp_sw_01 -j 1
make -C sw PROGRAM=pp_sw_02 -j 1
flock /tmp/edrv32-sim.lock python3 verif/soc/pp_sw_01/run.py
flock /tmp/edrv32-sim.lock python3 verif/soc/pp_sw_02/run.py
```

The runners build Verilator with -Wall and -j 1 and load ROM/SRAM/DDR through the
standard SoC image interfaces. Run each scenario once after postprocessing RTL
integration; current software-task acceptance builds them without simulation.
Logs stay in build/npu/post_sw; no FPGA measurements are claimed.
