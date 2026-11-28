set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
report_timing -input_db_file input-pnr.adf -from {u_probe/g_setup*.u_ram/rd_data_r*/*/CLK} -to {u_probe/g_setup*.capture_r*/*/*} -max_path 20 -nworst 1 -force_to_run
