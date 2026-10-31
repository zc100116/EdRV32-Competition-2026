// File: edrv32_eth.v
// Spec: eth 2-6; dma2d 2-5; SoC 4.2-4.3, 5.2 X7.
// Description: Gigabit store-forward UDP/ARP engine with DDR windows and descriptors.
//              MAC clocks cross only through shared FIFO and completion CDC primitives.
// Clock domain: clk_mem, eth_rx_clk, eth_tx_clk.
module edrv32_eth (
    // Clocks and local-domain resets.
    input wire clk_mem_i,
    input wire rst_mem_n_i,
    input wire clk_eth_rx_i,
    input wire rst_eth_rx_n_i,
    input wire clk_eth_tx_i,
    input wire rst_eth_tx_n_i,
    input wire [7:0] eth_rxd_i,
    input wire eth_rx_dv_i,
    input wire eth_rx_er_i,
    output wire [7:0] eth_txd_o,
    output wire eth_tx_en_o,
    output wire eth_tx_er_o,
    output wire eth_mdc_o,
    output wire eth_mdio_o,
    output wire eth_mdio_oe,
    input wire eth_mdio_i,
    output wire eth_phy_rst_n_o,
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output wire apb_pready_o,
    output wire [31:0] apb_prdata_o,
    output wire apb_pslverr_o,
    output wire axi_arid_o,
    output wire [31:0] axi_araddr_o,
    output wire [3:0] axi_arlen_o,
    output wire axi_arvalid_o,
    input wire axi_arready_i,
    input wire axi_rid_i,
    input wire [255:0] axi_rdata_i,
    input wire [1:0] axi_rresp_i,
    input wire axi_rlast_i,
    input wire axi_rvalid_i,
    output wire axi_rready_o,
    output wire axi_awid_o,
    output wire [31:0] axi_awaddr_o,
    output wire [3:0] axi_awlen_o,
    output wire axi_awvalid_o,
    input wire axi_awready_i,
    output wire [255:0] axi_wdata_o,
    output wire [31:0] axi_wstrb_o,
    output wire axi_wlast_o,
    output wire axi_wvalid_o,
    input wire axi_wready_i,
    input wire axi_bid_i,
    input wire [1:0] axi_bresp_i,
    input wire axi_bvalid_i,
    output wire axi_bready_o,
    output wire irq_o
);
    wire rx_front_valid_w;
    wire [9:0] rx_front_data_w;
    wire rx_front_ready_w;
    wire rx_valid_w;
    wire [9:0] rx_data_w;
    wire clear_w;
    wire enable_w;
    wire error_w;
    wire [31:0] ip_w;
    wire [15:0] rx_port_w;
    wire [127:0] sizes_w;
    wire [10:0] release_w;
    wire packet_valid_w;
    wire [151:0] metadata_w;
    wire metadata_ready_w;
    wire rx_wr_en_w;
    wire [9:0] rx_wr_addr_w;
    wire [31:0] rx_wr_data_w;
    wire rx_busy_w;
    wire arp_event_w;
    wire arp_valid_w;
    wire [47:0] arp_rx_mac_w;
    wire [31:0] arp_rx_ip_w;
    wire frame_w;
    wire [3:0] drop_w;
    wire write_packet_w;
    wire write_ready_w;
    wire [151:0] write_metadata_w;
    wire [127:0] bases_w;
    wire rx_rd_en_w;
    wire [9:0] rx_rd_addr_w;
    wire [31:0] rx_rd_data_w;
    wire write_desc_valid_w;
    wire write_desc_ready_w;
    wire [31:0] write_base_w;
    wire [15:0] write_width_w;
    wire write_data_valid_w;
    wire write_data_ready_w;
    wire [255:0] write_data_w;
    wire [31:0] write_strb_w;
    wire write_done_w;
    wire write_dma_error_w;
    wire write_busy_w;
    wire rx_complete_w;
    wire write_error_w;
    wire write_retire_error_w;
    wire [10:0] rx_length_w;
    wire [1:0] rx_window_w;
    wire rx_notify_w;
    wire [95:0] peer_w;
    wire write_idle_w;
    wire start_w;
    wire abort_w;
    wire [31:0] desc_base_w;
    wire [15:0] desc_count_w;
    wire [31:0] dst_ip_w;
    wire [31:0] ports_w;
    wire arp_ready_w;
    wire tx_valid_w;
    wire tx_ready_w;
    wire [9:0] tx_data_w;
    wire tx_done_w;
    wire tx_busy_w;
    wire tx_running_w;
    wire done_w;
    wire read_error_w;
    wire [15:0] current_w;
    wire desc_done_w;
    wire udp_done_w;
    wire arp_done_w;
    wire tx_front_valid_w;
    wire tx_front_ready_w;
    wire [9:0] tx_front_data_w;
    wire tx_front_done_w;
    wire busy_w;
    wire mdio_busy_w;
    wire [15:0] mdio_data_w;
    wire [11:0] irq_en_w;
    wire [31:0] mac_lo_w;
    wire [15:0] mac_hi_w;
    wire [31:0] dst_mac_lo_w;
    wire [15:0] dst_mac_hi_w;
    wire phy_w;
    wire mdio_start_w;
    wire [31:0] mdio_command_w;
    reg arp_pending_r;
    reg [47:0] arp_mac_r;
    reg [31:0] arp_ip_r;
    wire unused_w;
    assign write_error_w = axi_bvalid_i && axi_bready_o && axi_bresp_i != 0;
    assign busy_w = tx_busy_w || rx_busy_w || write_busy_w || write_packet_w || !write_idle_w;
    // The registered RX event already owns the pending slot. Forward it when
    // TX is idle so an extra pending-register hop cannot let a UDP packet win.
    assign arp_valid_w = arp_pending_r || arp_event_w;
    assign eth_phy_rst_n_o = !phy_w;
    assign unused_w = &{1'b0, rx_front_ready_w, tx_front_data_w[9], irq_en_w, write_retire_error_w};
    always @(posedge clk_mem_i or negedge rst_mem_n_i) begin
        if (!rst_mem_n_i)
            arp_pending_r <= 1'b0;
        else if (clear_w)
            arp_pending_r <= 1'b0;
        else if (arp_ready_w)
            arp_pending_r <= 1'b0;
        else if (arp_event_w)
            arp_pending_r <= 1'b1;
    end
    always @(posedge clk_mem_i) begin
        if (arp_event_w) begin
            arp_mac_r <= arp_rx_mac_w;
            arp_ip_r <= arp_rx_ip_w;
        end
    end
    edrv32_eth_rx_front u_rx_front (
        .clk_i(clk_eth_rx_i),
        .rst_n_i(rst_eth_rx_n_i),
        .data_i(eth_rxd_i),
        .valid_i(eth_rx_dv_i),
        .error_i(eth_rx_er_i),
        .valid_o(rx_front_valid_w),
        .data_o(rx_front_data_w)
    );
    edrv32_eth_fifo u_rx_fifo (
        .clk_write_i(clk_eth_rx_i),
        .rst_write_n_i(rst_eth_rx_n_i),
        .clk_read_i(clk_mem_i),
        .rst_read_n_i(rst_mem_n_i),
        .valid_i(rx_front_valid_w),
        .ready_o(rx_front_ready_w),
        .data_i(rx_front_data_w),
        .valid_o(rx_valid_w),
        .ready_i(1'b1),
        .data_o(rx_data_w)
    );
    edrv32_eth_rx u_rx (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),
        .clear_i(clear_w),
        .valid_i(rx_valid_w),
        .data_i(rx_data_w),
        .enable_i(enable_w),
        .error_i(error_w),
        .mac_i({mac_hi_w, mac_lo_w}),
        .ip_i(ip_w),
        .port_i(rx_port_w),
        .sizes_i(sizes_w),
        .release_i(release_w),
        .packet_o(packet_valid_w),
        .metadata_o(metadata_w),
        .metadata_ready_i(metadata_ready_w),
        .wr_en_o(rx_wr_en_w),
        .wr_addr_o(rx_wr_addr_w),
        .wr_data_o(rx_wr_data_w),
        .busy_o(rx_busy_w),
        .arp_pending_i(arp_valid_w),
        .arp_o(arp_event_w),
        .arp_mac_o(arp_rx_mac_w),
        .arp_ip_o(arp_rx_ip_w),
        .frame_o(frame_w),
        .drop_o(drop_w)
    );
    edrv32_sync_fifo #(
        .WIDTH(152),
        .DEPTH(4)
    ) u_rx_packets (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),
        .valid_i(packet_valid_w),
        .ready_o(metadata_ready_w),
        .data_i(metadata_w),
        .valid_o(write_packet_w),
        .ready_i(write_ready_w),
        .data_o(write_metadata_w)
    );
    edrv32_eth_rx_write u_rx_write (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),
        .clear_i(clear_w),
        .valid_i(write_packet_w),
        .ready_o(write_ready_w),
        .data_i(write_metadata_w),
        .bases_i(bases_w),
        .rd_en_o(rx_rd_en_w),
        .rd_addr_o(rx_rd_addr_w),
        .rd_data_i(rx_rd_data_w),
        .desc_valid_o(write_desc_valid_w),
        .desc_ready_i(write_desc_ready_w),
        .desc_base_o(write_base_w),
        .desc_width_o(write_width_w),
        .data_valid_o(write_data_valid_w),
        .data_ready_i(write_data_ready_w),
        .data_o(write_data_w),
        .strb_o(write_strb_w),
        .done_i(write_done_w),
        .error_i(write_dma_error_w),
        .busy_o(write_busy_w),
        .complete_o(rx_complete_w),
        .error_o(write_retire_error_w),
        .release_o(release_w),
        .length_o(rx_length_w),
        .window_o(rx_window_w),
        .notify_o(rx_notify_w),
        .peer_o(peer_w)
    );
    edrv32_ram_eth_buf u_rx_buffer (
        .clk_i(clk_mem_i),
        .wr_en_i(rx_wr_en_w),
        .wr_addr_i(rx_wr_addr_w),
        .wr_data_i(rx_wr_data_w),
        .rd_en_i(rx_rd_en_w),
        .rd_addr_i(rx_rd_addr_w),
        .rd_data_o(rx_rd_data_w)
    );
    edrv32_dma2d_wr #(
        .OUTSTANDING(4)
    ) u_write_dma (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),
        .desc_valid_i(write_desc_valid_w),
        .desc_ready_o(write_desc_ready_w),
        .desc_base_i(write_base_w),
        .desc_stride_i(32'd0),
        .desc_width_bytes_i(write_width_w),
        .desc_height_i(12'd1),
        .data_valid_i(write_data_valid_w),
        .data_ready_o(write_data_ready_w),
        .data_i(write_data_w),
        .data_strb_i(write_strb_w),
        .axi_awid_o(axi_awid_o),
        .axi_awaddr_o(axi_awaddr_o),
        .axi_awlen_o(axi_awlen_o),
        .axi_awvalid_o(axi_awvalid_o),
        .axi_awready_i(axi_awready_i),
        .axi_wdata_o(axi_wdata_o),
        .axi_wstrb_o(axi_wstrb_o),
        .axi_wlast_o(axi_wlast_o),
        .axi_wvalid_o(axi_wvalid_o),
        .axi_wready_i(axi_wready_i),
        .axi_bid_i(axi_bid_i),
        .axi_bresp_i(axi_bresp_i),
        .axi_bvalid_i(axi_bvalid_i),
        .axi_bready_o(axi_bready_o),
        .abort_i(1'b0),
        .idle_o(write_idle_w),
        .done_o(write_done_w),
        .err_o(write_dma_error_w)
    );
    edrv32_eth_tx u_tx (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),
        .clear_i(clear_w),
        .start_i(start_w),
        .abort_i(abort_w),
        .desc_base_i(desc_base_w),
        .desc_count_i(desc_count_w),
        .mac_i({mac_hi_w, mac_lo_w}),
        .ip_i(ip_w),
        .dst_mac_i({dst_mac_hi_w, dst_mac_lo_w}),
        .dst_ip_i(dst_ip_w),
        .ports_i(ports_w),
        .arp_valid_i(arp_valid_w),
        .arp_ready_o(arp_ready_w),
        .arp_mac_i(arp_pending_r ? arp_mac_r : arp_rx_mac_w),
        .arp_ip_i(arp_pending_r ? arp_ip_r : arp_rx_ip_w),
        .valid_o(tx_valid_w),
        .ready_i(tx_ready_w),
        .data_o(tx_data_w),
        .frame_done_i(tx_done_w),
        .axi_arid_o(axi_arid_o),
        .axi_araddr_o(axi_araddr_o),
        .axi_arlen_o(axi_arlen_o),
        .axi_arvalid_o(axi_arvalid_o),
        .axi_arready_i(axi_arready_i),
        .axi_rid_i(axi_rid_i),
        .axi_rdata_i(axi_rdata_i),
        .axi_rresp_i(axi_rresp_i),
        .axi_rlast_i(axi_rlast_i),
        .axi_rvalid_i(axi_rvalid_i),
        .axi_rready_o(axi_rready_o),
        .busy_o(tx_busy_w),
        .running_o(tx_running_w),
        .done_o(done_w),
        .error_o(read_error_w),
        .current_o(current_w),
        .descriptor_done_o(desc_done_w),
        .udp_done_o(udp_done_w),
        .arp_done_o(arp_done_w)
    );
    edrv32_eth_fifo u_tx_fifo (
        .clk_write_i(clk_mem_i),
        .rst_write_n_i(rst_mem_n_i),
        .clk_read_i(clk_eth_tx_i),
        .rst_read_n_i(rst_eth_tx_n_i),
        .valid_i(tx_valid_w),
        .ready_o(tx_ready_w),
        .data_i(tx_data_w),
        .valid_o(tx_front_valid_w),
        .ready_i(tx_front_ready_w),
        .data_o(tx_front_data_w)
    );
    edrv32_eth_tx_front u_tx_front (
        .clk_i(clk_eth_tx_i),
        .rst_n_i(rst_eth_tx_n_i),
        .valid_i(tx_front_valid_w),
        .ready_o(tx_front_ready_w),
        .data_i(tx_front_data_w[8:0]),
        .data_o(eth_txd_o),
        .valid_o(eth_tx_en_o),
        .error_o(eth_tx_er_o),
        .done_o(tx_front_done_w)
    );
    edrv32_cdc_pulse u_tx_done (
        .clk_src_i(clk_eth_tx_i),
        .rst_src_n_i(rst_eth_tx_n_i),
        .clk_dst_i(clk_mem_i),
        .rst_dst_n_i(rst_mem_n_i),
        .pulse_i(tx_front_done_w),
        .pulse_o(tx_done_w)
    );
    edrv32_eth_regs u_regs (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),
        .apb_paddr_i(apb_paddr_i),
        .apb_psel_i(apb_psel_i),
        .apb_penable_i(apb_penable_i),
        .apb_pwrite_i(apb_pwrite_i),
        .apb_pwdata_i(apb_pwdata_i),
        .apb_pstrb_i(apb_pstrb_i),
        .apb_pready_o(apb_pready_o),
        .apb_prdata_o(apb_prdata_o),
        .apb_pslverr_o(apb_pslverr_o),
        .busy_i(busy_w),
        .tx_busy_i(tx_running_w),
        .done_i(done_w),
        .desc_done_i(desc_done_w),
        .current_i(current_w),
        .read_error_i(read_error_w),
        .write_error_i(write_error_w),
        .frame_i(frame_w),
        .drop_i(drop_w),
        .rx_complete_i(rx_complete_w),
        .rx_length_i(rx_length_w),
        .rx_window_i(rx_window_w),
        .rx_notify_i(rx_notify_w),
        .peer_i(peer_w),
        .udp_done_i(udp_done_w),
        .arp_done_i(arp_done_w),
        .mdio_busy_i(mdio_busy_w),
        .mdio_data_i(mdio_data_w),
        .enable_o(enable_w),
        .irq_en_o(irq_en_w),
        .desc_base_o(desc_base_w),
        .desc_count_o(desc_count_w),
        .mac_lo_o(mac_lo_w),
        .mac_hi_o(mac_hi_w),
        .ip_o(ip_w),
        .rx_port_o(rx_port_w),
        .dst_mac_lo_o(dst_mac_lo_w),
        .dst_mac_hi_o(dst_mac_hi_w),
        .dst_ip_o(dst_ip_w),
        .ports_o(ports_w),
        .phy_o(phy_w),
        .bases_o(bases_w),
        .sizes_o(sizes_w),
        .clear_o(clear_w),
        .start_o(start_w),
        .abort_o(abort_w),
        .mdio_start_o(mdio_start_w),
        .mdio_command_o(mdio_command_w),
        .error_o(error_w),
        .irq_o(irq_o)
    );
    edrv32_eth_mdio u_mdio (
        .clear_i(clear_w),
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),
        .start_i(mdio_start_w),
        .command_i(mdio_command_w),
        .busy_o(mdio_busy_w),
        .data_o(mdio_data_w),
        .mdc_o(eth_mdc_o),
        .mdio_o(eth_mdio_o),
        .mdio_oe(eth_mdio_oe),
        .mdio_i(eth_mdio_i)
    );
endmodule
