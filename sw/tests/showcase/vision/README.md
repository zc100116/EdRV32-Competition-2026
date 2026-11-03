# Vision host tests

```
make -C sw/tests/showcase/vision test runtime
make -C sw/tests/showcase test
```

C11 builds use `-Wall -Wextra -Werror`; vision tests also use undefined-behavior
sanitization. Numerical tests compare sliced YOLO against `sw/lib/yolo_post.c`
for empty/dense OUTPUT and five fixed-seed dense/sparse pairs, checking detections,
workspace and operation counts exactly. They also check sparse EDNM and EDDT bytes.

Runtime tests execute production vision logic with mocked hardware boundaries:
camera/CH2 pairing, VRN without PIX/GEO, pause/resume, L0 submission followed by
SWITCH / REL_BASE slot release, layer disable release, two upload slots, VIN DDR
CH2 completion before NPU, rejected/busy ETH submission, all-three TX completion,
PIX/GEO parameter changes, original view and deferred model/image BULK completion.
GUI descriptor reads cannot release the scanned frame. Scheduler tests separately
prove that a static GUI does not delay application slices and due GUI work does.

Host tests establish behavior and numerical equivalence, not FPGA latency.
Artifacts remain under `build/sw/showcase/vision/` and `build/sw/tests/showcase/`.
