-s tb_core_compliance
+define+EDRV32_CACHED_TEST
+define+SIM_MODE
-f rtl/competition/rv32imc_rewrite_cached_core.f
sim/models/edrv32_cached_core_native_harness.sv
sim/models/edrv32_mem_model.sv
sim/riscv-arch-test/tb_core_compliance.sv
