// File: edrv32_npu.v
// Spec: npu-spec 2.4, 3, 4, 5, 6; edrv32-soc-spec 5.2 X9/X10.
// Description: Descriptor engine and serial operator ownership with boundary-only CDC.
// AXI cancellation drains accepted work before purging local queues and reporting IDLE.
// Clock: clk_npu; only the two boundary bridges also use clk_mem.
module edrv32_npu (
    // Clocks and domain-local resets.
    input wire clk_npu_i,
    input wire rst_npu_n_i,
    input wire clk_mem_i,
    input wire rst_mem_n_i,

    // Media APB slave, clk_mem.
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output wire apb_pready_o,
    output wire [31:0] apb_prdata_o,
    output wire apb_pslverr_o,

    // AXI256 DDR master, clk_mem.
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

    // Level interrupt, clk_npu.
    output wire irq_o
);
    wire local_apb_psel_w;
    wire local_apb_penable_w;
    wire local_apb_pwrite_w;
    wire [31:0] local_apb_pwdata_w;
    wire [3:0] local_apb_pstrb_w;
    wire local_apb_pready_w;
    wire [31:0] local_apb_prdata_w;
    wire local_apb_pslverr_w;
    wire busy_w;
    wire done_w;
    wire error_w;
    wire [2:0] error_code_w;
    wire [7:0] perf_event_w;
    wire start_w;
    wire abort_w;
    wire soft_reset_w;
    wire [31:0] desc_base_w;
    wire [31:0] desc_count_w;
    wire [127:0] bases_w;
    wire cancel_w;
    wire desc_data_valid_w;
    wire [255:0] read_data_w;
    wire decode_w;
    wire [511:0] desc_w;
    wire [31:0] in_addr_w;
    wire [31:0] out_addr_w;
    wire [31:0] residual_addr_w;
    wire [31:0] weight_addr_w;
    wire [31:0] quant_addr_w;
    wire decode_done_w;
    wire [2:0] decode_error_w;
    wire conv_start_w;
    wire stop_w;
    reg stop_r;
    wire conv_read_req_valid_w;
    wire conv_read_req_ready_w;
    wire [31:0] conv_read_req_addr_w;
    wire [4:0] conv_read_req_beats_w;
    wire [31:0] conv_read_req_tag_w;
    wire conv_read_data_valid_w;
    wire conv_read_data_ready_w;
    wire [255:0] conv_read_data_w;
    wire [31:0] conv_read_data_tag_w;
    wire [3:0] conv_read_data_index_w;
    wire conv_read_data_last_w;
    wire conv_write_req_valid_w;
    wire conv_write_req_ready_w;
    wire [31:0] conv_write_req_addr_w;
    wire [4:0] conv_write_req_beats_w;
    wire conv_write_data_valid_w;
    wire conv_write_data_ready_w;
    wire [255:0] conv_write_data_w;
    wire write_stream_idle_w;
    wire conv_done_w;
    wire conv_writer_idle_w;
    wire conv_mac_beat_w;
    wire conv_input_wait_w;
    wire conv_model_wait_w;
    wire nonconv_start_w;
    wire nonconv_read_req_valid_w;
    wire nonconv_read_req_ready_w;
    wire [31:0] nonconv_read_req_addr_w;
    wire [4:0] nonconv_read_req_beats_w;
    wire [31:0] nonconv_read_req_tag_w;
    wire nonconv_read_data_valid_w;
    wire nonconv_read_data_ready_w;
    wire [255:0] nonconv_read_data_w;
    wire [31:0] nonconv_read_data_tag_w;
    wire [3:0] nonconv_read_data_index_w;
    wire nonconv_read_data_last_w;
    wire nonconv_write_req_valid_w;
    wire nonconv_write_req_ready_w;
    wire [31:0] nonconv_write_req_addr_w;
    wire [4:0] nonconv_write_req_beats_w;
    wire nonconv_write_data_valid_w;
    wire nonconv_write_data_ready_w;
    wire [255:0] nonconv_write_data_w;
    wire nonconv_done_w;
    wire nonconv_writer_idle_w;
    wire nonconv_active_w;
    wire read_req_valid_w;
    wire read_req_ready_w;
    wire [31:0] read_req_addr_w;
    wire [4:0] read_req_beats_w;
    wire [31:0] read_req_tag_w;
    wire read_data_valid_w;
    wire read_data_ready_w;
    wire [31:0] read_data_tag_w;
    wire [3:0] read_data_index_w;
    wire read_data_last_w;
    wire local_axi_arid_w;
    wire [31:0] local_axi_araddr_w;
    wire [3:0] local_axi_arlen_w;
    wire local_axi_arvalid_w;
    wire local_axi_arready_w;
    wire local_axi_rid_w;
    wire [255:0] local_axi_rdata_w;
    wire [1:0] local_axi_rresp_w;
    wire local_axi_rlast_w;
    wire local_axi_rvalid_w;
    wire local_axi_rready_w;
    wire read_idle_w;
    wire read_error_w;
    wire read_beat_w;
    wire write_req_valid_w;
    wire write_req_ready_w;
    wire [31:0] write_req_addr_w;
    wire [4:0] write_req_beats_w;
    wire write_data_valid_w;
    wire write_data_ready_w;
    wire [255:0] write_data_w;
    wire local_axi_awid_w;
    wire [31:0] local_axi_awaddr_w;
    wire [3:0] local_axi_awlen_w;
    wire local_axi_awvalid_w;
    wire local_axi_awready_w;
    wire [255:0] local_axi_wdata_w;
    wire [31:0] local_axi_wstrb_w;
    wire local_axi_wlast_w;
    wire local_axi_wvalid_w;
    wire local_axi_wready_w;
    wire local_axi_bid_w;
    wire [1:0] local_axi_bresp_w;
    wire local_axi_bvalid_w;
    wire local_axi_bready_w;
    wire write_idle_w;
    wire write_error_w;
    wire write_beat_w;
    wire write_response_wait_w;
    wire [15:0] unused_apb_addr_w;

    localparam [3:0] S_IDLE = 4'd0;
    localparam [3:0] S_FETCH = 4'd1;
    localparam [3:0] S_FETCH_WAIT = 4'd2;
    localparam [3:0] S_DECODE = 4'd3;
    localparam [3:0] S_DECODE_WAIT = 4'd4;
    localparam [3:0] S_START = 4'd5;
    localparam [3:0] S_RUN = 4'd6;
    localparam [3:0] S_FENCE = 4'd7;
    localparam [3:0] S_COMPLETE = 4'd8;
    localparam [3:0] S_STOP = 4'd9;
    localparam [3:0] S_CANCEL = 4'd10;
    reg [3:0] state_r;
    reg [31:0] cur_desc_r;
    reg [31:0] desc_addr_r;
    reg is_conv_r;
    wire response_error_w;
    wire descriptor_error_w;
    wire local_done_w;
    wire local_writer_idle_w;
    assign busy_w = (state_r != S_IDLE);
    assign response_error_w = read_error_w || write_error_w;
    assign descriptor_error_w = (state_r == S_DECODE_WAIT) && decode_done_w
        && (decode_error_w != 3'd0);
    assign error_w = busy_w && (response_error_w || descriptor_error_w);
    assign error_code_w = read_error_w ? 3'd1 : write_error_w ? 3'd2 : decode_error_w;
    assign stop_w = (state_r == S_STOP) || (state_r == S_CANCEL)
        || (busy_w && (abort_w || descriptor_error_w));
    // Register the execution stop before the conv/DMA request-enable cone.
    // The top-level request and DONE masks below still use the immediate stop.
    always @(posedge clk_npu_i or negedge rst_npu_n_i) begin
        if (!rst_npu_n_i) begin
            stop_r <= 1'b0;
        end else begin
            stop_r <= stop_w;
        end
    end
    assign cancel_w = (state_r == S_CANCEL) || soft_reset_w;
    assign done_w = (state_r == S_COMPLETE) && !stop_w;
    assign decode_w = (state_r == S_DECODE);
    assign conv_start_w = (state_r == S_START) && is_conv_r && !stop_w;
    assign nonconv_start_w = (state_r == S_START) && !is_conv_r && !stop_w;
    assign local_done_w = is_conv_r ? conv_done_w : nonconv_done_w;
    assign local_writer_idle_w = conv_writer_idle_w && nonconv_writer_idle_w;
    assign desc_data_valid_w = (state_r == S_FETCH_WAIT) && read_data_valid_w && !stop_w;

    assign read_req_valid_w = !stop_w && ((state_r == S_FETCH)
        || ((state_r == S_RUN) && (is_conv_r ? conv_read_req_valid_w : nonconv_read_req_valid_w)));
    assign read_req_addr_w = (state_r == S_FETCH) ? desc_addr_r
        : is_conv_r ? conv_read_req_addr_w : nonconv_read_req_addr_w;
    assign read_req_beats_w = (state_r == S_FETCH) ? 5'd2
        : is_conv_r ? conv_read_req_beats_w : nonconv_read_req_beats_w;
    assign read_req_tag_w = (state_r == S_FETCH) ? 32'd0
        : is_conv_r ? conv_read_req_tag_w : nonconv_read_req_tag_w;
    assign conv_read_req_ready_w = read_req_ready_w && (state_r == S_RUN) && is_conv_r;
    assign nonconv_read_req_ready_w = read_req_ready_w && (state_r == S_RUN) && !is_conv_r;
    assign read_data_ready_w = (state_r == S_FETCH_WAIT) || stop_w
        || (is_conv_r ? conv_read_data_ready_w : nonconv_read_data_ready_w);
    assign conv_read_data_valid_w = read_data_valid_w && (state_r == S_RUN) && is_conv_r;
    assign nonconv_read_data_valid_w = read_data_valid_w && (state_r == S_RUN) && !is_conv_r;
    assign conv_read_data_w = read_data_w;
    assign nonconv_read_data_w = read_data_w;
    assign conv_read_data_tag_w = read_data_tag_w;
    assign nonconv_read_data_tag_w = read_data_tag_w;
    assign conv_read_data_index_w = read_data_index_w;
    assign nonconv_read_data_index_w = read_data_index_w;
    assign conv_read_data_last_w = read_data_last_w;
    assign nonconv_read_data_last_w = read_data_last_w;
    assign write_req_valid_w = !stop_w
        && (is_conv_r ? conv_write_req_valid_w : nonconv_write_req_valid_w);
    assign write_req_addr_w = is_conv_r ? conv_write_req_addr_w : nonconv_write_req_addr_w;
    assign write_req_beats_w = is_conv_r ? conv_write_req_beats_w : nonconv_write_req_beats_w;
    assign conv_write_req_ready_w = write_req_ready_w && is_conv_r;
    assign nonconv_write_req_ready_w = write_req_ready_w && !is_conv_r;
    assign write_data_valid_w = is_conv_r ? conv_write_data_valid_w : nonconv_write_data_valid_w;
    assign write_data_w = is_conv_r ? conv_write_data_w : nonconv_write_data_w;
    assign conv_write_data_ready_w = write_data_ready_w && is_conv_r;
    assign nonconv_write_data_ready_w = write_data_ready_w && !is_conv_r;
    assign perf_event_w = {nonconv_active_w, write_response_wait_w, conv_model_wait_w,
        conv_input_wait_w, write_beat_w, read_beat_w, conv_mac_beat_w, busy_w};

    always @(posedge clk_npu_i or negedge rst_npu_n_i) begin
        if (!rst_npu_n_i) begin
            state_r <= S_IDLE;
            cur_desc_r <= 32'd0;
            is_conv_r <= 1'b0;
        end else if (soft_reset_w) begin
            state_r <= S_IDLE;
            cur_desc_r <= 32'd0;
            is_conv_r <= 1'b0;
        end else if (busy_w && (abort_w || response_error_w || descriptor_error_w)
            && (state_r != S_STOP) && (state_r != S_CANCEL)) begin
            state_r <= S_STOP;
        end else begin
            case (state_r)
                S_IDLE: begin
                    if (start_w) begin
                        // With no descriptors, the completed index is COUNT-1 as in spec 4.
                        cur_desc_r <= (desc_count_w == 32'd0) ? 32'hffffffff : 32'd0;
                        state_r <= (desc_count_w == 32'd0) ? S_COMPLETE : S_FETCH;
                    end
                end
                S_FETCH: begin
                    if (read_req_ready_w) begin
                        state_r <= S_FETCH_WAIT;
                    end
                end
                S_FETCH_WAIT: begin
                    if (desc_data_valid_w && read_data_last_w) begin
                        state_r <= S_DECODE;
                    end
                end
                S_DECODE: state_r <= S_DECODE_WAIT;
                S_DECODE_WAIT: begin
                    if (decode_done_w) begin
                        is_conv_r <= (desc_w[3:0] == 4'd0);
                        state_r <= S_START;
                    end
                end
                S_START: state_r <= S_RUN;
                S_RUN: begin
                    if (local_done_w) begin
                        state_r <= S_FENCE;
                    end
                end
                S_FENCE: begin
                    if (read_idle_w && write_idle_w) begin
                        if (cur_desc_r == desc_count_w - 32'd1) begin
                            state_r <= S_COMPLETE;
                        end else begin
                            cur_desc_r <= cur_desc_r + 32'd1;
                            state_r <= S_FETCH;
                        end
                    end
                end
                S_COMPLETE: state_r <= S_IDLE;
                S_STOP: begin
                    if (read_idle_w && write_idle_w && local_writer_idle_w) begin
                        state_r <= S_CANCEL;
                    end
                end
                S_CANCEL: state_r <= S_IDLE;
                default: begin end
            endcase
        end
    end
    always @(posedge clk_npu_i) begin
        if (start_w) begin
            desc_addr_r <= desc_base_w;
        end else if ((state_r == S_FENCE) && read_idle_w && write_idle_w) begin
            desc_addr_r <= desc_addr_r + 32'd64;
        end
    end
    edrv32_npu_regs u_regs (
        // Clocks and domain-local resets.
        .clk_i(clk_npu_i),
        .rst_n_i(rst_npu_n_i),

        // APB register interface.
        .apb_paddr_i(unused_apb_addr_w[11:0]),
        .apb_psel_i(local_apb_psel_w),
        .apb_penable_i(local_apb_penable_w),
        .apb_pwrite_i(local_apb_pwrite_w),
        .apb_pwdata_i(local_apb_pwdata_w),
        .apb_pstrb_i(local_apb_pstrb_w),
        .apb_pready_o(local_apb_pready_w),
        .apb_prdata_o(local_apb_prdata_w),
        .apb_pslverr_o(local_apb_pslverr_w),

        // Descriptor configuration and execution status.
        .busy_i(busy_w),
        .done_i(done_w),

        // Interrupt and activity events.
        .error_i(error_w),
        .error_code_i(error_code_w),

        // Descriptor configuration and execution status.
        .cur_desc_i(cur_desc_r),

        // Interrupt and activity events.
        .perf_event_i(perf_event_w),

        // Descriptor configuration and execution status.
        .start_o(start_w),

        // Execution lifetime.
        .abort_o(abort_w),
        .soft_reset_o(soft_reset_w),

        // Descriptor configuration and execution status.
        .desc_base_o(desc_base_w),
        .desc_count_o(desc_count_w),
        .bases_o(bases_w),

        // Interrupt and activity events.
        .irq_o(irq_o)
    );

    edrv32_npu_descriptor u_descriptor (
        // Clocks and domain-local resets.
        .clk_i(clk_npu_i),
        .rst_n_i(rst_npu_n_i),

        // Execution lifetime.
        .cancel_i(cancel_w),

        // Descriptor configuration and execution status.
        .data_valid_i(desc_data_valid_w),
        .data_index_i(read_data_index_w[0]),
        .data_i(read_data_w),
        .decode_i(decode_w),
        .bases_i(bases_w),
        .desc_o(desc_w),
        .in_addr_o(in_addr_w),
        .out_addr_o(out_addr_w),

        // Residual batches and scatter writes.
        .residual_addr_o(residual_addr_w),

        // Resident weights.
        .weight_addr_o(weight_addr_w),

        // Quantization parameter loading.
        .quant_addr_o(quant_addr_w),

        // Descriptor configuration and execution status.
        .done_o(decode_done_w),

        // Interrupt and activity events.
        .error_o(decode_error_w)
    );

    edrv32_npu_conv u_conv (
        // Clocks and domain-local resets.
        .clk_i(clk_npu_i),
        .rst_n_i(rst_npu_n_i),

        // Execution lifetime.
        .start_i(conv_start_w),
        .stop_i(stop_r),
        .cancel_i(cancel_w),

        // Descriptor configuration and execution status.
        .desc_i(desc_w),
        .in_addr_i(in_addr_w),
        .out_addr_i(out_addr_w),

        // Residual batches and scatter writes.
        .residual_addr_i(residual_addr_w),

        // Resident weights.
        .weight_addr_i(weight_addr_w),

        // Quantization parameter loading.
        .quant_addr_i(quant_addr_w),

        // Read DMA requests and returns.
        .read_req_valid_o(conv_read_req_valid_w),
        .read_req_ready_i(conv_read_req_ready_w),
        .read_req_addr_o(conv_read_req_addr_w),
        .read_req_beats_o(conv_read_req_beats_w),
        .read_req_tag_o(conv_read_req_tag_w),
        .read_data_valid_i(conv_read_data_valid_w),
        .read_data_ready_o(conv_read_data_ready_w),
        .read_data_i(conv_read_data_w),
        .read_data_tag_i(conv_read_data_tag_w),
        .read_data_index_i(conv_read_data_index_w),
        .read_data_last_i(conv_read_data_last_w),

        // Write DMA requests and data.
        .write_req_valid_o(conv_write_req_valid_w),
        .write_req_ready_i(conv_write_req_ready_w),
        .write_req_addr_o(conv_write_req_addr_w),
        .write_req_beats_o(conv_write_req_beats_w),
        .write_data_valid_o(conv_write_data_valid_w),
        .write_data_ready_i(conv_write_data_ready_w),
        .write_data_o(conv_write_data_w),
        .write_stream_idle_i(write_stream_idle_w),

        // Descriptor configuration and execution status.
        .done_o(conv_done_w),
        .writer_idle_o(conv_writer_idle_w),
        .mac_beat_o(conv_mac_beat_w),
        .input_wait_o(conv_input_wait_w),
        .model_wait_o(conv_model_wait_w)
    );

    edrv32_npu_nonconv u_nonconv (
        // Clocks and domain-local resets.
        .clk_i(clk_npu_i),
        .rst_n_i(rst_npu_n_i),

        // Execution lifetime.
        .start_i(nonconv_start_w),
        .stop_i(stop_w),
        .cancel_i(cancel_w),

        // Descriptor configuration and execution status.
        .desc_i(desc_w),
        .in_addr_i(in_addr_w),
        .out_addr_i(out_addr_w),

        // Read DMA requests and returns.
        .read_req_valid_o(nonconv_read_req_valid_w),
        .read_req_ready_i(nonconv_read_req_ready_w),
        .read_req_addr_o(nonconv_read_req_addr_w),
        .read_req_beats_o(nonconv_read_req_beats_w),
        .read_req_tag_o(nonconv_read_req_tag_w),
        .read_data_valid_i(nonconv_read_data_valid_w),
        .read_data_ready_o(nonconv_read_data_ready_w),
        .read_data_i(nonconv_read_data_w),
        .read_data_tag_i(nonconv_read_data_tag_w),
        .read_data_index_i(nonconv_read_data_index_w),
        .read_data_last_i(nonconv_read_data_last_w),

        // Write DMA requests and data.
        .write_req_valid_o(nonconv_write_req_valid_w),
        .write_req_ready_i(nonconv_write_req_ready_w),
        .write_req_addr_o(nonconv_write_req_addr_w),
        .write_req_beats_o(nonconv_write_req_beats_w),
        .write_data_valid_o(nonconv_write_data_valid_w),
        .write_data_ready_i(nonconv_write_data_ready_w),
        .write_data_o(nonconv_write_data_w),
        .write_stream_idle_i(write_stream_idle_w),

        // Descriptor configuration and execution status.
        .done_o(nonconv_done_w),
        .writer_idle_o(nonconv_writer_idle_w),
        .active_o(nonconv_active_w)
    );

    edrv32_npu_read_dma u_read_dma (
        // Clocks and domain-local resets.
        .clk_i(clk_npu_i),
        .rst_n_i(rst_npu_n_i),

        // Execution lifetime.
        .stop_i(stop_r),

        // Descriptor configuration and execution status.
        .req_valid_i(read_req_valid_w),
        .req_ready_o(read_req_ready_w),
        .req_addr_i(read_req_addr_w),
        .req_beats_i(read_req_beats_w),
        .req_tag_i(read_req_tag_w),
        .data_valid_o(read_data_valid_w),
        .data_ready_i(read_data_ready_w),
        .data_o(read_data_w),
        .data_tag_o(read_data_tag_w),
        .data_index_o(read_data_index_w),
        .data_last_o(read_data_last_w),

        // AXI256 channels.
        .axi_arid_o(local_axi_arid_w),
        .axi_araddr_o(local_axi_araddr_w),
        .axi_arlen_o(local_axi_arlen_w),
        .axi_arvalid_o(local_axi_arvalid_w),
        .axi_arready_i(local_axi_arready_w),
        .axi_rid_i(local_axi_rid_w),
        .axi_rdata_i(local_axi_rdata_w),
        .axi_rresp_i(local_axi_rresp_w),
        .axi_rlast_i(local_axi_rlast_w),
        .axi_rvalid_i(local_axi_rvalid_w),
        .axi_rready_o(local_axi_rready_w),

        // Descriptor configuration and execution status.
        .idle_o(read_idle_w),

        // Interrupt and activity events.
        .error_o(read_error_w),

        // Descriptor configuration and execution status.
        .beat_o(read_beat_w)
    );

    edrv32_npu_write_dma u_write_dma (
        // Clocks and domain-local resets.
        .clk_i(clk_npu_i),
        .rst_n_i(rst_npu_n_i),

        // Execution lifetime.
        .stop_i(stop_w),

        // Descriptor configuration and execution status.
        .req_valid_i(write_req_valid_w),
        .req_ready_o(write_req_ready_w),
        .req_addr_i(write_req_addr_w),
        .req_beats_i(write_req_beats_w),
        .data_valid_i(write_data_valid_w),
        .data_ready_o(write_data_ready_w),
        .data_i(write_data_w),
        .data_strb_i(32'hffffffff),
        .stream_idle_o(write_stream_idle_w),

        // AXI256 channels.
        .axi_awid_o(local_axi_awid_w),
        .axi_awaddr_o(local_axi_awaddr_w),
        .axi_awlen_o(local_axi_awlen_w),
        .axi_awvalid_o(local_axi_awvalid_w),
        .axi_awready_i(local_axi_awready_w),
        .axi_wdata_o(local_axi_wdata_w),
        .axi_wstrb_o(local_axi_wstrb_w),
        .axi_wlast_o(local_axi_wlast_w),
        .axi_wvalid_o(local_axi_wvalid_w),
        .axi_wready_i(local_axi_wready_w),
        .axi_bid_i(local_axi_bid_w),
        .axi_bresp_i(local_axi_bresp_w),
        .axi_bvalid_i(local_axi_bvalid_w),
        .axi_bready_o(local_axi_bready_w),

        // Descriptor configuration and execution status.
        .idle_o(write_idle_w),

        // Interrupt and activity events.
        .error_o(write_error_w),

        // Descriptor configuration and execution status.
        .beat_o(write_beat_w),
        .response_wait_o(write_response_wait_w)
    );

    edrv32_apb_async_bridge u_apb_bridge (
        // Clocks and domain-local resets.
        .clk_s_i(clk_mem_i),
        .rst_s_n_i(rst_mem_n_i),
        .clk_m_i(clk_npu_i),
        .rst_m_n_i(rst_npu_n_i),

        // APB register interface.
        .s_apb_paddr_i({4'd0, apb_paddr_i}),
        .s_apb_psel_i(apb_psel_i),
        .s_apb_penable_i(apb_penable_i),
        .s_apb_pwrite_i(apb_pwrite_i),
        .s_apb_pwdata_i(apb_pwdata_i),
        .s_apb_pstrb_i(apb_pstrb_i),
        .s_apb_prdata_o(apb_prdata_o),
        .s_apb_pready_o(apb_pready_o),
        .s_apb_pslverr_o(apb_pslverr_o),
        .m_apb_paddr_o(unused_apb_addr_w),
        .m_apb_psel_o(local_apb_psel_w),
        .m_apb_penable_o(local_apb_penable_w),
        .m_apb_pwrite_o(local_apb_pwrite_w),
        .m_apb_pwdata_o(local_apb_pwdata_w),
        .m_apb_pstrb_o(local_apb_pstrb_w),
        .m_apb_prdata_i(local_apb_prdata_w),
        .m_apb_pready_i(local_apb_pready_w),
        .m_apb_pslverr_i(local_apb_pslverr_w)
    );

    edrv32_axi256_async_bridge u_axi_bridge (
        // Clocks and domain-local resets.
        .clk_npu_i(clk_npu_i),
        .rst_npu_n_i(rst_npu_n_i),
        .clk_mem_i(clk_mem_i),
        .rst_mem_n_i(rst_mem_n_i),

        // AXI256 channels.
        .s_axi_awid_i(local_axi_awid_w),
        .s_axi_awaddr_i(local_axi_awaddr_w),
        .s_axi_awlen_i(local_axi_awlen_w),
        .s_axi_awvalid_i(local_axi_awvalid_w),
        .s_axi_awready_o(local_axi_awready_w),
        .s_axi_wdata_i(local_axi_wdata_w),
        .s_axi_wstrb_i(local_axi_wstrb_w),
        .s_axi_wlast_i(local_axi_wlast_w),
        .s_axi_wvalid_i(local_axi_wvalid_w),
        .s_axi_wready_o(local_axi_wready_w),
        .s_axi_bid_o(local_axi_bid_w),
        .s_axi_bresp_o(local_axi_bresp_w),
        .s_axi_bvalid_o(local_axi_bvalid_w),
        .s_axi_bready_i(local_axi_bready_w),
        .s_axi_arid_i(local_axi_arid_w),
        .s_axi_araddr_i(local_axi_araddr_w),
        .s_axi_arlen_i(local_axi_arlen_w),
        .s_axi_arvalid_i(local_axi_arvalid_w),
        .s_axi_arready_o(local_axi_arready_w),
        .s_axi_rid_o(local_axi_rid_w),
        .s_axi_rdata_o(local_axi_rdata_w),
        .s_axi_rresp_o(local_axi_rresp_w),
        .s_axi_rlast_o(local_axi_rlast_w),
        .s_axi_rvalid_o(local_axi_rvalid_w),
        .s_axi_rready_i(local_axi_rready_w),
        .m_axi_awid_o(axi_awid_o),
        .m_axi_awaddr_o(axi_awaddr_o),
        .m_axi_awlen_o(axi_awlen_o),
        .m_axi_awvalid_o(axi_awvalid_o),
        .m_axi_awready_i(axi_awready_i),
        .m_axi_wdata_o(axi_wdata_o),
        .m_axi_wstrb_o(axi_wstrb_o),
        .m_axi_wlast_o(axi_wlast_o),
        .m_axi_wvalid_o(axi_wvalid_o),
        .m_axi_wready_i(axi_wready_i),
        .m_axi_bid_i(axi_bid_i),
        .m_axi_bresp_i(axi_bresp_i),
        .m_axi_bvalid_i(axi_bvalid_i),
        .m_axi_bready_o(axi_bready_o),
        .m_axi_arid_o(axi_arid_o),
        .m_axi_araddr_o(axi_araddr_o),
        .m_axi_arlen_o(axi_arlen_o),
        .m_axi_arvalid_o(axi_arvalid_o),
        .m_axi_arready_i(axi_arready_i),
        .m_axi_rid_i(axi_rid_i),
        .m_axi_rdata_i(axi_rdata_i),
        .m_axi_rresp_i(axi_rresp_i),
        .m_axi_rlast_i(axi_rlast_i),
        .m_axi_rvalid_i(axi_rvalid_i),
        .m_axi_rready_o(axi_rready_o)
    );
endmodule
