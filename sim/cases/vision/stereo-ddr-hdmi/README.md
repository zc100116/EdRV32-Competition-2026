# Stereo OV5640 stream → display DDR → HDMI directed test

This reduced 32×8 test drives two independent 8-bit DVP camera streams. It
checks multiple asynchronous frames from both receivers, the selected stream writes directly
to the triple-buffered display pool, a debounced button selects the right
camera at a frame boundary, and HDMI changes source only after a completed
display page. It also rejects any AXI access outside the three display-buffer
ranges. Camera raw buffers and the former DDR-to-DDR composer are not in the
display path.

The test emits `stereo_left_hdmi.ppm`, `stereo_right_hdmi.ppm`, and
`stereo_pixel_gray_hdmi.ppm` from active HDMI pixels. The third image proves
that a toggle-handshaked pixel configuration commits on a camera frame
boundary and reaches DDR/HDMI without disturbing page flipping.

Render and verify them with:

```sh
python sim/cases/vision/stereo-ddr-hdmi/render_images.py \
  sim/build/modelsim/cases/vision/stereo-ddr-hdmi
```

Run with:

```sh
make case-sim CASE=vision/stereo-ddr-hdmi
```
