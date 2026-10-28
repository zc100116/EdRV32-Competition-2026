// File: edrv32_geo.v
// Spec: geo-spec 2--6; dma2d-spec 3, 5; SoC 4.2, 4.3, 7.1--7.3, 8.11.
// Description: Descriptor-driven affine engine with overlapped source filling and sampling.
// All DDR traffic passes through the shared 2D DMA units; ABORT drains both units.
// Clock domain: clk_mem.
module edrv32_geo (
    // Clock and reset.
    input wire clk_mem_i,
    input wire rst_mem_n_i,

    // APB control.
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output wire apb_pready_o,
    output wire [31:0] apb_prdata_o,
    output wire apb_pslverr_o,

    // P5 AXI256 data plane.
    output wire p5_awid_o,
    output wire [31:0] p5_awaddr_o,
    output wire [3:0] p5_awlen_o,
    output wire p5_awvalid_o,
    input wire p5_awready_i,
    output wire [255:0] p5_wdata_o,
    output wire [31:0] p5_wstrb_o,
    output wire p5_wlast_o,
    output wire p5_wvalid_o,
    input wire p5_wready_i,
    input wire p5_bid_i,
    input wire [1:0] p5_bresp_i,
    input wire p5_bvalid_i,
    output wire p5_bready_o,
    output wire p5_arid_o,
    output wire [31:0] p5_araddr_o,
    output wire [3:0] p5_arlen_o,
    output wire p5_arvalid_o,
    input wire p5_arready_i,
    input wire p5_rid_i,
    input wire [255:0] p5_rdata_i,
    input wire [1:0] p5_rresp_i,
    input wire p5_rlast_i,
    input wire p5_rvalid_i,
    output wire p5_rready_o,

    // Interrupt.
    output wire irq_o
);
    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_DESC_REQ = 3'd1;
    localparam [2:0] S_DESC_DATA = 3'd2;
    localparam [2:0] S_CHECK = 3'd3;
    localparam [2:0] S_RUN = 3'd4;
    localparam [2:0] S_NEXT = 3'd5;
    localparam [2:0] S_DRAIN = 3'd6;
    localparam [2:0] S_PREP = 3'd7;
    reg [2:0] state_r;
    reg [1:0] prepare_r;
    reg [2:0] fill_state_r;
    reg [1:0] compute_state_r;
    reg fill_group_r;
    reg compute_group_r;
    reg [1:0] source_ready_r;
    reg [6:0] fill_row_r;
    reg [2:0] fill_word_r;
    reg desc_half_r;
    reg [511:0] desc_r;
    reg [31:0] table_base_r;
    reg [15:0] table_count_r;
    reg [15:0] cur_desc_r;
    wire start_w;
    wire abort_w;
    wire soft_reset_w;
    wire [31:0] desc_base_w;
    wire [15:0] desc_count_w;
    wire busy_w;
    wire stop_w;
    wire clear_w;
    reg [1:0] error_w;
    wire range_error_w;
    wire rd_idle_w;
    wire wr_idle_w;
    wire rd_desc_ready_w;
    wire wr_desc_ready_w;
    wire rd_done_w;
    wire wr_done_w;
    wire rd_err_w;
    wire wr_err_w;
    wire rd_valid_w;
    wire [255:0] rd_data_w;
    wire rd_sol_w;
    wire rd_eol_w;
    wire rd_eof_w;
    wire rd_desc_valid_w;
    wire [31:0] rd_base_w;
    wire [31:0] rd_stride_w;
    wire [15:0] rd_width_w;
    wire [11:0] rd_height_w;
    wire wr_desc_valid_w;
    wire wr_data_ready_w;
    wire [31:0] wr_base_w;
    wire [12:0] wr_row_w;
    wire read_addr_done_w;
    wire write_addr_done_w;
    wire [31:0] read_addr_w;
    wire [31:0] write_addr_w;
    wire [12:0] wr_column_w;
    wire [15:0] wr_width_w;
    wire [11:0] wr_height_w;
    wire desc_done_w;
    wire table_done_w;
    wire unused_w;
    wire [31:0] src_base_w;
    wire [31:0] src_stride_w;
    wire [11:0] src_w_w;
    wire [11:0] src_h_w;
    wire [31:0] dst_base_w;
    wire [31:0] dst_stride_w;
    wire [11:0] rect_x_w;
    wire [11:0] rect_y_w;
    wire [11:0] rect_w_w;
    wire [11:0] rect_h_w;
    wire [15:0] bg_w;
    wire [31:0] a_w;
    wire [31:0] b_w;
    wire [31:0] tx_w;
    wire [31:0] c_w;
    wire [31:0] d_w;
    wire [31:0] ty_w;
    wire tile_valid_w;
    wire tile_ready_w;
    wire [11:0] tile_u_w;
    wire [11:0] tile_v_w;
    wire [5:0] tile_width_w;
    wire [4:0] tile_height_w;
    wire [31:0] tile_x_w;
    wire [31:0] tile_y_w;
    wire tile_last_w;
    wire tiles_start_w;
    wire bounds_empty_w;
    wire bounds_done_w;
    wire bounds_start_w;
    wire [11:0] bounds_x_w;
    wire [11:0] bounds_y_w;
    wire [15:0] bounds_width_w;
    wire [11:0] bounds_height_w;
    reg [11:0] group_u_r [0:1];
    reg [11:0] group_v_r [0:1];
    reg [5:0] group_width_r [0:1];
    reg [4:0] group_height_r [0:1];
    reg [31:0] group_x_r [0:1];
    reg [31:0] group_y_r [0:1];
    reg [11:0] group_origin_x_r [0:1];
    reg [11:0] group_origin_y_r [0:1];
    reg [15:0] group_read_width_r [0:1];
    reg [11:0] group_read_height_r [0:1];
    reg [1:0] group_last_r;
    wire coord_start_w;
    wire coord_valid_w;
    wire [31:0] coord_x_w;
    wire [31:0] coord_y_w;
    wire coord_eol_w;
    wire coord_last_w;
    wire advance_w;
    wire sample_fire_w;
    reg sample_valid_r;
    reg [7:0] sample_fx_r;
    reg [7:0] sample_fy_r;
    reg sample_eol_r;
    wire [15:0] p00_w;
    wire [15:0] p01_w;
    wire [15:0] p10_w;
    wire [15:0] p11_w;
    wire pixel_valid_w;
    wire pixel_eol_w;
    wire [15:0] pixel_w;
    reg [3:0] pack_lane_r;
    reg pack_valid_r;
    reg [255:0] accumulator_r;
    reg [255:0] pack_data_r;
    reg [31:0] pack_strb_r;
    reg [255:0] pack_next_w;
    wire pixel_fire_w;
    reg [4:0] write_pixels_w;
    integer pixel_lane;
    assign busy_w = state_r != S_IDLE || !rd_idle_w || !wr_idle_w;
    assign stop_w = busy_w && (abort_w || error_w != 0);
    assign clear_w = stop_w || state_r == S_DRAIN || soft_reset_w;
    assign desc_done_w = state_r == S_NEXT && !stop_w;
    assign table_done_w = desc_done_w && cur_desc_r + 16'd1 == table_count_r;
    assign unused_w = &{rd_sol_w, rd_eof_w, rd_err_w, wr_err_w, coord_last_w};
    always @(*) begin
        error_w = 2'd0;
        if (state_r == S_CHECK && range_error_w)
            error_w = 2'd3;
        if (busy_w && p5_rvalid_i && p5_rready_o && p5_rresp_i != 0)
            error_w = 2'd1;
        if (busy_w && p5_bvalid_i && p5_bready_o && p5_bresp_i != 0)
            error_w = 2'd2;
    end
    assign tiles_start_w = state_r == S_CHECK && !range_error_w && !stop_w;
    assign bounds_start_w = state_r == S_RUN && fill_state_r == 0 &&
        tile_valid_w && !source_ready_r[fill_group_r] && !stop_w;
    assign tile_ready_w = state_r == S_RUN && fill_state_r == 1 && bounds_done_w &&
        !stop_w;
    assign rd_desc_valid_w = !stop_w && (state_r == S_DESC_REQ ||
        (state_r == S_RUN && fill_state_r == 3));
    assign rd_base_w = state_r == S_DESC_REQ ?
        table_base_r + {10'd0, cur_desc_r, 6'd0} :
        read_addr_w;
    assign rd_stride_w = state_r == S_DESC_REQ ? 32'd64 : src_stride_w;
    assign rd_width_w = state_r == S_DESC_REQ ? 16'd64 :
        group_read_width_r[fill_group_r];
    assign rd_height_w = state_r == S_DESC_REQ ? 12'd1 :
        group_read_height_r[fill_group_r];
    assign wr_desc_valid_w = state_r == S_RUN && compute_state_r == 2 && !stop_w;
    assign wr_row_w = {1'b0, rect_y_w} + {1'b0, group_v_r[compute_group_r]};
    assign wr_column_w = {1'b0, rect_x_w} + {1'b0, group_u_r[compute_group_r]};
    assign wr_base_w = write_addr_w;
    assign wr_width_w = {9'd0, group_width_r[compute_group_r], 1'b0};
    assign wr_height_w = {7'd0, group_height_r[compute_group_r]};
    assign coord_start_w = wr_desc_valid_w && wr_desc_ready_w;
    assign advance_w = !pack_valid_r || wr_data_ready_w;
    assign sample_fire_w = coord_valid_w && advance_w &&
        state_r == S_RUN && compute_state_r == 3 && !stop_w;
    assign pixel_fire_w = pixel_valid_w && advance_w && !clear_w;
    // PERF1 counts pixels that actually cross the DDR write channel, including ABORT tails.
    always @(*) begin
        write_pixels_w = 5'd0;
        if (p5_wvalid_o && p5_wready_i) begin
            for (pixel_lane = 0; pixel_lane < 16; pixel_lane = pixel_lane + 1)
                write_pixels_w = write_pixels_w + {4'd0, p5_wstrb_o[pixel_lane*2]};
        end
    end
    always @(*) begin
        pack_next_w = accumulator_r;
        pack_next_w[{pack_lane_r, 4'd0} +: 16] = pixel_w;
    end
    always @(posedge clk_mem_i or negedge rst_mem_n_i) begin
        if (!rst_mem_n_i) begin
            state_r <= S_IDLE;
            prepare_r <= 2'd0;
            fill_state_r <= 3'd0;
            compute_state_r <= 2'd0;
            fill_group_r <= 1'b0;
            compute_group_r <= 1'b0;
            source_ready_r <= 2'd0;
            fill_row_r <= 7'd0;
            fill_word_r <= 3'd0;
            desc_half_r <= 1'b0;
            cur_desc_r <= 16'd0;
        end else if (soft_reset_w) begin
            state_r <= S_IDLE;
            fill_state_r <= 3'd0;
            compute_state_r <= 2'd0;
            source_ready_r <= 2'd0;
            cur_desc_r <= 16'd0;
        end else if (stop_w) begin
            state_r <= S_DRAIN;
            source_ready_r <= 2'd0;
            fill_state_r <= 3'd0;
            compute_state_r <= 2'd0;
        end else begin
            case (state_r)
                S_IDLE: begin
                    if (start_w) begin
                        cur_desc_r <= 16'd0;
                        if (desc_count_w != 0)
                            state_r <= S_DESC_REQ;
                    end
                end
                S_DESC_REQ: begin
                    if (rd_desc_ready_w) begin
                        state_r <= S_DESC_DATA;
                        desc_half_r <= 1'b0;
                    end
                end
                S_DESC_DATA: begin
                    if (rd_valid_w)
                        desc_half_r <= 1'b1;
                    if (rd_done_w) begin
                        state_r <= S_PREP;
                        prepare_r <= 2'd0;
                    end
                end
                S_PREP: begin
                    // Complete the four registered range-check stages before using the result.
                    prepare_r <= prepare_r + 2'd1;
                    if (prepare_r == 2'd3)
                        state_r <= S_CHECK;
                end
                S_CHECK: begin
                    fill_group_r <= 1'b0;
                    compute_group_r <= 1'b0;
                    source_ready_r <= 2'd0;
                    fill_state_r <= 3'd0;
                    compute_state_r <= 2'd0;
                    if (rect_w_w == 0 || rect_h_w == 0)
                        state_r <= S_NEXT;
                    else
                        state_r <= S_RUN;
                end
                S_RUN: begin
                    if (bounds_start_w)
                        fill_state_r <= 3'd1;
                    if (tile_valid_w && tile_ready_w) begin
                        if (bounds_empty_w) begin
                            fill_state_r <= 3'd0;
                            source_ready_r[fill_group_r] <= 1'b1;
                            fill_group_r <= !fill_group_r;
                        end else begin
                            fill_state_r <= 3'd2;
                        end
                    end
                    if (fill_state_r == 2 && read_addr_done_w)
                        fill_state_r <= 3'd3;
                    if (fill_state_r == 3 && rd_desc_ready_w) begin
                        fill_state_r <= 3'd4;
                        fill_row_r <= 7'd0;
                        fill_word_r <= 3'd0;
                    end
                    if (fill_state_r == 4 && rd_valid_w) begin
                        if (rd_eol_w) begin
                            fill_row_r <= fill_row_r + 7'd1;
                            fill_word_r <= 3'd0;
                        end else begin
                            fill_word_r <= fill_word_r + 3'd1;
                        end
                    end
                    if (fill_state_r == 4 && rd_done_w) begin
                        source_ready_r[fill_group_r] <= 1'b1;
                        fill_group_r <= !fill_group_r;
                        fill_state_r <= 3'd0;
                    end
                    if (compute_state_r == 0 && source_ready_r[compute_group_r])
                        compute_state_r <= 2'd1;
                    if (compute_state_r == 1 && write_addr_done_w)
                        compute_state_r <= 2'd2;
                    if (coord_start_w)
                        compute_state_r <= 2'd3;
                    if (compute_state_r == 3 && wr_done_w) begin
                        compute_state_r <= 2'd0;
                        source_ready_r[compute_group_r] <= 1'b0;
                        compute_group_r <= !compute_group_r;
                        if (group_last_r[compute_group_r])
                            state_r <= S_NEXT;
                    end
                end
                S_NEXT: begin
                    cur_desc_r <= cur_desc_r + 16'd1;
                    state_r <= table_done_w ? S_IDLE : S_DESC_REQ;
                end
                S_DRAIN: begin
                    if (rd_idle_w && wr_idle_w)
                        state_r <= S_IDLE;
                end
                default: begin end
            endcase
        end
    end
    // Descriptor and group payloads have no reset; ownership is held in control bits.
    always @(posedge clk_mem_i) begin
        if (start_w) begin
            table_base_r <= desc_base_w;
            table_count_r <= desc_count_w;
        end
        if (state_r == S_DESC_DATA && rd_valid_w)
            desc_r[{desc_half_r, 8'd0} +: 256] <= rd_data_w;
        if (tile_valid_w && tile_ready_w) begin
            group_u_r[fill_group_r] <= tile_u_w;
            group_v_r[fill_group_r] <= tile_v_w;
            group_width_r[fill_group_r] <= tile_width_w;
            group_height_r[fill_group_r] <= tile_height_w;
            group_x_r[fill_group_r] <= tile_x_w;
            group_y_r[fill_group_r] <= tile_y_w;
            group_origin_x_r[fill_group_r] <= bounds_x_w;
            group_origin_y_r[fill_group_r] <= bounds_y_w;
            group_read_width_r[fill_group_r] <= bounds_width_w;
            group_read_height_r[fill_group_r] <= bounds_height_w;
            group_last_r[fill_group_r] <= tile_last_w;
        end
        if (sample_fire_w) begin
            sample_fx_r <= coord_x_w[15:8];
            sample_fy_r <= coord_y_w[15:8];
            sample_eol_r <= coord_eol_w;
        end
    end
    always @(posedge clk_mem_i or negedge rst_mem_n_i) begin
        if (!rst_mem_n_i) begin
            sample_valid_r <= 1'b0;
            pack_valid_r <= 1'b0;
            pack_lane_r <= 4'd0;
        end else if (clear_w || coord_start_w) begin
            sample_valid_r <= 1'b0;
            pack_valid_r <= 1'b0;
            pack_lane_r <= 4'd0;
        end else begin
            if (advance_w)
                sample_valid_r <= sample_fire_w;
            if (pack_valid_r && wr_data_ready_w)
                pack_valid_r <= 1'b0;
            if (pixel_fire_w) begin
                if (pack_lane_r == 4'd15 || pixel_eol_w) begin
                    pack_lane_r <= 4'd0;
                    pack_valid_r <= 1'b1;
                end else begin
                    pack_lane_r <= pack_lane_r + 4'd1;
                end
            end
        end
    end
    always @(posedge clk_mem_i) begin
        if (pixel_fire_w) begin
            accumulator_r <= pack_next_w;
            if (pack_lane_r == 4'd15 || pixel_eol_w) begin
                pack_data_r <= pack_next_w;
                pack_strb_r <= 32'hffffffff >> (5'd30 - {pack_lane_r, 1'b0});
            end
        end
    end
    edrv32_geo_address u_read_address (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),
        .start_i(tile_valid_w && tile_ready_w && !bounds_empty_w),
        .clear_i(clear_w),
        .base_i(src_base_w),
        .stride_i(src_stride_w),
        .row_i({1'b0, bounds_y_w}),
        .column_i({1'b0, bounds_x_w}),
        .done_o(read_addr_done_w),
        .addr_o(read_addr_w)
    );
    edrv32_geo_address u_write_address (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),
        .start_i(state_r == S_RUN && compute_state_r == 0 &&
            source_ready_r[compute_group_r]),
        .clear_i(clear_w),
        .base_i(dst_base_w),
        .stride_i(dst_stride_w),
        .row_i(wr_row_w),
        .column_i(wr_column_w),
        .done_o(write_addr_done_w),
        .addr_o(write_addr_w)
    );
    edrv32_geo_regs u_regs (
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
        .done_i(table_done_w),
        .desc_done_i(desc_done_w),
        .cur_desc_i(cur_desc_r),
        .error_i(error_w),
        .pixel_i(write_pixels_w),
        .read_beat_i(p5_rvalid_i && p5_rready_o),
        .write_beat_i(p5_wvalid_o && p5_wready_i),
        .source_wait_i(state_r == S_RUN && compute_state_r == 0 &&
            !source_ready_r[compute_group_r]),
        .writer_wait_i(state_r == S_RUN && !advance_w),
        .start_o(start_w),
        .abort_o(abort_w),
        .soft_reset_o(soft_reset_w),
        .desc_base_o(desc_base_w),
        .desc_count_o(desc_count_w),
        .irq_o(irq_o)
    );
    edrv32_geo_desc u_desc (
        .data_i(desc_r),
        .src_base_o(src_base_w),
        .src_stride_o(src_stride_w),
        .src_w_o(src_w_w),
        .src_h_o(src_h_w),
        .dst_base_o(dst_base_w),
        .dst_stride_o(dst_stride_w),
        .rect_x_o(rect_x_w),
        .rect_y_o(rect_y_w),
        .rect_w_o(rect_w_w),
        .rect_h_o(rect_h_w),
        .bg_o(bg_w),
        .a_o(a_w),
        .b_o(b_w),
        .tx_o(tx_w),
        .c_o(c_w),
        .d_o(d_w),
        .ty_o(ty_w)
    );
    edrv32_geo_range u_range (
        .clk_i(clk_mem_i),
        .a_i(a_w),
        .b_i(b_w),
        .c_i(c_w),
        .d_i(d_w),
        .error_o(range_error_w)
    );
    edrv32_geo_tiles u_tiles (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),
        .start_i(tiles_start_w),
        .clear_i(clear_w),
        .width_i(rect_w_w),
        .height_i(rect_h_w),
        .a_i(a_w),
        .b_i(b_w),
        .tx_i(tx_w),
        .c_i(c_w),
        .d_i(d_w),
        .ty_i(ty_w),
        .valid_o(tile_valid_w),
        .u_o(tile_u_w),
        .v_o(tile_v_w),
        .width_o(tile_width_w),
        .height_o(tile_height_w),
        .x_o(tile_x_w),
        .y_o(tile_y_w),
        .last_o(tile_last_w),
        .ready_i(tile_ready_w)
    );
    edrv32_geo_bounds u_bounds (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),
        .start_i(bounds_start_w),
        .clear_i(clear_w),
        .done_o(bounds_done_w),
        .x_i(tile_x_w),
        .y_i(tile_y_w),
        .width_i(tile_width_w),
        .height_i(tile_height_w),
        .a_i(a_w),
        .b_i(b_w),
        .c_i(c_w),
        .d_i(d_w),
        .src_w_i(src_w_w),
        .src_h_i(src_h_w),
        .empty_o(bounds_empty_w),
        .origin_x_o(bounds_x_w),
        .origin_y_o(bounds_y_w),
        .width_bytes_o(bounds_width_w),
        .height_o(bounds_height_w)
    );
    edrv32_geo_coords u_coords (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),
        .start_i(coord_start_w),
        .clear_i(clear_w),
        .width_i(group_width_r[compute_group_r]),
        .height_i(group_height_r[compute_group_r]),
        .x_i(group_x_r[compute_group_r]),
        .y_i(group_y_r[compute_group_r]),
        .a_i(a_w),
        .b_i(b_w),
        .c_i(c_w),
        .d_i(d_w),
        .valid_o(coord_valid_w),
        .x_o(coord_x_w),
        .y_o(coord_y_w),
        .eol_o(coord_eol_w),
        .last_o(coord_last_w),
        .ready_i(advance_w)
    );
    edrv32_geo_source u_source (
        .clk_i(clk_mem_i),
        .wr_en_i(state_r == S_RUN && fill_state_r == 4 && rd_valid_w),
        .wr_group_i(fill_group_r),
        .wr_row_i(fill_row_r),
        .wr_word_i(fill_word_r),
        .wr_data_i(rd_data_w),
        .rd_en_i(sample_fire_w),
        .rd_group_i(compute_group_r),
        .x_i(coord_x_w),
        .y_i(coord_y_w),
        .origin_x_i(group_origin_x_r[compute_group_r]),
        .origin_y_i(group_origin_y_r[compute_group_r]),
        .src_w_i(src_w_w),
        .src_h_i(src_h_w),
        .bg_i(bg_w),
        .p00_o(p00_w),
        .p01_o(p01_w),
        .p10_o(p10_w),
        .p11_o(p11_w)
    );
    edrv32_geo_bilinear u_bilinear (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),
        .advance_i(advance_w),
        .clear_i(clear_w || coord_start_w),
        .valid_i(sample_valid_r),
        .eol_i(sample_eol_r),
        .p00_i(p00_w),
        .p01_i(p01_w),
        .p10_i(p10_w),
        .p11_i(p11_w),
        .fx_i(sample_fx_r),
        .fy_i(sample_fy_r),
        .valid_o(pixel_valid_w),
        .eol_o(pixel_eol_w),
        .pixel_o(pixel_w)
    );
    edrv32_dma2d_rd #(
        .OUTSTANDING(4)
    ) u_rd (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),
        .desc_valid_i(rd_desc_valid_w),
        .desc_ready_o(rd_desc_ready_w),
        .desc_base_i(rd_base_w),
        .desc_stride_i(rd_stride_w),
        .desc_width_bytes_i(rd_width_w),
        .desc_height_i(rd_height_w),
        .data_valid_o(rd_valid_w),
        .data_ready_i(1'b1),
        .data_o(rd_data_w),
        .data_sol_o(rd_sol_w),
        .data_eol_o(rd_eol_w),
        .data_eof_o(rd_eof_w),
        .axi_arid_o(p5_arid_o),
        .axi_araddr_o(p5_araddr_o),
        .axi_arlen_o(p5_arlen_o),
        .axi_arvalid_o(p5_arvalid_o),
        .axi_arready_i(p5_arready_i),
        .axi_rid_i(p5_rid_i),
        .axi_rdata_i(p5_rdata_i),
        .axi_rresp_i(p5_rresp_i),
        .axi_rlast_i(p5_rlast_i),
        .axi_rvalid_i(p5_rvalid_i),
        .axi_rready_o(p5_rready_o),
        .abort_i(stop_w),
        .idle_o(rd_idle_w),
        .done_o(rd_done_w),
        .err_o(rd_err_w)
    );
    edrv32_dma2d_wr #(
        .OUTSTANDING(4)
    ) u_wr (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),
        .desc_valid_i(wr_desc_valid_w),
        .desc_ready_o(wr_desc_ready_w),
        .desc_base_i(wr_base_w),
        .desc_stride_i(dst_stride_w),
        .desc_width_bytes_i(wr_width_w),
        .desc_height_i(wr_height_w),
        .data_valid_i(pack_valid_r),
        .data_ready_o(wr_data_ready_w),
        .data_i(pack_data_r),
        .data_strb_i(pack_strb_r),
        .axi_awid_o(p5_awid_o),
        .axi_awaddr_o(p5_awaddr_o),
        .axi_awlen_o(p5_awlen_o),
        .axi_awvalid_o(p5_awvalid_o),
        .axi_awready_i(p5_awready_i),
        .axi_wdata_o(p5_wdata_o),
        .axi_wstrb_o(p5_wstrb_o),
        .axi_wlast_o(p5_wlast_o),
        .axi_wvalid_o(p5_wvalid_o),
        .axi_wready_i(p5_wready_i),
        .axi_bid_i(p5_bid_i),
        .axi_bresp_i(p5_bresp_i),
        .axi_bvalid_i(p5_bvalid_i),
        .axi_bready_o(p5_bready_o),
        .abort_i(stop_w),
        .idle_o(wr_idle_w),
        .done_o(wr_done_w),
        .err_o(wr_err_w)
    );
endmodule
