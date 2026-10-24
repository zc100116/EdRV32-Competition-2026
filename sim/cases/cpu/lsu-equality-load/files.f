-s tb_lsu_equality_load
+define+EDRV32_CACHED_TEST
+define+SIM_MODE
-f rtl/competition/rv32imc_rewrite_cached_core.f
sim/models/edrv32_cached_core_native_harness.sv
sim/models/edrv32_mem_model.sv
sim/cases/cpu/lsu-equality-load/tb_lsu_equality_load.sv
