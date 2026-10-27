# AXI256 asynchronous bridge unit test

The test targets SoC specification 4.2, 5.2 X9 and 5.3, and task N-C0.
Only the local `files.f` / `sources.f` lists are used; shared RTL lists are untouched.

Run from the repository root after loading the tool environment:

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/check/verilog_style.py rtl/common/edrv32_axi256_async_bridge.v
tools/check/lint.sh --top-module edrv32_axi256_async_bridge \
    rtl/common/edrv32_async_fifo.v rtl/common/edrv32_axi256_async_bridge.v
make smoke REGRESS_ARGS='-j 1 --path verif/unit/axi256_async_bridge'
make full REGRESS_ARGS='-j 1 --path verif/unit/axi256_async_bridge'
```

Smoke runs NPU/memory clocks at 150/125 MHz. Full includes that test plus
125/125 MHz with coincident edges and 100/125 MHz. Builds use `-Wall`, and
regression runs each simulation sequentially with one Verilator build job.
The runner's 120-second timeout bounds tests that fail to drain.

Each run first streams 4096 single-beat read and write transactions, with
continuous producer VALID and consumer READY. B waits for accepted AW and
WLAST; R waits for accepted AR. Following 128 slower-clock warm-up cycles,
the test measures 1024 consecutive slower-clock edges. Each channel must
handshake on every sampled edge. W/R are measured at the slower endpoint:
W output and R input when memory is slower, W input and R output when NPU
is slower or equal. The printed `THROUGHPUT` counts must each equal 1024;
any individual bubble fails immediately. Testing single-beat transactions
also exercises the maximum AW/AR/B rate, which determines their minimum
FIFO depth. The RTL header derives depth 8 for all five channels.

The second phase sends 512 read and 512 write transactions with independent
random 1–16-beat lengths, IDs, aligned addresses that stay inside 4 KiB,
256-bit data, arbitrary byte strobes and OKAY/SLVERR responses. Producers
insert independent random gaps and hold VALID/payload through stalls;
consumers independently randomize READY in both clock domains. An initial
512-slower-cycle response stall fills B/R FIFOs so that even infrequent
burst write responses exercise upstream backpressure. The test requires
input and output stalls on every channel.

The scoreboard compares every accepted output beat against the generated
channel sequence, checks for unsolicited or extra beats, and checks all
payload fields and VALID while stalled. Both phases drain all transactions;
monitors stay active for another 16 slower cycles to detect trailing copies.
The fixed random seed is `0x006a1b42`. Logs are under
`build/regress/{smoke,full}/unit/axi256_async_bridge/`.
