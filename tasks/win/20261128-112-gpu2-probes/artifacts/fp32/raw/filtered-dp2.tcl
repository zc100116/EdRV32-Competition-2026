set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
report_timing -input_db_file input-pnr.adf -from {u_fp32/u_*/s1_small_r*/*/CLK} -to {u_fp32/u_*/s2_sum_r*/*/*} -max_path 20 -nworst 1 -force_to_run
