-s edrv32_clock_reset_driver
+define+EDRV32_TB=tb_soc_ddr
-f sim/soc/soc_rtl.f
rtl/soc/fabric/edrv32_axi_m2s_arbiter.v
rtl/soc/fabric/edrv32_axi_m2s_read.v
rtl/soc/fabric/edrv32_axi_m2s_write.v
rtl/soc/fabric/edrv32_axi_m2s_interconnect.v
rtl/soc/ddr/edrv32_pango_ddr_axi_adapter.v
sim/models/pango_ddr_ui_model.sv
sim/soc/soc-ddr-smoke/tb_soc_ddr.sv
sim/common/edrv32_clock_reset_driver.sv
