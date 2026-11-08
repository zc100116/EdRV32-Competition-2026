# NPU postprocessing SoC software test

See sw/tests/npu_post/README.md for oracle generation, coverage and invocation.
The real edrv32_soc_top, CPU, D-cache, BSP and NPU DMA are used; no candidate DMA
is replaced by a testbench copy. Integration execution awaits postprocessing RTL.
