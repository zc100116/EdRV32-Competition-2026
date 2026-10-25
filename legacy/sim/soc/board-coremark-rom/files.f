-s edrv32_clock_reset_driver
+define+EDRV32_TB=tb_coremark_rom
+define+EDRV32_SOC_100MHZ
-f sim/soc/soc_rtl.f
sim/models/axi_mem_model.sv
sim/models/spi_flash_jedec_model.sv
sim/soc/board-coremark-rom/tb_coremark_rom.sv
sim/common/edrv32_clock_reset_driver.sv
