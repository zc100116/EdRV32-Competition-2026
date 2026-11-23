# DISP GPU reader unit

Copied from `verif/unit/disp_reader/`, with the DUT/module filename changed to
`edrv32_disp_reader_gpu` and LAYER_CTRL widened to three bits. Existing ordered
descriptor, scroll, admission, backlog and L1 tests remain intact.

ST-07 in `verif/block/disp_gpu/tb_urgent.sv` additionally checks X2's paired
source-row addresses, 40-beat line reservation, exact urgent threshold and frame
latching through the same public reader interface.

Run `python3 tools/regress.py full -j 1 --path verif/unit/disp_reader_gpu`.
The copied resource scripts target the GPU module and separate build outputs;
resource synthesis is outside this task's acceptance criteria.
