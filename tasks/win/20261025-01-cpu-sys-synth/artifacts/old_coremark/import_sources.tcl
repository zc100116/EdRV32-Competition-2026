# PG2L200H cached CoreMark SoC source import.
# Imports the current CPU RTL, existing IP and 100-MHz constraints into PDS.
# The low-32-bit MUL backend is RTL; the existing mul IP keeps its configuration.
# Wide fetch uses the existing 128x128 cache_data and 128x21 cache_tag IP.
# Board top parameters CPU_DUAL_ISSUE=1 and CPU_FETCH_WIDE=1 enable the prototype.
# Board defaults enable both features; use top-level overrides of 0 for scalar comparisons.
# This script imports and compiles only. Run synthesis and implementation in PDS.

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir .. .. ..]]
set include_dirs [list [file join $repo_root rtl include]]
set top_module edrv32_pango_200h_coremark_top

set compiler_defines [list \
    FPGA_MODE \
    EDRV32_SOC_100MHZ \
    EDRV32_ENABLE_DECOUPLED_LSU]

set rtl_sources [list \
    rtl/cpu/datapath/edrv32_full_adder.v \
    rtl/cpu/datapath/edrv32_adder32.v \
    rtl/cpu/datapath/edrv32_adder64.v \
    rtl/cpu/datapath/edrv32_shifter32.v \
    rtl/cpu/datapath/edrv32_compare32.v \
    rtl/cpu/datapath/edrv32_wallace_compress_3to2.v \
    rtl/cpu/datapath/edrv32_regfile.v \
    rtl/cpu/frontend/edrv32_rvc_decompress.v \
    rtl/cpu/frontend/edrv32_if1_stage.v \
    rtl/cpu/pipeline/edrv32_pipe_if1_to_if2.v \
    rtl/cpu/frontend/edrv32_if2_stage.v \
    rtl/cpu/pipeline/edrv32_pipe_if2_to_align.v \
    rtl/cpu/pipeline/edrv32_pipe_if2_to_align_pair.v \
    rtl/cpu/frontend/edrv32_align_stage.v \
    rtl/cpu/frontend/edrv32_align_pair_stage.v \
    rtl/cpu/pipeline/edrv32_pipe_align_to_decode.v \
    rtl/cpu/pipeline/edrv32_pipe_align_to_decode_pair.v \
    rtl/cpu/decode/edrv32_immgen.v \
    rtl/cpu/decode/edrv32_decoder.v \
    rtl/cpu/decode/edrv32_operand_resolve.v \
    rtl/cpu/decode/edrv32_decode_stage.v \
    rtl/cpu/pipeline/edrv32_pipe_decode_to_ex.v \
    rtl/cpu/execute/edrv32_alu.v \
    rtl/cpu/execute/edrv32_branch_unit.v \
    rtl/cpu/execute/edrv32_ex_stage.v \
    rtl/cpu/pipeline/edrv32_pipe_ex_to_mem1.v \
    rtl/cpu/lsu/edrv32_lsu_format.v \
    rtl/cpu/lsu/edrv32_pma_classifier.v \
    rtl/cpu/lsu/edrv32_load_queue.v \
    rtl/cpu/lsu/edrv32_store_queue.v \
    rtl/cpu/lsu/edrv32_mem1_stage.v \
    rtl/cpu/pipeline/edrv32_pipe_mem1_to_mem2.v \
    rtl/cpu/lsu/edrv32_mem2_stage.v \
    rtl/cpu/pipeline/edrv32_pipe_mem2_to_commit.v \
    rtl/cpu/csr/edrv32_hpm_counters.v \
    rtl/cpu/csr/edrv32_csr_file.v \
    rtl/cpu/commit/edrv32_commit_stage.v \
    rtl/cpu/mdu/edrv32_mul_booth4_wallace.v \
    rtl/cpu/mdu/edrv32_mul_low32_pipe2.v \
    rtl/cpu/mdu/edrv32_mul_low32_pipe1.v \
    rtl/cpu/mdu/edrv32_mul_pango_apm.v \
    rtl/cpu/mdu/edrv32_div_nonrestoring.v \
    rtl/cpu/mdu/edrv32_mdu.v \
    rtl/cpu/control/edrv32_mdu_scoreboard.v \
    rtl/cpu/control/edrv32_branch_predictor.v \
    rtl/cpu/control/edrv32_redirect_ctrl.v \
    rtl/cpu/control/edrv32_hpm_attribution.v \
    rtl/cpu/core/edrv32_core.v \
    rtl/cpu/cache/edrv32_cache_array.v \
    rtl/cpu/cache/edrv32_cache_maint.v \
    rtl/cpu/cache/edrv32_icache.v \
    rtl/cpu/cache/edrv32_dcache.v \
    rtl/cpu/core/edrv32_cached_core.v \
    rtl/cpu/core/edrv32_cpu_minimal_top.v \
    rtl/com/reset_sync.v \
    rtl/com/sync_fifo.v \
    rtl/soc/fabric/axi2native.v \
    rtl/soc/fabric/axi2apb.v \
    rtl/soc/fabric/axi_rd_fabric.v \
    rtl/soc/fabric/axi_wr_fabric.v \
    rtl/soc/fabric/axi_interconnect.v \
    rtl/soc/fabric/apb_mux.v \
    rtl/soc/mem/sram_storage.v \
    rtl/soc/mem/pango_sram_storage.v \
    rtl/soc/mem/sram_axi.v \
    rtl/soc/mem/boot_rom_storage.v \
    rtl/soc/mem/pango_boot_rom_storage.v \
    rtl/soc/mem/boot_rom_axi.v \
    rtl/soc/mem/itcm.v \
    rtl/soc/mem/pango_itcm_storage.v \
    rtl/soc/mem/dtcm.v \
    rtl/soc/mem/edrv32_tcm_subsystem.v \
    rtl/soc/intc/clint.v \
    rtl/soc/intc/plic.v \
    rtl/soc/periph/uart.v \
    rtl/soc/periph/gpio.v \
    rtl/soc/periph/spi.v \
    rtl/soc/top/edrv32_soc_top.v]

foreach source $rtl_sources {
    add_design [file join $repo_root $source]
}

add_design [file join $script_dir source edrv32_pango_200h_coremark_top.v]

foreach ip_name {cache_tag cache_data sram boot_rom mul pll0} {
    add_design [file join $script_dir ipcore $ip_name ${ip_name}.idf]
}

add_constraint [file join $script_dir io.fdc]
add_constraint [file join $script_dir clock.fdc]

set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676

compile \
    -top_module $top_module \
    -include_path $include_dirs \
    -compiler_directives $compiler_defines

puts "EdRV32 CoreMark SoC RTL, IP and constraints imported and compiled."
puts "Top module: $top_module"
puts "Include path: $include_dirs"
puts "Defines: $compiler_defines"
