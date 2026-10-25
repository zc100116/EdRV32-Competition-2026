# S-R1 system bus unit tests

These tests implement sys-subsys-spec sections 2.1–2.3 and the coordinator's
v0.2 APB split: AXI bridge → decoder in clk_sys, or AXI bridge → asynchronous
bridge → decoder in clk_mem. The decoder has no configuration parameter;
reserved slots are tied to ready=1, error=1, data=0 by its caller.

| Test directory | Coverage |
|---|---|
| `bus_sys_xbar` | XB-01–06: region first/last byte and following unmapped byte, both DDR windows, M0 restrictions, local DECERR including LEN=255, AW/W ordering, round robin on S0/S1/S6, independent targets and read/write directions, held responses, real ROM/SRAM latency and SRAM burst throughput, reset |
| `bus_rom` | MEM-01/02: image contents, SIZE=0–3, ROM writes including bursts return SLVERR without changing contents, R/B stalls, reset keeps data |
| `bus_sram` | MEM-03/04/05: image contents, SIZE=0–2 and all 256 WSTRB masks for each size, full/partial four-beat writes, consecutive read beats, R/B stalls, reset keeps data |
| `bus_apb_bridge` | AB-01/03/05/06: all slot addresses, both 32-bit halves, every strobe nibble, delayed ready, APB errors, invalid SIZE/alignment/LEN including LEN=255 never assert APB PSEL, SETUP/ACCESS and stalled payload checks, reset |
| `bus_apb_decoder` | AB-01/02/04/05: both system/media slot maps, reserved-slot tie-offs do not select any actual peripheral, exactly 256 ACCESS edges for timeout, ready on edge 256 wins, following transaction succeeds |
| `apb_async_bridge` | AB-07 plus media decode/errors/timeout: clk_mem/clk_sys = 0.5, 5/6, 1, 2, seeded random clock phase at each ratio, 1,024 sequential reads/writes across used/reserved slots, varied ready delays, recovery after timeout and simultaneous reset of both CDC ends |

All six `test.yaml` files select `smoke full` and both Verilator and Icarus.
The crossbar bench uses packed bus vectors for procedural dynamic indexing so
both simulators observe the same request and ready transitions before each edge.

Run only the task's tests (the coordinator requested targeted runs because of
host memory pressure; the repository-wide regression is deferred to integration):

```sh
. ~/.local/opt/edrv32/env.sh
python3 -u - <<'PY'
import tools.regress as r
results = []
for name in ('bus_rom', 'bus_sram', 'bus_apb_bridge', 'bus_apb_decoder',
             'apb_async_bridge', 'bus_sys_xbar'):
    path = r.ROOT / 'verif/unit' / name / 'test.yaml'
    fields = r.read_test(path)
    for simulator in fields['simulator'].split():
        results.append(r.run_test(path, fields, simulator, 'smoke'))
print(f'Summary: {sum(results)} PASS, {len(results)-sum(results)} FAIL')
raise SystemExit(not all(results))
PY
make lint
python3 tools/check/verilog_style.py rtl/
```

The standard regression runner imports the Icarus argument conversion from
upstream commit `ec4b8c9` (cherry-picked as `4744e98` on this task branch).
Logs are under `build/regress/smoke/unit/<test>/<simulator>/`.

The sparse `bus_rom/init.hex` and `bus_sram/init.hex` fixtures initialize the
first four and final memory words. The normal smoke test initializes the
behavioral memory from its testbench when no image argument is present.
These additional invocations exercise the wrappers' actual plusarg loading
without that testbench initialization:

```sh
build/regress/smoke/unit/bus_rom/verilator/obj/sim +ROM_HEX=verif/unit/bus_rom/init.hex
build/regress/smoke/unit/bus_sram/verilator/obj/sim +SRAM_HEX=verif/unit/bus_sram/init.hex
vvp build/regress/smoke/unit/bus_rom/iverilog/sim +ROM_HEX=verif/unit/bus_rom/init.hex
vvp build/regress/smoke/unit/bus_sram/iverilog/sim +SRAM_HEX=verif/unit/bus_sram/init.hex
```

The coordinator must add the following source entries to the shared file lists
and create the PDS IP instructions (those paths are outside this task's ownership):

```text
rtl/tech/edrv32_rom_boot.v
rtl/tech/edrv32_ram_sram.v
rtl/common/edrv32_apb_async_bridge.v
rtl/bus/edrv32_bus_sys_xbar.v
rtl/bus/edrv32_bus_rom.v
rtl/bus/edrv32_bus_sram.v
rtl/bus/edrv32_bus_apb_bridge.v
rtl/bus/edrv32_bus_apb_decoder.v
```

Both wrappers expose `clk_i`, `en_i`, `addr_i`, `rd_data_o`. ROM address width
is 11, SRAM address width is 15, and data width is 64. SRAM additionally exposes
`wr_en_i[7:0]` (one enable per byte) and `wr_data_i[63:0]`. The FPGA branches
instantiate `ip_rom_boot` / `ip_ram_sram`, using ports `clk`, `en`, `addr`,
`rd_data` and (SRAM only) `wr_en`, `wr_data`. Read latency is one cycle;
disabled outputs hold; storage and read data are not reset.

## Validation result

RTL/test commit: `14a487ce7d36119923fdfd11bb0489cce3d18b76`.
Environment: Verilator 5.020, Icarus Verilog 12.0, 2026-10-25 Linux.

| Suite | Verilator | Icarus | Checks per simulator |
|---|---|---|---:|
| bus_rom | PASS | PASS | 20 |
| bus_sram | PASS | PASS | 1555 |
| bus_apb_bridge | PASS | PASS | 829 |
| bus_apb_decoder | PASS | PASS | 70 |
| apb_async_bridge | PASS | PASS | 1037 |
| bus_sys_xbar | PASS | PASS | 514 |

The targeted `regress.run_test` commands above completed **12 PASS, 0 FAIL**,
with 4,025 response checks per simulator. The four explicit plusarg invocations
completed **4 PASS, 0 FAIL**. Each final compile log contains no warnings.
`make lint` and `python3 tools/check/verilog_style.py rtl/` report **0 warnings**
(the style scan covers 25 RTL/header files on this task branch).

The following independent `-Wall` lint invocations also completed without warnings:

```sh
verilator --lint-only -Wall -Irtl/include --top-module edrv32_bus_sys_xbar rtl/bus/edrv32_bus_sys_xbar.v
verilator --lint-only -Wall -Irtl/include --top-module edrv32_bus_rom rtl/bus/edrv32_bus_rom.v rtl/tech/edrv32_rom_boot.v
verilator --lint-only -Wall -Irtl/include --top-module edrv32_bus_sram rtl/bus/edrv32_bus_sram.v rtl/tech/edrv32_ram_sram.v
verilator --lint-only -Wall --top-module edrv32_bus_apb_bridge rtl/bus/edrv32_bus_apb_bridge.v
verilator --lint-only -Wall --top-module edrv32_bus_apb_decoder rtl/bus/edrv32_bus_apb_decoder.v
verilator --lint-only -Wall --top-module edrv32_apb_async_bridge rtl/common/edrv32_apb_async_bridge.v rtl/common/edrv32_cdc_handshake.v rtl/common/edrv32_cdc_sync_bit.v
```

System integration, full-repository smoke/full, FPGA IP generation/equivalence,
and physical timing/resource measurements remain with the coordinator and the
corresponding integration/Windows tasks.
