# DDR gateway unit tests

`test.yaml` registers GW-01/02/03 in smoke, inherited by full. Full adds `nominal/`
(150/125 MHz), `equal/` (125/125 MHz), and `slow_sys/` (75/125 MHz), each with
GW-04/05 enabled. All configurations run in Verilator and Icarus. The byte-array
AXI256 slave and independent reference memory live in `tb_mem_ddr_gw.sv`.

| Test | Checks |
|---|---|
| GW-01 | Both virtual windows, physical aliases, 4-to-1 writes, 1-to-4 reads, all-byte strobes, beat order |
| GW-02 | SIZE 0–3 at every naturally aligned byte position in a 32-byte line; complete 64-bit read-lane selection and byte preservation |
| GW-03 | Unsupported LEN (including 255), SIZE, BURST, and alignment; no downstream transfer; exact LEN+1 read errors and write drain before B |
| GW-04 | Second AR/AW held valid while upstream R/B is blocked; no second acceptance or downstream request; opposite direction still completes; original IDs returned |
| GW-05 | 160 random write/read pairs per frequency ratio, random aliases, addresses, sizes, IDs, data, all response codes and independent channel stalls |

Smoke also tests all four downstream response codes, held-payload stability,
reset inactivity and reset with both directions in flight. The fixed random seed
is `0x05f82a91`. Assertions and protocol checks are confined to the testbench.
The zero-wait measurement samples 24 cache-line reads with varied request phase;
ARREADY and upstream RREADY remain high, and the slave makes RVALID available
immediately after the AR handshake, allowing R transfer at the next mem edge.

To reproduce only this Task's tests using the repository regression functions,
without launching the other repository tests:

```sh
. ~/.local/opt/edrv32/env.sh
python3 -u - <<'PY'
from pathlib import Path
import tools.regress as r
original_command = r.command

def serial_command(args, log, timeout):
    if args[0] == 'verilator':
        args = args[:1] + ['-j', '1'] + args[1:]
    return original_command(args, log, timeout)

r.command = serial_command
results = []
for name in ['axi_async_bridge', 'mem_ddr_gw']:
    for path in sorted((Path('verif/unit') / name).rglob('test.yaml')):
        fields = r.read_test(path)
        tier = 'smoke' if path.parent.name == name else 'full'
        for simulator in fields['simulator'].split():
            results.append(r.run_test(path.resolve(), fields, simulator, tier))
print(f'Summary: {sum(results)} PASS, {len(results) - sum(results)} FAIL')
raise SystemExit(0 if all(results) else 1)
PY
make lint
python3 tools/check/verilog_style.py rtl/
verilator --lint-only -Wall --top-module edrv32_mem_ddr_gw \
  rtl/common/edrv32_async_fifo.v rtl/common/edrv32_axi_async_bridge.v \
  rtl/mem/edrv32_mem_ddr_gw.v
```

The existing `make smoke` and `make full` automatically discover these YAML files;
no regression infrastructure edit is needed. Each simulation is run sequentially.
Integration into `rtl/filelists/mem_subsys.f` requires these entries (paths relative
to the file-list directory):

```text
../common/edrv32_async_fifo.v
../common/edrv32_axi_async_bridge.v
../mem/edrv32_mem_ddr_gw.v
```

The five CDC FIFOs reuse the existing common primitive's unreset dual-clock
behavioral storage (496 payload bits total). The width converter uses one
256-bit register per direction, plus address/ID/strobe/response metadata. No
new memory IP or wrapper is introduced. FPGA mapping of the common FIFO remains
the common primitive's existing implementation responsibility.
