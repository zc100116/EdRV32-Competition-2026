# Run in the existing B3VN PDS project, from its project directory.
# Copy files individually so existing IP directories can be overwritten.
proc edrv32_copy_ip_tree {src dst} {
    file mkdir $dst
    foreach item [glob -nocomplain -directory $src *] {
        set target [file join $dst [file tail $item]]
        if {[file isdirectory $item]} {
            edrv32_copy_ip_tree $item $target
        } else {
            file copy -force $item $target
        }
    }
}
foreach ip {
    ip_ram_icache_tag ip_ram_icache_data ip_ram_dcache_tag ip_ram_dcache_data
    ip_ram_mem_xbar_w ip_ram_npu_quant ip_ram_npu_residual ip_ram_npu_result
    ip_ram_npu_lut
} {
    remove_design [file join ./ipcore $ip ${ip}.idf]
}
foreach ip {
    ip_ram_icache_tag ip_ram_icache_data ip_ram_dcache_tag ip_ram_dcache_data
    ip_lutram_mem_xbar_w ip_lutram_npu_quant ip_lutram_npu_residual
    ip_lutram_npu_result ip_ram_npu_lut
} {
    edrv32_copy_ip_tree [file join ../EdRV32-B3N/ipcore $ip] [file join ./ipcore $ip]
    add_design [file join ./ipcore $ip ${ip}.idf]
}
save_project
puts "edrv32: copied and added 9 IP types from B3N to B3VN"
