# Run in the open EdRV32-B1-ILA project, from its project directory.
# Reuse the eight IP types required by card 34; ILA is added after synthesis.
file mkdir ./ipcore
foreach ip {
    ip_pll_sys
    ip_ram_icache_tag
    ip_ram_icache_data
    ip_ram_dcache_tag
    ip_ram_dcache_data
    ip_mul_s33x33
    ip_rom_boot
    ip_ram_sram
} {
    file copy [file join ../EdRV32-B3F/ipcore $ip] ./ipcore
    add_design [file join ./ipcore $ip ${ip}.idf]
}
save_project
puts "edrv32: copied and added 8 IP types from B3F to B1-ILA"
