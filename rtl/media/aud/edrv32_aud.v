// File: edrv32_aud.v
// Spec: aud-spec 1-6; gpu-soc-spec 5.2 X11, 6.2; edrv32-soc-spec 4.2, 4.3, 7.1.
// Description: APB-controlled ring DMA, sample CDC FIFO and fixed-rate I2S master.
//              Media APB slot 1, mem_xbar P1 read port and PLIC source 8.
// Clock domain: clk_mem configuration/DMA; clk_aud serial output.
module edrv32_aud (
    // Clocks and domain resets.
    input wire clk_mem_i,
    input wire rst_mem_n_i,
    input wire clk_aud_i,
    input wire rst_aud_n_i,

    // Media APB slave.
    input wire [11:0] s_apb_paddr_i,
    input wire s_apb_psel_i,
    input wire s_apb_penable_i,
    input wire s_apb_pwrite_i,
    input wire [31:0] s_apb_pwdata_i,
    input wire [3:0] s_apb_pstrb_i,
    output wire s_apb_pready_o,
    output wire [31:0] s_apb_prdata_o,
    output wire s_apb_pslverr_o,

    // AXI256 read master.
    output wire m_axi_arvalid_o,
    input wire m_axi_arready_i,
    output wire [31:0] m_axi_araddr_o,
    output wire [3:0] m_axi_arlen_o,
    output wire m_axi_arid_o,
    input wire m_axi_rvalid_i,
    output wire m_axi_rready_o,
    input wire [255:0] m_axi_rdata_i,
    input wire [1:0] m_axi_rresp_i,
    input wire m_axi_rlast_i,
    input wire m_axi_rid_i,

    // Urgency, interrupt and I2S pins.
    output wire urgent_o,
    output wire irq_o,
    output wire aud_bclk_o,
    output wire aud_lrck_o,
    output wire aud_sdata_o
);
    wire rst_mem_n_w;
    wire rst_aud_n_w;
    wire enable_w;
    wire restart_w;
    wire clear_error_w;
    wire [31:0] ring_base_w;
    wire [23:0] ring_size_w;
    wire [23:0] wr_ptr_w;
    wire [23:0] rd_ptr_w;
    wire [23:0] avail_w;
    wire busy_w;
    wire error_w;
    wire underrun_aud_w;
    wire underrun_mem_w;
    wire write_valid_w;
    wire write_ready_w;
    wire [31:0] write_data_w;
    wire read_valid_w;
    wire read_ready_w;
    wire [31:0] read_data_w;
    wire i2s_ready_w;
    wire [9:0] level_w;
    wire [9:0] free_w;
    wire play_mem_w;
    wire play_aud_w;
    wire flush_done_w;
    reg enable_previous_r;
    reg flushed_r;

    assign flush_done_w = !flushed_r && !busy_w && (level_w == 10'd0);
    assign free_w = 10'd512 - level_w;
    assign urgent_o = enable_w && (level_w < 10'd64);
    assign play_mem_w = enable_w && flushed_r;
    assign read_ready_w = !play_aud_w || i2s_ready_w;

    always @(posedge clk_mem_i or negedge rst_mem_n_w) begin
        if (!rst_mem_n_w) begin
            enable_previous_r <= 1'b0;
            flushed_r <= 1'b1;
        end else begin
            enable_previous_r <= enable_w;
            if (enable_previous_r && !enable_w) begin
                flushed_r <= 1'b0;
            end else if (flush_done_w) begin
                flushed_r <= 1'b1;
            end
        end
    end
    edrv32_reset_copy u_reset_mem (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),
        .rst_n_o(rst_mem_n_w)
    );
    edrv32_reset_copy u_reset_aud (
        .clk_i(clk_aud_i),
        .rst_n_i(rst_aud_n_i),
        .rst_n_o(rst_aud_n_w)
    );
    edrv32_aud_regs u_regs (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_w),
        .s_apb_paddr_i(s_apb_paddr_i),
        .s_apb_psel_i(s_apb_psel_i),
        .s_apb_penable_i(s_apb_penable_i),
        .s_apb_pwrite_i(s_apb_pwrite_i),
        .s_apb_pwdata_i(s_apb_pwdata_i),
        .s_apb_pstrb_i(s_apb_pstrb_i),
        .s_apb_pready_o(s_apb_pready_o),
        .s_apb_prdata_o(s_apb_prdata_o),
        .s_apb_pslverr_o(s_apb_pslverr_o),
        .enable_o(enable_w),
        .restart_o(restart_w),
        .clear_error_o(clear_error_w),
        .ring_base_o(ring_base_w),
        .ring_size_o(ring_size_w),
        .wr_ptr_o(wr_ptr_w),
        .rd_ptr_i(rd_ptr_w),
        .avail_i(avail_w),
        .busy_i(busy_w),
        .error_i(error_w),
        .underrun_i(underrun_mem_w),
        .irq_o(irq_o)
    );
    edrv32_aud_dma u_dma (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_w),
        .enable_i(play_mem_w),
        .restart_i((restart_w && !busy_w) || flush_done_w),
        .clear_error_i(clear_error_w),
        .ring_base_i(ring_base_w),
        .ring_size_i(ring_size_w),
        .wr_ptr_i(wr_ptr_w),
        .rd_ptr_o(rd_ptr_w),
        .avail_o(avail_w),
        .busy_o(busy_w),
        .error_o(error_w),
        .free_i(free_w),
        .sample_valid_o(write_valid_w),
        .sample_ready_i(write_ready_w),
        .sample_data_o(write_data_w),
        .m_axi_arvalid_o(m_axi_arvalid_o),
        .m_axi_arready_i(m_axi_arready_i),
        .m_axi_araddr_o(m_axi_araddr_o),
        .m_axi_arlen_o(m_axi_arlen_o),
        .m_axi_arid_o(m_axi_arid_o),
        .m_axi_rvalid_i(m_axi_rvalid_i),
        .m_axi_rready_o(m_axi_rready_o),
        .m_axi_rdata_i(m_axi_rdata_i),
        .m_axi_rresp_i(m_axi_rresp_i),
        .m_axi_rlast_i(m_axi_rlast_i),
        .m_axi_rid_i(m_axi_rid_i)
    );
    edrv32_aud_fifo u_fifo (
        .clk_mem_i(clk_mem_i),
        .rst_mem_n_i(rst_mem_n_w),
        .clk_aud_i(clk_aud_i),
        .rst_aud_n_i(rst_aud_n_w),
        .sample_valid_i(write_valid_w),
        .sample_ready_o(write_ready_w),
        .sample_data_i(write_data_w),
        .level_o(level_w),
        .sample_valid_o(read_valid_w),
        .sample_ready_i(read_ready_w),
        .sample_data_o(read_data_w)
    );
    edrv32_cdc_sync_bit u_play_enable (
        .clk_i(clk_aud_i),
        .rst_n_i(rst_aud_n_w),
        .bit_i(play_mem_w),
        .bit_o(play_aud_w)
    );
    edrv32_cdc_pulse u_underrun (
        .clk_src_i(clk_aud_i),
        .rst_src_n_i(rst_aud_n_w),
        .clk_dst_i(clk_mem_i),
        .rst_dst_n_i(rst_mem_n_w),
        .pulse_i(underrun_aud_w),
        .pulse_o(underrun_mem_w)
    );
    edrv32_aud_i2s u_i2s (
        .clk_i(clk_aud_i),
        .rst_n_i(rst_aud_n_w),
        .enable_i(play_aud_w),
        .sample_valid_i(read_valid_w),
        .sample_ready_o(i2s_ready_w),
        .sample_data_i(read_data_w),
        .aud_bclk_o(aud_bclk_o),
        .aud_lrck_o(aud_lrck_o),
        .aud_sdata_o(aud_sdata_o),
        .underrun_o(underrun_aud_w)
    );
endmodule
