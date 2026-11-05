set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
report_timing -input_db_file {G:/codex_project/EdRV32-FPGA/EdRV32-PROBE-V015/report-captures/card56-default/place_route/edrv32_cpu_l1_timing_probe_pnr.adf} -delay_type max -max_path 10 -nworst 1 -input_pins TRUE -through {u_cpu/u_core/u_frontend/u_predictor/u_direction/*/*/mem_*/ram*/DO} -force_to_run
