# Run with pds_shell -file <this script> -work_dir <scratch output directory>.
# Read the existing routed database; do not rerun mapping or place and route.
set repo [file normalize [file join [file dirname [info script]] .. .. .. ..]]
set db [file normalize [file join $repo .. EdRV32-FPGA EdRV32 place_route \
    edrv32_fpga_cpu_sys_top_pnr.adf]]
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
report_timing -input_db_file $db -max_path 200 -nworst 1 -input_pins TRUE -force_to_run
