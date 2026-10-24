// ============================================================================
// File        : edrv32_yolo_v8n_post.v
// Description : Three-scale YOLOv8n Detect decode, class NMS and DDR META.
// Notes       : Fixed 640x384 graph. One synchronous row RAM is reused across
//               all nine Detect planes; DDR reads remain contiguous bursts.
// ============================================================================

`include "edrv32_build_mode.vh"

module edrv32_yolo_v8n_post (
    input  wire         clk_i,
    input  wire         rst_n_i,
    input  wire         start_i,
    output wire         start_ready_o,
    input  wire [15:0]  source_width_i,
    input  wire [15:0]  source_height_i,
    input  wire [15:0]  scaled_width_i,
    input  wire [15:0]  scaled_height_i,
    input  wire [15:0]  pad_left_i,
    input  wire [15:0]  pad_top_i,
    output wire         busy_o,
    output wire         done_o,
    output wire         error_o,
    output wire [9:0]   candidate_count_o,
    output wire [6:0]   detection_count_o,
    output wire [1:0]   scale_o,
    output wire [6:0]   row_o,
    output wire [6:0]   pixel_o,
    output wire [31:0]  load_cycles_o,
    output wire [31:0]  class_cycles_o,
    output wire [31:0]  dfl_cycles_o,
    output wire [31:0]  nms_cycles_o,
    output wire [31:0]  meta_write_cycles_o,
    output wire [31:0]  read_beats_o,
    output wire [31:0]  write_beats_o,
    output wire [31:0]  ar_stall_o,
    output wire [31:0]  read_wait_o,
    output wire [31:0]  aw_stall_o,
    output wire [31:0]  write_stall_o,
    output wire [31:0]  response_wait_o,
    output wire         detection_valid_o,
    output wire [6:0]   detection_index_o,
    output wire [255:0] detection_record_o,

    output wire [3:0]   m_arid_o,
    output wire [31:0]  m_araddr_o,
    output wire [7:0]   m_arlen_o,
    output wire [2:0]   m_arsize_o,
    output wire [1:0]   m_arburst_o,
    output wire         m_arvalid_o,
    input  wire         m_arready_i,
    input  wire [3:0]   m_rid_i,
    input  wire [255:0] m_rdata_i,
    input  wire [1:0]   m_rresp_i,
    input  wire         m_rlast_i,
    input  wire         m_rvalid_i,
    output wire         m_rready_o,

    output wire [3:0]   m_awid_o,
    output wire [31:0]  m_awaddr_o,
    output wire [7:0]   m_awlen_o,
    output wire [2:0]   m_awsize_o,
    output wire [1:0]   m_awburst_o,
    output wire         m_awvalid_o,
    input  wire         m_awready_i,
    output wire [255:0] m_wdata_o,
    output wire [31:0]  m_wstrb_o,
    output wire         m_wlast_o,
    output wire         m_wvalid_o,
    input  wire         m_wready_i,
    input  wire [3:0]   m_bid_i,
    input  wire [1:0]   m_bresp_i,
    input  wire         m_bvalid_i,
    output wire         m_bready_o
);

    localparam [31:0] META_BASE = 32'h02a0_b000;
    localparam [4:0] S_IDLE       = 5'd0;
    localparam [4:0] S_ROW_REQ    = 5'd1;
    localparam [4:0] S_ROW_WAIT   = 5'd2;
    localparam [4:0] S_CLASS_INIT = 5'd3;
    localparam [4:0] S_CLASS_SCAN = 5'd4;
    localparam [4:0] S_CLASS_EVAL = 5'd5;
    localparam [4:0] S_DFL_START  = 5'd6;
    localparam [4:0] S_DFL_WAIT   = 5'd7;
    localparam [4:0] S_BOX        = 5'd8;
    localparam [4:0] S_PUSH       = 5'd9;
    localparam [4:0] S_ADV        = 5'd10;
    localparam [4:0] S_NMS_WAIT   = 5'd11;
    localparam [4:0] S_WRITE_AW   = 5'd12;
    localparam [4:0] S_WRITE_W    = 5'd13;
    localparam [4:0] S_WRITE_B    = 5'd14;
    localparam [4:0] S_BOX_FETCH  = 5'd15;
    localparam [4:0] S_FINAL_INIT = 5'd16;
    localparam [4:0] S_FINAL_ADV  = 5'd17;
    localparam [4:0] S_CLASS_CAPTURE = 5'd18;
    localparam [4:0] S_BOX_CAPTURE = 5'd19;
    localparam [4:0] S_BOX_CHECK = 5'd20;

    reg [4:0] state_r;
    reg [1:0] scale_r;
    reg [6:0] row_r, pixel_r;
    reg [3:0] plane_r;
    reg [6:0] class_index_r;
    reg signed [7:0] best_code_r;
    reg [6:0] best_class_r;
    reg [15:0] score_r;
    reg [11:0] distance_r [0:3];
    reg [255:0] pixel_word_r;
    reg signed [7:0] best_code_mem_r [0:79];
    reg [6:0] best_class_mem_r [0:79];
    reg [11:0] distance_mem_r [0:3][0:79];
    reg [31:0] box_x1_r, box_y1_r, box_x2_r, box_y2_r;
    reg [31:0] write_addr_r;
    reg [255:0] write_data_r;
    reg [1:0] header_write_r;
    reg [15:0] source_width_r, source_height_r;
    reg [15:0] scaled_width_r, scaled_height_r;
    reg [15:0] pad_left_r, pad_top_r;
    reg nms_done_seen_r;
    reg error_r, done_r;
    reg [31:0] load_cycles_r, class_cycles_r, dfl_cycles_r;
    reg [31:0] nms_cycles_r, meta_write_cycles_r;
    reg [31:0] read_beats_r, write_beats_r;
    reg [31:0] ar_stall_r, read_wait_r, aw_stall_r;
    reg [31:0] write_stall_r, response_wait_r;
    reg [11:0] read_pending_r;
    reg [7:0] write_pending_r, response_pending_r;

    wire [6:0] width_w = scale_r == 2'd0 ? 7'd80 :
                         scale_r == 2'd1 ? 7'd40 : 7'd20;
    wire [6:0] height_w = scale_r == 2'd0 ? 7'd48 :
                          scale_r == 2'd1 ? 7'd24 : 7'd12;
    wire [5:0] width_pairs_w = {1'b0, width_w[6:1]};
    wire [3:0] plane_index_w = plane_r < 4'd4 ?
                               plane_r : plane_r - 4'd4;
    wire [31:0] plane_offset_w = scale_r == 2'd0 ?
        ({28'd0, plane_index_w} << 16) -
        ({28'd0, plane_index_w} << 12) :
        scale_r == 2'd1 ?
        ({28'd0, plane_index_w} << 14) -
        ({28'd0, plane_index_w} << 10) :
        ({28'd0, plane_index_w} << 12) -
        ({28'd0, plane_index_w} << 8);
    wire [31:0] row_offset_w = scale_r == 2'd0 ?
        ({25'd0, row_r} << 10) + ({25'd0, row_r} << 8) :
        scale_r == 2'd1 ?
        ({25'd0, row_r} << 9) + ({25'd0, row_r} << 7) :
        ({25'd0, row_r} << 8) + ({25'd0, row_r} << 6);
    wire [31:0] box_base_w = scale_r == 2'd0 ? 32'h027d_3000 :
                             scale_r == 2'd1 ? 32'h0285_a000 :
                                                 32'h0287_c000;
    wire [31:0] class_base_w = scale_r == 2'd0 ? 32'h0280_f000 :
                               scale_r == 2'd1 ? 32'h0286_9000 :
                                                   32'h0287_fc00;
    wire [31:0] current_base_w = plane_r < 4'd4 ?
        box_base_w + plane_offset_w : class_base_w + plane_offset_w;
    wire [31:0] row_addr_w = current_base_w + row_offset_w;
    wire reader_req_ready_w, reader_beat_valid_w;
    wire [15:0] reader_beat_index_w;
    wire [255:0] reader_beat_data_w;
    wire reader_done_w, reader_error_w;
    wire [3:0] reader_arlen_w;
    wire [255:0] line_word_w;
    wire [2:0] class_plane_w = plane_r[2:0] - 3'd4;
    wire [6:0] class_number_w =
        {class_plane_w, 4'd0} + class_index_r;
    wire [7:0] class_bit_offset_w =
        {pixel_r[0], class_index_r[3:0], 3'b000};
    wire signed [7:0] class_code_w =
        $signed(pixel_word_r[class_bit_offset_w +: 8]);
    wire [15:0] confidence_w;
    wire [127:0] side_logits_w = pixel_r[0] ?
        pixel_word_r[255:128] : pixel_word_r[127:0];
    wire dfl_start_ready_w, dfl_done_w;
    wire [11:0] dfl_distance_w;
    wire nms_input_ready_w, nms_out_valid_w, nms_done_w, nms_error_w;
    wire [6:0] nms_out_class_w, nms_out_index_w, nms_output_count_w;
    wire [15:0] nms_out_score_w;
    wire [31:0] nms_out_x1_w, nms_out_y1_w;
    wire [31:0] nms_out_x2_w, nms_out_y2_w;
    wire [1:0] nms_out_scale_w;
    wire [12:0] nms_out_anchor_w;
    wire [9:0] nms_candidate_count_w;
    wire last_pixel_w = pixel_r == width_w - 7'd1;
    wire last_row_w = row_r == height_w - 7'd1;
    wire last_scale_w = scale_r == 2'd2;
    wire nms_finish_w =
        (state_r == S_FINAL_ADV && last_pixel_w && last_row_w &&
         last_scale_w) ||
        (state_r == S_ROW_WAIT && reader_done_w && reader_error_w);
    wire nms_out_ready_w = state_r == S_NMS_WAIT && !nms_done_seen_r;

    wire [3:0] stride_shift_w = {2'd0, scale_r} + 4'd3;
    wire [3:0] center_shift_w = {2'd0, scale_r} + 4'd11;
    wire [31:0] center_x_w =
        ({25'd0, pixel_r} << center_shift_w) +
        (32'd1 << (center_shift_w - 4'd1));
    wire [31:0] center_y_w =
        ({25'd0, row_r} << center_shift_w) +
        (32'd1 << (center_shift_w - 4'd1));
    wire signed [31:0] x1_raw_w = $signed(center_x_w) -
        $signed({20'd0, distance_r[0]} << stride_shift_w);
    wire signed [31:0] y1_raw_w = $signed(center_y_w) -
        $signed({20'd0, distance_r[1]} << stride_shift_w);
    wire signed [31:0] x2_raw_w = $signed(center_x_w) +
        $signed({20'd0, distance_r[2]} << stride_shift_w);
    wire signed [31:0] y2_raw_w = $signed(center_y_w) +
        $signed({20'd0, distance_r[3]} << stride_shift_w);
    wire [31:0] x1_w = x1_raw_w < 32'sd0 ? 32'd0 :
        x1_raw_w > 32'sd163840 ? 32'd163840 : x1_raw_w[31:0];
    wire [31:0] y1_w = y1_raw_w < 32'sd0 ? 32'd0 :
        y1_raw_w > 32'sd98304 ? 32'd98304 : y1_raw_w[31:0];
    wire [31:0] x2_w = x2_raw_w < 32'sd0 ? 32'd0 :
        x2_raw_w > 32'sd163840 ? 32'd163840 : x2_raw_w[31:0];
    wire [31:0] y2_w = y2_raw_w < 32'sd0 ? 32'd0 :
        y2_raw_w > 32'sd98304 ? 32'd98304 : y2_raw_w[31:0];
    wire [12:0] row_anchor_offset_w = scale_r == 2'd0 ?
        ({6'd0, row_r} << 6) + ({6'd0, row_r} << 4) :
        scale_r == 2'd1 ?
        ({6'd0, row_r} << 5) + ({6'd0, row_r} << 3) :
        ({6'd0, row_r} << 4) + ({6'd0, row_r} << 2);
    wire [12:0] anchor_w =
        (scale_r == 2'd0 ? 13'd0 :
         scale_r == 2'd1 ? 13'd3840 : 13'd4800) +
        row_anchor_offset_w + {6'd0, pixel_r};
    reg [255:0] record_w;
    reg [255:0] header_w;
    reg [255:0] geometry_w;

    wire line_read_w = state_r == S_CLASS_INIT ||
                       state_r == S_BOX_FETCH;
`ifdef EDRV32_BUILD_MODE_CONFLICT
    edrv32_build_mode_error__define_only_one_of_FPGA_MODE_or_SIM_MODE
        u_build_mode_error ();
