set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
report_timing -input_db_file {G:/codex_project/EdRV32-FPGA/EdRV32-PROBE-V015/report-captures/card56-d2/place_route/edrv32_cpu_l1_timing_probe_pnr.adf} -delay_type max -max_path 10 -through {u_cpu/u_core/u_frontend/u_predictor/u_btb/u_ip/*/mem_*/ram64x1d/DO} -nworst 1 -input_pins TRUE -force_to_run
