# File: export_timing_200.tcl
# Task: 20261025-01-cpu-sys-synth, detailed post-route timing export.
# Reads the completed design DB; run in a separate output project under build/.
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
report_timing \
    -input_db_file G:/codex_project/EdRV32-FPGA/EdRV32/place_route/edrv32_fpga_cpu_sys_top_pnr.adf \
    -max_path 200 \
    -nworst 1 \
    -input_pins TRUE \
    -force_to_run
