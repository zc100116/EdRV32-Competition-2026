# B2 SoC verification

The coordinator reduced B2-1d to SC-02 (existing), SC-05 and SC-06 after the
user's decision. SC-01, SC-03, SC-04 and SC-07 through SC-11 are archived in Git
and are no longer part of this working tree or regression discovery.

| Retained item | Directory | Current evidence | Timeout |
|---|---|---|---|
| SC-02 | `../soc_connect` | Existing connection smoke, unchanged and not rerun by this task | Existing |
| SC-05 | `../sc_05_s1` | PASS on VIN v0.3, 150.58 s total, 63.197 s simulation | 300 s |
| SC-06 | `../sc_06_eth_rx` | PASS after cleanup, 480.26 s total, 298.490 s simulation | 600 s |

The SC-05 failure is documented in
[`2026-10-29-soc-sc05-ch2-overflow.md`](../../../docs/debug/2026-10-29-soc-sc05-ch2-overflow.md).
The user approved VIN v0.3 memory-source backpressure and paced padding; its
RTL implementation was integrated in coordinator commit `40743c6`. DDR timing
and required comparisons remain unchanged. SC-06 was rerun after scope reduction
with original pre-rebase source `8934bfa` (verification content now `26a52ba`);
its regression log is `build/soc_full/reduced/sc06-regress.log`. The SoC bench
and both software programs passed lint/build checks after cleanup.

SC-05 was rerun with source `105ed67`, based on the VIN v0.3 correction.
Its full CH2 and NPU comparisons each checked 983040 bytes, at simulation times
4.430300 ms and 7.961000 ms respectively. VIN overflow/error, matching CH0/CH2
frame IDs, VIN/NPU PLIC delivery and NPU DONE_COUNT=1 all passed. The result is
`build/soc_full/reduced/sc05-postfix-regress.log`; detailed UART/model output is
`build/soc_full/sc_05_s1/run.log`. Its timeout is twice the measured total,
rounded to 300 seconds; SC-06 retains 600 seconds for its measured 480-second run.

The requested full VIN command also ran against the correction. Six directories
passed immediately; CH2 selftest first failed on an unused test-dispatch signal,
then passed its targeted rerun after a scoped lint annotation (12.79 s). All seven
directories have final passing results; the initial whole command was 6 PASS /
1 FAIL, not a clean seven-pass invocation. Detailed per-directory times, the
exact commands and VI-21b/d/e results are in
[`VIN CH2 README`](../../block/vin/ch2/README.md#修复后v03-rtl).
No stimulus or functional comparison was weakened to fix that lint warning.

## Archived tests

Commit `38c7901` contains all implemented tests before scope reduction;
`6975d9a` introduced the complete suite, `6463fa2` includes the capture-control
and boot-timeout adjustments, and `a17f1e6` adds SC-05 failure diagnostics.
The archived tests have not been accepted as passing tests.

| Item | Archived verification directory | Archived software directory |
|---|---|---|
| SC-01 | `verif/soc/sc_01_boot` | `sw/tests/soc/sc_01_boot` |
| SC-03 | `verif/soc/sc_03_s2` | `sw/tests/soc/sc_03_s2` |
| SC-04 | `verif/soc/sc_04_geo` | `sw/tests/soc/sc_04_geo` |
| SC-07 | `verif/soc/sc_07_eth_tx` | `sw/tests/soc/sc_07_eth_tx` |
| SC-08 | `verif/soc/sc_08_concurrent` | `sw/tests/soc/sc_08_concurrent` |
| SC-09 | `verif/soc/sc_09_latency` | `sw/tests/soc/sc_09_latency` |
| SC-10 | `verif/soc/sc_10_media_reset` | `sw/tests/soc/sc_10_media_reset` |
| SC-11 | `verif/soc/sc_11_interrupts` | `sw/tests/soc/sc_11_interrupts` |

Recover a selected directory from that commit for a targeted investigation:

```sh
git restore --source=38c7901 -- verif/soc/sc_03_s2 sw/tests/soc/sc_03_s2
```

The archived testbench supplements were shared under `verif/soc/common/`, and
software helpers were shared under `sw/tests/soc/`; recover the corresponding
helpers from `38c7901` as required by the selected test. No SC-08/09 port
statistics were measured before those tests were removed from scope.

| Archived item | MEM_XBAR per-port statistics | urgent count |
|---|---|---|
| SC-08 | Not measured: removed from active scope | Not measured |
| SC-09 | Not measured: removed from active scope | Not measured |

## Retained environment

The testbench instantiates `edrv32_soc_top`, DDR, two DVP cameras, two SCCB
peers, TMDS receiver, Ethernet peer and UART. The two retained scenarios use
the memory source and Ethernet pins; the TMDS capture model remains in reset.
DUT sys/mem/npu/pix/ETH clocks are 100/125/150/74.25/125 MHz. Every simulation
is built and run separately with `-j 1` in group `soc_full`.

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/regress.py full --path verif/soc/sc_05_s1 -j 1
python3 tools/regress.py full --path verif/soc/sc_06_eth_rx -j 1
```

The runner builds SRAM programs with `sw/Makefile`, preloads ROM/SRAM through
the existing 64-bit-word image convention, and preloads DDR bytes through the
model's public `poke` API. The CPU uses the uncached DDR alias for engine
ownership transfers (SoC 7.4). Generated media register definitions come only
from `sw/bsp/include/regs/`. Software ends through SIM_EXIT; UART output,
compiler/lint evidence and all generated files remain in `build/soc_full/`.

A DDR mailbox at physical `0x0a3ff000` requests external RX stimuli or complete
CH2/NPU byte comparisons. It never observes or drives DUT internal data,
control or interrupt signals. SIM_EXIT uses the existing `soc_connect` hook.
`lint.vlt` restricts exceptions to timed external-model blocking assignments,
unused model instrumentation and the harness's shared reset.

SC-05 uses the independent VIN CH2 reference and `tools/npu/ref/npu_ref.py`.
`sc_05_s1/npu.json` generates K3/S2, K1/S1 and K1/S1 plus RES_EN, each with
16 output channels; the residual source is the first layer's output. All three
OUT_ZP values are 0 to satisfy the shared-zero-point residual contract; weights,
biases, multipliers and shifts retain the generator's random values. Reference
execution consumes the predicted CH2 result, while the simulation must produce
CH2 itself; the expected CH2 image is never preloaded into its output buffer.
NPU generation/reference use the documented `~/.local/opt/edrv32-py` interpreter.

SC-06 sends ARP plus 64 KiB UDP data, with one wrong-port packet and one bad
IPv4 checksum inserted. The Ethernet peer independently checks wire framing
and FCS; the testbench checks every ARP reply field, and software checks every
received byte, WIN2_BYTES, NOTIFY through PLIC and exact filter-drop counters.
