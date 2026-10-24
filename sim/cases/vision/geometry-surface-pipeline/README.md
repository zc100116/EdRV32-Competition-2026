# Geometry Surface-to-Surface pipeline simulation

Connects both Geometry AXI masters to one memory model and validates complete
DDR read, crop/rotation, bilinear, RGB565 packing, bounded write bursts, row
stride and partial-tail WSTRB behavior. Identity, clockwise 90-degree, and
centered half-width image frames are checked in destination DDR.  The latter
checks black side borders and the first/last active source columns.

```sh
make case-sim CASE=vision/geometry-surface-pipeline
```
