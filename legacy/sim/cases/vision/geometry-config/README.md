# Geometry hardware configuration simulation

Validates the autonomous geometry setup path: synchronous Q2.16 trig ROM,
iterative independent X/Y ratio calculation, clockwise inverse rotation,
crop centering, horizontal/vertical flip and launch of the Q16.16 coordinate
walker.  The 90-degree case also drains the walker with randomized
backpressure and checks every generated source coordinate.  Additional cases
check a centered image rectangle with unequal X/Y ratios, rotation combined
with non-uniform scaling, and reuse of the cached matrix.

```sh
make case-sim CASE=vision/geometry-config
```
