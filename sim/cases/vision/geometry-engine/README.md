# Geometry engine end-to-end simulation

Runs the autonomous geometry engine against a 256-bit AXI memory model holding
a 32x32 RGB565 source Surface. Directed frames cover a crop crossing four
16x16 tiles, clockwise 90-degree rotation and non-integer bilinear scale. Every
output pixel, destination coordinate and frame marker is checked while AXI and
the output stream experience backpressure.
Additional cases check unequal X/Y scaling before 90-degree rotation and
45-degree square corners outside the original axis-aligned image rectangle.

```sh
make case-sim CASE=vision/geometry-engine
```
