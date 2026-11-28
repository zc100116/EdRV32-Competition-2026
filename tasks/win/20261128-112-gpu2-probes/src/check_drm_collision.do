# Run with ModelSim: vsim -c -do "do <absolute path to this file>"
# Set the three IP directories to the generated ipcore folders of the B and D projects.
transcript on
onerror {quit -code 1 -f}
set repo_root G:/codex_project/EdRV32-Competition-2026
set task_src $repo_root/tasks/win/20261128-112-gpu2-probes/src
set vendor_root G:/Program/pango/PDS_2022.2-SP6.1/arch/vendor/pango/verilog/simulation
set ip_dirs [dict create \
    ip_ram_gpu2_sdp72 G:/codex_project/EdRV32-FPGA/gpu2_probe_banks/ipcore/ip_ram_gpu2_sdp72 \
    ip_ram_gpu2_sdp36 G:/codex_project/EdRV32-FPGA/gpu2_probe_banks/ipcore/ip_ram_gpu2_sdp36 \
    ip_ram_gpu2_sfu_scratch G:/codex_project/EdRV32-FPGA/gpu2_probe_sfu/ipcore/ip_ram_gpu2_sfu_scratch]
set build_dir [file join $repo_root build/win/20261128-112-gpu2-probes]
file mkdir $build_dir
cd $build_dir
vlib drm_check_work
vmap work drm_check_work
set includes [list +incdir+$repo_root/rtl/include]
set sources [list $repo_root/rtl/tech/edrv32_ram_gpu2_sdp72.v \
    $repo_root/rtl/tech/edrv32_ram_gpu2_sdp36.v $repo_root/rtl/tech/edrv32_ram_gpu2_sfu_scratch.v]
dict for {name dir} $ip_dirs {
    lappend includes +incdir+$dir/rtl
    lappend sources $dir/$name.v
    foreach source [glob -nocomplain $dir/rtl/*.v] {
        if {![string match *_init_param.v $source] && ![string match *_Reset_Value.v $source]} {
            lappend sources $source
        }
    }
}
foreach name {GTP_DRM18K_E1 GTP_DRM36K_E1 GTP_GRS} {
    lappend sources $vendor_root/$name.v
}
lappend sources $task_src/drm_collision_check.sv
eval vlog -sv +define+FPGA_MODE $includes $sources
vsim -c work.drm_collision_check
run -all
quit -f
