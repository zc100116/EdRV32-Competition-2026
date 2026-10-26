# CPU-only evaluation flow. Run from the project Tcl console.
set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir import_sources.tcl]
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/datapath/edrv32_full_adder.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/datapath/edrv32_adder32.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/datapath/edrv32_adder64.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/datapath/edrv32_shifter32.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/datapath/edrv32_compare32.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/datapath/edrv32_wallace_compress_3to2.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/datapath/edrv32_regfile.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/frontend/edrv32_rvc_decompress.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/frontend/edrv32_if1_stage.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/pipeline/edrv32_pipe_if1_to_if2.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/frontend/edrv32_if2_stage.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/pipeline/edrv32_pipe_if2_to_align.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/frontend/edrv32_align_stage.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/pipeline/edrv32_pipe_align_to_decode.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/decode/edrv32_immgen.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/decode/edrv32_decoder.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/decode/edrv32_operand_resolve.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/decode/edrv32_decode_stage.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/pipeline/edrv32_pipe_decode_to_ex.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/execute/edrv32_alu.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/execute/edrv32_branch_unit.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/execute/edrv32_ex_stage.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/pipeline/edrv32_pipe_ex_to_mem1.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/lsu/edrv32_lsu_format.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/lsu/edrv32_pma_classifier.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/lsu/edrv32_load_queue.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/lsu/edrv32_store_queue.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/lsu/edrv32_mem1_stage.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/pipeline/edrv32_pipe_mem1_to_mem2.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/lsu/edrv32_mem2_stage.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/pipeline/edrv32_pipe_mem2_to_commit.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/csr/edrv32_hpm_counters.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/csr/edrv32_csr_file.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/commit/edrv32_commit_stage.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/mdu/edrv32_mul_booth4_wallace.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/mdu/edrv32_mul_pango_apm.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/mdu/edrv32_div_nonrestoring.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/mdu/edrv32_mdu.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/control/edrv32_mdu_scoreboard.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/control/edrv32_branch_predictor.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/control/edrv32_redirect_ctrl.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/control/edrv32_hpm_attribution.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/core/edrv32_core.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/cache/edrv32_cache_array.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/cache/edrv32_cache_maint.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/cache/edrv32_icache.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/cache/edrv32_dcache.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/core/edrv32_cached_core.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/core/edrv32_cpu_minimal_top.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/com/reset_sync.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/com/sync_fifo.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/soc/fabric/axi2native.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/soc/fabric/axi2apb.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/soc/fabric/axi_rd_fabric.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/soc/fabric/axi_wr_fabric.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/soc/fabric/axi_interconnect.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/soc/fabric/apb_mux.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/soc/mem/sram_storage.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/soc/mem/pango_sram_storage.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/soc/mem/sram_axi.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/soc/mem/boot_rom_storage.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/soc/mem/pango_boot_rom_storage.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/soc/mem/boot_rom_axi.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/soc/mem/itcm.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/soc/mem/pango_itcm_storage.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/soc/mem/dtcm.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/soc/mem/edrv32_tcm_subsystem.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/soc/intc/clint.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/soc/intc/plic.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/soc/periph/uart.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/soc/periph/gpio.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/soc/periph/spi.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/soc/top/edrv32_soc_top.v"
add_design "G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc_coremark/source/edrv32_pango_200h_coremark_top.v"
add_design G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc_coremark/ipcore/cache_tag/cache_tag.idf
add_design G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc_coremark/ipcore/cache_data/cache_data.idf
add_design G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc_coremark/ipcore/sram/sram.idf
add_design G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc_coremark/ipcore/boot_rom/boot_rom.idf
add_design G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc_coremark/ipcore/mul/mul.idf
add_design G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc_coremark/ipcore/pll0/pll0.idf
add_constraint "G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc_coremark/io.fdc"
add_constraint "G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc_coremark/clock.fdc"
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -top_module {edrv32_pango_200h_coremark_top} -include_path {G:/claude code/EdRV32-Competition-2026/rtl/include	} -compiler_directives {FPGA_MODE EDRV32_SOC_100MHZ EDRV32_ENABLE_DECOUPLED_LSU} -top_module edrv32_pango_200h_coremark_top
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -top_module {edrv32_pango_200h_coremark_top} -include_path {G:/claude code/EdRV32-Competition-2026/rtl/include	} -compiler_directives {FPGA_MODE EDRV32_SOC_100MHZ EDRV32_ENABLE_DECOUPLED_LSU} -top_module edrv32_pango_200h_coremark_top
synthesize -ads -selected_syn_tool_opt 2 
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -top_module {edrv32_pango_200h_coremark_top} -include_path {G:/claude code/EdRV32-Competition-2026/rtl/include	} -compiler_directives {FPGA_MODE EDRV32_SOC_100MHZ EDRV32_ENABLE_DECOUPLED_LSU} -top_module edrv32_pango_200h_coremark_top
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -top_module {edrv32_pango_200h_coremark_top} -include_path {G:/claude code/EdRV32-Competition-2026/rtl/include	} -compiler_directives {FPGA_MODE EDRV32_SOC_100MHZ EDRV32_ENABLE_DECOUPLED_LSU} -top_module edrv32_pango_200h_coremark_top
synthesize -ads -selected_syn_tool_opt 2 
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/camera/edrv32_camera_axi_writer.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/cpu/core/edrv32_cpu_minimal_top.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/display/edrv32_frame_composer.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/geometry/edrv32_geometry_engine.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc_coremark/source/edrv32_pango_200h_colorbar_hdmi_top.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc_coremark/source/edrv32_pango_200h_ddr_top.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/soc/fabric/edrv32_axi_async_bridge.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/display/edrv32_colorbar_hdmi.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/com/edrv32_counter_cdc.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/geometry/edrv32_geometry_axi_tile_reader.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/geometry/edrv32_geometry_coord_walker.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/geometry/edrv32_geometry_tile_cache.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/display/edrv32_colorbar_axi_writer.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/display/edrv32_hdmi_axi_reader.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc_coremark/source/edrv32_pango_200h_stereo_hdmi_top.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/camera/edrv32_stereo_hdmi.v"
remove_design G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc_coremark/ipcore/ddr/ddr.idf
remove_design G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc_coremark/ipcore/pll0/pll0.idf
remove_design G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc_coremark/ipcore/hdmi_pll/hdmi_pll.idf
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/soc/fabric/edrv32_axi_m2s_interconnect.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/camera/edrv32_camera_fifo.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/camera/edrv32_camera_select.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/camera/edrv32_camera_stream_mux.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/display/edrv32_display_axi_writer.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/geometry/edrv32_geometry_frame_scheduler.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/geometry/edrv32_geometry_surface_pipeline.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/display/edrv32_hdmi_axi_reader_pageflip.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/display/edrv32_hdmi_fifo.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/display/edrv32_hdmi_scanout.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/camera/edrv32_ov5640_capture.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/camera/edrv32_ov5640_stereo_init.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/soc/ddr/edrv32_pango_ddr_axi_adapter.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/pixel/edrv32_pixel_pipeline.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/soc/fabric/edrv32_axi_m2s_read.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/soc/fabric/edrv32_axi_m2s_write.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/geometry/edrv32_geometry_axi_writer.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/geometry/edrv32_geometry_block_engine.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/display/edrv32_hdmi_timing.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/camera/edrv32_ov5640_reg_rom.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/camera/edrv32_ov5640_sccb.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/pixel/edrv32_pixel_pack_2p.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/pixel/edrv32_pixel_point_pipe.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/pixel/edrv32_pixel_unpack_2p.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/pixel/edrv32_pixel_window_3x3_2p.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/display/edrv32_tmds_tx.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/com/reset_sync.v"
remove_design G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc_coremark/ipcore/hdmi_fifo/hdmi_fifo.idf
remove_design G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc_coremark/ipcore/cam_fifo/cam_fifo.idf
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/soc/fabric/edrv32_axi_m2s_arbiter.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/geometry/edrv32_geometry_axi_patch_reader.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/geometry/edrv32_geometry_band_ram.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/geometry/edrv32_geometry_bilinear.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/geometry/edrv32_geometry_config.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/geometry/edrv32_geometry_patch_ram.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/pixel/edrv32_pixel_filter_3x3.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/pixel/edrv32_pixel_line_ram.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/display/edrv32_tmds_encoder.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/display/edrv32_tmds_serdes.v"
remove_design G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc_coremark/ipcore/cam_rom/cam_rom.idf
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/geometry/edrv32_geometry_tile_ram.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/geometry/edrv32_geometry_trig_rom.v"
remove_design -verilog "G:/claude code/EdRV32-Competition-2026/rtl/vision/geometry/edrv32_geometry_udiv48_16.v"
remove_design G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc_coremark/ipcore/geometry_band_ram/geometry_band_ram.idf
remove_design G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc_coremark/ipcore/pixel_line_ram/pixel_line_ram.idf
remove_design G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc_coremark/ipcore/trig_rom/trig_rom.idf
remove_design G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc_coremark/ipcore/geometry_tile_ram/geometry_tile_ram.idf
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -include_path {G:/claude code/EdRV32-Competition-2026/rtl/include	} -compiler_directives {FPGA_MODE EDRV32_SOC_100MHZ EDRV32_ENABLE_DECOUPLED_LSU} -top_module edrv32_soc_top
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/core/edrv32_cpu_minimal_top.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/com/reset_sync.v"
add_design "G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc_coremark/source/edrv32_pango_200h_coremark_top.v"
add_design G:/claude code/EdRV32-Competition-2026/fpga/pango_200h/edrv32_soc_coremark/ipcore/pll0/pll0.idf
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -include_path {G:/claude code/EdRV32-Competition-2026/rtl/include	} -compiler_directives {FPGA_MODE EDRV32_SOC_100MHZ EDRV32_ENABLE_DECOUPLED_LSU} -top_module edrv32_pango_200h_coremark_top
synthesize -dir {G:/Program/pango/PDS_2022.2-SP6.1/syn/bin/synplify_pro.exe} -ads -selected_syn_tool_opt 2 
dev_map 
pnr 
report_timing 
gen_bit_stream 
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -top_module {edrv32_pango_200h_coremark_top} -include_path {G:/claude code/EdRV32-Competition-2026/rtl/include	} -compiler_directives {FPGA_MODE EDRV32_SOC_100MHZ EDRV32_ENABLE_DECOUPLED_LSU} -top_module edrv32_pango_200h_coremark_top
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -include_path {G:/claude code/EdRV32-Competition-2026/rtl/include	} -compiler_directives {FPGA_MODE EDRV32_SOC_100MHZ EDRV32_ENABLE_DECOUPLED_LSU} -top_module edrv32_pango_200h_coremark_top
synthesize -dir {G:/Program/pango/PDS_2022.2-SP6.1/syn/bin/synplify_pro.exe} -ads -selected_syn_tool_opt 2 
dev_map 
pnr 
report_timing 
gen_bit_stream 
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -include_path {G:/claude code/EdRV32-Competition-2026/rtl/include	} -compiler_directives {FPGA_MODE EDRV32_SOC_100MHZ EDRV32_ENABLE_DECOUPLED_LSU} -top_module edrv32_pango_200h_coremark_top
synthesize -dir {G:/Program/pango/PDS_2022.2-SP6.1/syn/bin/synplify_pro.exe} -ads -selected_syn_tool_opt 2 
dev_map 
pnr 
report_timing 
gen_bit_stream 
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -include_path {G:/claude code/EdRV32-Competition-2026/rtl/include	} -compiler_directives {FPGA_MODE EDRV32_SOC_100MHZ EDRV32_ENABLE_DECOUPLED_LSU} -top_module edrv32_pango_200h_coremark_top
synthesize -dir {G:/Program/pango/PDS_2022.2-SP6.1/syn/bin/synplify_pro.exe} -ads -selected_syn_tool_opt 2 
dev_map 
pnr 
report_timing 
gen_bit_stream 
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -include_path {G:/claude code/EdRV32-Competition-2026/rtl/include	} -compiler_directives {FPGA_MODE EDRV32_SOC_100MHZ EDRV32_ENABLE_DECOUPLED_LSU} -top_module edrv32_pango_200h_coremark_top
synthesize -dir {G:/Program/pango/PDS_2022.2-SP6.1/syn/bin/synplify_pro.exe} -ads -selected_syn_tool_opt 2 
dev_map 
pnr 
report_timing 
gen_bit_stream 
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -include_path {G:/claude code/EdRV32-Competition-2026/rtl/include	} -compiler_directives {FPGA_MODE EDRV32_SOC_100MHZ EDRV32_ENABLE_DECOUPLED_LSU} -top_module edrv32_pango_200h_coremark_top
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -include_path {G:/claude code/EdRV32-Competition-2026/rtl/include	} -compiler_directives {FPGA_MODE EDRV32_SOC_100MHZ EDRV32_ENABLE_DECOUPLED_LSU} -top_module edrv32_pango_200h_coremark_top
synthesize -dir {G:/Program/pango/PDS_2022.2-SP6.1/syn/bin/synplify_pro.exe} -ads -selected_syn_tool_opt 2 
dev_map 
pnr 
report_timing 
gen_bit_stream 
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -include_path {G:/claude code/EdRV32-Competition-2026/rtl/include	} -compiler_directives {FPGA_MODE EDRV32_SOC_100MHZ EDRV32_ENABLE_DECOUPLED_LSU} -top_module edrv32_pango_200h_coremark_top
synthesize -dir {G:/Program/pango/PDS_2022.2-SP6.1/syn/bin/synplify_pro.exe} -ads -selected_syn_tool_opt 2 
dev_map 
pnr 
report_timing 
gen_bit_stream 
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -include_path {G:/claude code/EdRV32-Competition-2026/rtl/include	} -compiler_directives {FPGA_MODE EDRV32_SOC_100MHZ EDRV32_ENABLE_DECOUPLED_LSU} -top_module edrv32_pango_200h_coremark_top
synthesize -dir {G:/Program/pango/PDS_2022.2-SP6.1/syn/bin/synplify_pro.exe} -ads -selected_syn_tool_opt 2 
dev_map 
pnr 
report_timing 
gen_bit_stream 
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -include_path {G:/claude code/EdRV32-Competition-2026/rtl/include	} -compiler_directives {FPGA_MODE EDRV32_SOC_100MHZ EDRV32_ENABLE_DECOUPLED_LSU} -top_module edrv32_pango_200h_coremark_top
synthesize -dir {G:/Program/pango/PDS_2022.2-SP6.1/syn/bin/synplify_pro.exe} -ads -selected_syn_tool_opt 2 
dev_map 
pnr 
report_timing 
gen_bit_stream 
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -include_path {G:/claude code/EdRV32-Competition-2026/rtl/include	} -compiler_directives {FPGA_MODE EDRV32_SOC_100MHZ EDRV32_ENABLE_DECOUPLED_LSU} -top_module edrv32_pango_200h_coremark_top
synthesize -dir {G:/Program/pango/PDS_2022.2-SP6.1/syn/bin/synplify_pro.exe} -ads -selected_syn_tool_opt 2 
dev_map 
pnr 
report_timing 
gen_bit_stream 
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -include_path {G:/claude code/EdRV32-Competition-2026/rtl/include	} -compiler_directives {FPGA_MODE EDRV32_SOC_100MHZ EDRV32_ENABLE_DECOUPLED_LSU} -top_module edrv32_pango_200h_coremark_top
synthesize -dir {G:/Program/pango/PDS_2022.2-SP6.1/syn/bin/synplify_pro.exe} -ads -selected_syn_tool_opt 2 
dev_map 
pnr 
report_timing 
gen_bit_stream 
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -include_path {G:/claude code/EdRV32-Competition-2026/rtl/include	} -compiler_directives {FPGA_MODE EDRV32_SOC_100MHZ EDRV32_ENABLE_DECOUPLED_LSU} -top_module edrv32_pango_200h_coremark_top
synthesize -dir {G:/Program/pango/PDS_2022.2-SP6.1/syn/bin/synplify_pro.exe} -ads -selected_syn_tool_opt 2 
dev_map 
pnr 
report_timing 
gen_bit_stream 
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/mdu/edrv32_mul_low32_pipe1.v"
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -include_path {G:/claude code/EdRV32-Competition-2026/rtl/include	} -compiler_directives {FPGA_MODE EDRV32_SOC_100MHZ EDRV32_ENABLE_DECOUPLED_LSU} -top_module edrv32_pango_200h_coremark_top
synthesize -dir {G:/Program/pango/PDS_2022.2-SP6.1/syn/bin/synplify_pro.exe} -ads -selected_syn_tool_opt 2 
dev_map 
pnr 
report_timing 
gen_bit_stream 
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/pipeline/edrv32_pipe_if2_to_align_pair.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/frontend/edrv32_align_pair_stage.v"
add_design "G:/claude code/EdRV32-Competition-2026/rtl/cpu/pipeline/edrv32_pipe_align_to_decode_pair.v"
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -include_path {G:/claude code/EdRV32-Competition-2026/rtl/include	} -compiler_directives {FPGA_MODE EDRV32_SOC_100MHZ EDRV32_ENABLE_DECOUPLED_LSU} -top_module edrv32_pango_200h_coremark_top
synthesize -dir {G:/Program/pango/PDS_2022.2-SP6.1/syn/bin/synplify_pro.exe} -ads -selected_syn_tool_opt 2 
dev_map 
pnr 
report_timing 
gen_bit_stream 
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -include_path {G:/claude code/EdRV32-Competition-2026/rtl/include	} -compiler_directives {FPGA_MODE EDRV32_SOC_100MHZ EDRV32_ENABLE_DECOUPLED_LSU} -top_module edrv32_pango_200h_coremark_top
synthesize -dir {G:/Program/pango/PDS_2022.2-SP6.1/syn/bin/synplify_pro.exe} -ads -selected_syn_tool_opt 2 
dev_map 
pnr 
report_timing 
gen_bit_stream 
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
compile -include_path {G:/claude code/EdRV32-Competition-2026/rtl/include	} -compiler_directives {FPGA_MODE EDRV32_SOC_100MHZ EDRV32_ENABLE_DECOUPLED_LSU} -top_module edrv32_pango_200h_coremark_top
synthesize -dir {G:/Program/pango/PDS_2022.2-SP6.1/syn/bin/synplify_pro.exe} -ads -selected_syn_tool_opt 2 
dev_map 
pnr 
report_timing 
gen_bit_stream 
