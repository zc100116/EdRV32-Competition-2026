# Color Bar → DDR → HDMI directed test

This case reduces the raster to 128x72 while retaining the production datapath:

1. the RGB565 color-bar writer emits full-width AXI bursts;
2. the DDR interconnect routes them into the 256-bit memory model;
3. the HDMI reader loops over the completed framebuffer;
4. `edrv32_hdmi_fifo` selects the common RTL asynchronous FIFO in `SIM_MODE`;
5. the pixel-domain scanout checks two complete active frames;
6. the TMDS encoder is elaborated behind the checked RGB stream.

The testbench also writes `colorbar_ddr.ppm` from decoded DDR RGB565 words and
`colorbar_hdmi.ppm` from the HDMI RGB888 active stream. Render and compare them
with:

```sh
python sim/cases/vision/colorbar-ddr-hdmi/render_images.py <simulation-output-dir>
```

Run with:

```sh
make case-sim CASE=vision/colorbar-ddr-hdmi
```
