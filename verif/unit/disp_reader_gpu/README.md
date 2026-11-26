# GPU DISP reader

`python3 tools/regress.py full --path verif/unit/disp_reader_gpu -j 1`

Checks L0 descriptor order and stability, FIFO reservation, native scrolling at all
16 beat offsets, X2 repeated source rows, queued frames and local reset.
