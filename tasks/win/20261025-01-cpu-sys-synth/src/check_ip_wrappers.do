# Run with ModelSim: vsim -c -do "do <absolute path to this file>"
# Generated IP and vendor files remain outside the repository.
transcript off
onerror {quit -code 1 -f}
set repo_root G:/codex_project/EdRV32-Competition-2026
set task_src $repo_root/tasks/win/20261025-01-cpu-sys-synth/src
set ip_root G:/codex_project/EdRV32-FPGA/EdRV32/ipcore
set vendor_root G:/Program/pango/PDS_2022.2-SP6.1/arch/vendor/pango/verilog/simulation
set build_dir [file join $repo_root build/win/20261025-01-cpu-sys-synth]
file mkdir $build_dir
cd $build_dir
vlib ip_check_work
vmap work ip_check_work
set names {ram_icache_tag ram_icache_data ram_dcache_tag ram_dcache_data rom_boot ram_sram mul_s33x33}
set includes [list +incdir+$repo_root/rtl/include]
set sources {}
foreach name $names {
    lappend includes +incdir+$ip_root/ip_$name/rtl
    lappend sources $repo_root/rtl/tech/edrv32_$name.v
    lappend sources $ip_root/ip_$name/ip_$name.v
    foreach source [glob $ip_root/ip_$name/rtl/*.v] {
        if {![string match *_init_param.v $source] && ![string match *_Reset_Value.v $source]} {
            lappend sources $source
        }
    }
}
foreach source [glob $ip_root/ip_mul_s33x33/rtl/ipm2l_apm_data_pipeline/*.v] {
    lappend sources $source
}
foreach name {GTP_DRM18K_E1 GTP_DRM36K_E1 GTP_APM_E2 GTP_GRS} {
    lappend sources $vendor_root/$name.v
}
set input [open $repo_root/verif/unit/cache_ram/tb.sv r]
set cache_test [read $input]
close $input
set cache_test [string map [list {module tb;} {module cache_ip_check;
    GTP_GRS GRS_INST (.GRS_N(1'b1));
    bit test_passed = 0;}] $cache_test]
set cache_test [string map [list {$display("PASS cache_ram");} {test_passed = 1; $display("PASS cache_ram");}] $cache_test]
set output [open cache_ip_check.sv w]
puts $output $cache_test
close $output
lappend sources cache_ip_check.sv $task_src/port_check.sv $task_src/mul_ip_check.sv $task_src/sram_ip_check.sv
vlog -sv -timescale 1ns/1ps +define+FPGA_MODE {*}$includes {*}$sources
vsim work.port_check
run 0
quit -sim
foreach top {cache_ip_check mul_ip_check sram_ip_check} {
    vsim -voptargs=+acc -onfinish stop work.$top
    run -all
    if {[examine -radix unsigned /$top/test_passed] != 1} {quit -code 1 -f}
    quit -sim
}
quit -code 0 -f
