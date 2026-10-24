# Block Engine 15° stress test

`make case-sim CASE=vision/geometry-rot15-stress`

Default: 128×80, 15°, immediate AXI responses. The test checks every output
coordinate/marker, legal 4-KiB AXI read bursts, frame completion and errors.

Useful runtime variants:

- `+STALL=1`: periodic AR/R backpressure.
- `+SWITCH=1`: process Identity followed immediately by 15°.
- `+WIDTH=1280 +HEIGHT=720`: full board resolution. At 125 MHz, the reported
  cycle count covers the Block Engine only, not the DDR interconnect and
  destination S2MM writer.
- `+WIDTH=1280 +HEIGHT=720 +IMAGE_WIDTH=650 +IMAGE_HEIGHT=650 +ANGLE=45`:
  full-frame square-scale/rotation patch-capacity regression.
