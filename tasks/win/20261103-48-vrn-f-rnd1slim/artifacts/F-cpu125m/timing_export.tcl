set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
report_timing -input_db_file {G:/codex_project/EdRV32-FPGA/EdRV32-B3F-RND1S-CPU125/place_route/edrv32_fpga_board_full_top_pnr.adf} -delay_type min_max -max_path 200 -nworst 1 -input_pins TRUE -force_to_run
