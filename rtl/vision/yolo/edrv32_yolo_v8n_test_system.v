// ============================================================================
// File        : edrv32_yolo_v8n_test_system.v
// Description : Board self-test for the shared YOLOv8n execution unit.
// Notes       : Initializes a small DDR tensor, runs CONV/ADD/POOL/UP in
//               sequence, and reads back every final output beat. One AXI
//               master is owned either by the test sequencer or executor.
// ============================================================================

module edrv32_yolo_v8n_test_system (
    input  wire         clk_i,
    input  wire         rst_n_i,
    input  wire         ddr_ready_i,
    output wire         init_done_o,
    output wire         layer_busy_o,
    output wire         done_o,
    output wire         fail_o,
    output wire [4:0]   error_flags_o,
    output wire [15:0]  first_bad_index_o,
    output wire [31:0]  first_bad_got_o,
    output wire [31:0]  first_bad_expected_o,
    output wire [31:0]  mac_count_o,
    output wire [31:0]  read_count_o,
    output wire [31:0]  write_count_o,
    output wire [31:0]  cycle_count_o,
    output wire [31:0]  conv_cycle_count_o,
    output wire [31:0]  pool_cycle_count_o,
    output wire [31:0]  other_cycle_count_o,
    output wire [31:0]  ar_wait_count_o,
    output wire [31:0]  w_wait_count_o,

    output wire [3:0]   m_awid_o,
    output wire [31:0]  m_awaddr_o,
    output wire [7:0]   m_awlen_o,
    output wire [2:0]   m_awsize_o,
    output wire [1:0]   m_awburst_o,
    output wire [3:0]   m_awqos_o,
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
    output wire         m_bready_o,
    output wire [3:0]   m_arid_o,
    output wire [31:0]  m_araddr_o,
    output wire [7:0]   m_arlen_o,
    output wire [2:0]   m_arsize_o,
    output wire [1:0]   m_arburst_o,
    output wire [3:0]   m_arqos_o,
    output wire         m_arvalid_o,
    input  wire         m_arready_i,
    input  wire [3:0]   m_rid_i,
    input  wire [255:0] m_rdata_i,
    input  wire [1:0]   m_rresp_i,
    input  wire         m_rlast_i,
    input  wire         m_rvalid_i,
    output wire         m_rready_o
);

    localparam [3:0] S_WAIT_DDR = 4'd0;
    localparam [3:0] S_INIT_AW = 4'd1;
    localparam [3:0] S_INIT_W = 4'd2;
    localparam [3:0] S_INIT_B = 4'd3;
    localparam [3:0] S_CMD_START = 4'd4;
    localparam [3:0] S_CMD_WAIT = 4'd5;
    localparam [3:0] S_CHECK_AR = 4'd6;
    localparam [3:0] S_CHECK_R = 4'd7;
    localparam [3:0] S_CHECK_DRAIN = 4'd8;
    localparam [3:0] S_FINISHED = 4'd9;

    reg [3:0] state_r;
    reg init_segment_r;
    reg [4:0] init_index_r;
    reg [1:0] cmd_index_r;
    reg [1:0] check_request_r;
    reg [3:0] check_index_r;
    reg [4:0] error_flags_r;
    reg first_bad_valid_r;
    reg [15:0] first_bad_index_r;
    reg [31:0] first_bad_got_r;
    reg [31:0] first_bad_expected_r;
    reg check_valid_r;
    reg [255:0] check_data_r;
    reg [5:0] check_beat_r;
    reg check_resp_bad_r;
    reg check_last_bad_r;
    reg [31:0] mac_count_r, read_count_r, write_count_r;
    reg [31:0] cycle_count_r, conv_cycle_count_r;
    reg [31:0] pool_cycle_count_r, other_cycle_count_r;
    reg [31:0] ar_wait_count_r, w_wait_count_r;

    wire owner_exec_w = state_r == S_CMD_START ||
                        state_r == S_CMD_WAIT;
    wire exec_cmd_ready_w, exec_busy_w, exec_done_w;
    wire exec_error_w, exec_mac_beat_w;
    wire [4:0] exec_cfg_block_w, exec_cfg_channel_w;
    wire exec_cfg_ready_w;
    wire [3:0] exec_awid_w, exec_arid_w;
    wire [31:0] exec_awaddr_w, exec_araddr_w;
    wire [7:0] exec_awlen_w, exec_arlen_w;
    wire [2:0] exec_awsize_w, exec_arsize_w;
    wire [1:0] exec_awburst_w, exec_arburst_w;
    wire exec_awvalid_w, exec_wvalid_w, exec_wlast_w;
    wire exec_bready_w, exec_arvalid_w, exec_rready_w;
    wire [255:0] exec_wdata_w;
    wire [31:0] exec_wstrb_w;
    wire [31:0] cmd_input_base_w = cmd_index_r == 2'd0 ?
        32'h1000 : cmd_index_r == 2'd1 ?
        32'h2000 : cmd_index_r == 2'd2 ?
        32'h2180 : 32'h3000;
    wire [31:0] cmd_output_base_w = cmd_index_r == 2'd0 ?
        32'h2000 : cmd_index_r == 2'd1 ?
        32'h2180 : cmd_index_r == 2'd2 ?
        32'h3000 : 32'h4000;
    wire check_fire_w = state_r == S_CHECK_R &&
                        m_rvalid_i && m_rready_o;
    wire check_data_bad_w = check_valid_r &&
                            check_data_r != {32{8'd2}};
    wire [15:0] check_beat_index_w = {10'd0, check_beat_r};

    assign init_done_o = state_r >= S_CMD_START;
    assign layer_busy_o = owner_exec_w;
    assign done_o = state_r == S_FINISHED;
    assign fail_o = |error_flags_r;
    assign error_flags_o = error_flags_r;
    assign first_bad_index_o = first_bad_index_r;
    assign first_bad_got_o = first_bad_got_r;
    assign first_bad_expected_o = first_bad_expected_r;
    assign mac_count_o = mac_count_r;
    assign read_count_o = read_count_r;
    assign write_count_o = write_count_r;
    assign cycle_count_o = cycle_count_r;
    assign conv_cycle_count_o = conv_cycle_count_r;
    assign pool_cycle_count_o = pool_cycle_count_r;
    assign other_cycle_count_o = other_cycle_count_r;
    assign ar_wait_count_o = ar_wait_count_r;
    assign w_wait_count_o = w_wait_count_r;

    edrv32_yolo_v8n_exec u_exec (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .cmd_valid_i(state_r == S_CMD_START),
        .cmd_ready_o(exec_cmd_ready_w),
        .cmd_op_i(cmd_index_r),
        .cmd_input_base_i(cmd_input_base_w),
        .cmd_aux_base_i(32'h2180),
        .cmd_output_base_i(cmd_output_base_w),
        .cmd_input_plane_stride_i(32'd384),
        .cmd_output_plane_stride_i(cmd_index_r == 2'd3 ?
                                    32'd1536 : 32'd384),
        .cmd_weight_base_i(32'd0),
        .cmd_weight_block_stride_i(32'd0),
        .cmd_input_width_i(11'd8),
        .cmd_input_height_i(16'd3),
        .cmd_output_width_pairs_i(10'd4),
        .cmd_output_height_i(16'd3),
        .cmd_cin_blocks_i(6'd1),
        .cmd_output_blocks_i(5'd1),
        .cmd_cache_bank_stride_i(9'd2),
        .cmd_cache_row_stride_i(10'd2),
        .cmd_tile_pairs_i(10'd2),
        .cmd_kernel3_i(1'b0), .cmd_stride2_i(1'b0),
        .cmd_last_c16_only_i(1'b0),
        .cmd_beat_count_i(16'd12),
        .cmd_residual_zero_point_i(8'd0),
        .cmd_lut_enable_i(1'b0),
        .busy_o(exec_busy_w), .done_o(exec_done_w),
        .error_o(exec_error_w), .mac_beat_o(exec_mac_beat_w),
        .cfg_block_o(exec_cfg_block_w),
        .cfg_channel_o(exec_cfg_channel_w),
        .cfg_valid_i(1'b1), .cfg_ready_o(exec_cfg_ready_w),
        .cfg_bias_i(32'd0), .cfg_multiplier_i(16'd1),
        .cfg_shift_i(6'd4), .cfg_zero_point_i(8'd0),
        .cfg_lut_valid_i(1'b0), .cfg_lut_ready_o(),
        .cfg_lut_addr_o(), .cfg_lut_data_i(8'd0),
        .m_awid_o(exec_awid_w), .m_awaddr_o(exec_awaddr_w),
        .m_awlen_o(exec_awlen_w), .m_awsize_o(exec_awsize_w),
        .m_awburst_o(exec_awburst_w),
        .m_awvalid_o(exec_awvalid_w),
        .m_awready_i(owner_exec_w && m_awready_i),
        .m_wdata_o(exec_wdata_w), .m_wstrb_o(exec_wstrb_w),
        .m_wlast_o(exec_wlast_w), .m_wvalid_o(exec_wvalid_w),
        .m_wready_i(owner_exec_w && m_wready_i),
        .m_bid_i(m_bid_i), .m_bresp_i(m_bresp_i),
        .m_bvalid_i(owner_exec_w && m_bvalid_i),
        .m_bready_o(exec_bready_w),
        .m_arid_o(exec_arid_w), .m_araddr_o(exec_araddr_w),
        .m_arlen_o(exec_arlen_w), .m_arsize_o(exec_arsize_w),
        .m_arburst_o(exec_arburst_w),
        .m_arvalid_o(exec_arvalid_w),
        .m_arready_i(owner_exec_w && m_arready_i),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i(owner_exec_w && m_rvalid_i),
        .m_rready_o(exec_rready_w)
    );

    assign m_awid_o = owner_exec_w ? exec_awid_w : 4'h1;
    assign m_awaddr_o = owner_exec_w ? exec_awaddr_w :
                         (init_segment_r ? 32'h1000 : 32'd0);
    assign m_awlen_o = owner_exec_w ? exec_awlen_w :
                        (init_segment_r ? 8'd11 : 8'd15);
    assign m_awsize_o = owner_exec_w ? exec_awsize_w : 3'd5;
    assign m_awburst_o = owner_exec_w ? exec_awburst_w : 2'b01;
    assign m_awqos_o = 4'd0;
    assign m_awvalid_o = owner_exec_w ? exec_awvalid_w :
                         state_r == S_INIT_AW;
    assign m_wdata_o = owner_exec_w ? exec_wdata_w : {32{8'd1}};
    assign m_wstrb_o = owner_exec_w ? exec_wstrb_w : 32'hffff_ffff;
    assign m_wlast_o = owner_exec_w ? exec_wlast_w :
        init_segment_r ? init_index_r == 5'd11 :
                         init_index_r == 5'd15;
    assign m_wvalid_o = owner_exec_w ? exec_wvalid_w :
                        state_r == S_INIT_W;
    assign m_bready_o = owner_exec_w ? exec_bready_w :
                        state_r == S_INIT_B;
    assign m_arid_o = owner_exec_w ? exec_arid_w : 4'h2;
    assign m_araddr_o = owner_exec_w ? exec_araddr_w :
        32'h4000 + {21'd0, check_request_r, 9'd0};
    assign m_arlen_o = owner_exec_w ? exec_arlen_w : 8'd15;
    assign m_arsize_o = owner_exec_w ? exec_arsize_w : 3'd5;
    assign m_arburst_o = owner_exec_w ? exec_arburst_w : 2'b01;
    assign m_arqos_o = 4'd0;
    assign m_arvalid_o = owner_exec_w ? exec_arvalid_w :
                         state_r == S_CHECK_AR;
    assign m_rready_o = owner_exec_w ? exec_rready_w :
                        state_r == S_CHECK_R;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_WAIT_DDR;
            init_segment_r <= 1'b0;
            init_index_r <= 5'd0;
            cmd_index_r <= 2'd0;
            check_request_r <= 2'd0;
            check_index_r <= 4'd0;
            error_flags_r <= 5'd0;
            first_bad_valid_r <= 1'b0;
            first_bad_index_r <= 16'd0;
            first_bad_got_r <= 32'd0;
            first_bad_expected_r <= 32'd0;
            check_valid_r <= 1'b0;
            check_beat_r <= 6'd0;
            check_resp_bad_r <= 1'b0;
            check_last_bad_r <= 1'b0;
            mac_count_r <= 32'd0;
            read_count_r <= 32'd0;
            write_count_r <= 32'd0;
            cycle_count_r <= 32'd0;
            conv_cycle_count_r <= 32'd0;
            pool_cycle_count_r <= 32'd0;
            other_cycle_count_r <= 32'd0;
            ar_wait_count_r <= 32'd0;
            w_wait_count_r <= 32'd0;
        end else begin
            if (check_valid_r) begin
                if (check_data_bad_w || check_resp_bad_r ||
                    check_last_bad_r) begin
                    error_flags_r[4] <= error_flags_r[4] ||
                                        check_data_bad_w;
                    error_flags_r[3] <= error_flags_r[3] ||
                                        check_last_bad_r;
                    error_flags_r[2] <= error_flags_r[2] ||
                                        check_resp_bad_r;
                    if (!first_bad_valid_r) begin
                        first_bad_valid_r <= 1'b1;
                        first_bad_index_r <= check_beat_index_w - 16'd1;
                        first_bad_got_r <= check_data_r[31:0];
                        first_bad_expected_r <= 32'h02020202;
                    end
                end
            end
            check_valid_r <= check_fire_w;
            if (check_fire_w) begin
                check_data_r <= m_rdata_i;
                check_beat_r <= check_beat_r + 6'd1;
                check_resp_bad_r <= m_rid_i != 4'h2 ||
                                    m_rresp_i != 2'b00;
                check_last_bad_r <= m_rlast_i !=
                                    (check_index_r == 4'd15);
            end
            if (owner_exec_w) begin
                cycle_count_r <= cycle_count_r + 32'd1;
                if (cmd_index_r == 2'd0)
                    conv_cycle_count_r <= conv_cycle_count_r + 32'd1;
                else if (cmd_index_r == 2'd2)
                    pool_cycle_count_r <= pool_cycle_count_r + 32'd1;
                else
                    other_cycle_count_r <= other_cycle_count_r + 32'd1;
                if (exec_mac_beat_w)
                    mac_count_r <= mac_count_r + 32'd1;
                if (m_rvalid_i && m_rready_o)
                    read_count_r <= read_count_r + 32'd1;
                if (m_wvalid_o && m_wready_i)
                    write_count_r <= write_count_r + 32'd1;
                if (m_arvalid_o && !m_arready_i)
                    ar_wait_count_r <= ar_wait_count_r + 32'd1;
                if (m_wvalid_o && !m_wready_i)
                    w_wait_count_r <= w_wait_count_r + 32'd1;
            end
            case (state_r)
                S_WAIT_DDR: if (ddr_ready_i)
                    state_r <= S_INIT_AW;
                S_INIT_AW: if (m_awvalid_o && m_awready_i) begin
                    init_index_r <= 5'd0;
                    state_r <= S_INIT_W;
                end
                S_INIT_W: if (m_wvalid_o && m_wready_i) begin
                    if (m_wlast_o)
                        state_r <= S_INIT_B;
                    else
                        init_index_r <= init_index_r + 5'd1;
                end
                S_INIT_B: if (m_bvalid_i && m_bready_o) begin
                    if (m_bid_i != 4'h1 || m_bresp_i != 2'b00)
                        error_flags_r[0] <= 1'b1;
                    if (init_segment_r)
                        state_r <= S_CMD_START;
                    else begin
                        init_segment_r <= 1'b1;
                        state_r <= S_INIT_AW;
                    end
                end
                S_CMD_START: if (exec_cmd_ready_w)
                    state_r <= S_CMD_WAIT;
                S_CMD_WAIT: if (exec_done_w) begin
                    if (exec_error_w)
                        error_flags_r[1] <= 1'b1;
                    if (cmd_index_r == 2'd3) begin
                        check_request_r <= 2'd0;
                        check_index_r <= 4'd0;
                        state_r <= S_CHECK_AR;
                    end else begin
                        cmd_index_r <= cmd_index_r + 2'd1;
                        state_r <= S_CMD_START;
                    end
                end
                S_CHECK_AR: if (m_arvalid_o && m_arready_i) begin
                    check_index_r <= 4'd0;
                    state_r <= S_CHECK_R;
                end
                S_CHECK_R: if (check_fire_w) begin
                    if (check_index_r == 4'd15) begin
                        if (check_request_r == 2'd2)
                            state_r <= S_CHECK_DRAIN;
                        else begin
                            check_request_r <= check_request_r + 2'd1;
                            state_r <= S_CHECK_AR;
                        end
                    end else
                        check_index_r <= check_index_r + 4'd1;
                end
                S_CHECK_DRAIN: state_r <= S_FINISHED;
                S_FINISHED: state_r <= S_FINISHED;
                default: state_r <= S_WAIT_DDR;
            endcase
        end
    end
endmodule
