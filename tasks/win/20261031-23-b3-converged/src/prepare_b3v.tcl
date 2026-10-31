# Run in the B3V PDS console from its project directory.
# Copy the three generated card23 IPs from R, then update V sources.
proc edrv32_c23_copy_v_tree {src dst} {
    file mkdir $dst
    foreach item [glob -directory $src *] {
        set target [file join $dst [file tail $item]]
        if {[file isdirectory $item]} {
            edrv32_c23_copy_v_tree $item $target
        } else {
            file copy -force $item $target
        }
    }
}
foreach ip {ip_rom_boot ip_ram_sram ip_ram_dcache_tag} {
    remove_design [file join ./ipcore $ip ${ip}.idf]
    edrv32_c23_copy_v_tree [file join ../EdRV32-B3R/ipcore $ip] [file join ./ipcore $ip]
    add_design [file join ./ipcore $ip ${ip}.idf]
}
remove_design ../../EdRV32-Competition-2026/rtl/mem/edrv32_mem_perf_mon.v
remove_design ../../EdRV32-Competition-2026/rtl/mem/edrv32_mem_p6_arb.v
source ../../EdRV32-Competition-2026/fpga/scripts/import_board_vision_top.tcl
save_project
