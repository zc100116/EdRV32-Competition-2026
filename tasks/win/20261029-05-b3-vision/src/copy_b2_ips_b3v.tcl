# Run in the open EdRV32-B3V project from its project directory.
# Copy existing B2 IPs; then use copy_b2_boot_ips.tcl for ROM/SRAM configuration.
file mkdir ./ipcore
foreach ip {
    ip_pll_sys
    ip_pll_video
    ip_ddr3
    ip_mul_s33x33
    ip_ram_icache_data
    ip_ram_icache_tag
    ip_ram_dcache_data
    ip_ram_dcache_tag
    ip_ram_mem_xbar_r
    ip_ram_mem_xbar_w
    ip_ram_disp_scan
    ip_pll_eth
    ip_ram_vin_wfifo
    ip_ram_pix_line
    ip_ram_geo_src
    ip_ram_eth_buf
    ip_ram_eth_fifo
} {
    file copy ../EdRV32-B2/ipcore/$ip ./ipcore
    add_design ./ipcore/$ip/${ip}.idf
}
puts "edrv32: copied and imported 17 existing IP types for B3V"
