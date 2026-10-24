# Geometry AXI tile reader simulation

Exercises randomized AR stalls, multiple outstanding single-beat rows, reverse
RID return order, row-output backpressure, a partial bottom tile completed with
local zero rows, and rejection of an out-of-range tile request.

```sh
make case-sim CASE=vision/geometry-tile-reader
```
