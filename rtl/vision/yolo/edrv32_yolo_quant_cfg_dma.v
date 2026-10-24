// ============================================================================
// File        : edrv32_yolo_quant_cfg_dma.v
// Description : Fetch one C32 output block's quantization record from DDR.
// Notes       : A 512-byte record contains 32 eight-byte channel entries,
//               then one 256-byte activation LUT. The reader owns AXI only
//               during the fetch; the CONV engine is in configuration state.
// ============================================================================

module edrv32_yolo_quant_cfg_dma (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         enable_i,
    input  wire [31:0]  cfg_base_i,
    input  wire [4:0]   cfg_block_i,
    input  wire         cfg_phase_i,
    input  wire         lut_enable_i,
    input  wire [4:0]   cfg_channel_i,
    input  wire         cfg_ready_i,
    output wire         cfg_valid_o,
    output wire [31:0]  cfg_bias_o,
    output wire [15:0]  cfg_multiplier_o,
    output wire [5:0]   cfg_shift_o,
    output wire [7:0]   cfg_zero_point_o,
    input  wire [7:0]   lut_index_i,
    input  wire         lut_ready_i,
    output wire         lut_valid_o,
    output wire [7:0]   lut_data_o,
    output wire         axi_owner_o,
    output wire         error_o,

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
    output wire         m_rready_o
);

    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_REQ = 3'd1;
    localparam [2:0] S_WAIT = 3'd2;
    localparam [2:0] S_CFG = 3'd3;
    localparam [2:0] S_LUT = 3'd4;
    localparam [2:0] S_FAULT = 3'd5;

    reg [2:0] state_r;
    reg error_r;
    reg [31:0] record_addr_r;
    reg [255:0] record_r [0:15];
    reg [63:0] channel_record_r;
    reg channel_valid_r;
    reg [7:0] lut_data_r;
    reg lut_data_valid_r;
    wire req_ready_w;
    wire beat_valid_w;
    wire [15:0] beat_index_w;
    wire [255:0] beat_data_w;
    wire read_done_w;
    wire read_error_w;
    wire [3:0] arlen_w;
    wire [4:0] fetch_channel_w = channel_valid_r ?
        cfg_channel_i + 5'd1 : cfg_channel_i;
    wire [255:0] channel_beat_w = record_r[{1'b0,
                                             fetch_channel_w[4:2]}];
    wire [63:0] channel_record_w =
        channel_beat_w[fetch_channel_w[1:0]*64 +: 64];
    wire lut_fire_w = lut_valid_o && lut_ready_i;
    wire [7:0] lut_fetch_index_w =
        lut_fire_w ? lut_index_i + 8'd1 : lut_index_i;
    wire [255:0] lut_beat_w = record_r[4'd8 +
                                      {1'b0, lut_fetch_index_w[7:5]}];
    wire [7:0] lut_fetch_data_w =
        lut_beat_w[lut_fetch_index_w[4:0]*8 +: 8];

    assign cfg_valid_o = state_r == S_CFG && channel_valid_r;
    assign cfg_bias_o = channel_record_r[31:0];
    assign cfg_multiplier_o = channel_record_r[47:32];
    assign cfg_shift_o = channel_record_r[53:48];
    assign cfg_zero_point_o = channel_record_r[63:56];
    assign lut_valid_o = state_r == S_LUT && lut_data_valid_r;
    assign lut_data_o = lut_data_r;
    assign axi_owner_o = state_r == S_REQ || state_r == S_WAIT;
    assign error_o = error_r;
    assign m_arlen_o = {4'd0, arlen_w};

    edrv32_yolo_axi_reader #(.AXI_ID(4'hd)) u_reader (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .req_valid_i(state_r == S_REQ),
        .req_ready_o(req_ready_w),
        .req_addr_i(record_addr_r),
        .req_beats_i(16'd16),
        .beat_valid_o(beat_valid_w),
        .beat_index_o(beat_index_w),
        .beat_data_o(beat_data_w),
        .busy_o(), .done_o(read_done_w), .error_o(read_error_w),
        .m_arid_o(m_arid_o), .m_araddr_o(m_araddr_o),
        .m_arlen_o(arlen_w), .m_arsize_o(m_arsize_o),
        .m_arburst_o(m_arburst_o),
        .m_arvalid_o(m_arvalid_o), .m_arready_i(m_arready_i),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i(m_rvalid_i), .m_rready_o(m_rready_o)
    );

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            error_r <= 1'b0;
            record_addr_r <= 32'd0;
            channel_valid_r <= 1'b0;
            lut_data_valid_r <= 1'b0;
        end else begin
            if (beat_valid_w && beat_index_w < 16'd16)
                record_r[beat_index_w[3:0]] <= beat_data_w;
            case (state_r)
                S_IDLE: if (enable_i && cfg_phase_i) begin
                    record_addr_r <= cfg_base_i +
                                     {18'd0, cfg_block_i, 9'd0};
                    channel_valid_r <= 1'b0;
                    lut_data_valid_r <= 1'b0;
                    state_r <= S_REQ;
                end
                S_REQ: if (req_ready_w)
                    state_r <= S_WAIT;
                S_WAIT: if (read_done_w) begin
                    if (read_error_w) begin
                        error_r <= 1'b1;
                        state_r <= S_FAULT;
                    end else
                        state_r <= S_CFG;
                end
                S_CFG: begin
                    if (!channel_valid_r) begin
                        channel_record_r <= channel_record_w;
                        channel_valid_r <= 1'b1;
                    end else if (cfg_ready_i) begin
                        if (cfg_channel_i == 5'd31) begin
                            channel_valid_r <= 1'b0;
                            lut_data_valid_r <= 1'b0;
                            state_r <= lut_enable_i ? S_LUT : S_IDLE;
                        end else
                            channel_record_r <= channel_record_w;
                    end
                end
                S_LUT: begin
                    if (lut_fire_w && lut_index_i == 8'd255) begin
                        lut_data_valid_r <= 1'b0;
                        state_r <= S_IDLE;
                    end else if (!lut_data_valid_r || lut_fire_w) begin
                        lut_data_r <= lut_fetch_data_w;
                        lut_data_valid_r <= 1'b1;
                    end
                end
                default: state_r <= S_FAULT;
            endcase
        end
    end
endmodule
