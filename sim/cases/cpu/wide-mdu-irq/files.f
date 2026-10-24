-s tb_wide_mdu_irq
+define+EDRV32_CACHED_TEST
+define+SIM_MODE
-f rtl/competition/rv32imc_rewrite_cached_core.f
sim/models/edrv32_cached_core_native_harness.sv
sim/models/edrv32_mem_model.sv
sim/cases/cpu/core-mdu-raw-irq/tb_core_mdu_raw_irq.sv

sim/cases/cpu/wide-mdu-irq/tb_wide_mdu_irq.sv
