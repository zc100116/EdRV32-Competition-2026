# Common reset, CDC and FIFO primitives

These primitives implement I-06 and SoC specification 5.2–5.3. The coordinator
approved the minimal interfaces and WIDTH/DEPTH parameters for this work package.
All sources use Verilog-2001. Control state resets asynchronously; payload
registers and storage arrays are not reset. Except for `edrv32_reset_sync`,
callers supply resets that release synchronously in the named clock domain.
Reset both ends of a CDC together before transferring new traffic; independent
mid-transaction reset is outside these interfaces.

| Module | Interface and behavior |
|---|---|
| `edrv32_reset_sync` | `clk_i`, asynchronous active-low `rst_n_i`, `rst_n_o`; asserts immediately and releases after two rising edges |
| `edrv32_cdc_sync_bit` | `clk_i`, `rst_n_i`, asynchronous level `bit_i`, synchronized `bit_o`; two destination flops, reset value zero |
| `edrv32_cdc_pulse` | Source/destination clocks and resets; source-cycle `pulse_i` transfers through a toggle and produces one destination-cycle `pulse_o` |
| `edrv32_cdc_handshake` | `WIDTH` (default 32); source `valid_i/ready_o/data_i`, destination `valid_o/ready_i/data_o`; one outstanding bundled payload with req/ack toggles |
| `edrv32_cdc_gray_cnt` | `WIDTH` (default 8); source binary `count_i`, destination binary `count_o`; source-registered Gray value crosses two destination stages |
| `edrv32_sync_fifo` | `WIDTH` (default 32), `DEPTH` (default 16); `clk_i/rst_n_i`; producer `valid_i/ready_o/data_i`, consumer `valid_o/ready_i/data_o` |
| `edrv32_axi_async_bridge` | Fixed AXI64 five-channel bridge, `s_axi_*` on `clk_sys_i/rst_sys_n_i`, `m_axi_*` on `clk_mem_i/rst_mem_n_i`; each channel uses a depth-2 async FIFO, supports independent channel backpressure |
| `edrv32_axi256_async_bridge` | Fixed AXI256 five-channel NPU boundary bridge (SoC 4.2, 5.2 X9); `s_axi_*` on `clk_npu_i/rst_npu_n_i`, `m_axi_*` on `clk_mem_i/rst_mem_n_i`; depth 8 on AW/W/B/AR/R sustains one beat per slower clock at 150/125, 125/125 and 100/125 MHz, with independent backpressure |
| `edrv32_async_fifo` | Same FIFO parameters and data interface; independent `clk_write_i/rst_write_n_i` and `clk_read_i/rst_read_n_i` |

For both FIFOs DEPTH is a power of two and at least 2; WIDTH is positive.
A transfer occurs on a rising edge when that side's valid and ready are both
high. FIFO outputs expose the current head combinationally and remain stable
while stalled; data has meaning only when valid is high. Full blocks writes,
empty blocks reads, and simultaneous read/write is supported. The synchronous
FIFO does not accept a write on a full cycle even if a read occurs on that edge.
The asynchronous FIFO uses Gray pointers, so remote full/empty changes appear
after synchronization latency. Its storage is a dual-clock behavioral memory;
FPGA memory-IP mapping is outside this infrastructure task.

A handshake producer holds valid/data until accepted. The primitive holds the
payload until the acknowledgement returns, and a stalled destination keeps
valid/data. The payload is a bundled-data crossing: its timing must settle
before the synchronized request is consumed.

`cdc_sync_bit` is for levels, not unconstrained pulses or correlated buses.
For the open-loop pulse synchronizer, source events must be separated by at
least three destination clock periods, with pulse_i asserted for one source
cycle. Use the handshake for events requiring backpressure. Gray-counter input
changes by at most one count per source cycle (including modulo wrap); the
destination may skip intermediate counts. Physical implementation must constrain
Gray-bus skew within one source clock period. Gray pointer buses in the async
FIFO need the same physical constraint.

`verif/unit/<module>/` provides smoke tests for every primitive under Verilator
and Icarus. Tests cover reset, synchronization latency, pulse delivery, handshake
stalling, counter wrap and snapshots, FIFO empty/full blocking, ordering,
concurrent transfers, pointer wrap and occupancy reset. The async FIFO uses
10-unit and 14-unit clock periods.
