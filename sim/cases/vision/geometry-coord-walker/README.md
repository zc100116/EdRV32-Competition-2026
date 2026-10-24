# Geometry coordinate walker simulation

Validates the Q16.16 inverse-map raster walker used by the future Geometry
Surface DMA. Directed cases cover identity/crop, fractional downscale, horizontal
and vertical flip, 90-degree rotation, fractional coordinates, negative source
coordinates, bounds flags and randomized output backpressure.

```sh
make case-sim CASE=vision/geometry-coord-walker
```
