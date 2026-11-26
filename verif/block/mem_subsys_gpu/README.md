# GPU memory subsystem regression

`python3 tools/regress.py full --path verif/block/mem_subsys_gpu -j 1`

The independent scheduling reference reconstructs legal ingress heads, completed
W bursts, fixed outstanding limits and read-buffer reservations. It checks exact
urgent P0/P1, CPU and P0/P1/P3/P4 rotating grants, including per-port read/write
alternation. Protocol, data, W ordering, gateway and credit scoreboards remain.

The removed token, starvation, weighted-round, direction-batch and statistics cases
have been deleted. MX-06..09, MX-11..13, twenty random seeds, gateway and environment
self-tests remain; ST-02 directed order is in `verif/unit/mem_xbar_gpu/st_02`.

ST-03 runs CPU/GPU/ETH with sustained queues and random DDR/response delays while
P0/P1 use capacity-reserving FIFO models. After priming, P0 consumes 40 beats per
720p60 row (45000 total rows/s, 125MHz memory clock); P1 consumes 48000 stereo sample
frames/s, eight samples per beat. Both FIFOs hold 512 elements, with urgent below
40 beats / 64 samples respectively. One active frame (720 rows) must finish with
no underflow/underrun and no protocol error. The FIFO minima are printed.
