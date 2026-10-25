# Geometry AXI writer simulation

Validates a 400-pixel row beginning at address 0x0f00. The writer must split it
into 8, 16 and 1-beat bursts so no transaction crosses the 4-KiB boundary and
no burst exceeds 16 beats. DDR contents and abort recovery are also checked.

```sh
make case-sim CASE=vision/geometry-axi-writer
```
