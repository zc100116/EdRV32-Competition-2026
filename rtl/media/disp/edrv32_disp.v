// File: edrv32_disp.v
// Spec: disp-spec 2-6; edrv32-soc-spec 3.3, 4.2, 4.3, 5.2 X5/X6.
// Description: Two-layer RGB565/ARGB8888 scanout with line DMA and parallel TMDS symbols.
//              FIFO and control/status crossings use the common CDC primitives.
// Clock domain: clk_mem and clk_pix.
module edrv32_disp (
    // Clock domains and resets.
    input wire clk_mem_i,
    input wire rst_mem_n_i,
    input wire clk_pix_i,
    input wire rst_pix_n_i,

    // Media APB slave.
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output wire apb_pready_o,
    output wire [31:0] apb_prdata_o,
    output wire apb_pslverr_o,

    // P0 AXI256 read master.
    output wire p0_arid_o,
    output wire [31:0] p0_araddr_o,
    output wire [3:0] p0_arlen_o,
    output wire p0_arvalid_o,
    input wire p0_arready_i,
    input wire p0_rid_i,
    input wire [255:0] p0_rdata_i,
    input wire [1:0] p0_rresp_i,
    input wire p0_rlast_i,
    input wire p0_rvalid_i,
    output wire p0_rready_o,
    output wire p0_urgent_o,

    // Parallel B/G/R TMDS and interrupt.
    output wire [29:0] tmds_sym_o,
    output wire irq_o
);
    wire enable_w;
    wire enable_pix_w;
    wire scan_live_mem_w;
    wire [31:0] next_base_w;
    wire [31:0] stride_w;
    wire [31:0] l0_scroll_w;
    wire [1:0] layer_ctrl_w;
    wire [31:0] l1_next_base_w;
    wire [31:0] l1_stride_w;
    wire [31:0] l1_pos_w;
    wire [31:0] l1_size_w;
    wire [7:0] l1_opa_w;
    wire [55:0] params_mem_w;
    wire [55:0] params_pix_w;
    wire params_valid_w;
    wire params_ready_w;
    wire write_layer_w;
    wire soft_clear_w;
    wire busy_w;
    reg [3:0] frames_pending_r;
    wire reader_busy_w;
    wire fifo_pending_w;
    wire frame_start_w;
    wire delayed_req_w;
    wire [31:0] req_cnt_w;
    wire [31:0] scan_cnt_w;
    // Eleven scan stages; the row/column predicates precede their combined rectangle decision.
    reg [10:0] hs_pipe_r;
    reg [10:0] vs_pipe_r;
    reg [10:0] de_pipe_r;
    wire hs_w;
    wire vs_w;
    wire de_w;
    wire [10:0] x_w;
    wire [9:0] y_w;
    wire vblank_w;
    wire frame_req_pix_w;
    wire frame_req_mem_w;
    wire underflow_pix_w;
    wire underflow1_pix_w;
    wire underflow_mem_w;
    wire underflow1_mem_w;
    wire [9:0] read_cnt_pix_w;
    wire [9:0] read1_cnt_pix_w;
    wire [9:0] read_cnt_mem_w;
    wire [9:0] read1_cnt_mem_w;
    wire ram_wr_en_w;
    wire ram1_wr_en_w;
    wire [8:0] ram_wr_addr_w;
    wire [8:0] ram1_wr_addr_w;
    wire [255:0] ram_wr_data_w;
    wire [255:0] ram1_wr_data_w;
    wire ram_rd_en_w;
    wire ram1_rd_en_w;
    wire [8:0] ram_rd_addr_w;
    wire [8:0] ram1_rd_addr_w;
    wire [255:0] ram_rd_data_w;
    wire [255:0] ram1_rd_data_w;
    wire fifo_valid_w;
    wire fifo1_valid_w;
    wire fifo_read_w;
    wire fifo1_read_w;
    wire [255:0] fifo_data_w;
    wire [255:0] fifo1_data_w;
    wire dma_valid_w;
    wire [255:0] dma_data_w;
    wire dma_done_w;
    wire dma_err_w;
    wire desc_valid_w;
    wire desc_ready_w;
    wire [31:0] desc_base_w;
    wire [31:0] desc_stride_w;
    wire [15:0] desc_width_bytes_w;
    wire [11:0] desc_height_w;
    wire [23:0] rgb_w;
    wire unused_fifo_ready_w;
    wire unused_fifo1_ready_w;
    wire unused_dma_sol_w;
    wire unused_dma_eol_w;
    wire unused_dma_eof_w;
    wire unused_dma_idle_w;
    wire raster_start_w;
    wire [31:0] perf0_pix_w;
    wire [31:0] perf0_mem_w;
    wire [31:0] perf1_pix_w;
    wire [31:0] perf1_mem_w;
    wire [31:0] perf2_pix_w;
    wire [31:0] perf2_mem_w;

    wire [31:0] perf5_pix_w;
    wire [31:0] perf5_mem_w;

    wire [31:0] perf6_pix_w;
    wire [31:0] perf6_mem_w;

    // X6 completion and FIFO accounting include late debt repayment in STATUS.IDLE.
    assign busy_w = scan_live_mem_w || reader_busy_w || fifo_pending_w || !params_ready_w ||
        |frames_pending_r;

    // spec 4.1: isolate completed-frame arithmetic from stop and STATUS reduction.
    // Each byte comparison has its own register boundary; the count values retain
    // their existing sampling time. Reader/scan-live cover a newly arriving request.
    always @(posedge clk_mem_i or negedge rst_mem_n_i) begin
        if (!rst_mem_n_i) begin
            frames_pending_r <= 4'd0;
        end else begin
            frames_pending_r <= {req_cnt_w[31:24] != scan_cnt_w[31:24],
                req_cnt_w[23:16] != scan_cnt_w[23:16],
                req_cnt_w[15:8] != scan_cnt_w[15:8], req_cnt_w[7:0] != scan_cnt_w[7:0]};
        end
    end

    assign params_mem_w = {layer_ctrl_w[0], l0_scroll_w[3:0], layer_ctrl_w[1],
        l1_pos_w[10:0], l1_pos_w[25:16], l1_size_w[10:0], l1_size_w[25:16], l1_opa_w};

    // spec 2.4: the handshake captures the same shadow values as the frame reader.
    edrv32_cdc_handshake #(
        .WIDTH(56)
    ) u_params (
        // Clock domains and resets.
        .clk_src_i(clk_mem_i),
        .rst_src_n_i(rst_mem_n_i),
        .clk_dst_i(clk_pix_i),
        .rst_dst_n_i(rst_pix_n_i),

        // One parameter message per frame latch, acknowledged on pixel receipt.
        .valid_i(frame_start_w),
        .ready_o(params_ready_w),
        .data_i(params_mem_w),
        .valid_o(params_valid_w),
        .ready_i(1'b1),
        .data_o(params_pix_w)
    );

    edrv32_disp_regs u_regs (
        // Clock domains and resets.
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),

        // Media APB slave.
        .apb_paddr_i(apb_paddr_i),
        .apb_psel_i(apb_psel_i),
        .apb_penable_i(apb_penable_i),
        .apb_pwrite_i(apb_pwrite_i),
        .apb_pwdata_i(apb_pwdata_i),
        .apb_pstrb_i(apb_pstrb_i),
        .apb_pready_o(apb_pready_o),
        .apb_prdata_o(apb_prdata_o),
        .apb_pslverr_o(apb_pslverr_o),

        // Frame controls and events.
        .enable_o(enable_w),
        .next_base_o(next_base_w),
        .stride_o(stride_w),
        .l0_scroll_o(l0_scroll_w),
        .layer_ctrl_o(layer_ctrl_w),
        .l1_next_base_o(l1_next_base_w),
        .l1_stride_o(l1_stride_w),
        .l1_pos_o(l1_pos_w),
        .l1_size_o(l1_size_w),
        .l1_opa_o(l1_opa_w),
        .soft_clear_o(soft_clear_w),
        .busy_i(busy_w),
        .frame_start_i(frame_start_w),
        .urgent_i(p0_urgent_o),
        .delayed_req_i(delayed_req_w),
        .underflow_i(underflow_mem_w),
        .underflow1_i(underflow1_mem_w),
        .dma_err_i(dma_err_w),

        // Synchronized scan statistics.
        .perf0_i(perf0_mem_w),
        .perf1_i(perf1_mem_w),
        .perf2_i(perf2_mem_w),
        .perf5_i(perf5_mem_w),
        .perf6_i(perf6_mem_w),
        .scan_cnt_o(scan_cnt_w),

        // Interrupt.
        .irq_o(irq_o)
    );

    edrv32_disp_control u_control (
        // Clock domains and resets.
        .clk_mem_i(clk_mem_i),
        .rst_mem_n_i(rst_mem_n_i),
        .clk_pix_i(clk_pix_i),
        .rst_pix_n_i(rst_pix_n_i),

        // Scan enable and acknowledged frame request.
        .enable_i(enable_w),
        .frame_req_i(frame_req_pix_w),
        .enable_o(enable_pix_w),
        .frame_req_o(frame_req_mem_w),
        .scan_live_o(scan_live_mem_w)
    );

    edrv32_cdc_pulse u_underflow (
        // Clock domains and resets.
        .clk_src_i(clk_pix_i),
        .rst_src_n_i(rst_pix_n_i),
        .clk_dst_i(clk_mem_i),
        .rst_dst_n_i(rst_mem_n_i),

        // Domain-local interface.
        .pulse_i(underflow_pix_w),
        .pulse_o(underflow_mem_w)
    );

    edrv32_cdc_pulse u_underflow1 (
        // Clock domains and resets.
        .clk_src_i(clk_pix_i),
        .rst_src_n_i(rst_pix_n_i),
        .clk_dst_i(clk_mem_i),
        .rst_dst_n_i(rst_mem_n_i),

        // Domain-local interface.
        .pulse_i(underflow1_pix_w),
        .pulse_o(underflow1_mem_w)
    );

    edrv32_cdc_gray_cnt #(
        .WIDTH(10)
    ) u_read_cnt (
        // Clock domains and resets.
        .clk_src_i(clk_pix_i),
        .rst_src_n_i(rst_pix_n_i),
        .clk_dst_i(clk_mem_i),
        .rst_dst_n_i(rst_mem_n_i),

        // Domain-local interface.
        .count_i(read_cnt_pix_w),
        .count_o(read_cnt_mem_w)
    );

    edrv32_cdc_gray_cnt #(
        .WIDTH(10)
    ) u_read1_cnt (
        // Clock domains and resets.
        .clk_src_i(clk_pix_i),
        .rst_src_n_i(rst_pix_n_i),
        .clk_dst_i(clk_mem_i),
        .rst_dst_n_i(rst_mem_n_i),

        // Domain-local interface.
        .count_i(read1_cnt_pix_w),
        .count_o(read1_cnt_mem_w)
    );

    edrv32_cdc_gray_cnt #(
        .WIDTH(32)
    ) u_perf0 (
        // Clock domains and resets.
        .clk_src_i(clk_pix_i),
        .rst_src_n_i(rst_pix_n_i),
        .clk_dst_i(clk_mem_i),
        .rst_dst_n_i(rst_mem_n_i),

        // Domain-local interface.
        .count_i(perf0_pix_w),
        .count_o(perf0_mem_w)
    );

    edrv32_cdc_gray_cnt #(
        .WIDTH(32)
    ) u_perf1 (
        // Clock domains and resets.
        .clk_src_i(clk_pix_i),
        .rst_src_n_i(rst_pix_n_i),
        .clk_dst_i(clk_mem_i),
        .rst_dst_n_i(rst_mem_n_i),

        // Domain-local interface.
        .count_i(perf1_pix_w),
        .count_o(perf1_mem_w)
    );

    edrv32_cdc_gray_cnt #(
        .WIDTH(32)
    ) u_perf2 (
        // Clock domains and resets.
        .clk_src_i(clk_pix_i),
        .rst_src_n_i(rst_pix_n_i),
        .clk_dst_i(clk_mem_i),
        .rst_dst_n_i(rst_mem_n_i),

        // Domain-local interface.
        .count_i(perf2_pix_w),
        .count_o(perf2_mem_w)
    );

    edrv32_cdc_gray_cnt #(
        .WIDTH(32)
    ) u_perf5 (
        // Clock domains and resets.
        .clk_src_i(clk_pix_i),
        .rst_src_n_i(rst_pix_n_i),
        .clk_dst_i(clk_mem_i),
        .rst_dst_n_i(rst_mem_n_i),

        // Domain-local interface.
        .count_i(perf5_pix_w),
        .count_o(perf5_mem_w)
    );

    edrv32_cdc_gray_cnt #(
        .WIDTH(32)
    ) u_perf6 (
        // Clock domains and resets.
        .clk_src_i(clk_pix_i),
        .rst_src_n_i(rst_pix_n_i),
        .clk_dst_i(clk_mem_i),
        .rst_dst_n_i(rst_mem_n_i),

        // Domain-local interface.
        .count_i(perf6_pix_w),
        .count_o(perf6_mem_w)
    );

    edrv32_disp_reader u_reader (
        // Clock domains and resets.
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),

        // Frame requests, configuration and FIFO accounting.
        .frame_req_i(frame_req_mem_w),
        .soft_clear_i(soft_clear_w),
        .next_base_i(next_base_w),
        .stride_i(stride_w),
        .l0_scroll_i(l0_scroll_w),
        .layer_ctrl_i(layer_ctrl_w),
        .l1_next_base_i(l1_next_base_w),
        .l1_stride_i(l1_stride_w),
        .l1_pos_i(l1_pos_w),
        .l1_size_i(l1_size_w),
        .read_cnt_i(read_cnt_mem_w),
        .read1_cnt_i(read1_cnt_mem_w),
        .write_i(dma_valid_w),

        // Line DMA descriptor and completion.
        .desc_valid_o(desc_valid_w),
        .desc_ready_i(desc_ready_w),
        .desc_base_o(desc_base_w),
        .desc_stride_o(desc_stride_w),
        .desc_width_bytes_o(desc_width_bytes_w),
        .desc_height_o(desc_height_w),
        .done_i(dma_done_w),
        .write_layer_o(write_layer_w),

        // Frame status and scheduling.
        .frame_start_o(frame_start_w),
        .delayed_req_o(delayed_req_w),
        .req_cnt_o(req_cnt_w),
        .fifo_pending_o(fifo_pending_w),
        .busy_o(reader_busy_w),
        .urgent_o(p0_urgent_o)
    );

    edrv32_dma2d_rd #(
        .OUTSTANDING(4)
    ) u_dma (
        // Clock domains and resets.
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),

        // Line descriptor and reserved-space stream.
        .desc_valid_i(desc_valid_w),
        .desc_base_i(desc_base_w),
        .desc_stride_i(desc_stride_w),
        .desc_width_bytes_i(desc_width_bytes_w),
        .desc_height_i(desc_height_w),
        .desc_ready_o(desc_ready_w),
        .data_valid_o(dma_valid_w),
        // spec 2.5: a full line of FIFO space was reserved before accepting this DMA.
        .data_ready_i(1'b1),
        .data_o(dma_data_w),
        .data_sol_o(unused_dma_sol_w),
        .data_eol_o(unused_dma_eol_w),
        .data_eof_o(unused_dma_eof_w),

        // P0 AXI256 read master.
        .axi_arid_o(p0_arid_o),
        .axi_araddr_o(p0_araddr_o),
        .axi_arlen_o(p0_arlen_o),
        .axi_arvalid_o(p0_arvalid_o),
        .axi_rready_o(p0_rready_o),
        .axi_arready_i(p0_arready_i),
        .axi_rid_i(p0_rid_i),
        .axi_rdata_i(p0_rdata_i),
        .axi_rresp_i(p0_rresp_i),
        .axi_rlast_i(p0_rlast_i),
        .axi_rvalid_i(p0_rvalid_i),

        // DISP drains requested frames; ABORT never aborts the DMA.
        .abort_i(1'b0),
        .idle_o(unused_dma_idle_w),
        .done_o(dma_done_w),
        .err_o(dma_err_w)
    );

    edrv32_async_fifo_ram #(
        .WIDTH(256),
        .DEPTH(512)
    ) u_scan_fifo (
        // Clock domains and resets.
        .clk_write_i(clk_mem_i),
        .rst_write_n_i(rst_mem_n_i),
        .clk_read_i(clk_pix_i),
        .rst_read_n_i(rst_pix_n_i),

        // Reserved whole-line writes.
        .valid_i(dma_valid_w && !write_layer_w),
        .ready_o(unused_fifo_ready_w),
        .data_i(dma_data_w),

        // Pixel-domain beat consumption.
        .valid_o(fifo_valid_w),
        .ready_i(fifo_read_w),
        .data_o(fifo_data_w),

        // External DRM ports.
        .wr_en_o(ram_wr_en_w),
        .wr_addr_o(ram_wr_addr_w),
        .wr_data_o(ram_wr_data_w),
        .rd_en_o(ram_rd_en_w),
        .rd_addr_o(ram_rd_addr_w),
        .rd_data_i(ram_rd_data_w)
    );

    edrv32_ram_disp_scan u_fifo_ram (
        // Storage clocks and enabled ports.
        .wr_clk_i(clk_mem_i),
        .rd_clk_i(clk_pix_i),
        .wr_en_i(ram_wr_en_w),
        .wr_addr_i(ram_wr_addr_w),
        .wr_data_i(ram_wr_data_w),
        .rd_en_i(ram_rd_en_w),
        .rd_addr_i(ram_rd_addr_w),
        .rd_data_o(ram_rd_data_w)
    );

    edrv32_async_fifo_ram #(
        .WIDTH(256),
        .DEPTH(512)
    ) u_scan1_fifo (
        // Clock domains and resets.
        .clk_write_i(clk_mem_i),
        .rst_write_n_i(rst_mem_n_i),
        .clk_read_i(clk_pix_i),
        .rst_read_n_i(rst_pix_n_i),

        // Reserved whole-line writes.
        .valid_i(dma_valid_w && write_layer_w),
        .ready_o(unused_fifo1_ready_w),
        .data_i(dma_data_w),

        // Pixel-domain beat consumption.
        .valid_o(fifo1_valid_w),
        .ready_i(fifo1_read_w),
        .data_o(fifo1_data_w),

        // External DRM ports.
        .wr_en_o(ram1_wr_en_w),
        .wr_addr_o(ram1_wr_addr_w),
        .wr_data_o(ram1_wr_data_w),
        .rd_en_o(ram1_rd_en_w),
        .rd_addr_o(ram1_rd_addr_w),
        .rd_data_i(ram1_rd_data_w)
    );

    edrv32_ram_disp_scan u_fifo1_ram (
        // Storage clocks and enabled ports.
        .wr_clk_i(clk_mem_i),
        .rd_clk_i(clk_pix_i),
        .wr_en_i(ram1_wr_en_w),
        .wr_addr_i(ram1_wr_addr_w),
        .wr_data_i(ram1_wr_data_w),
        .rd_en_i(ram1_rd_en_w),
        .rd_addr_i(ram1_rd_addr_w),
        .rd_data_o(ram1_rd_data_w)
    );

    edrv32_disp_timing u_timing (
        // Clock domains and resets.
        .clk_i(clk_pix_i),
        .rst_n_i(rst_pix_n_i),

        // Domain-local interface.
        .hs_o(hs_w),
        .vs_o(vs_w),
        .de_o(de_w),
        .x_o(x_w),
        .y_o(y_w),
        .vblank_o(vblank_w),
        .frame_start_o(raster_start_w)
    );

    edrv32_disp_scan u_scan (
        // Clock domains and resets.
        .clk_i(clk_pix_i),
        .rst_n_i(rst_pix_n_i),

        // Raster and frame enable.
        .enable_i(enable_pix_w),
        .de_i(de_w),
        .x_i(x_w),
        .y_i(y_w),
        .vblank_i(vblank_w),
        .frame_start_i(raster_start_w),
        .params_valid_i(params_valid_w),
        .params_i(params_pix_w),

        // Scan FIFO and expanded pixel.
        .fifo_valid_i(fifo_valid_w),
        .fifo_ready_o(fifo_read_w),
        .fifo_data_i(fifo_data_w),
        .fifo1_valid_i(fifo1_valid_w),
        .fifo1_ready_o(fifo1_read_w),
        .fifo1_data_i(fifo1_data_w),
        .rgb_o(rgb_w),

        // Frame events and unit-step counts.
        .frame_req_o(frame_req_pix_w),
        .underflow_o(underflow_pix_w),
        .underflow1_o(underflow1_pix_w),
        .read_cnt_o(read_cnt_pix_w),
        .read1_cnt_o(read1_cnt_pix_w),
        .perf0_o(perf0_pix_w),
        .perf1_o(perf1_pix_w),
        .perf2_o(perf2_pix_w),
        .perf5_o(perf5_pix_w),
        .perf6_o(perf6_pix_w)
    );

    // spec 2.1/2.2/2.7: sync and DE travel with the same pixel through scan/blend.
    always @(posedge clk_pix_i or negedge rst_pix_n_i) begin
        if (!rst_pix_n_i) begin
            de_pipe_r <= 11'd0;
        end else begin
            de_pipe_r <= {de_pipe_r[9:0], de_w};
        end
    end

    always @(posedge clk_pix_i) begin
        hs_pipe_r <= {hs_pipe_r[9:0], hs_w};
        vs_pipe_r <= {vs_pipe_r[9:0], vs_w};
    end

    edrv32_disp_tmds_enc u_blue (
        // Clock domains and resets.
        .clk_i(clk_pix_i),
        .rst_n_i(rst_pix_n_i),

        // Pixel data and blanking controls.
        .data_i(rgb_w[7:0]),
        .control0_i(hs_pipe_r[10]),
        .control1_i(vs_pipe_r[10]),
        .de_i(de_pipe_r[10]),

        // Parallel TMDS symbol.
        .symbol_o(tmds_sym_o[9:0])
    );

    edrv32_disp_tmds_enc u_green (
        // Clock domains and resets.
        .clk_i(clk_pix_i),
        .rst_n_i(rst_pix_n_i),

        // Pixel data and blanking controls.
        .data_i(rgb_w[15:8]),
        .control0_i(1'b0),
        .control1_i(1'b0),
        .de_i(de_pipe_r[10]),

        // Parallel TMDS symbol.
        .symbol_o(tmds_sym_o[19:10])
    );

    edrv32_disp_tmds_enc u_red (
        // Clock domains and resets.
        .clk_i(clk_pix_i),
        .rst_n_i(rst_pix_n_i),

        // Pixel data and blanking controls.
        .data_i(rgb_w[23:16]),
        .control0_i(1'b0),
        .control1_i(1'b0),
        .de_i(de_pipe_r[10]),

        // Parallel TMDS symbol.
        .symbol_o(tmds_sym_o[29:20])
    );

endmodule
