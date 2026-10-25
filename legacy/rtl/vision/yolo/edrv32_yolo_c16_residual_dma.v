// ============================================================================
// File        : edrv32_yolo_c16_residual_dma.v
// Description : DDR-to-DDR C16 residual add using bounded 256-bit bursts.
// Notes       : Each chunk reads A and B, then writes their saturated sum.
//               It uses 16-beat local buffers and splits at every 4 KiB
//               boundary. A, B and output share one quantization scale.
// ============================================================================

module edrv32_yolo_c16_residual_dma (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         start_i,
    output wire         start_ready_o,
    input  wire [31:0]  a_base_i,
    input  wire [31:0]  b_base_i,
    input  wire [31:0]  output_base_i,
    input  wire [15:0]  beat_count_i,
    input  wire [7:0]   zero_point_i,
    output wire         busy_o,
    output wire         done_o,
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

    localparam [3:0] S_IDLE    = 4'd0;
    localparam [3:0] S_CHUNK   = 4'd1;
    localparam [3:0] S_A_REQ   = 4'd2;
    localparam [3:0] S_A_WAIT  = 4'd3;
    localparam [3:0] S_B_REQ   = 4'd4;
    localparam [3:0] S_B_WAIT  = 4'd5;
    localparam [3:0] S_B_DRAIN = 4'd6;
    localparam [3:0] S_AW      = 4'd7;
    localparam [3:0] S_W       = 4'd8;
    localparam [3:0] S_B_RESP  = 4'd9;

    reg [3:0] state_r;
    reg done_r;
    reg error_r;
    reg [31:0] a_addr_r;
    reg [31:0] b_addr_r;
    reg [31:0] output_addr_r;
    reg [15:0] total_beats_r;
    reg [15:0] completed_beats_r;
    reg [4:0] chunk_beats_r;
    reg [4:0] output_count_r;
    reg [4:0] write_index_r;
    reg [7:0] zero_point_r;
    reg [255:0] a_buffer_r [0:15];
    reg [255:0] output_buffer_r [0:15];

    wire [15:0] remaining_w = total_beats_r - completed_beats_r;
    wire [7:0] a_boundary_w = 8'd128 - {1'b0, a_addr_r[11:5]};
    wire [7:0] b_boundary_w = 8'd128 - {1'b0, b_addr_r[11:5]};
    wire [7:0] output_boundary_w =
        8'd128 - {1'b0, output_addr_r[11:5]};
    wire [7:0] remaining_capped_w = remaining_w < 16'd16 ?
        {1'b0, remaining_w[6:0]} : 8'd16;
    wire [7:0] chunk_a_w = remaining_capped_w < a_boundary_w ?
                            remaining_capped_w : a_boundary_w;
    wire [7:0] chunk_b_w = chunk_a_w < b_boundary_w ?
                            chunk_a_w : b_boundary_w;
    wire [7:0] chunk_w = chunk_b_w < output_boundary_w ?
                          chunk_b_w : output_boundary_w;
    wire [31:0] chunk_bytes_w = {22'd0, chunk_beats_r, 5'd0};

    wire reader_req_ready_w;
    wire reader_beat_valid_w;
    wire [15:0] reader_beat_index_w;
    wire [255:0] reader_beat_data_w;
    wire reader_done_w;
    wire reader_error_w;
    wire add_in_valid_w = state_r == S_B_WAIT && reader_beat_valid_w;
    wire add_in_ready_w;
    wire add_out_valid_w;
    wire [255:0] add_out_data_w;
    wire w_fire_w = m_wvalid_o && m_wready_i;
    wire b_fire_w = m_bvalid_i && m_bready_o;

    assign start_ready_o = state_r == S_IDLE && beat_count_i != 16'd0;
    assign busy_o = state_r != S_IDLE;
    assign done_o = done_r;
    assign error_o = error_r;

    edrv32_yolo_axi_reader u_reader (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .req_valid_i(state_r == S_A_REQ || state_r == S_B_REQ),
        .req_ready_o(reader_req_ready_w),
        .req_addr_i(state_r == S_A_REQ ? a_addr_r : b_addr_r),
        .req_beats_i({11'd0, chunk_beats_r}),
        .beat_valid_o(reader_beat_valid_w),
        .beat_index_o(reader_beat_index_w),
        .beat_data_o(reader_beat_data_w),
        .busy_o(), .done_o(reader_done_w),
        .error_o(reader_error_w),
        .m_arid_o(m_arid_o), .m_araddr_o(m_araddr_o),
        .m_arlen_o(m_arlen_o[3:0]),
        .m_arsize_o(m_arsize_o),
        .m_arburst_o(m_arburst_o),
        .m_arvalid_o(m_arvalid_o),
        .m_arready_i(m_arready_i),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i(m_rvalid_i), .m_rready_o(m_rready_o)
    );
    assign m_arlen_o[7:4] = 4'd0;

    edrv32_yolo_c16_residual_add u_add (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .in_valid_i(add_in_valid_w),
        .in_ready_o(add_in_ready_w),
        .in_a_data_i(a_buffer_r[reader_beat_index_w[3:0]]),
        .in_b_data_i(reader_beat_data_w),
        .zero_point_i(zero_point_r),
        .out_valid_o(add_out_valid_w),
        .out_ready_i(1'b1),
        .out_data_o(add_out_data_w)
    );

    assign m_awid_o = 4'h9;
    assign m_awaddr_o = output_addr_r;
    assign m_awlen_o = {3'd0, chunk_beats_r} - 8'd1;
    assign m_awsize_o = 3'd5;
    assign m_awburst_o = 2'b01;
    assign m_awvalid_o = state_r == S_AW;
    assign m_wdata_o = output_buffer_r[write_index_r[3:0]];
    assign m_wstrb_o = 32'hffff_ffff;
    assign m_wlast_o = write_index_r + 5'd1 == chunk_beats_r;
    assign m_wvalid_o = state_r == S_W;
    assign m_bready_o = state_r == S_B_RESP;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            done_r <= 1'b0;
            error_r <= 1'b0;
            a_addr_r <= 32'd0;
            b_addr_r <= 32'd0;
            output_addr_r <= 32'd0;
            total_beats_r <= 16'd0;
            completed_beats_r <= 16'd0;
            chunk_beats_r <= 5'd0;
            output_count_r <= 5'd0;
            write_index_r <= 5'd0;
            zero_point_r <= 8'd0;
        end else begin
            done_r <= 1'b0;
            if (state_r == S_A_WAIT && reader_beat_valid_w)
                a_buffer_r[reader_beat_index_w[3:0]] <=
                    reader_beat_data_w;
            if (add_out_valid_w) begin
                output_buffer_r[output_count_r[3:0]] <= add_out_data_w;
                output_count_r <= output_count_r + 5'd1;
            end

            case (state_r)
                S_IDLE: if (start_i && start_ready_o) begin
                    a_addr_r <= a_base_i;
                    b_addr_r <= b_base_i;
                    output_addr_r <= output_base_i;
                    total_beats_r <= beat_count_i;
                    completed_beats_r <= 16'd0;
                    zero_point_r <= zero_point_i;
                    error_r <= a_base_i[4:0] != 5'd0 ||
                               b_base_i[4:0] != 5'd0 ||
                               output_base_i[4:0] != 5'd0;
                    state_r <= S_CHUNK;
                end
                S_CHUNK: begin
                    chunk_beats_r <= chunk_w[4:0];
                    output_count_r <= 5'd0;
                    write_index_r <= 5'd0;
                    state_r <= S_A_REQ;
                end
                S_A_REQ: if (reader_req_ready_w)
                    state_r <= S_A_WAIT;
                S_A_WAIT: if (reader_done_w) begin
                    if (reader_error_w)
                        error_r <= 1'b1;
                    state_r <= S_B_REQ;
                end
                S_B_REQ: if (reader_req_ready_w)
                    state_r <= S_B_WAIT;
                S_B_WAIT: if (reader_done_w) begin
                    if (reader_error_w)
                        error_r <= 1'b1;
                    state_r <= S_B_DRAIN;
                end
                S_B_DRAIN: if (output_count_r == chunk_beats_r)
                    state_r <= S_AW;
                S_AW: if (m_awvalid_o && m_awready_i)
                    state_r <= S_W;
                S_W: if (w_fire_w) begin
                    if (m_wlast_o)
                        state_r <= S_B_RESP;
                    else
                        write_index_r <= write_index_r + 5'd1;
                end
                S_B_RESP: if (b_fire_w) begin
                    if (m_bid_i != 4'h9 || m_bresp_i != 2'b00)
                        error_r <= 1'b1;
                    completed_beats_r <= completed_beats_r +
                                         {11'd0, chunk_beats_r};
                    a_addr_r <= a_addr_r + chunk_bytes_w;
                    b_addr_r <= b_addr_r + chunk_bytes_w;
                    output_addr_r <= output_addr_r + chunk_bytes_w;
                    if (completed_beats_r + {11'd0, chunk_beats_r} ==
                        total_beats_r) begin
                        done_r <= 1'b1;
                        state_r <= S_IDLE;
                    end else
                        state_r <= S_CHUNK;
                end
                default: state_r <= S_IDLE;
            endcase
        end
    end
endmodule
