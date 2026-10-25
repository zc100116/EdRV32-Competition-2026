-s tb_lsu_early_lookup
+define+EDRV32_CACHED_TEST
+define+SIM_MODE
-f rtl/competition/rv32imc_rewrite_cached_core.f
sim/models/edrv32_cached_core_native_harness.sv
sim/models/edrv32_mem_model.sv
sim/cases/cpu/lsu-early-lookup/tb_lsu_early_lookup.sv
