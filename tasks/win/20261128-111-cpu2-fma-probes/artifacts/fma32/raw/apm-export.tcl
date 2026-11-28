set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
report_timing -input_db_file input-pnr.adf -from {u_fma/u_product/u_head/u_apm/gopapm/CLK u_fma/u_product/u_tail/u_apm/gopapm/CLK} -to {u_fma/u_product/u_head/u_apm/gopapm/* u_fma/u_product/u_tail/u_apm/gopapm/*} -max_path 20 -nworst 1 -force_to_run
