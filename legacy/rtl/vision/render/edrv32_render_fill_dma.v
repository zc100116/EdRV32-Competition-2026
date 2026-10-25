// ============================================================================
// File        : edrv32_render_fill_dma.v
// Description : RGB565/ARGB8888 fill and incremental linear gradient DMA.
// Notes       : Solid fill keeps the full-width AXI burst path. Gradient
//               prepares each beat before its one-beat write transaction.
// ============================================================================

module edrv32_render_fill_dma #(
    parameter [3:0] AXI_ID = 4'h6
) (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         start_i,
    output wire         start_ready_o,
    input  wire [31:0]  row0_base_i,
    input  wire [31:0]  stride_i,
    input  wire [15:0]  x_i,
    input  wire [15:0]  width_i,
    input  wire [15:0]  height_i,
    input  wire         argb_i,
    input  wire [31:0]  color_i,
    input  wire         gradient_i,
    input  wire         gradient_vertical_i,
    input  wire [31:0]  gradient_step_a_i,
    input  wire [31:0]  gradient_step_r_i,
    input  wire [31:0]  gradient_step_g_i,
    input  wire [31:0]  gradient_step_b_i,
    output wire         busy_o,
    output wire         done_o,
    output wire         error_o,
    output wire [31:0]  beat_count_o,
    output wire [31:0]  burst_count_o,

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
    output wire         m_bready_o
);

    localparam [2:0] ST_IDLE = 3'd0;
    localparam [2:0] ST_ROW  = 3'd1;
    localparam [2:0] ST_AW   = 3'd2;
    localparam [2:0] ST_W    = 3'd3;
    localparam [2:0] ST_B    = 3'd4;
    localparam [2:0] ST_PREP = 3'd5;

    function [7:0] clamp_q16;
        input signed [39:0] value;
        begin
            if (value < 40'sd0)
                clamp_q16 = 8'd0;
            else if (value > 40'sd16711680)
                clamp_q16 = 8'hff;
            else
                clamp_q16 = value[23:16];
        end
    endfunction

    reg [2:0]  state_r;
    reg        done_r;
    reg        error_r;
    reg [31:0] row_base_r;
    reg [31:0] stride_r;
    reg [15:0] x_r;
    reg [15:0] width_r;
    reg [15:0] height_r;
    reg [15:0] row_index_r;
    reg        argb_r;
    reg [31:0] color_r;
    reg        gradient_r;
    reg        gradient_vertical_r;
    reg [31:0] gradient_step_a_r;
    reg [31:0] gradient_step_r_r;
    reg [31:0] gradient_step_g_r;
    reg [31:0] gradient_step_b_r;
    reg signed [39:0] gradient_row_a_r;
    reg signed [39:0] gradient_row_r_r;
    reg signed [39:0] gradient_row_g_r;
    reg signed [39:0] gradient_row_b_r;
    reg signed [39:0] gradient_a_r;
    reg signed [39:0] gradient_red_r;
    reg signed [39:0] gradient_green_r;
    reg signed [39:0] gradient_blue_r;
    reg [4:0]  gradient_lane_r;
    reg [255:0] gradient_word_r;
    reg [31:0] gradient_strobe_r;
    reg [31:0] row_first_byte_r;
    reg [31:0] row_end_byte_r;
    reg [31:0] beat_addr_r;
    reg [13:0] beats_remaining_r;
    reg [4:0]  prepared_burst_len_r;
    reg [4:0]  burst_len_r;
    reg [4:0]  beat_index_r;
    reg [31:0] beat_count_r;
    reg [31:0] burst_count_r;

    wire [31:0] x_bytes_w = argb_r ?
        {14'd0, x_r, 2'b00} : {15'd0, x_r, 1'b0};
    wire [31:0] width_bytes_w = argb_r ?
        {14'd0, width_r, 2'b00} : {15'd0, width_r, 1'b0};
    wire [31:0] first_byte_w = row_base_r + x_bytes_w;
    wire [31:0] end_byte_w = first_byte_w + width_bytes_w;
    wire [31:0] first_beat_addr_w = first_byte_w & 32'hffff_ffe0;
    // Row bases and strides are 32-byte aligned. Count beats from the pixel
    // span so burst preparation does not subtract two 32-bit addresses.
    wire [18:0] first_span_rounded_w =
        {1'b0,width_bytes_w[17:0]} +
        {14'd0,x_bytes_w[4:0]} + 19'd31;
    wire [13:0] first_beats_left_w = first_span_rounded_w[18:5];
    wire [7:0] first_boundary_beats_w = 8'd128 -
        {1'b0,first_beat_addr_w[11:5]};
    wire [4:0] first_burst_beats_w = first_beats_left_w < 14'd16 ?
        (first_beats_left_w < {6'd0,first_boundary_beats_w} ?
         first_beats_left_w[4:0] : first_boundary_beats_w[4:0]) :
        (first_boundary_beats_w < 8'd16 ?
         first_boundary_beats_w[4:0] : 5'd16);
    wire [7:0] boundary_beats_w = 8'd128 -
                                  {1'b0, beat_addr_r[11:5]};
    wire [4:0] burst_beats_w = beats_remaining_r < 14'd16 ?
        (beats_remaining_r < {6'd0,boundary_beats_w} ?
         beats_remaining_r[4:0] : boundary_beats_w[4:0]) :
        (boundary_beats_w < 8'd16 ? boundary_beats_w[4:0] : 5'd16);
    wire [255:0] argb_word_w = {8{color_r}};
    wire [255:0] rgb565_word_w = {16{color_r[15:0]}};
    wire [16:0] end_pixel_w = {1'b0,x_i} + {1'b0,width_i};
    wire [31:0] end_bytes_w = argb_i ?
        {13'd0,end_pixel_w,2'b00} :
        {14'd0,end_pixel_w,1'b0};
    wire [31:0] gradient_lane_addr_w = beat_addr_r +
        (argb_r ? {25'd0,gradient_lane_r,2'b00} :
                  {26'd0,gradient_lane_r,1'b0});
    wire gradient_pixel_valid_w =
        (gradient_lane_addr_w >= row_first_byte_r) &&
        (gradient_lane_addr_w < row_end_byte_r);
    wire [7:0] gradient_a_w = clamp_q16(gradient_a_r);
    wire [7:0] gradient_red_w = clamp_q16(gradient_red_r);
    wire [7:0] gradient_green_w = clamp_q16(gradient_green_r);
    wire [7:0] gradient_blue_w = clamp_q16(gradient_blue_r);
    wire [31:0] gradient_argb_w = {
        gradient_a_w,gradient_red_w,
        gradient_green_w,gradient_blue_w
    };
    wire [15:0] gradient_rgb565_w = {
        gradient_red_w[7:3],
        gradient_green_w[7:2],
        gradient_blue_w[7:3]
    };
    wire gradient_last_lane_w = argb_r ?
        (gradient_lane_r == 5'd7) :
        (gradient_lane_r == 5'd15);
    wire signed [39:0] step_a_w =
        {{8{gradient_step_a_r[31]}},gradient_step_a_r};
    wire signed [39:0] step_r_w =
        {{8{gradient_step_r_r[31]}},gradient_step_r_r};
    wire signed [39:0] step_g_w =
        {{8{gradient_step_g_r[31]}},gradient_step_g_r};
    wire signed [39:0] step_b_w =
        {{8{gradient_step_b_r[31]}},gradient_step_b_r};
    wire aw_fire_w = m_awvalid_o && m_awready_i;
    wire w_fire_w  = m_wvalid_o && m_wready_i;
    wire b_fire_w  = m_bvalid_i && m_bready_o;

    reg [31:0] strobe_w;
    integer byte_index;
    always @(*) begin
        strobe_w = 32'b0;
        for (byte_index = 0; byte_index < 32;
             byte_index = byte_index + 1) begin
            if ((beat_addr_r + byte_index >= row_first_byte_r) &&
                (beat_addr_r + byte_index < row_end_byte_r))
                strobe_w[byte_index] = 1'b1;
        end
    end

    assign start_ready_o = state_r == ST_IDLE;
    assign busy_o = state_r != ST_IDLE;
    assign done_o = done_r;
    assign error_o = error_r;
    assign beat_count_o = beat_count_r;
    assign burst_count_o = burst_count_r;

    assign m_awid_o    = AXI_ID;
    assign m_awaddr_o  = beat_addr_r;
    assign m_awlen_o   = {3'd0,prepared_burst_len_r} - 8'd1;
    assign m_awsize_o  = 3'd5;
    assign m_awburst_o = 2'b01;
    assign m_awqos_o   = 4'd4;
    assign m_awvalid_o = state_r == ST_AW;
    assign m_wdata_o   = gradient_r ? gradient_word_r :
                         (argb_r ? argb_word_w : rgb565_word_w);
    assign m_wstrb_o   = gradient_r ? gradient_strobe_r : strobe_w;
    assign m_wlast_o   = gradient_r ||
                         (beat_index_r == burst_len_r - 5'd1);
    assign m_wvalid_o  = state_r == ST_W;
    assign m_bready_o  = state_r == ST_B;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r      <= ST_IDLE;
            done_r       <= 1'b0;
            error_r      <= 1'b0;
            row_base_r   <= 32'b0;
            stride_r     <= 32'b0;
            x_r          <= 16'b0;
            width_r      <= 16'b0;
            height_r     <= 16'b0;
            row_index_r  <= 16'b0;
            argb_r       <= 1'b0;
            color_r      <= 32'b0;
            gradient_r   <= 1'b0;
            gradient_vertical_r <= 1'b0;
            gradient_step_a_r <= 32'd0;
            gradient_step_r_r <= 32'd0;
            gradient_step_g_r <= 32'd0;
            gradient_step_b_r <= 32'd0;
            gradient_row_a_r <= 40'sd0;
            gradient_row_r_r <= 40'sd0;
            gradient_row_g_r <= 40'sd0;
            gradient_row_b_r <= 40'sd0;
            gradient_a_r <= 40'sd0;
            gradient_red_r <= 40'sd0;
            gradient_green_r <= 40'sd0;
            gradient_blue_r <= 40'sd0;
            gradient_lane_r <= 5'd0;
            gradient_word_r <= 256'd0;
            gradient_strobe_r <= 32'd0;
            beat_addr_r  <= 32'b0;
            beats_remaining_r <= 14'd0;
            prepared_burst_len_r <= 5'd0;
            burst_len_r  <= 5'b0;
            beat_index_r <= 5'b0;
            beat_count_r <= 32'b0;
            burst_count_r <= 32'b0;
        end else begin
            done_r <= 1'b0;
            if (start_i && start_ready_o) begin
                error_r <= (row0_base_i[4:0] != 5'd0) ||
                           (stride_i[4:0] != 5'd0) ||
                           (gradient_i && ((end_pixel_w > 17'd65536) ||
                            (end_bytes_w > stride_i)));
                row_base_r    <= row0_base_i;
                stride_r      <= stride_i;
                x_r           <= x_i;
                width_r       <= width_i;
                height_r      <= height_i;
                row_index_r   <= 16'b0;
                argb_r        <= argb_i;
                color_r       <= color_i;
                gradient_r <= gradient_i;
                gradient_vertical_r <= gradient_vertical_i;
                gradient_step_a_r <= gradient_step_a_i;
                gradient_step_r_r <= gradient_step_r_i;
                gradient_step_g_r <= gradient_step_g_i;
                gradient_step_b_r <= gradient_step_b_i;
                gradient_row_a_r <= {16'd0,color_i[31:24],16'd0};
                gradient_row_r_r <= {16'd0,color_i[23:16],16'd0};
                gradient_row_g_r <= {16'd0,color_i[15:8],16'd0};
                gradient_row_b_r <= {16'd0,color_i[7:0],16'd0};
                gradient_a_r <= {16'd0,color_i[31:24],16'd0};
                gradient_red_r <= {16'd0,color_i[23:16],16'd0};
                gradient_green_r <= {16'd0,color_i[15:8],16'd0};
                gradient_blue_r <= {16'd0,color_i[7:0],16'd0};
                beat_count_r  <= 32'b0;
                burst_count_r <= 32'b0;
                if ((row0_base_i[4:0] != 5'd0) ||
                    (stride_i[4:0] != 5'd0) ||
                    (width_i == 16'd0) || (height_i == 16'd0) ||
                    (gradient_i && ((end_pixel_w > 17'd65536) ||
                                    (end_bytes_w > stride_i)))) begin
                    state_r <= ST_IDLE;
                    done_r <= 1'b1;
                end else begin
                    state_r <= ST_ROW;
                end
            end else begin
                case (state_r)
                    ST_ROW: begin
                        row_first_byte_r <= first_byte_w;
                        row_end_byte_r <= end_byte_w;
                        beat_addr_r <= first_beat_addr_w;
                        beats_remaining_r <= first_beats_left_w;
                        prepared_burst_len_r <= gradient_r ? 5'd1 :
                                                first_burst_beats_w;
                        gradient_lane_r <= 5'd0;
                        gradient_word_r <= 256'd0;
                        gradient_strobe_r <= 32'd0;
                        state_r <= gradient_r ? ST_PREP : ST_AW;
                    end
                    ST_PREP: begin
                        if (gradient_pixel_valid_w) begin
                            if (argb_r) begin
                                gradient_word_r[
                                    gradient_lane_r*32 +: 32] <=
                                        gradient_argb_w;
                                gradient_strobe_r[
                                    gradient_lane_r*4 +: 4] <= 4'hf;
                            end else begin
                                gradient_word_r[
                                    gradient_lane_r*16 +: 16] <=
                                        gradient_rgb565_w;
                                gradient_strobe_r[
                                    gradient_lane_r*2 +: 2] <= 2'b11;
                            end
                            if (!gradient_vertical_r) begin
                                gradient_a_r <= gradient_a_r + step_a_w;
                                gradient_red_r <= gradient_red_r +
                                                  step_r_w;
                                gradient_green_r <= gradient_green_r +
                                                    step_g_w;
                                gradient_blue_r <= gradient_blue_r +
                                                   step_b_w;
                            end
                        end
                        if (gradient_last_lane_w)
                            state_r <= ST_AW;
                        else
                            gradient_lane_r <= gradient_lane_r + 5'd1;
                    end
                    ST_AW: begin
                        if (aw_fire_w) begin
                            burst_len_r <= prepared_burst_len_r;
                            beat_index_r <= 5'd0;
                            burst_count_r <= burst_count_r + 32'd1;
                            state_r <= ST_W;
                        end
                    end
                    ST_W: begin
                        if (w_fire_w) begin
                            beat_addr_r <= beat_addr_r + 32'd32;
                            beats_remaining_r <= beats_remaining_r - 14'd1;
                            beat_count_r <= beat_count_r + 32'd1;
                            if (m_wlast_o)
                                state_r <= ST_B;
                            else
                                beat_index_r <= beat_index_r + 5'd1;
                        end
                    end
                    ST_B: begin
                        if (b_fire_w) begin
                            if ((m_bid_i != AXI_ID) ||
                                (m_bresp_i != 2'b00)) begin
                                error_r <= 1'b1;
                                done_r <= 1'b1;
                                state_r <= ST_IDLE;
                            end else if (beats_remaining_r == 14'd0) begin
                                if (row_index_r == height_r - 16'd1) begin
                                    done_r <= 1'b1;
                                    state_r <= ST_IDLE;
                                end else begin
                                    row_index_r <= row_index_r + 16'd1;
                                    row_base_r <= row_base_r + stride_r;
                                    if (gradient_vertical_r) begin
                                        gradient_row_a_r <=
                                            gradient_row_a_r + step_a_w;
                                        gradient_row_r_r <=
                                            gradient_row_r_r + step_r_w;
                                        gradient_row_g_r <=
                                            gradient_row_g_r + step_g_w;
                                        gradient_row_b_r <=
                                            gradient_row_b_r + step_b_w;
                                        gradient_a_r <=
                                            gradient_row_a_r + step_a_w;
                                        gradient_red_r <=
                                            gradient_row_r_r + step_r_w;
                                        gradient_green_r <=
                                            gradient_row_g_r + step_g_w;
                                        gradient_blue_r <=
                                            gradient_row_b_r + step_b_w;
                                    end else begin
                                        gradient_a_r <=
                                            {16'd0,color_r[31:24],16'd0};
                                        gradient_red_r <=
                                            {16'd0,color_r[23:16],16'd0};
                                        gradient_green_r <=
                                            {16'd0,color_r[15:8],16'd0};
                                        gradient_blue_r <=
                                            {16'd0,color_r[7:0],16'd0};
                                    end
                                    state_r <= ST_ROW;
                                end
                            end else begin
                                prepared_burst_len_r <= gradient_r ? 5'd1 :
                                                        burst_beats_w;
                                gradient_lane_r <= 5'd0;
                                gradient_word_r <= 256'd0;
                                gradient_strobe_r <= 32'd0;
                                state_r <= gradient_r ? ST_PREP : ST_AW;
                            end
                        end
                    end
                    default: state_r <= ST_IDLE;
                endcase
            end
        end
    end

endmodule
