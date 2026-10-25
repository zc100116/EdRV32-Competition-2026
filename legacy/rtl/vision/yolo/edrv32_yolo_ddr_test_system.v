// ============================================================================
// File        : edrv32_yolo_ddr_test_system.v
// Description : DDR-backed convolution board self-test in the 150-MHz domain.
// Notes       : The short self-test and the 64x32 throughput case both read
//               back every output beat before reporting completion.
//               Test and layer own the AXI port in non-overlapping phases.
// ============================================================================

module edrv32_yolo_ddr_test_system #(
    parameter integer BENCHMARK_MODE = 0,
    parameter [9:0] BENCH_TILE_PAIRS = 10'd4
) (
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
    output wire [31:0]  weight_cycle_count_o,
    output wire [31:0]  feature_cycle_count_o,
    output wire [31:0]  run_cycle_count_o,
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

    localparam [3:0] S_WAIT_DDR   = 4'd0;
    localparam [3:0] S_CONFIG     = 4'd1;
    localparam [3:0] S_INIT_AW    = 4'd2;
    localparam [3:0] S_INIT_W     = 4'd3;
    localparam [3:0] S_INIT_B     = 4'd4;
    localparam [3:0] S_LAYER_START= 4'd5;
    localparam [3:0] S_LAYER_WAIT = 4'd6;
    localparam [3:0] S_CHECK_AR   = 4'd7;
    localparam [3:0] S_CHECK_R    = 4'd8;
    localparam [3:0] S_FINISHED   = 4'd9;
    localparam [3:0] S_CHECK_DRAIN = 4'd10;
    localparam [11:0] INIT_BEATS = BENCHMARK_MODE ? 12'd1168 : 12'd156;
    localparam [6:0] CHECK_REQUEST_LAST = BENCHMARK_MODE ? 7'd127 : 7'd5;
    localparam [4:0] CHECK_BURST_BEATS = BENCHMARK_MODE ? 5'd16 : 5'd4;

    reg [3:0] state_r;
    reg [4:0] error_flags_r;
    reg first_bad_valid_r;
    reg [15:0] first_bad_index_r;
    reg [31:0] first_bad_got_r;
    reg [31:0] first_bad_expected_r;
    reg check_valid_r;
    reg [255:0] check_data_r;
    reg [7:0] check_expected0_r;
    reg [7:0] check_expected1_r;
    reg [6:0] check_request_pipe_r;
    reg [3:0] check_pair_pipe_r;
    reg check_response_bad_r;
    reg check_last_bad_r;
    reg [4:0] config_channel_r;
    reg [11:0] init_base_r;
    reg [4:0] init_w_index_r;
    reg [6:0] check_request_r;
    reg [3:0] check_pair_r;
    reg [31:0] mac_count_r;
    reg [31:0] read_count_r;
    reg [31:0] write_count_r;
    reg [31:0] cycle_count_r;
    reg [31:0] weight_cycle_count_r;
    reg [31:0] feature_cycle_count_r;
    reg [31:0] run_cycle_count_r;
    reg [31:0] ar_wait_count_r;
    reg [31:0] w_wait_count_r;

    wire owner_layer_w = state_r == S_LAYER_START ||
                         state_r == S_LAYER_WAIT;
    wire init_weight_w = init_base_r < 12'd144;
    wire [4:0] init_burst_beats_w = BENCHMARK_MODE ? 5'd16 :
                                     (init_weight_w ? 5'd16 : 5'd4);
    wire [11:0] init_beat_w = init_base_r + {7'd0, init_w_index_r};
    wire [11:0] feature_beat_w = init_beat_w - 12'd144;
    wire [2:0] feature_row_w = feature_beat_w[5:2];
    wire [1:0] feature_pair_w = feature_beat_w[1:0];
    wire [7:0] feature_value0_w =
        {4'd0, feature_row_w, 1'b0} +
        {5'd0, feature_pair_w, 1'b0} + 8'd1;
    wire [7:0] feature_value1_w = feature_value0_w + 8'd1;
    wire [255:0] init_data_w = BENCHMARK_MODE || init_weight_w ?
        {32{8'h01}} : {{16{feature_value1_w}}, {16{feature_value0_w}}};
    wire [31:0] init_addr_w = init_weight_w ?
        {15'd0, init_base_r, 5'd0} :
        32'h0001_0000 +
        {15'd0, (init_base_r - 12'd144), 5'd0};
    wire [1:0] short_check_row_w = check_request_r < 7'd3 ?
                                  check_request_r[1:0] :
                                  check_request_r[1:0] - 2'd3;
    wire [4:0] bench_check_row_w = check_request_r[5:1];
    wire [5:0] bench_check_x0_w = {check_request_r[0], check_pair_r, 1'b0};
    wire [5:0] bench_check_x1_w = bench_check_x0_w + 6'd1;
    wire [31:0] check_addr_w = BENCHMARK_MODE ?
        (check_request_r[6] ? 32'h0003_0000 : 32'h0002_0000) +
        {17'd0, check_request_r[5:0], 9'd0} :
        (check_request_r < 7'd3 ? 32'h0002_0000 : 32'h0003_0000) +
        {23'd0, short_check_row_w, 7'd0};

    function [7:0] bench_golden_pixel;
        input [4:0] row_i;
        input [5:0] x_i;
        reg x_edge;
        reg y_edge;
        begin
            x_edge = x_i == 6'd0 || x_i == 6'd63;
            y_edge = row_i == 5'd0 || row_i == 5'd31;
            bench_golden_pixel = x_edge && y_edge ? 8'd4 :
                                 x_edge || y_edge ? 8'd6 : 8'd9;
        end
    endfunction

    function [7:0] golden_pixel;
        input [1:0] row_i;
        input [2:0] x_i;
        begin
            golden_pixel = 8'd0;
            case ({row_i, x_i})
                5'd0: golden_pixel = 8'd10;
                5'd1: golden_pixel = 8'd18;
                5'd2: golden_pixel = 8'd24;
                5'd3: golden_pixel = 8'd30;
                5'd4: golden_pixel = 8'd36;
                5'd5: golden_pixel = 8'd42;
                5'd6: golden_pixel = 8'd48;
                5'd7: golden_pixel = 8'd34;
                5'd8: golden_pixel = 8'd21;
                5'd9: golden_pixel = 8'd36;
                5'd10: golden_pixel = 8'd45;
                5'd11: golden_pixel = 8'd54;
                5'd12: golden_pixel = 8'd63;
                5'd13: golden_pixel = 8'd72;
                5'd14: golden_pixel = 8'd81;
                5'd15: golden_pixel = 8'd57;
                5'd16: golden_pixel = 8'd18;
                5'd17: golden_pixel = 8'd30;
                5'd18: golden_pixel = 8'd36;
                5'd19: golden_pixel = 8'd42;
                5'd20: golden_pixel = 8'd48;
                5'd21: golden_pixel = 8'd54;
                5'd22: golden_pixel = 8'd60;
                5'd23: golden_pixel = 8'd42;
                default: golden_pixel = 8'd0;
            endcase
        end
    endfunction

    wire [2:0] check_x0_w = {check_pair_r[1:0], 1'b0};
    wire [2:0] check_x1_w = check_x0_w + 3'd1;
    wire [7:0] check_expected0_w = BENCHMARK_MODE ?
        bench_golden_pixel(bench_check_row_w, bench_check_x0_w) :
        golden_pixel(short_check_row_w, check_x0_w);
    wire [7:0] check_expected1_w = BENCHMARK_MODE ?
        bench_golden_pixel(bench_check_row_w, bench_check_x1_w) :
        golden_pixel(short_check_row_w, check_x1_w);
    wire [255:0] check_expected_pipe_w =
        {{16{check_expected1_r}}, {16{check_expected0_r}}};
    wire check_data_bad_w = check_valid_r &&
                            check_data_r != check_expected_pipe_w;
    wire init_response_bad_w = state_r == S_INIT_B &&
        m_bvalid_i && m_bready_o &&
        (m_bid_i != 4'h1 || m_bresp_i != 2'b00);
    wire layer_bad_w = state_r == S_LAYER_WAIT &&
                       layer_done_w && layer_error_w;
    wire [4:0] error_events_w = {
        check_data_bad_w,
        check_valid_r && check_last_bad_r,
        check_valid_r && check_response_bad_r,
        layer_bad_w,
        init_response_bad_w
    };

    wire layer_start_ready_w;
    wire layer_done_w;
    wire layer_error_w;
    wire layer_mac_beat_w;
    wire layer_weight_phase_w;
    wire layer_feature_phase_w;
    wire layer_run_phase_w;
    wire layer_quant_ready_w;
    wire [3:0] layer_awid_w;
    wire [31:0] layer_awaddr_w;
    wire [7:0] layer_awlen_w;
    wire [2:0] layer_awsize_w;
    wire [1:0] layer_awburst_w;
    wire layer_awvalid_w;
    wire [255:0] layer_wdata_w;
    wire [31:0] layer_wstrb_w;
    wire layer_wlast_w;
    wire layer_wvalid_w;
    wire layer_bready_w;
    wire [3:0] layer_arid_w;
    wire [31:0] layer_araddr_w;
    wire [7:0] layer_arlen_w;
    wire [2:0] layer_arsize_w;
    wire [1:0] layer_arburst_w;
    wire layer_arvalid_w;
    wire layer_rready_w;

    assign init_done_o = state_r >= S_LAYER_START;
    assign layer_busy_o = state_r == S_LAYER_START ||
                          state_r == S_LAYER_WAIT;
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
    assign weight_cycle_count_o = weight_cycle_count_r;
    assign feature_cycle_count_o = feature_cycle_count_r;
    assign run_cycle_count_o = run_cycle_count_r;
    assign ar_wait_count_o = ar_wait_count_r;
    assign w_wait_count_o = w_wait_count_r;

    edrv32_yolo_conv_layer u_layer (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(state_r == S_LAYER_START),
        .start_ready_o(layer_start_ready_w),
        .feature_base_i(32'h0001_0000),
        .feature_plane_stride_i(BENCHMARK_MODE ? 32'd32768 : 32'd384),
        .weight_base_i(32'd0),
        .output_plane0_base_i(32'h0002_0000),
        .output_plane1_base_i(32'h0003_0000),
        .output_plane1_enable_i(1'b1),
        .input_width_i(BENCHMARK_MODE ? 11'd64 : 11'd8),
        .input_height_i(BENCHMARK_MODE ? 16'd32 : 16'd3),
        .output_width_pairs_i(BENCHMARK_MODE ? 10'd32 : 10'd4),
        .output_height_i(BENCHMARK_MODE ? 16'd32 : 16'd3),
        .cin_blocks_i(6'd1),
        .cache_bank_stride_i(BENCHMARK_MODE ? 9'd16 : 9'd2),
        .cache_row_stride_i(BENCHMARK_MODE ? 10'd16 : 10'd2),
        .tile_pairs_i(BENCHMARK_MODE ? BENCH_TILE_PAIRS : 10'd2),
        .kernel3_i(1'b1), .stride2_i(1'b0),
        .busy_o(), .done_o(layer_done_w),
        .error_o(layer_error_w),
        .mac_beat_o(layer_mac_beat_w),
        .weight_phase_o(layer_weight_phase_w),
        .feature_phase_o(layer_feature_phase_w),
        .run_phase_o(layer_run_phase_w),
        .quant_cfg_valid_i(state_r == S_CONFIG),
        .quant_cfg_ready_o(layer_quant_ready_w),
        .quant_cfg_channel_i(config_channel_r),
        .quant_cfg_bias_i(32'd0),
        .quant_cfg_multiplier_i(16'd1),
        .quant_cfg_shift_i(6'd4),
        .quant_cfg_zero_point_i(8'd0),
        .lut_enable_i(1'b0), .lut_cfg_valid_i(1'b0),
        .lut_cfg_ready_o(), .lut_cfg_addr_i(8'd0),
        .lut_cfg_data_i(8'd0),
        .m_awid_o(layer_awid_w),
        .m_awaddr_o(layer_awaddr_w),
        .m_awlen_o(layer_awlen_w),
        .m_awsize_o(layer_awsize_w),
        .m_awburst_o(layer_awburst_w),
        .m_awvalid_o(layer_awvalid_w),
        .m_awready_i(m_awready_i && owner_layer_w),
        .m_wdata_o(layer_wdata_w),
        .m_wstrb_o(layer_wstrb_w),
        .m_wlast_o(layer_wlast_w),
        .m_wvalid_o(layer_wvalid_w),
        .m_wready_i(m_wready_i && owner_layer_w),
        .m_bid_i(m_bid_i), .m_bresp_i(m_bresp_i),
        .m_bvalid_i(m_bvalid_i && owner_layer_w),
        .m_bready_o(layer_bready_w),
        .m_arid_o(layer_arid_w),
        .m_araddr_o(layer_araddr_w),
        .m_arlen_o(layer_arlen_w),
        .m_arsize_o(layer_arsize_w),
        .m_arburst_o(layer_arburst_w),
        .m_arvalid_o(layer_arvalid_w),
        .m_arready_i(m_arready_i && owner_layer_w),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i(m_rvalid_i && owner_layer_w),
        .m_rready_o(layer_rready_w)
    );

    assign m_awid_o = owner_layer_w ? layer_awid_w : 4'h1;
    assign m_awaddr_o = owner_layer_w ? layer_awaddr_w : init_addr_w;
    assign m_awlen_o = owner_layer_w ? layer_awlen_w :
                       {3'd0, init_burst_beats_w} - 8'd1;
    assign m_awsize_o = owner_layer_w ? layer_awsize_w : 3'd5;
    assign m_awburst_o = owner_layer_w ? layer_awburst_w : 2'b01;
    assign m_awqos_o = owner_layer_w ? 4'd2 : 4'd0;
    assign m_awvalid_o = owner_layer_w ? layer_awvalid_w :
                         state_r == S_INIT_AW;
    assign m_wdata_o = owner_layer_w ? layer_wdata_w : init_data_w;
    assign m_wstrb_o = owner_layer_w ? layer_wstrb_w : 32'hffff_ffff;
    assign m_wlast_o = owner_layer_w ? layer_wlast_w :
                       init_w_index_r + 5'd1 == init_burst_beats_w;
    assign m_wvalid_o = owner_layer_w ? layer_wvalid_w :
                        state_r == S_INIT_W;
    assign m_bready_o = owner_layer_w ? layer_bready_w :
                        state_r == S_INIT_B;
    assign m_arid_o = owner_layer_w ? layer_arid_w : 4'h1;
    assign m_araddr_o = owner_layer_w ? layer_araddr_w : check_addr_w;
    assign m_arlen_o = owner_layer_w ? layer_arlen_w :
                       {3'd0, CHECK_BURST_BEATS} - 8'd1;
    assign m_arsize_o = owner_layer_w ? layer_arsize_w : 3'd5;
    assign m_arburst_o = owner_layer_w ? layer_arburst_w : 2'b01;
    assign m_arqos_o = owner_layer_w ? 4'd2 : 4'd0;
    assign m_arvalid_o = owner_layer_w ? layer_arvalid_w :
                         state_r == S_CHECK_AR;
    assign m_rready_o = owner_layer_w ? layer_rready_w :
                        state_r == S_CHECK_R;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r           <= S_WAIT_DDR;
            error_flags_r     <= 5'd0;
            first_bad_valid_r <= 1'b0;
            first_bad_index_r <= 16'd0;
            first_bad_got_r   <= 32'd0;
            first_bad_expected_r <= 32'd0;
            check_valid_r     <= 1'b0;
            config_channel_r  <= 5'd0;
            init_base_r       <= 12'd0;
            init_w_index_r    <= 5'd0;
            check_request_r   <= 7'd0;
            check_pair_r      <= 4'd0;
            mac_count_r       <= 32'd0;
            read_count_r      <= 32'd0;
            write_count_r     <= 32'd0;
            cycle_count_r     <= 32'd0;
            weight_cycle_count_r <= 32'd0;
            feature_cycle_count_r <= 32'd0;
            run_cycle_count_r <= 32'd0;
            ar_wait_count_r <= 32'd0;
            w_wait_count_r <= 32'd0;
        end else begin
            error_flags_r <= error_flags_r | error_events_w;
            check_valid_r <= state_r == S_CHECK_R &&
                             m_rvalid_i && m_rready_o;
            if (check_data_bad_w && !first_bad_valid_r) begin
                first_bad_valid_r <= 1'b1;
                first_bad_index_r <= BENCHMARK_MODE ?
                    {5'd0, check_request_pipe_r, check_pair_pipe_r} :
                    {8'd0, 2'd0, check_request_pipe_r[2:0],
                     1'd0, check_pair_pipe_r[1:0]};
                first_bad_got_r <= check_data_r[31:0];
                first_bad_expected_r <= {4{check_expected0_r}};
            end
            if (owner_layer_w) begin
                if (layer_mac_beat_w)
                    mac_count_r <= mac_count_r + 32'd1;
                if (m_rvalid_i && m_rready_o)
                    read_count_r <= read_count_r + 32'd1;
                if (m_wvalid_o && m_wready_i)
                    write_count_r <= write_count_r + 32'd1;
                if (state_r == S_LAYER_WAIT)
                    cycle_count_r <= cycle_count_r + 32'd1;
                if (layer_weight_phase_w)
                    weight_cycle_count_r <= weight_cycle_count_r + 32'd1;
                if (layer_feature_phase_w)
                    feature_cycle_count_r <= feature_cycle_count_r + 32'd1;
                if (layer_run_phase_w)
                    run_cycle_count_r <= run_cycle_count_r + 32'd1;
                if (m_arvalid_o && !m_arready_i)
                    ar_wait_count_r <= ar_wait_count_r + 32'd1;
                if (m_wvalid_o && !m_wready_i)
                    w_wait_count_r <= w_wait_count_r + 32'd1;
            end
            case (state_r)
                S_WAIT_DDR: if (ddr_ready_i)
                    state_r <= S_CONFIG;
                S_CONFIG: if (layer_quant_ready_w) begin
                    if (config_channel_r == 5'd31)
                        state_r <= S_INIT_AW;
                    else
                        config_channel_r <= config_channel_r + 5'd1;
                end
                S_INIT_AW: if (m_awvalid_o && m_awready_i) begin
                    init_w_index_r <= 5'd0;
                    state_r <= S_INIT_W;
                end
                S_INIT_W: if (m_wvalid_o && m_wready_i) begin
                    if (m_wlast_o)
                        state_r <= S_INIT_B;
                    else
                        init_w_index_r <= init_w_index_r + 5'd1;
                end
                S_INIT_B: if (m_bvalid_i && m_bready_o) begin
                    if (init_base_r + {7'd0, init_burst_beats_w} ==
                        INIT_BEATS)
                        state_r <= S_LAYER_START;
                    else begin
                        init_base_r <= init_base_r +
                                       {7'd0, init_burst_beats_w};
                        state_r <= S_INIT_AW;
                    end
                end
                S_LAYER_START: if (layer_start_ready_w)
                    state_r <= S_LAYER_WAIT;
                S_LAYER_WAIT: if (layer_done_w) begin
                    check_request_r <= 7'd0;
                    state_r <= S_CHECK_AR;
                end
                S_CHECK_AR: if (m_arvalid_o && m_arready_i) begin
                    check_pair_r <= 4'd0;
                    state_r <= S_CHECK_R;
                end
                S_CHECK_R: if (m_rvalid_i && m_rready_o) begin
                    check_data_r <= m_rdata_i;
                    check_expected0_r <= check_expected0_w;
                    check_expected1_r <= check_expected1_w;
                    check_request_pipe_r <= check_request_r;
                    check_pair_pipe_r <= check_pair_r;
                    check_response_bad_r <= m_rid_i != 4'h1 ||
                                            m_rresp_i != 2'b00;
                    check_last_bad_r <= m_rlast_i !=
                                        (check_pair_r + 5'd1 ==
                                         CHECK_BURST_BEATS);
                    if (check_pair_r + 5'd1 == CHECK_BURST_BEATS) begin
                        if (check_request_r == CHECK_REQUEST_LAST)
                            state_r <= S_CHECK_DRAIN;
                        else begin
                            check_request_r <= check_request_r + 7'd1;
                            state_r <= S_CHECK_AR;
                        end
                    end else
                        check_pair_r <= check_pair_r + 4'd1;
                end
                S_CHECK_DRAIN: state_r <= S_FINISHED;
                default: state_r <= S_FINISHED;
            endcase
        end
    end
endmodule
