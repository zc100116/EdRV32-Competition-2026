# EQ-01: NPU SIMD cascade equivalence

Run from the repository root with Icarus Verilog 12.0:

```sh
. ~/.local/opt/edrv32/env.sh
export EDRV32_PANGO_SIM_DIR="$HOME/.local/share/edrv32/pango"
flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/unit/npu_mac_chain -j 1
```

`EDRV32_PANGO_SIM_DIR` must contain the unmodified vendor `GTP_APM_E2.v`.
An unset variable terminates with an explicit error. The model stays outside
Git; the runner compiles it from that directory. The test supplies the vendor
model's `GRS_INST.GRSNET` hierarchical reference.

The runner compiles both committed wrappers twice, retaining each SIM_MODE branch
and renaming a second copy to select its FPGA branch. The generated FPGA head
copy exposes only the unused vendor CPI as a test probe; random nonzero CPI must
be ignored by MODEZ=0 while its P/CPO match the head SIM model each cycle. The test compares each
SIM CPO against the matching FPGA CPO, and both wrappers' P outputs against
vendor P after every rising edge's settling interval. A single cell receives
arbitrary CPI values, including positive and negative 24-bit wraparound. A head followed by seven chain cells receives operands skewed
by their stage index and accumulate through independent reference/DUT chains.
The last cell's P is also checked against a scalar signed sum delayed ten
edges. Both lanes cover random inputs and repeated −128/127 extremes over
1012 clocks; 1003 completed dot products are checked.

Generated wrapper copies, executable and direct-run artifacts are under
`build/npu_mac_chain/`; regression logs are under
`build/regress/{smoke,full}/unit/npu_mac_chain/iverilog/`.
