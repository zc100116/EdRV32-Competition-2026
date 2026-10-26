外部器件模型（DDR、OV5640、HDMI 接收、UART、QSPI flash、ETH 对端）


`ddr3_axi256_model.sv` is the mem-subsystem MB DDR timing model (testplan 2.3).
It exposes the SoC 3.2 scalar slave pins, with no BREADY/RREADY. Commands share an
ordered depth-8 queue; AW precedes AR on simultaneous arrival. Address mapping:
row `[29:15]`, bank `[14:12]`, byte column `[11:0]`. Data storage is sparse by byte;
unwritten test locations read as zero, and `poke`/`peek` provide explicit preloads
and byte error injection. Reset clears control/queues and open-row validity;
stored bytes survive reset.

Timing plusargs, in clk_mem cycles: `+T_HIT=8 +T_MISS=4 +T_TURN=3 +T_REFI=975
+T_RFC=38 +T_B=2`. Read-command latency overlaps earlier data transfers; the
shared data bus transfers at most one read or write beat per cycle. Refresh stops
data transfers, closes rows, and preserves queued transactions. B follows the
last executed write beat by T_B cycles. Backpressure applies only to AW/AR/W.
`read_response` and `write_response` are test controls for response-error routing.

Model, driver and protocol-checker self-tests and the case mapping live in
`verif/block/mem_subsys/README.md`. Run `. ~/.local/opt/edrv32/env.sh` first.
