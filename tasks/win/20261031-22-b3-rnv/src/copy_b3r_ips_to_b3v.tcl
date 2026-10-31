# Run from the existing B3V project directory in its PDS console.
# Update generated IPs by copying files into existing directories.
proc edrv32_c22_copy_v_tree {src dst} {
    file mkdir $dst
    foreach item [glob -directory $src *] {
        set target [file join $dst [file tail $item]]
        if {[file isdirectory $item]} {
            edrv32_c22_copy_v_tree $item $target
        } else {
            file copy -force $item $target
        }
    }
}
foreach ip {
    ip_rom_boot ip_ram_sram
    ip_ram_icache_tag ip_ram_icache_data ip_ram_dcache_tag ip_ram_dcache_data
    ip_ram_mem_xbar_w
} {
    remove_design [file join ./ipcore $ip ${ip}.idf]
}
foreach ip {
    ip_rom_boot ip_ram_sram
    ip_ram_icache_tag ip_ram_icache_data ip_ram_dcache_tag ip_ram_dcache_data
    ip_lutram_mem_xbar_w
} {
    edrv32_c22_copy_v_tree [file join ../EdRV32-B3R/ipcore $ip] [file join ./ipcore $ip]
    add_design [file join ./ipcore $ip ${ip}.idf]
}
save_project
puts "edrv32: copied and added 7 updated IP types from B3R to B3V"