`elsif EDRV32_FPGA_MEMORY_MODE
    yolo_weight_ram u_post_row_ram (
        .wr_data(reader_beat_data_w),
        .wr_addr({3'd0, reader_beat_index_w[5:0]}),
        .wr_en(reader_beat_valid_w),
        .wr_clk(clk_i), .wr_rst(~rst_n_i),
        .wr_byte_en(32'hffff_ffff),
        .rd_data(line_word_w),
        .rd_addr({3'd0, pixel_r[6:1]}),
        .rd_clk(clk_i), .rd_rst(~rst_n_i),
        .rd_clk_en(line_read_w)
    );
`else
    reg [255:0] line_mem_r [0:39];
    reg [255:0] line_read_r;
    always @(posedge clk_i) begin
        if (reader_beat_valid_w)
            line_mem_r[reader_beat_index_w[5:0]] <= reader_beat_data_w;
        if (line_read_w)
            line_read_r <= line_mem_r[pixel_r[6:1]];
    end
    assign line_word_w = line_read_r;
`endif

    edrv32_yolo_axi_reader #(.AXI_ID(4'h8)) u_reader (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .req_valid_i(state_r == S_ROW_REQ),
        .req_ready_o(reader_req_ready_w),
        .req_addr_i(row_addr_w),
        .req_beats_i({10'd0, width_pairs_w}),
        .beat_valid_o(reader_beat_valid_w),
        .beat_index_o(reader_beat_index_w),
        .beat_data_o(reader_beat_data_w),
        .busy_o(), .done_o(reader_done_w), .error_o(reader_error_w),
        .m_arid_o(m_arid_o), .m_araddr_o(m_araddr_o),
        .m_arlen_o(reader_arlen_w),
        .m_arsize_o(m_arsize_o), .m_arburst_o(m_arburst_o),
        .m_arvalid_o(m_arvalid_o), .m_arready_i(m_arready_i),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i(m_rvalid_i), .m_rready_o(m_rready_o)
    );
    assign m_arlen_o = {4'd0, reader_arlen_w};

    edrv32_yolo_v8n_post_lut u_confidence (
        .scale_i(scale_r), .diff_i(8'd0),
        .cls_code_i(best_code_r),
        .exp_o(), .confidence_o(confidence_w)
    );

    edrv32_yolo_dfl16 u_dfl (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(state_r == S_DFL_START),
        .start_ready_o(dfl_start_ready_w),
        .scale_i(scale_r), .logits_i(side_logits_w),
        .busy_o(), .done_o(dfl_done_w), .distance_o(dfl_distance_w)
    );

    edrv32_yolo_nms u_nms (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(start_i && start_ready_o), .start_ready_o(),
        .in_valid_i(state_r == S_PUSH), .in_ready_o(nms_input_ready_w),
        .in_class_i(best_class_r), .in_score_i(score_r),
        .in_x1_i(box_x1_r), .in_y1_i(box_y1_r),
        .in_x2_i(box_x2_r), .in_y2_i(box_y2_r),
        .in_scale_i(scale_r), .in_anchor_i(anchor_w),
        .finish_i(nms_finish_w),
        .out_valid_o(nms_out_valid_w), .out_ready_i(nms_out_ready_w),
        .out_class_o(nms_out_class_w), .out_score_o(nms_out_score_w),
        .out_x1_o(nms_out_x1_w), .out_y1_o(nms_out_y1_w),
        .out_x2_o(nms_out_x2_w), .out_y2_o(nms_out_y2_w),
        .out_scale_o(nms_out_scale_w), .out_anchor_o(nms_out_anchor_w),
        .out_index_o(nms_out_index_w),
        .candidate_count_o(nms_candidate_count_w),
        .output_count_o(nms_output_count_w),
        .busy_o(), .done_o(nms_done_w), .error_o(nms_error_w)
    );

    always @(*) begin
        record_w = 256'd0;
        record_w[31:0] = nms_out_x1_w;
        record_w[63:32] = nms_out_y1_w;
        record_w[95:64] = nms_out_x2_w;
        record_w[127:96] = nms_out_y2_w;
        record_w[135:128] = {1'b0, nms_out_class_w};
        record_w[151:136] = nms_out_score_w;
        record_w[159:152] = {6'd0, nms_out_scale_w};
        record_w[175:160] = {3'd0, nms_out_anchor_w};
        header_w = 256'd0;
        header_w[31:0] = 32'h5445_4d59;
        header_w[63:32] = 32'd2;
        header_w[95:64] = {25'd0, nms_output_count_w};
        header_w[127:96] = {31'd0, error_r || nms_error_w};
        header_w[159:128] = 32'd640;
        header_w[191:160] = 32'd384;
        header_w[223:192] = {22'd0, nms_candidate_count_w};
        geometry_w = 256'd0;
        geometry_w[31:0] = {16'd0, source_width_r};
        geometry_w[63:32] = {16'd0, source_height_r};
        geometry_w[95:64] = {16'd0, scaled_width_r};
        geometry_w[127:96] = {16'd0, scaled_height_r};
        geometry_w[159:128] = {16'd0, pad_left_r};
        geometry_w[191:160] = {16'd0, pad_top_r};
    end

    assign start_ready_o = state_r == S_IDLE;
    assign busy_o = state_r != S_IDLE;
    assign done_o = done_r;
    assign error_o = error_r || nms_error_w;
    assign candidate_count_o = nms_candidate_count_w;
    assign detection_count_o = nms_output_count_w;
    assign scale_o = scale_r;
    assign row_o = row_r;
    assign pixel_o = pixel_r;
    assign load_cycles_o = load_cycles_r;
    assign class_cycles_o = class_cycles_r;
    assign dfl_cycles_o = dfl_cycles_r;
    assign nms_cycles_o = nms_cycles_r;
    assign meta_write_cycles_o = meta_write_cycles_r;
    assign read_beats_o = read_beats_r;
    assign write_beats_o = write_beats_r;
    assign ar_stall_o = ar_stall_r;
    assign read_wait_o = read_wait_r;
    assign aw_stall_o = aw_stall_r;
    assign write_stall_o = write_stall_r;
    assign response_wait_o = response_wait_r;
    assign detection_valid_o = nms_out_valid_w && nms_out_ready_w;
    assign detection_index_o = nms_out_index_w;
    assign detection_record_o = record_w;
    assign m_awid_o = 4'ha;
    assign m_awaddr_o = write_addr_r;
    assign m_awlen_o = 8'd0;
    assign m_awsize_o = 3'd5;
    assign m_awburst_o = 2'b01;
    assign m_awvalid_o = state_r == S_WRITE_AW;
    assign m_wdata_o = write_data_r;
    assign m_wstrb_o = 32'hffff_ffff;
    assign m_wlast_o = 1'b1;
    assign m_wvalid_o = state_r == S_WRITE_W;
    assign m_bready_o = state_r == S_WRITE_B;

    wire ar_fire_w = m_arvalid_o && m_arready_i;
    wire r_fire_w = m_rvalid_i && m_rready_o;
    wire aw_fire_w = m_awvalid_o && m_awready_i;
    wire w_fire_w = m_wvalid_o && m_wready_i;
    wire b_fire_w = m_bvalid_i && m_bready_o;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            load_cycles_r <= 32'd0;
            class_cycles_r <= 32'd0;
            dfl_cycles_r <= 32'd0;
            nms_cycles_r <= 32'd0;
            meta_write_cycles_r <= 32'd0;
            read_beats_r <= 32'd0;
            write_beats_r <= 32'd0;
            ar_stall_r <= 32'd0;
            read_wait_r <= 32'd0;
            aw_stall_r <= 32'd0;
            write_stall_r <= 32'd0;
            response_wait_r <= 32'd0;
            read_pending_r <= 12'd0;
            write_pending_r <= 8'd0;
            response_pending_r <= 8'd0;
        end else if (start_i && start_ready_o) begin
            load_cycles_r <= 32'd0;
            class_cycles_r <= 32'd0;
            dfl_cycles_r <= 32'd0;
            nms_cycles_r <= 32'd0;
            meta_write_cycles_r <= 32'd0;
            read_beats_r <= 32'd0;
            write_beats_r <= 32'd0;
            ar_stall_r <= 32'd0;
            read_wait_r <= 32'd0;
            aw_stall_r <= 32'd0;
            write_stall_r <= 32'd0;
            response_wait_r <= 32'd0;
            read_pending_r <= 12'd0;
            write_pending_r <= 8'd0;
            response_pending_r <= 8'd0;
        end else if (state_r != S_IDLE) begin
            if (state_r == S_ROW_REQ || state_r == S_ROW_WAIT)
                load_cycles_r <= load_cycles_r + 32'd1;
            if (state_r == S_CLASS_INIT || state_r == S_CLASS_CAPTURE ||
                state_r == S_CLASS_SCAN || state_r == S_CLASS_EVAL ||
                state_r == S_BOX_FETCH || state_r == S_BOX_CAPTURE ||
                state_r == S_FINAL_INIT || state_r == S_BOX_CHECK ||
                state_r == S_FINAL_ADV || state_r == S_ADV)
                class_cycles_r <= class_cycles_r + 32'd1;
            if (state_r == S_DFL_START || state_r == S_DFL_WAIT ||
                state_r == S_BOX || state_r == S_PUSH)
                dfl_cycles_r <= dfl_cycles_r + 32'd1;
            if (state_r == S_NMS_WAIT)
                nms_cycles_r <= nms_cycles_r + 32'd1;
            if (state_r == S_WRITE_AW || state_r == S_WRITE_W ||
                state_r == S_WRITE_B)
                meta_write_cycles_r <= meta_write_cycles_r + 32'd1;
            if (r_fire_w)
                read_beats_r <= read_beats_r + 32'd1;
            if (w_fire_w)
                write_beats_r <= write_beats_r + 32'd1;
            if (m_arvalid_o && !m_arready_i)
                ar_stall_r <= ar_stall_r + 32'd1;
            if (read_pending_r != 12'd0 && !r_fire_w)
                read_wait_r <= read_wait_r + 32'd1;
            if (m_awvalid_o && !m_awready_i)
                aw_stall_r <= aw_stall_r + 32'd1;
            if (m_wvalid_o && !m_wready_i)
                write_stall_r <= write_stall_r + 32'd1;
            if (response_pending_r != 8'd0 &&
                write_pending_r == 8'd0 && !b_fire_w)
                response_wait_r <= response_wait_r + 32'd1;
            case ({ar_fire_w, r_fire_w})
                2'b10: read_pending_r <= read_pending_r +
                        {4'd0, m_arlen_o} + 12'd1;
                2'b01: read_pending_r <= read_pending_r - 12'd1;
                2'b11: read_pending_r <= read_pending_r +
                        {4'd0, m_arlen_o};
                default: read_pending_r <= read_pending_r;
            endcase
            case ({aw_fire_w, w_fire_w})
                2'b10: write_pending_r <= write_pending_r + 8'd1;
                2'b01: write_pending_r <= write_pending_r - 8'd1;
                default: write_pending_r <= write_pending_r;
            endcase
            case ({aw_fire_w, b_fire_w})
                2'b10: response_pending_r <= response_pending_r + 8'd1;
                2'b01: response_pending_r <= response_pending_r - 8'd1;
                default: response_pending_r <= response_pending_r;
            endcase
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            scale_r <= 2'd0;
            row_r <= 7'd0;
            pixel_r <= 7'd0;
            plane_r <= 4'd0;
            class_index_r <= 7'd0;
            best_code_r <= 8'sh80;
            best_class_r <= 7'd0;
            score_r <= 16'd0;
            box_x1_r <= 32'd0;
            box_y1_r <= 32'd0;
            box_x2_r <= 32'd0;
            box_y2_r <= 32'd0;
            write_addr_r <= 32'd0;
            write_data_r <= 256'd0;
            header_write_r <= 2'd0;
            source_width_r <= 16'd0;
            source_height_r <= 16'd0;
            scaled_width_r <= 16'd0;
            scaled_height_r <= 16'd0;
            pad_left_r <= 16'd0;
            pad_top_r <= 16'd0;
            nms_done_seen_r <= 1'b0;
            error_r <= 1'b0;
            done_r <= 1'b0;
        end else begin
            done_r <= 1'b0;
            if (nms_done_w)
                nms_done_seen_r <= 1'b1;
            case (state_r)
                S_IDLE: if (start_i) begin
                    source_width_r <= source_width_i;
                    source_height_r <= source_height_i;
                    scaled_width_r <= scaled_width_i;
                    scaled_height_r <= scaled_height_i;
                    pad_left_r <= pad_left_i;
                    pad_top_r <= pad_top_i;
                    scale_r <= 2'd0;
                    row_r <= 7'd0;
                    pixel_r <= 7'd0;
                    plane_r <= 4'd4;
                    nms_done_seen_r <= 1'b0;
                    error_r <= 1'b0;
                    state_r <= S_ROW_REQ;
                end
                S_ROW_REQ: if (reader_req_ready_w)
                    state_r <= S_ROW_WAIT;
                S_ROW_WAIT: if (reader_done_w) begin
                    if (reader_error_w) begin
                        error_r <= 1'b1;
                        state_r <= S_NMS_WAIT;
                    end else begin
                        pixel_r <= 7'd0;
                        state_r <= plane_r >= 4'd4 ?
                                   S_CLASS_INIT : S_BOX_FETCH;
                    end
                end
                S_CLASS_INIT: begin
                    class_index_r <= 7'd0;
                    best_code_r <= plane_r == 4'd4 ?
                                   8'sh80 : best_code_mem_r[pixel_r];
                    best_class_r <= plane_r == 4'd4 ?
                                    7'd0 : best_class_mem_r[pixel_r];
                    state_r <= S_CLASS_CAPTURE;
                end
                S_CLASS_CAPTURE: begin
                    pixel_word_r <= line_word_w;
                    state_r <= S_CLASS_SCAN;
                end
                S_CLASS_SCAN: begin
                    if (class_code_w > best_code_r) begin
                        best_code_r <= class_code_w;
                        best_class_r <= class_number_w;
                    end
                    if (class_index_r == 7'd15) begin
                        best_code_mem_r[pixel_r] <=
                            class_code_w > best_code_r ?
                            class_code_w : best_code_r;
                        best_class_mem_r[pixel_r] <=
                            class_code_w > best_code_r ?
                            class_number_w : best_class_r;
                        state_r <= S_ADV;
                    end
                    else
                        class_index_r <= class_index_r + 7'd1;
                end
                S_BOX_FETCH: begin
                    best_code_r <= best_code_mem_r[pixel_r];
                    state_r <= S_BOX_CAPTURE;
                end
                S_BOX_CAPTURE: begin
                    pixel_word_r <= line_word_w;
                    state_r <= S_CLASS_EVAL;
                end
                S_CLASS_EVAL: begin
                    score_r <= confidence_w;
                    if (confidence_w >= 16'd8192) begin
                        state_r <= S_DFL_START;
                    end else
                        state_r <= S_ADV;
                end
                S_DFL_START: if (dfl_start_ready_w)
                    state_r <= S_DFL_WAIT;
                S_DFL_WAIT: if (dfl_done_w) begin
                    distance_mem_r[plane_r[1:0]][pixel_r] <=
                        dfl_distance_w;
                    state_r <= S_ADV;
                end
                S_FINAL_INIT: begin
                    best_code_r <= best_code_mem_r[pixel_r];
                    best_class_r <= best_class_mem_r[pixel_r];
                    distance_r[0] <= distance_mem_r[0][pixel_r];
                    distance_r[1] <= distance_mem_r[1][pixel_r];
                    distance_r[2] <= distance_mem_r[2][pixel_r];
                    distance_r[3] <= distance_mem_r[3][pixel_r];
                    state_r <= S_BOX;
                end
                S_BOX: begin
                    score_r <= confidence_w;
                    box_x1_r <= x1_w;
                    box_y1_r <= y1_w;
                    box_x2_r <= x2_w;
                    box_y2_r <= y2_w;
                    state_r <= S_BOX_CHECK;
                end
                S_BOX_CHECK: state_r <=
                    score_r >= 16'd8192 &&
                    box_x2_r > box_x1_r && box_y2_r > box_y1_r ?
                    S_PUSH : S_FINAL_ADV;
                S_PUSH: if (nms_input_ready_w)
                    state_r <= S_FINAL_ADV;
                S_ADV: begin
                    if (last_pixel_w) begin
                        pixel_r <= 7'd0;
                        if (plane_r == 4'd3)
                            state_r <= S_FINAL_INIT;
                        else begin
                            plane_r <= plane_r == 4'd8 ?
                                       4'd0 : plane_r + 4'd1;
                            state_r <= S_ROW_REQ;
                        end
                    end else begin
                        pixel_r <= pixel_r + 7'd1;
                        state_r <= plane_r >= 4'd4 ?
                                   S_CLASS_INIT : S_BOX_FETCH;
                    end
                end
                S_FINAL_ADV: begin
                    if (last_pixel_w) begin
                        pixel_r <= 7'd0;
                        plane_r <= 4'd4;
                        if (last_row_w) begin
                            row_r <= 7'd0;
                            if (last_scale_w)
                                state_r <= S_NMS_WAIT;
                            else begin
                                scale_r <= scale_r + 2'd1;
                                state_r <= S_ROW_REQ;
                            end
                        end else begin
                            row_r <= row_r + 7'd1;
                            state_r <= S_ROW_REQ;
                        end
                    end else begin
                        pixel_r <= pixel_r + 7'd1;
                        state_r <= S_FINAL_INIT;
                    end
                end
                S_NMS_WAIT: begin
                    if (nms_out_valid_w && nms_out_ready_w) begin
                        write_addr_r <= META_BASE + 32'd64 +
                            {20'd0, nms_out_index_w, 5'd0};
                        write_data_r <= record_w;
                        header_write_r <= 2'd0;
                        state_r <= S_WRITE_AW;
                    end else if (nms_done_seen_r) begin
                        write_addr_r <= META_BASE;
                        write_data_r <= header_w;
                        header_write_r <= 2'd1;
                        state_r <= S_WRITE_AW;
                    end
                end
                S_WRITE_AW: if (m_awready_i)
                    state_r <= S_WRITE_W;
                S_WRITE_W: if (m_wready_i)
                    state_r <= S_WRITE_B;
                S_WRITE_B: if (m_bvalid_i) begin
                    if (m_bid_i != 4'ha || m_bresp_i != 2'b00)
                        error_r <= 1'b1;
                    if (header_write_r == 2'd1) begin
                        write_addr_r <= META_BASE + 32'd32;
                        write_data_r <= geometry_w;
                        header_write_r <= 2'd2;
                        state_r <= S_WRITE_AW;
                    end else if (header_write_r == 2'd2) begin
                        done_r <= 1'b1;
                        state_r <= S_IDLE;
                    end else
                        state_r <= S_NMS_WAIT;
                end
                default: state_r <= S_IDLE;
            endcase
        end
    end
endmodule
