# Cache RTL (K-R1–K-R3)

All controllers use `clk_i` / `rst_n_i` in clk_sys. Business RTL is Verilog-2001;
only fixed RAM wrappers select FPGA IP versus behavioral memory.

| Module | Ports and function |
|---|---|
| `edrv32_icache` | Complete reversed cpu-spec 3.2 `ic_*` interface; AXI64 AR/R, 4-bit ID fixed to zero; two synchronous RAM ways, pipelined hits, blocking refill and ROM bypass. |
| `edrv32_dcache` | Complete reversed cpu-spec 3.3 `dc_*` interface; all five AXI64 channels, ID zero; cache-spec 3.2 maintenance handshake, busy/error outputs, and `dc_wb_event_o` for HPM event 15. |
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

P0 infrastructure is integrated in this branch. Run the repository regressions
with `make smoke` and `make full`; manifests use the scalar P0 schema and file
lists resolve relative to their own directory. Independent block tests are now
connected to the real RTL (see `verif/block/cache/README.md`).

RTL lint commands (all complete with zero warnings):

```sh
. ~/.local/opt/edrv32/env.sh
verilator --lint-only -Wall +incdir+rtl/include --top-module edrv32_icache rtl/cache/edrv32_icache.v rtl/cache/edrv32_cache_pma.v rtl/tech/edrv32_ram_icache_tag.v rtl/tech/edrv32_ram_icache_data.v
verilator --lint-only -Wall +incdir+rtl/include --top-module edrv32_dcache rtl/cache/edrv32_dcache.v rtl/cache/edrv32_cache_pma.v rtl/tech/edrv32_ram_dcache_tag.v rtl/tech/edrv32_ram_dcache_data.v
verilator --lint-only -Wall --top-module edrv32_cache_ctrl rtl/cache/edrv32_cache_ctrl.v
python3 tools/check/verilog_style.py rtl/cache rtl/tech/edrv32_ram_icache_tag.v rtl/tech/edrv32_ram_icache_data.v rtl/tech/edrv32_ram_dcache_tag.v rtl/tech/edrv32_ram_dcache_data.v
```

FPGA IP compilation/equivalence is the coordinator's Windows/IP work package.

## Confirmed integration behavior

PMA now includes the P0 generated `edrv32_soc_map.vh`; each comparison's low bit
is derived with `$clog2(EDRV32_<region>_SIZE)`. Only the unused declarations in
that shared generated map have a local Verilator UNUSEDPARAM waiver; PMA and
controller logic diagnostics remain enabled.

The coordinator confirmed all previous questions in the K-I1 dispatch:

- I$ invalidate overrides an in-flight fill: receive the remaining beats and
  return data unless killed, but do not make that line valid.
- A new writeback error wins over simultaneous IRQ_STAT RW1C; ERR_ADDR captures
  the new error's line address.
- OP_SIZE=0 completes range commands 1–3 immediately. Command 4 ignores OP_ADDR
  and OP_SIZE and cleans all sets and ways, as does FENCE.I.
- I$ ROM fetches use a single SIZE=3 read; the data-side single-beat limit is SIZE≤2.

These conclusions match the RTL reviewed at the previous K-RTL checkpoint.

`dc_wb_event_o` follows the v0.3/v0.5 interface addition confirmed during K-I1:
it pulses only on a dirty-line AWVALID && AWREADY handshake, including all
maintenance sources; device-store AW handshakes do not generate it. Both the
unit and block monitors compare every pulse with accepted four-beat writebacks.

## K-I1 final validation

Implementation and formal-test snapshot: `a5ec3be` (rebased on P0 `7ada537`,
with independent verification cherry-picked as `37bd102`). The remaining report
commit only updates documentation and normalizes the retained stub file list.

- `make smoke`: 44 PASS / 0 FAIL, including the final fixed-source run.
- `make full OPT_FAST=-O0 OPT_SLOW=-O0`: 56 PASS / 0 FAIL; IC-08 and DC-15 each
  complete 50 distinct seeds 1–50, 300 requests per seed.
- `python3 tools/regress.py perf`: 2 PASS / 0 FAIL. All three hit streams accept
  16 requests in 16 cycles; clean cold miss is 8 cycles against an 11-cycle bound.
- `make lint`, `python3 tools/check/verilog_style.py rtl/` and the three Cache
  top-level lint commands above: zero warnings (17 RTL/header files checked).
- All 29 required coverage bins are nonzero; 5590 writeback-event pulses match
  5590 accepted dirty-line writeback bursts in full regression.

The two observed functional simulation failures were test errors: checking
maintenance before mailbox acceptance, and attributing maintenance AW traffic
to an uncommitted device request. The corrected core driver/checker preserves
precommit device exclusion and obeys the E-to-M request-valid contract. No Cache
maintenance, forwarding or error-handling RTL was changed to accommodate tests.
The requested PMA map integration and HPM writeback port are the RTL additions.

`verif/block/cache/README.md` contains the full coverage counts, failure
classification, reproduction commands, log paths and scoped lint configuration.
There are no outstanding specification replies or K-I1 functional blockers.
