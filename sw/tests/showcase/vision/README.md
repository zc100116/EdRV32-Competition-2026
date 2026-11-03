# Vision host tests

After integrating BOARD's `ui_data_process(unsigned mode)` contract and initializing
the LVGL submodule, run:

```sh
make -C sw/tests/showcase/vision test runtime
```

Both executables use C11 `-Wall -Wextra -Werror` and undefined-behavior sanitization.
`test` compares sliced YOLO with `sw/lib/yolo_post.c` for empty/dense OUTPUT and five
fixed-seed dense/sparse pairs: all detections, sorted/suppressed workspace entries,
and operation statistics match exactly. The coordinator authorized generated OUTPUT
because this repository does not contain saved NPU OUTPUT reference files.
It also checks sparse EDNM framing, exact EDDT bytes and all 384 CPU CH2 rows.

`runtime` executes production `vision.c` with mocked hardware/BOARD services. It checks
camera pairing, VRN absence of PIX/GEO accesses, render-completion slot retirement,
pause/resume, image CH2 without VIN, rejected/busy TX submission, all-three-descriptor
TX completion, distinct per-image receive windows, seven PIX/GEO modes, sparse model
copy including tail bytes, upload status values and deferred BULK completion.
All cases pass. No FPGA timing claim is derived from these host tests.

Parallel-worktree validation on 2026-11-03 used the existing LVGL checkout and BOARD's
updated header without editing either dependency:

```sh
make -C sw/tests/showcase/vision test runtime \
  LVGL_ROOT=/home/workspace/orca/workspaces/EdRV32-Competition-2026/b3-int/third_party/lvgl \
  UI_CONTRACT=/home/workspace/orca/workspaces/EdRV32-Competition-2026/task-show-board/sw/apps/showcase/ui/ui_data.h
```

RV32 syntax validation (zero warnings/errors):

```sh
. /home/workspace/.local/opt/edrv32/env.sh
riscv-none-elf-gcc -std=c11 -march=rv32im_zicsr -mabi=ilp32 \
  -Wall -Wextra -Werror -fsyntax-only -DLV_CONF_INCLUDE_SIMPLE \
  -I/home/workspace/orca/workspaces/EdRV32-Competition-2026/b3-int/third_party/lvgl \
  -Isw/apps/showcase/lvgl -Isw/drivers/include -Isw/bsp/include -Isw/lib \
  -Isw/lib/sched -Isw/apps/showcase/board/vision -Isw/apps/showcase/board \
  -Isw/tests/showcase/vision \
  -include /home/workspace/orca/workspaces/EdRV32-Competition-2026/task-show-board/sw/apps/showcase/ui/ui_data.h \
  sw/apps/showcase/board/vision/*.c
```

The syntax check uses the mock BOARD header only for the two frozen BOARD function
prototypes. Tests/build outputs remain under `build/sw/showcase/vision/`.
