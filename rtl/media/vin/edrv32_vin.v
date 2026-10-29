// File: edrv32_vin.v
// Spec: vin 1--6; SoC 4.2--4.5, 5.2 X4, 7.1--7.3.
// Description: Two DVP sources and a memory source feed CH0 through external PIX and CH1/CH2.
//              DMA writers share whole-burst arbitration; CH2 adapts the source to INT8_C4.
// Clock domain: cam0_pclk/cam1_pclk frontends, clk_mem for all other logic.
module edrv32_vin (
    // Memory clock and reset.
    input wire clk_mem_i,
    // Reset.
    input wire rst_mem_n_i,
    // Camera zero.
    input wire cam0_pclk_i,
    // Reset.
    input wire rst_cam0_n_i,
    // Camera zero.
    input wire cam0_vsync_i,
    input wire cam0_href_i,
    input wire [7:0] cam0_data_i,
    // Camera one.
    input wire cam1_pclk_i,
    // Reset.
    input wire rst_cam1_n_i,
    // Camera one.
    input wire cam1_vsync_i,
    input wire cam1_href_i,
    input wire [7:0] cam1_data_i,
    // Control APB.
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output wire apb_pready_o,
    output wire [31:0] apb_prdata_o,
    output wire apb_pslverr_o,
    // P1 AXI256 master.
    output wire p1_awid_o,
    output wire [31:0] p1_awaddr_o,
    output wire [3:0] p1_awlen_o,
    output wire p1_awvalid_o,
    input wire p1_awready_i,
    output wire [255:0] p1_wdata_o,
    output wire [31:0] p1_wstrb_o,
    output wire p1_wlast_o,
    output wire p1_wvalid_o,
    input wire p1_wready_i,
    input wire p1_bid_i,
    input wire [1:0] p1_bresp_i,
    input wire p1_bvalid_i,
    output wire p1_bready_o,
    output wire p1_arid_o,
    output wire [31:0] p1_araddr_o,
    output wire [3:0] p1_arlen_o,
    output wire p1_arvalid_o,
    input wire p1_arready_i,
    input wire p1_rid_i,
    input wire [255:0] p1_rdata_i,
    input wire [1:0] p1_rresp_i,
    input wire p1_rlast_i,
    input wire p1_rvalid_i,
    output wire p1_rready_o,
    output wire p1_urgent_o,
    // External PIX streams.
    output wire pix_in_valid_o,
    input wire pix_in_ready_i,
    output wire [31:0] pix_in_data_o,
    output wire pix_in_sof_o,
    output wire pix_in_eol_o,
    output wire pix_in_eof_o,
    input wire pix_out_valid_i,
    output wire pix_out_ready_o,
    input wire [31:0] pix_out_data_i,
    input wire pix_out_sof_i,
    input wire pix_out_eol_i,
    input wire pix_out_eof_i,
    // Interrupt.
    output wire irq_o
);
    wire rst_vin_n_w;
    wire enable_w;
    wire abort_w;
    wire soft_rst_w;
    reg abort_all_r;
    wire busy_w;
    wire [31:0] cam0_size_w;
    wire [31:0] cam1_size_w;
    wire [31:0] msrc_base_w;
    wire [15:0] msrc_stride_w;
    wire [31:0] msrc_size_w;
    wire msrc_start_w;
    wire msrc_busy_w;
    wire msrc_done_w;
    wire msrc_error_w;
    wire msrc_cfg_error_w;
    wire [23:0] ch_ctrl_w;
    wire [47:0] ch_stride_w;
    wire [383:0] ch_bases_w;
    wire [11:0] ch_slot_busy_w;
    wire [17:0] ch_done_info_w;
    wire [95:0] ch_done_frame_id_w;
    wire [8:0] ch_wr_stat_w;
    wire [2:0] ch_done_w;
    wire [2:0] ch_error_w;
    wire [2:0] ch_overflow_w;
    wire [2:0] ch_skip_w;
    wire [2:0] ch_cfg_error_w;
    wire [2:0] ch_busy_w;
    wire [1:0] ch_urgent_w;
    wire [29:0] ch_count_w;
    wire [2:0] ch_abort_w;
    wire [5:0] ch_select_w;
    wire [1:0] ch_ready_w;
    wire [95:0] ch_awaddr_w;
    wire [11:0] ch_awlen_w;
    wire [2:0] ch_awvalid_w;
    wire [2:0] ch_awready_w;
    wire [767:0] ch_wdata_w;
    wire [95:0] ch_wstrb_w;
    wire [2:0] ch_wlast_w;
    wire [2:0] ch_wvalid_w;
    wire [2:0] ch_wready_w;
    wire [5:0] ch_bresp_w;
    wire [2:0] ch_bvalid_w;
    wire [2:0] ch_bready_w;
    wire [2:0] source_valid_w;
    wire [2:0] source_ready_w;
    wire [95:0] source_data_w;
    wire [2:0] source_sof_w;
    wire [2:0] source_eol_w;
    wire [2:0] source_eof_w;
    wire [95:0] source_frame_id_w;
    wire [32:0] source_width_w;
    wire [35:0] source_height_w;
    wire [2:0] source_incomplete_w;
    wire [1:0] cam_frame_w;
    wire [1:0] cam_incomplete_w;
    wire [1:0] cam_cfg_error_w;
    wire msrc_frame_w;
    wire [2:0] frame_boundary_w;
    wire [5:0] ch_cfg_errors_w;
    wire unused_pix_sof_w;
    wire unused_reserved_w;
    wire [3:0] cfg_errors_w;
    reg [3:0] error_code_w;
    wire [31:0] irq_set_w;
    wire [15:0] perf_event_w;
    reg soft_pending_r;
    reg clear_r;
    genvar source_idx;
    genvar channel_idx;

    // Soft reset first drains committed AXI traffic; CDC FIFOs keep their external resets.
    assign rst_vin_n_w = rst_mem_n_i && !clear_r;
    always @(posedge clk_mem_i or negedge rst_mem_n_i) begin
        if (!rst_mem_n_i)
            abort_all_r <= 1'b0;
        else
            abort_all_r <= abort_w || soft_rst_w;
    end
    assign busy_w = (|ch_busy_w) || msrc_busy_w;
    assign p1_urgent_o = |ch_urgent_w;
    assign unused_pix_sof_w = pix_out_sof_i;
    assign unused_reserved_w = |{cam0_size_w[31:28], cam0_size_w[15:11],
        cam1_size_w[31:28], cam1_size_w[15:11], msrc_size_w[31:28], msrc_size_w[15:11],
        ch_ctrl_w[23], ch_ctrl_w[19], ch_ctrl_w[15], ch_ctrl_w[11], ch_ctrl_w[7], ch_ctrl_w[3]};
    assign frame_boundary_w = source_valid_w & source_ready_w & source_sof_w;
    assign cfg_errors_w = {3'd0, cam_cfg_error_w[0]} + {3'd0, cam_cfg_error_w[1]} +
        {3'd0, msrc_cfg_error_w} + {2'd0, ch_cfg_errors_w[1:0]} +
        {2'd0, ch_cfg_errors_w[3:2]} + {2'd0, ch_cfg_errors_w[5:4]};
    assign irq_set_w = {22'd0, ch_done_w[2:1], 5'd0, ch_done_w[0],
        (error_code_w != 0), msrc_done_w};
    assign perf_event_w = {1'b0, p1_urgent_o, cam_incomplete_w, ch_skip_w,
        ch_overflow_w, ch_done_w, msrc_frame_w, cam_frame_w};

    always @(*) begin
        error_code_w = 4'd0;
        if (ch_overflow_w[0]) error_code_w = 4'd1;
        if (ch_overflow_w[1]) error_code_w = 4'd2;
        if (ch_overflow_w[2]) error_code_w = 4'd3;
        if (cam_incomplete_w[0]) error_code_w = 4'd4;
        if (cam_incomplete_w[1]) error_code_w = 4'd5;
        if (|cam_cfg_error_w) error_code_w = 4'd6;
        if (msrc_cfg_error_w) error_code_w = 4'd7;
        if (|ch_cfg_error_w) error_code_w = 4'd8;
        if (|ch_error_w) error_code_w = 4'd9;
        if (msrc_error_w) error_code_w = 4'd10;
    end

    always @(posedge clk_mem_i or negedge rst_mem_n_i) begin
        if (!rst_mem_n_i) begin
            soft_pending_r <= 1'b0;
            clear_r <= 1'b0;
        end else begin
            clear_r <= soft_pending_r && !abort_all_r && !busy_w;
            if (soft_rst_w)
                soft_pending_r <= 1'b1;
            else if (clear_r)
                soft_pending_r <= 1'b0;
        end
    end
    edrv32_vin_regs u_regs (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_vin_n_w),

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

        // Configuration and software commands.
        .enable_o(enable_w),
        .abort_o(abort_w),
        .soft_rst_o(soft_rst_w),
        .cam0_size_o(cam0_size_w),
        .cam1_size_o(cam1_size_w),
        .msrc_base_o(msrc_base_w),
        .msrc_stride_o(msrc_stride_w),
        .msrc_size_o(msrc_size_w),
        .msrc_start_o(msrc_start_w),
        .ch_ctrl_o(ch_ctrl_w),
        .ch_stride_o(ch_stride_w),
        .ch_bases_o(ch_bases_w),
        .ch_slot_busy_o(ch_slot_busy_w),

        // Live status and event accounting.
        .busy_i(busy_w),
        .msrc_busy_i(msrc_busy_w),
        .ch_done_info_i(ch_done_info_w),
        .ch_done_frame_id_i(ch_done_frame_id_w),
        .ch_wr_stat_i(ch_wr_stat_w),
        .irq_set_i(irq_set_w),
        .error_code_i(error_code_w),
        .perf_event_i(perf_event_w),
        .cfg_errors_i(cfg_errors_w),

        // Interrupt.
        .irq_o(irq_o)
    );

    // A multicast word transfers to every selected channel on the same edge.
    generate
        for (source_idx = 0; source_idx < 3; source_idx = source_idx + 1) begin : g_ready
            assign source_ready_w[source_idx] =
                (ch_select_w[1:0] != source_idx || ch_ready_w[0]) &&
                (ch_select_w[3:2] != source_idx || ch_ready_w[1]);
        end
    endgenerate
    wire item0_valid_w;
    wire item0_ready_w;
    wire [35:0] item0_data_w;
    edrv32_vin_dvp u_cam0 (
        .clk_cam_i(cam0_pclk_i),
        .rst_cam_n_i(rst_cam0_n_i),
        .clk_mem_i(clk_mem_i),
        .rst_mem_n_i(rst_mem_n_i),

        // DVP sensor input.
        .vsync_i(cam0_vsync_i),
        .href_i(cam0_href_i),
        .data_i(cam0_data_i),

        // CDC item consumer.
        .item_valid_o(item0_valid_w),
        .item_ready_i(item0_ready_w),
        .item_data_o(item0_data_w)
    );
    edrv32_vin_fmt u_fmt0 (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_vin_n_w),

        // CDC item producer.
        .item_valid_i(item0_valid_w),
        .item_ready_o(item0_ready_w),
        .item_data_i(item0_data_w),

        // Normalized pixel stream.
        .valid_o(source_valid_w[0]),
        .ready_i(source_ready_w[0]),
        .data_o(source_data_w[31:0]),
        .sof_o(source_sof_w[0]),
        .eol_o(source_eol_w[0]),
        .eof_o(source_eof_w[0]),
        .frame_id_o(source_frame_id_w[31:0]),
        .width_o(source_width_w[10:0]),
        .height_o(source_height_w[11:0]),
        .incomplete_o(source_incomplete_w[0]),

        // Frame admission and shadow configuration.
        .enable_i(enable_w && !soft_pending_r),
        .width_i(cam0_size_w[10:0]),
        .height_i(cam0_size_w[27:16]),

        // Frame and error events.
        .frame_o(cam_frame_w[0]),
        .incomplete_frame_o(cam_incomplete_w[0]),
        .cfg_error_o(cam_cfg_error_w[0])
    );
    wire item1_valid_w;
    wire item1_ready_w;
    wire [35:0] item1_data_w;
    edrv32_vin_dvp u_cam1 (
        .clk_cam_i(cam1_pclk_i),
        .rst_cam_n_i(rst_cam1_n_i),
        .clk_mem_i(clk_mem_i),
        .rst_mem_n_i(rst_mem_n_i),

        // DVP sensor input.
        .vsync_i(cam1_vsync_i),
        .href_i(cam1_href_i),
        .data_i(cam1_data_i),

        // CDC item consumer.
        .item_valid_o(item1_valid_w),
        .item_ready_i(item1_ready_w),
        .item_data_o(item1_data_w)
    );
    edrv32_vin_fmt u_fmt1 (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_vin_n_w),

        // CDC item producer.
        .item_valid_i(item1_valid_w),
        .item_ready_o(item1_ready_w),
        .item_data_i(item1_data_w),

        // Normalized pixel stream.
        .valid_o(source_valid_w[1]),
        .ready_i(source_ready_w[1]),
        .data_o(source_data_w[63:32]),
        .sof_o(source_sof_w[1]),
        .eol_o(source_eol_w[1]),
        .eof_o(source_eof_w[1]),
        .frame_id_o(source_frame_id_w[63:32]),
        .width_o(source_width_w[21:11]),
        .height_o(source_height_w[23:12]),
        .incomplete_o(source_incomplete_w[1]),

        // Frame admission and shadow configuration.
        .enable_i(enable_w && !soft_pending_r),
        .width_i(cam1_size_w[10:0]),
        .height_i(cam1_size_w[27:16]),

        // Frame and error events.
        .frame_o(cam_frame_w[1]),
        .incomplete_frame_o(cam_incomplete_w[1]),
        .cfg_error_o(cam_cfg_error_w[1])
    );
    edrv32_vin_msrc u_msrc (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_vin_n_w),

        // Memory-source command and surface.
        .start_i(msrc_start_w && !soft_pending_r),
        .abort_i(abort_all_r),
        .base_i(msrc_base_w),
        .stride_i(msrc_stride_w),
        .width_i(msrc_size_w[10:0]),
        .height_i(msrc_size_w[27:16]),

        // Normalized pixel stream.
        .valid_o(source_valid_w[2]),
        .ready_i(source_ready_w[2]),
        .data_o(source_data_w[95:64]),
        .sof_o(source_sof_w[2]),
        .eol_o(source_eol_w[2]),
        .eof_o(source_eof_w[2]),
        .frame_id_o(source_frame_id_w[95:64]),
        .width_o(source_width_w[32:22]),
        .height_o(source_height_w[35:24]),

        // P1 read master.
        .p1_arid_o(p1_arid_o),
        .p1_araddr_o(p1_araddr_o),
        .p1_arlen_o(p1_arlen_o),
        .p1_arvalid_o(p1_arvalid_o),
        .p1_arready_i(p1_arready_i),
        .p1_rid_i(p1_rid_i),
        .p1_rdata_i(p1_rdata_i),
        .p1_rresp_i(p1_rresp_i),
        .p1_rlast_i(p1_rlast_i),
        .p1_rvalid_i(p1_rvalid_i),
        .p1_rready_o(p1_rready_o),
        .busy_o(msrc_busy_w),
        .done_o(msrc_done_w),
        .error_o(msrc_error_w),
        .cfg_error_o(msrc_cfg_error_w),

        // Frame and error events.
        .frame_o(msrc_frame_w)
    );
    assign source_incomplete_w[2] = 1'b0;

    generate
        for (channel_idx = 0; channel_idx < 2; channel_idx = channel_idx + 1) begin : g_channel
            wire [1:0] select_w;
            wire [1:0] other_select_w;
            wire [1:0] source_w;
            wire pipe_valid_w;
            wire pipe_ready_w;
            wire [31:0] pipe_data_w;
            wire pipe_sof_w;
            wire pipe_eol_w;
            wire pipe_eof_w;
            wire result_valid_w;
            wire result_ready_w;
            wire [31:0] result_data_w;
            wire result_eol_w;
            wire result_eof_w;
            wire valid_w;
            assign ch_select_w[channel_idx * 2 +: 2] = select_w;
            assign source_w = select_w == 2'd3 ? 2'd0 : select_w;
            assign other_select_w = ch_select_w[(1 - channel_idx) * 2 +: 2];
            assign valid_w = source_valid_w[source_w] &&
                (other_select_w != source_w || ch_ready_w[1 - channel_idx]);
            if (channel_idx == 0) begin : g_pix
                assign pix_in_valid_o = pipe_valid_w;
                assign pix_in_data_o = pipe_data_w;
                assign pix_in_sof_o = pipe_sof_w;
                assign pix_in_eol_o = pipe_eol_w;
                assign pix_in_eof_o = pipe_eof_w;
                assign pipe_ready_w = pix_in_ready_i;
                assign result_valid_w = pix_out_valid_i;
                assign result_data_w = pix_out_data_i;
                assign result_eol_w = pix_out_eol_i;
                assign result_eof_w = pix_out_eof_i;
                assign pix_out_ready_o = result_ready_w;
            end else begin : g_bypass
                wire unused_sof_w;
                assign unused_sof_w = pipe_sof_w;
                assign result_valid_w = pipe_valid_w;
                assign result_data_w = pipe_data_w;
                assign result_eol_w = pipe_eol_w;
                assign result_eof_w = pipe_eof_w;
                assign pipe_ready_w = result_ready_w;
            end
            edrv32_vin_ch u_channel (
                .clk_i(clk_mem_i),
                .rst_n_i(rst_vin_n_w),

                // Selected source before the channel pipeline.
                .source_valid_i(valid_w),
                .source_ready_o(ch_ready_w[channel_idx]),
                .source_data_i(source_data_w[source_w * 32 +: 32]),
                .source_sof_i(source_sof_w[source_w]),
                .source_eol_i(source_eol_w[source_w]),
                .source_eof_i(source_eof_w[source_w]),
                .source_frame_id_i(source_frame_id_w[source_w * 32 +: 32]),
                .source_width_i(source_width_w[source_w * 11 +: 11]),
                .source_height_i(source_height_w[source_w * 12 +: 12]),
                .source_incomplete_i(source_incomplete_w[source_w]),
                .frame_boundary_i(frame_boundary_w),

                // External PIX or local bypass.
                .pipe_valid_o(pipe_valid_w),
                .pipe_ready_i(pipe_ready_w),
                .pipe_data_o(pipe_data_w),
                .pipe_sof_o(pipe_sof_w),
                .pipe_eol_o(pipe_eol_w),
                .pipe_eof_o(pipe_eof_w),

                // Pipeline result stream.
                .result_valid_i(result_valid_w),
                .result_ready_o(result_ready_w),
                .result_data_i(result_data_w),
                .result_eol_i(result_eol_w),
                .result_eof_i(result_eof_w),

                // Frame admission and shadow configuration.
                .enable_i(enable_w && !soft_pending_r),
                .en_i(ch_ctrl_w[channel_idx * 8]),
                .src_i(ch_ctrl_w[channel_idx * 8 + 1 +: 2]),
                .ring_i(ch_ctrl_w[channel_idx * 8 + 4 +: 3]),
                .stride_i(ch_stride_w[channel_idx * 16 +: 16]),
                .bases_i(ch_bases_w[channel_idx * 128 +: 128]),
                .slot_busy_i(ch_slot_busy_w[channel_idx * 4 +: 4]),
                .abort_i(abort_all_r),
                .source_select_o(select_w),
                .busy_o(ch_busy_w[channel_idx]),
                .urgent_o(ch_urgent_w[channel_idx]),
                .count_o(ch_count_w[channel_idx * 10 +: 10]),
                .dma_abort_o(ch_abort_w[channel_idx]),
                .wr_stat_o(ch_wr_stat_w[channel_idx * 3 +: 3]),
                .done_info_o(ch_done_info_w[channel_idx * 6 +: 6]),
                .done_frame_id_o(ch_done_frame_id_w[channel_idx * 32 +: 32]),
                .done_o(ch_done_w[channel_idx]),
                .bus_error_o(ch_error_w[channel_idx]),
                .overflow_o(ch_overflow_w[channel_idx]),
                .skip_o(ch_skip_w[channel_idx]),
                .cfg_error_o(ch_cfg_error_w[channel_idx]),
                .cfg_errors_o(ch_cfg_errors_w[channel_idx * 2 +: 2]),

                // DMA write client.
                .axi_awaddr_o(ch_awaddr_w[channel_idx * 32 +: 32]),
                .axi_awlen_o(ch_awlen_w[channel_idx * 4 +: 4]),
                .axi_awvalid_o(ch_awvalid_w[channel_idx]),
                .axi_awready_i(ch_awready_w[channel_idx]),
                .axi_wdata_o(ch_wdata_w[channel_idx * 256 +: 256]),
                .axi_wstrb_o(ch_wstrb_w[channel_idx * 32 +: 32]),
                .axi_wlast_o(ch_wlast_w[channel_idx]),
                .axi_wvalid_o(ch_wvalid_w[channel_idx]),
                .axi_wready_i(ch_wready_w[channel_idx]),
                .axi_bresp_i(ch_bresp_w[channel_idx * 2 +: 2]),
                .axi_bvalid_i(ch_bvalid_w[channel_idx]),
                .axi_bready_o(ch_bready_w[channel_idx])
            );
        end
    endgenerate
    wire [1:0] ch2_source_w;
    wire unused_ch2_ready_w;
    assign ch2_source_w = ch_select_w[5:4] == 2'd3 ? 2'd0 : ch_select_w[5:4];
    edrv32_vin_ch2 u_ch2 (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_vin_n_w),

        // Selected source before the channel pipeline.
        .source_valid_i(source_valid_w[ch2_source_w] && source_ready_w[ch2_source_w]),
        .source_ready_o(unused_ch2_ready_w),
        .source_data_i(source_data_w[ch2_source_w * 32 +: 32]),
        .source_sof_i(source_sof_w[ch2_source_w]),
        .source_eol_i(source_eol_w[ch2_source_w]),
        .source_eof_i(source_eof_w[ch2_source_w]),
        .source_frame_id_i(source_frame_id_w[ch2_source_w * 32 +: 32]),
        .source_width_i(source_width_w[ch2_source_w * 11 +: 11]),
        .source_height_i(source_height_w[ch2_source_w * 12 +: 12]),
        .source_incomplete_i(source_incomplete_w[ch2_source_w]),
        .frame_boundary_i(frame_boundary_w),

        // Frame admission and shadow configuration.
        .enable_i(enable_w && !soft_pending_r),
        .en_i(ch_ctrl_w[2 * 8]),
        .src_i(ch_ctrl_w[2 * 8 + 1 +: 2]),
        .ring_i(ch_ctrl_w[2 * 8 + 4 +: 3]),
        .stride_i(ch_stride_w[2 * 16 +: 16]),
        .bases_i(ch_bases_w[2 * 128 +: 128]),
        .slot_busy_i(ch_slot_busy_w[2 * 4 +: 4]),
        .abort_i(abort_all_r),
        .source_select_o(ch_select_w[5:4]),
        .busy_o(ch_busy_w[2]),
        .count_o(ch_count_w[2 * 10 +: 10]),
        .dma_abort_o(ch_abort_w[2]),
        .wr_stat_o(ch_wr_stat_w[2 * 3 +: 3]),
        .done_info_o(ch_done_info_w[2 * 6 +: 6]),
        .done_frame_id_o(ch_done_frame_id_w[2 * 32 +: 32]),
        .done_o(ch_done_w[2]),
        .bus_error_o(ch_error_w[2]),
        .overflow_o(ch_overflow_w[2]),
        .skip_o(ch_skip_w[2]),
        .cfg_error_o(ch_cfg_error_w[2]),
        .cfg_errors_o(ch_cfg_errors_w[2 * 2 +: 2]),

        // DMA write client.
        .axi_awaddr_o(ch_awaddr_w[2 * 32 +: 32]),
        .axi_awlen_o(ch_awlen_w[2 * 4 +: 4]),
        .axi_awvalid_o(ch_awvalid_w[2]),
        .axi_awready_i(ch_awready_w[2]),
        .axi_wdata_o(ch_wdata_w[2 * 256 +: 256]),
        .axi_wstrb_o(ch_wstrb_w[2 * 32 +: 32]),
        .axi_wlast_o(ch_wlast_w[2]),
        .axi_wvalid_o(ch_wvalid_w[2]),
        .axi_wready_i(ch_wready_w[2]),
        .axi_bresp_i(ch_bresp_w[2 * 2 +: 2]),
        .axi_bvalid_i(ch_bvalid_w[2]),
        .axi_bready_o(ch_bready_w[2])
    );
    edrv32_vin_p1_arb u_p1 (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_vin_n_w),

        // DMA write clients.
        .ch_awaddr_i(ch_awaddr_w),
        .ch_awlen_i(ch_awlen_w),
        .ch_awvalid_i(ch_awvalid_w),
        .ch_awready_o(ch_awready_w),
        .ch_wdata_i(ch_wdata_w),
        .ch_wstrb_i(ch_wstrb_w),
        .ch_wlast_i(ch_wlast_w),
        .ch_wvalid_i(ch_wvalid_w),
        .ch_wready_o(ch_wready_w),
        .ch_bresp_o(ch_bresp_w),
        .ch_bvalid_o(ch_bvalid_w),
        .ch_bready_i(ch_bready_w),
        .ch_count_i(ch_count_w),
        .ch_abort_i(ch_abort_w),

        // P1 write master.
        .p1_awid_o(p1_awid_o),
        .p1_awaddr_o(p1_awaddr_o),
        .p1_awlen_o(p1_awlen_o),
        .p1_awvalid_o(p1_awvalid_o),
        .p1_awready_i(p1_awready_i),
        .p1_wdata_o(p1_wdata_o),
        .p1_wstrb_o(p1_wstrb_o),
        .p1_wlast_o(p1_wlast_o),
        .p1_wvalid_o(p1_wvalid_o),
        .p1_wready_i(p1_wready_i),
        .p1_bid_i(p1_bid_i),
        .p1_bresp_i(p1_bresp_i),
        .p1_bvalid_i(p1_bvalid_i),
        .p1_bready_o(p1_bready_o)
    );
endmodule
