# Run with ModelSim: vsim -c -do "do <absolute path to this file>"
# Diagnosis for step B4: compiles the same sources as check_npu_ip.do plus npu_ram_diag.sv,
# runs npu_ram_diag_top (7 RAMs, four candidate models, no stop on mismatch) and then
# npu_mul_only_top (the multiplier checks that npu_ip_check did not reach).
# ip_root is the NPU project's ipcore directory (task card section 4).
transcript off
onerror {quit -code 1 -f}
set repo_root G:/codex_project/EdRV32-Competition-2026
set ip_root G:/codex_project/EdRV32-FPGA/EdRV32-NPU-DP/ipcore
set vendor_root G:/Program/pango/PDS_2022.2-SP6.1/arch/vendor/pango/verilog/simulation
set task_src $repo_root/tasks/win/20261027-02-cpu-npu-synth/src
set build_dir [file join $repo_root build/win/20261027-02-cpu-npu-synth]
file mkdir $build_dir
cd $build_dir
vlib npu_ram_diag_work
vmap work npu_ram_diag_work
set ip_names {ram_npu_line ram_npu_weight ram_npu_quant ram_npu_lut ram_npu_residual
    ram_npu_result ram_npu_scratch mul_npu_quant_low mul_npu_quant_high}
set includes [list +incdir+$repo_root/rtl/include]
set sources {}
foreach name $ip_names {
    lappend includes +incdir+$ip_root/ip_$name/rtl
    lappend sources $repo_root/rtl/tech/edrv32_$name.v
    lappend sources $ip_root/ip_$name/ip_$name.v
    foreach source [glob -nocomplain $ip_root/ip_$name/rtl/*.v] {
        if {![string match *_init_param.v $source] && ![string match *_Reset_Value.v $source]} {
            lappend sources $source
        }
    }
    foreach source [glob -nocomplain $ip_root/ip_$name/rtl/ipm2l_apm_data_pipeline/*.v] {
        lappend sources $source
    }
}
lappend sources $repo_root/rtl/tech/edrv32_mul_npu_int8_pair.v
foreach name {GTP_DRM18K_E1 GTP_DRM36K_E1 GTP_APM_E2 GTP_GRS} {
    lappend sources $vendor_root/$name.v
}
lappend sources $task_src/npu_ip_check.sv $task_src/npu_ram_diag.sv
vlog -sv -timescale 1ns/1ps +define+FPGA_MODE {*}$includes {*}$sources
vsim -voptargs=+acc -onfinish stop work.npu_ram_diag_top
run -all
quit -sim
vsim -voptargs=+acc -onfinish stop work.npu_mul_only_top
run -all
if {[examine -radix unsigned /npu_mul_only_top/test_passed] != 1} {quit -code 1 -f}
quit -sim
quit -code 0 -f
