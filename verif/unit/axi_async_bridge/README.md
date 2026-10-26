# AXI64 asynchronous bridge unit tests

The default smoke case runs at nominal 150/125 MHz. Full additionally discovers
`nominal/`, `equal/` (125/125 MHz), and `slow_sys/` (75/125 MHz). Every configuration
runs under Verilator and Icarus through `tools/regress.py` / `make smoke` / `make full`.

Each case checks 256 packed payloads on each of the five independent channels,
with independently randomized producer gaps and consumer backpressure. The fixed
seed is `0x006a1b42`. Payloads exercise every transported field. Checks compare
FIFO order and data and require stable VALID/payload during stalls. Before the
random run, every FIFO is filled, both domains are reset, and the test checks
that no stale VALID or unknown VALID appears after reset.

The bridge has five depth-2 FIFOs, the minimum supported by `edrv32_async_fifo`.
Long W/R streams use backpressure; whole-transaction buffering is unnecessary.
The gateway, rather than this transport primitive, owns transaction limits.
Reset both ends together; callers supply resets released synchronously in each
domain, as required by the common primitive contract.
