# SC-05: CH2 overflows with the standard SoC DDR model

## 1. Phenomenon

The full SoC SC-05 memory-source test reports VIN `ERR_CODE=3` (CH2 FIFO
 overflow) before CH2 can publish its completed frame. The test has enabled
CH0 and CH2 for the same preloaded 1280x720 RGB565 source. DISP, NPU and ETH
have not started; CPU configuration and polling are the only other activity.

This is a confirmed integration-test failure. Its classification as an RTL
problem or a missing testplan traffic precondition is awaiting the coordinator:
VIN 2.8 permits CH2 to drop even a memory-source frame when its FIFO fills,
while soc-testplan SC-05 requires a complete CH2 frame for NPU input.

## 2. Reproduction

Source commit: `2a2a18a06de4ff9a857b4584a7f6ff8006c6f9f0`.
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

No RTL or model change. The software completion loop checks VIN overflow/error
state and fails with expected/actual values instead of waiting for a frame
that cannot complete. Coordinator clarification is required before changing
the traffic setup or passing criterion.

## 6. Regression

SC-05 retains the full-sized CH2 byte comparison, matching CH0/CH2 frame IDs,
PLIC checks and three-layer NPU byte comparison. They remain pending because
this run fails earlier; none was removed or bypassed.

## 7. Similar paths

SC-08/09 also use CH0 plus CH2 and will be run with their specified camera
source. Camera overflow is explicitly prohibited in their concurrency load.
The existing module-integration history is documented in
`2026-10-29-vin-ch2-integration.md`; it describes a separate test with random
P1 stalls, whereas this SoC test uses the required DDR timing model defaults.
