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
P5 adds OUTPUT invalidation/cached reads, independent bypass with retained parameters,
selective/all defaults, per-image request encoding and cancellation immediately followed
by another upload while the old NPU job drains.
GUI descriptor reads cannot release the scanned frame. Scheduler tests separately
prove that a static GUI does not delay application slices and due GUI work does.

Host tests establish behavior and numerical equivalence, not FPGA latency.
Artifacts remain under `build/sw/showcase/vision/` and `build/sw/tests/showcase/`.

T-DEMO-PAGES: `make -C sw/tests/showcase/vision models` executes one real evaluation
image per gesture/face/helmet model through `models_eval.integer`, then the
production C post/keypoint decoder (coordinate error <= 0.5 px). It also checks
three-frame class debounce, interrupted candidate runs and missing hands.
Runtime covers six embedded snapshots, new model selection and detect restoration,
independent camera/memory source IDs, retained read slots, threshold reconfiguration,
and counting each result only at its first actual L1 presentation.
`make -C sw/apps/showcase/sim demos` captures all four pages from those C-verified
fixtures; models/data remain prerequisites from the NPU evaluation setup.
