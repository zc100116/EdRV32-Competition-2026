# Run in the new EdRV32-FPGA/EdRV32-B3N project PDS Console.
# Copy only the 21 IP types required by task 13, then register every IDF.
set b3n_ip_names {
    ip_pll_sys ip_pll_npu ip_ddr3
    ip_ram_icache_tag ip_ram_icache_data
    ip_ram_dcache_tag ip_ram_dcache_data ip_mul_s33x33
    ip_rom_boot ip_ram_sram
    ip_ram_mem_xbar_r ip_ram_mem_xbar_w
    ip_ram_npu_line ip_ram_npu_weight ip_ram_npu_quant ip_ram_npu_lut
    ip_ram_npu_residual ip_ram_npu_result ip_ram_npu_scratch
    ip_mul_npu_quant_low ip_mul_npu_quant_high
}
set b3n_ip_source ../EdRV32-B3VN/ipcore
foreach ip $b3n_ip_names {
    if {![file isfile [file join $b3n_ip_source $ip ${ip}.idf]]} {
        error "Missing source IP: $ip; run from EdRV32-FPGA/EdRV32-B3N"
    }
    if {[file exists [file join ./ipcore $ip]]} {
        error "Destination IP already exists: $ip; stopped without overwriting"
    }
}
file mkdir ./ipcore
foreach ip $b3n_ip_names {
    file copy [file join $b3n_ip_source $ip] ./ipcore
    add_design [file join ./ipcore $ip ${ip}.idf]
}
save_project
puts "edrv32: copied and added [llength $b3n_ip_names] IP types for B3N"
