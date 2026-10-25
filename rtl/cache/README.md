# Cache RTL (K-R1–K-R3)

All controllers use `clk_i` / `rst_n_i` in clk_sys. Business RTL is Verilog-2001;
only fixed RAM wrappers select FPGA IP versus behavioral memory.

| Module | Ports and function |
|---|---|
| `edrv32_icache` | Complete reversed cpu-spec 3.2 `ic_*` interface; AXI64 AR/R, 4-bit ID fixed to zero; two synchronous RAM ways, pipelined hits, blocking refill and ROM bypass. |
| `edrv32_dcache` | Complete reversed cpu-spec 3.3 `dc_*` interface; all five AXI64 channels, ID zero; cache-spec 3.2 maintenance handshake, busy and writeback error/address outputs. |
| `edrv32_cache_ctrl` | APB4 slave with 12-bit offset, 32-bit data and byte strobes; reversed cache-spec 3.2 maintenance interface; PLIC level `irq_o`. |
| `edrv32_cache_pma` | 32-bit address plus execute/store qualifiers; cacheable, device and access-error classification. |
| `edrv32_ram_icache_tag`, `edrv32_ram_dcache_tag` | Fixed 128×20; 7-bit write/read addresses, enables, write data and synchronous read data. |
| `edrv32_ram_icache_data` | Fixed 512×64; 9-bit addresses; otherwise the same wrapper interface. |
| `edrv32_ram_dcache_data` | Fixed 512×64 with additional 8-bit write byte enable. |

RAM wrappers have no reset. Both IP clocks connect to `clk_i`; enabled reads
update on the next rising edge, disabled reads hold, and same-edge same-address
read/write returns the old data. The four IP names and port spellings follow the
K-RTL task exactly.

D$ stores retain their commit metadata, enter the one-entry byte-enabled buffer
on commit and drain the following cycle. Buffer drain and replacement can occur
on the same edge. Lookup forwarding includes both the current buffer and a
snapshot needed for synchronous read/write collisions. Maintenance scans all
128 sets and both ways; its array walker yields to committed device transactions
so STATUS polling remains possible during maintenance.

## Validation

The direct build/run commands are in each test directory's README:

- `verif/unit/cache_ram`: enabled-read timing, hold, old-data collision and byte writes for all four wrappers.
- `verif/unit/cache_pma`: first/last/next address boundaries for all SoC regions, instruction/load/store classification.
- `verif/unit/cache_ctrl`: register reset/access, byte strobes, command snapshot/hold, busy command rejection, RW1C and IRQ output.
- `verif/unit/cache_icache`: cold miss/hit, hit throughput, fill/hit LRU, replacement, ROM bypass and invalidate during a refill.
- `verif/unit/cache_dcache`: load/store hits, dirty replacement, fill/hit LRU, partial stores, continuous commits, both forwarding cases, clean/invalidate, maintenance-time device polling and FENCE.I completion.

All five tests PASS. The in-progress P0 `tools/regress.py` was also loaded from
sibling `../task-p0-rest`, with its `ROOT` set to this worktree: smoke reported
**5 PASS / 0 FAIL**. Logs are under `build/regress/smoke/unit/cache_*/verilator/`.
The manifests follow that tool's scalar `test.yaml` schema and file lists are
relative to their own directory (`verilator -F`). Independent module-level
verification remains the separate K-V/K-I work package.

RTL lint commands (all complete with zero warnings):

```sh
. ~/.local/opt/edrv32/env.sh
verilator --lint-only -Wall +incdir+rtl/include --top-module edrv32_icache rtl/cache/edrv32_icache.v rtl/cache/edrv32_cache_pma.v rtl/tech/edrv32_ram_icache_tag.v rtl/tech/edrv32_ram_icache_data.v
verilator --lint-only -Wall +incdir+rtl/include --top-module edrv32_dcache rtl/cache/edrv32_dcache.v rtl/cache/edrv32_cache_pma.v rtl/tech/edrv32_ram_dcache_tag.v rtl/tech/edrv32_ram_dcache_data.v
verilator --lint-only -Wall --top-module edrv32_cache_ctrl rtl/cache/edrv32_cache_ctrl.v
python3 ../task-p0-rest/tools/check/verilog_style.py rtl/cache rtl/tech/edrv32_ram_icache_tag.v rtl/tech/edrv32_ram_icache_data.v rtl/tech/edrv32_ram_dcache_tag.v rtl/tech/edrv32_ram_dcache_data.v
```

The P0 style check reports **8 files, 0 warnings**. P0's check scripts are not yet
present on this worker branch, so the check above uses its sibling worktree.
FPGA IP compilation/equivalence is the coordinator's Windows/IP work package.

## Integration notes

The generated `rtl/include/edrv32_soc_map.vh` was absent when work began. As
explicitly authorized in K-RTL, `edrv32_cache_pma` currently uses local address
constants matching SoC 6.1. Switch these to the generated P0 constants during
integration; no other temporary RTL dependency is present.

The coordinator confirmed that I$ invalidate overrides an in-flight fill:
receive the remaining beats and return the requested data unless killed, but do
not make that line valid. `fill_invalidated_r` implements that decision.

Still awaiting coordinator replies before final delivery:

- `msg_c01b941b945b`: whether OP_SIZE=0 applies only to range commands 1–3. The current D$ treats command 4 / FENCE.I as whole-cache clean, independent of OP_ADDR/OP_SIZE.
- `msg_56509363e6b4`: simultaneous IRQ_STAT RW1C and a new writeback error. The current register block gives the new error priority and records its address.
- I$ ROM SIZE: cache-spec 5.1 explicitly requires a single SIZE=3 read, conflicting with SoC 4.1's SIZE≤2 single-beat rule. The current I$ implements cache-spec 5.1; an explicit exception is awaiting confirmation.

The integration `main` ref was checked at `7894b44`; these clarifications have
not yet been written into its specs. Passing tests above establish the current
implementation's behavior and do not settle these pending specification choices.

## Delivery checkpoint

RTL implementation snapshot: `51fb71b97d97a4948071959b11ad924dd1fb1b98`.
Subsequent changes only group interface comments and record this report.
All implementation modules and their unit tests are committed on
`zc100116/task-cache-rtl`; no merge or push was performed.

The dispatch cannot be marked successful while the three original questions
above remain unanswered. The first two have waited roughly one hour through
repeated waits on their original message IDs, with blocker escalations sent to
the coordinator. Resume review after the replies, settle the provisional
behaviors, and replace the local PMA constants during P0 integration.
