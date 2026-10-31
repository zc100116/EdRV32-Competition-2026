# Run in B3R after regenerating the three card23 IPs.
remove_design ../../EdRV32-Competition-2026/rtl/mem/edrv32_mem_perf_mon.v
remove_design ../../EdRV32-Competition-2026/rtl/mem/edrv32_mem_p6_arb.v
source ../../EdRV32-Competition-2026/fpga/scripts/import_board_render_top.tcl
save_project
