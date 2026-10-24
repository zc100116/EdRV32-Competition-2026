-s tb_uncached_load_use
+define+SIM_MODE
-f rtl/competition/rv32imc_rewrite_cached_core.f
sim/models/edrv32_cached_core_native_harness.sv
sim/models/edrv32_mem_model.sv
sim/cases/cpu/uncached-load-use/tb_uncached_load_use.sv
+incdir+rtl/include
