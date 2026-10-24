# Geometry RGB565 bilinear simulation

Checks the fixed bilinear arithmetic against a software integer reference,
including exact corners, fractional interpolation, fill pixels, metadata,
continuous input traffic, randomized output backpressure and payload stability.

```sh
make case-sim CASE=vision/geometry-bilinear
```
