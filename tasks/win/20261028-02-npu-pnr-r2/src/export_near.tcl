# Positive setup slack below 1 ns, from the existing routed NPU database.
set repo [file normalize [file join [file dirname [info script]] .. .. .. ..]]
set db [file normalize [file join $repo .. EdRV32-FPGA EdRV32-NPU place_route \
    edrv32_fpga_npu_top_pnr.adf]]
set_arch -family Logos2 -device PG2L200H -speedgrade -6 -package FBB676
report_timing -input_db_file $db -delay_type max -max_path 200 -nworst 1 \
    -slack_greater_than 0 -slack_less_than 1 -input_pins TRUE -force_to_run
