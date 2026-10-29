# B2 SoC verification environment

The environment instantiates `edrv32_soc_top` with the shared DDR, two DVP cameras,
two SCCB peers, TMDS receiver, Ethernet peer and UART model. Tests use software
built by `sw/Makefile`; all media register definitions come from the generated
`sw/bsp/include/regs/` headers. Test software uses the uncached DDR alias for
engine ownership transfers, as permitted by SoC 7.4.

Run one scenario at a time after sourcing `~/.local/opt/edrv32/env.sh`:

```sh
python3 tools/regress.py full --path verif/soc/sc_06_eth_rx -j 1
```

Each scenario has a separate result directory under `build/soc_full/`; Verilator
uses one shared `build/soc_full/obj/` directory and group `soc_full`. Generated
images and all tool outputs stay under `build/`. The runner invokes lint on the
complete testbench and its DUT, then builds the simulation with `-j 1`.
`lint.vlt` restricts exceptions to timed external-model blocking updates, unused
model instrumentation and the harness's shared asynchronous/synchronous reset.

The sys/mem/npu/pix/ETH clocks are 100/125/150/74.25/125 MHz. Camera pclk is
74.25 MHz; full 1280x720 RGB565 frames are spaced at 30 fps. VIN's two initial
sensor frames are supplied in full. ROM and SRAM preloads use the same packed
64-bit storage image convention as `soc_connect`. DDR preload files contain
byte-addressed hexadecimal data and use the DDR model's public `poke` API.
SC-01 alone executes the actual Boot ROM and downloads through the UART pins.

The software/model mailbox occupies physical DDR `0x0a3ff000` in the assigned
TX-buffer allocation. It carries only external stimulus/check requests; the CPU
accesses it through the uncached alias, and the model acknowledges through its
public `poke` API. No DUT internal data, control or interrupt signal is used for
stimulus or result comparison. SIM_EXIT observation uses the existing
`soc_connect` integration hook.

Reference frames come directly from `pix_ref.py`, `geo_ref.py`, VIN CH2's
`reference.py`, and `tools/npu/ref/npu_ref.py`. The NPU generator's random C4
input is replaced with the independently predicted CH2 image before reference
execution; the simulator does **not** preload that CH2 result. CH2 and NPU
output must actually be produced by their engines. The TMDS receiver records only during requested frame checks; its model reset
holds its capture queues empty at other times and has no connection to DUT reset.
HDMI compares every pixel of a complete captured frame; DDR compares every expected byte. ETH checks ARP
fields, UDP offsets/notifications, IPv4 checksums, EDVF fields and every Surface
byte, and all 16 EDTM records against the software's corresponding register
snapshot export. The ETH peer independently checks wire framing and FCS.

| Item | Directory | Stimulus/check |
|---|---|---|
| SC-01 | `sc_01_boot` | Normal boot, BIOS, UART download, reset and run |
| SC-03 | `sc_03_s2` | Bypass and mean 3x3, locked ring slots, HDMI and release |
| SC-04 | `sc_04_geo` | 45-degree GEO s=1 and HDMI |
| SC-05 | `sc_05_s1` | Memory-source CH0/CH2 and three NPU descriptors |
| SC-06 | `sc_06_eth_rx` | ARP, 64 KiB RX, wrong port/checksum drops |
| SC-07 | `sc_07_eth_tx` | 720p EDVF Surface and 16 EDTM records |
| SC-08 | `sc_08_concurrent` | Camera CH0/CH2, NPU loop, 720p30 TX, three scans |
| SC-09 | `sc_09_latency` | Same workload plus sequential read probe |
| SC-10 | `sc_10_media_reset` | Media reset and full-frame recovery |
| SC-11 | `sc_11_interrupts` | PLIC 8-10/12-14, RND source 11 stays clear |

SC-05/08/09 use `sc_05_s1/npu.json`: full 640x384 C4 input, three output layers
with 16 channels, K3/S2, K1/S1, and K1/S1 with residual from the first layer.
This follows the coordinator's clarification in commit `d8dc468`. SC-11 excludes
a MEM_XBAR fault trigger per clarification `74276b8`; legal SoC software cannot
produce the malformed AXI transactions that set that source.

SC-08/09 log each MEM_XBAR port as:
`PORT port rd_txn rd_beat wr_txn wr_beat wait_sum wait_max urg_cnt` (hexadecimal).
The P6 rate bound includes the specified initially full 32-token bucket:
`read_beats <= floor(window_cycles * RATE[6] / 256) + 32`.

Measured regression results and port statistics will be filled from completed
runs below.
