# Texture unit tests

`generate.py` calls `tools/gpu/model/texture.py` for every expected sample and the
model arithmetic helpers for LOD and vertex modulation. It creates 384 descriptor
cases and 13,248 four-pixel groups; generated files stay under `build/`.

Run on the user-provided simulation host, from the repository root:

```sh
/usr/bin/python3 tools/regress.py full --path verif/unit/gpu_texture -j 1
/usr/bin/python3 tools/regress.py full --path verif/unit/gpu_texture_ram -j 1
/usr/bin/python3 tools/regress.py full --path verif/unit/gpu_palette -j 1
```

Coverage includes all three formats and modes, every mip level through 1×1,
rectangular padding, all width/height powers from 8 through 256, signed wrapping,
LOD zero/96-bit extremes/table fractions/bias/clamping, pixel-center 1:1 bilinear,
all palette groups, preload response backpressure, output backpressure, empty
completion, and stop with work in flight. Directed nearest batches cover four
unique words in one bank, three words, two words and one shared word; each
128-group stream must produce exactly 64 PERF5 events. Nine 512-group streams
measure 4/2/1 pixel-per-cycle throughput for I4, I8 and RGB565 independently;
filtered performance streams use arbitrary UV coordinates.

`texture_ram` checks every physical row on both read ports of all four banks,
the 96 KiB boundary, final physical beat, byte keeps and accepted writes at stop.
`palette` checks all full-table entries on four arbitrary-group ports and all
256 entries on eight current-group ports after each of sixteen group preloads.

Integration uses separate texture/RAM/palette instances, shared finish and stop,
and the AND of their three `unit_done` signals. Internal read ports have no
backpressure: texture reserves a result context before issuing each request.
Texture addresses are bank-major, two 15-bit rows and two 16-bit results per bank;
read latency is five clocks. Full/current palette latencies are four clocks.
