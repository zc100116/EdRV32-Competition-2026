# Geometry frame scheduler

Checks the low-latency ownership policy: one active frame, one latest pending
frame, immediate release of stale pending buffers, and lossless handling when
active completion coincides with pending replacement.

```sh
make case-sim CASE=vision/geometry-frame-scheduler
```
