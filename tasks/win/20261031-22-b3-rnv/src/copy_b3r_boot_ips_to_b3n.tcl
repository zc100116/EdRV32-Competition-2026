# Run in B3N's PDS console from the B3N project directory.
# Copy generated files individually, overwriting existing files in place.
proc edrv32_c22_copy_boot_tree {src dst} {
    file mkdir $dst
    foreach item [glob -directory $src *] {
        set target [file join $dst [file tail $item]]
        if {[file isdirectory $item]} {
            edrv32_c22_copy_boot_tree $item $target
        } else {
            file copy -force $item $target
        }
    }
}
foreach ip {ip_rom_boot ip_ram_sram} {
    remove_design [file join ./ipcore $ip ${ip}.idf]
    edrv32_c22_copy_boot_tree [file join ../EdRV32-B3R/ipcore $ip] [file join ./ipcore $ip]
    add_design [file join ./ipcore $ip ${ip}.idf]
}
save_project
puts "edrv32: copied and added card22 ROM/SRAM from B3R to B3N"
