# SC-05: CH2 overflows with the standard SoC DDR model

## 1. Phenomenon

The full SoC SC-05 memory-source test reports VIN `ERR_CODE=3` (CH2 FIFO
 overflow) before CH2 can publish its completed frame. The test has enabled
CH0 and CH2 for the same preloaded 1280x720 RGB565 source. DISP, NPU and ETH
have not started; CPU configuration and polling are the only other activity.

This is a confirmed integration-test failure against the original v0.2 flow
contract: VIN 2.8 permitted CH2 to drop even a memory-source frame when its
FIFO filled, while soc-testplan SC-05 requires a complete CH2 frame for NPU
input. The coordinator confirmed the cause and the user changed the contract
to VIN v0.3 in specification commit `6537bc8`: memory-source CH2 must apply
backpressure, and letterbox padding must wait for write-FIFO space.

## 2. Reproduction

Original pre-rebase source commit: `2a2a18a06de4ff9a857b4584a7f6ff8006c6f9f0`.
The same verification content is now in `a17f1e6`, whose rebased ancestry
already contains the RTL correction. To reproduce with reachable history in a
temporary checkout, start at `6537bc8` (specification v0.3, pre-fix RTL), restore
`verif/soc/` and `sw/tests/soc/` from `a17f1e6`, then run the command below.
Simulator: Verilator 5.020, Debian 5.020-1; C++ optimization `-O2`; one simulation.
NPU generator seed: 42 (the NPU has not started when this failure occurs).

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/regress.py full --path verif/soc/sc_05_s1 -j 1
```

The complete regression took 111 seconds. Tool logs are under
`build/soc_full/sc_05_s1/`; the regression log is
`build/regress/full/soc/sc_05_s1/verilator/run.log`.

## 3. Observations

The DDR model uses its default timing: `T_HIT=8`, `T_MISS=4`, `T_TURN=3`,
`T_REFI=975`, `T_RFC=38`, `T_B=2`, in 125 MHz memory-clock cycles.
No injected backpressure, malformed transactions or response errors are used.
The pixel input is the VIN CH2 independent reference's full-size variant zero;
its physical DDR address is `0x08000000`, stride 2560 bytes.

Software polling produced this exact UART diagnostic:

```text
FAIL position=VIN ERR_CODE expected=00000000 actual=00000003 mtime=0009f23b
```

The diagnostic samples mtime after printing its first fields, so it is **not**
the precise first overflow time. Software eventually writes SIM_EXIT=1 at
`8862265000 ps` (8.862265 ms), after draining the diagnostic UART message.
The completion wait has not yet issued the external CH2 comparison command,
and NPU DOORBELL has not been written. The test's preliminary run without
this polling diagnostic waited for the missing completion and was stopped;
that run is not counted as a completed regression.

## 4. Root cause

Confirmed interface-level cause: VIN reports the specified CH2 overflow error,
so the SC-05 requirement of a completed input frame is not met under this
SoC environment. VIN 2.8 and 6 define that code and permit this drop for
memory-source frames. The reason the real P1 path cannot absorb this traffic
has not been investigated inside the DUT: the independent worker does not
read RTL. No internal FIFO timing or arbitration defect is asserted here.

## 5. Fix

This worker made no RTL or model changes. The software completion loop checks VIN overflow/error
state and fails with expected/actual values instead of waiting for a frame
that cannot complete. The DDR timing, source traffic and passing criterion remain intact. RTL
implementation of the user-approved v0.3 contract was integrated separately
in coordinator commit `40743c6`. The verification branch has been rebased onto
that correction for the full VIN regression and SC-05 rerun.

## 6. Regression

The rerun against coordinator correction `40743c6`, with verification source
`105ed67`, passed in 150.58 s total (63.197 s simulation execution). Command:

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/regress.py full --path verif/soc/sc_05_s1 -j 1
```

The full-sized CH2 byte comparison, matching CH0/CH2 frame IDs, VIN/NPU PLIC
checks, NPU DONE_COUNT=1 and three-layer NPU byte comparison all passed.
The coordinator approved setting all three NPU OUT_ZP values to 0 for the
residual contract; weights, biases, multipliers, shifts and full case size
remain as generated with seed 42. Expected CH2 data is used only by the
independent reference, never preloaded into the simulated CH2 output buffer.

```text
CHECK DDR ch2 bytes=983040 address=04000000 time=4430300000
CHECK DDR npu bytes=983040 address=05000000 time=7961000000
PASS SC-05
```

Times in this log are ps. The regression log is
`build/soc_full/reduced/sc05-postfix-regress.log`; UART/model output is
`build/soc_full/sc_05_s1/run.log`. The final test timeout is 300 s based on
the measured 150.58 s total. VIN module regression details, including the
unchanged VI-21b/d failure assertions now passing, are recorded in
`verif/block/vin/ch2/README.md`.

## 7. Similar paths

SC-08/09 also specify CH0 plus CH2 with a camera source, but the user removed
those tests from this task before they were run. Their archived prototypes
and lack of measured statistics are recorded in `verif/soc/common/README.md`.
The existing module-integration history is documented in
`2026-10-29-vin-ch2-integration.md`; it describes a separate test with random
P1 stalls, whereas this SoC test uses the required DDR timing model defaults.
