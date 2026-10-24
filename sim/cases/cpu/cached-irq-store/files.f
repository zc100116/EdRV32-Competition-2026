-s tb_cached_irq_store
+define+SIM_MODE
-f rtl/competition/rv32imc_rewrite_cached_core.f
sim/models/edrv32_cached_core_native_harness.sv
sim/models/edrv32_mem_model.sv
sim/cases/cpu/cached-irq-store/tb_cached_irq_store.sv
