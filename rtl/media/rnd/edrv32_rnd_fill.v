// File: edrv32_rnd_fill.v
// Spec: rnd-spec 2.6 FILL, 5.2.
// Description: Opaque solid-color fast path, with one streaming write descriptor per row.
//              Source color replication is constant throughout the command; no target reads.
// Clock domain: clk_mem (clk_i).
module edrv32_rnd_fill (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Clipped opaque non-gradient FILL.
    input wire start_i,
    input wire cancel_i,
    input wire [511:0] command_i,
    output wire done_o,
    output wire [4:0] pixel_count_o,

    // Row descriptor and one-beat-per-cycle data stream.
    output wire wr_valid_o,
    input wire wr_ready_i,
    output wire [31:0] wr_addr_o,
    output wire [15:0] wr_bytes_o,
    output wire wr_data_valid_o,
    input wire wr_data_ready_i,
    output wire [255:0] wr_data_o,
    output reg [31:0] wr_strb_o,
    input wire wr_done_i
);
    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_DESC = 3'd1;
    localparam [2:0] S_DATA = 3'd2;
    localparam [2:0] S_RESPONSE = 3'd3;
    localparam [2:0] S_DONE = 3'd4;
    reg [2:0] state_r;
    reg [11:0] y_r;
    reg [9:0] beat_r;
    wire [31:0] dst_addr_w;
    wire [17:0] row_bytes_w;
    wire [17:0] span_bytes_w;
    wire [17:0] rounded_bytes_w;
    wire [9:0] beats_w;
    wire [31:0] beat_byte_w;
    wire argb_w;
    wire [15:0] color565_w;
    wire signed [17:0] left_w;
    wire signed [17:0] top_w;
    wire signed [17:0] right_w;
    wire signed [17:0] bottom_w;
    wire [16:0] unused_width_w;
    wire [16:0] unused_height_w;
    wire [7:0] unused_op_w;
    wire [3:0] unused_format_w;
    wire [15:0] unused_flags_w;
    wire unused_illegal_w;
    wire unused_empty_w;
    wire unused_fast_w;
    wire unused_geometry_w;
    reg [5:0] enabled_bytes_w;
    integer byte_index;
    edrv32_rnd_decode u_decode (
        .command_i(command_i),
        .illegal_o(unused_illegal_w),
        .empty_o(unused_empty_w),
        .op_o(unused_op_w),
        .argb_o(argb_w),
        .src_fmt_o(unused_format_w),
        .flags_o(unused_flags_w),
        .left_o(left_w),
        .top_o(top_w),
        .right_o(right_w),
        .bottom_o(bottom_w),
        .width_o(unused_width_w),
        .height_o(unused_height_w),
        .fast_fill_o(unused_fast_w)
    );
    assign dst_addr_w = command_i[63:32] + {20'd0, y_r} *
        {16'd0, command_i[79:64]} + ({20'd0, left_w[11:0]} << (argb_w ? 2 : 1));
    assign row_bytes_w = (right_w - left_w + 18'd1) << (argb_w ? 2 : 1);
    assign span_bytes_w = row_bytes_w + {13'd0, dst_addr_w[4:0]};
    assign rounded_bytes_w = span_bytes_w + 18'd31;
    assign beats_w = rounded_bytes_w[14:5];
    assign beat_byte_w = {17'd0, beat_r, 5'd0};
    assign color565_w = {command_i[247:243], command_i[239:234], command_i[231:227]};
    assign wr_data_o = argb_w ? {8{{8'hff, command_i[247:224]}}} : {16{color565_w}};
    assign wr_addr_o = {dst_addr_w[31:5], 5'd0};
    assign wr_bytes_o = span_bytes_w[15:0];
    assign wr_valid_o = state_r == S_DESC && !cancel_i;
    assign wr_data_valid_o = state_r == S_DATA && !cancel_i;
    assign pixel_count_o = wr_data_valid_o && wr_data_ready_i ?
        (argb_w ? {1'd0, enabled_bytes_w[5:2]} : enabled_bytes_w[5:1]) : 5'd0;
    assign done_o = state_r == S_DONE;
    assign unused_geometry_w = ^{left_w[17:12], top_w[17:12], right_w[17:12],
        bottom_w[17:12], rounded_bytes_w[17:15], rounded_bytes_w[4:0], span_bytes_w[17:16]};
    always @(*) begin
        wr_strb_o = 32'd0;
        enabled_bytes_w = 6'd0;
        for (byte_index = 0; byte_index < 32; byte_index = byte_index + 1) begin
            if (beat_byte_w + byte_index >= {27'd0, dst_addr_w[4:0]} &&
                beat_byte_w + byte_index < {14'd0, span_bytes_w}) begin
                wr_strb_o[byte_index] = 1'b1;
                enabled_bytes_w = enabled_bytes_w + 6'd1;
            end
        end
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            y_r <= 12'd0;
            beat_r <= 10'd0;
        end else if (cancel_i)
            state_r <= S_IDLE;
        else begin
            case (state_r)
                S_IDLE: if (start_i) begin
                    y_r <= top_w[11:0];
                    state_r <= S_DESC;
                end
                S_DESC: if (wr_ready_i) begin
                    beat_r <= 10'd0;
                    state_r <= S_DATA;
                end
                S_DATA: if (wr_data_ready_i) begin
                    beat_r <= beat_r + 10'd1;
                    if (beat_r + 10'd1 == beats_w)
                        state_r <= S_RESPONSE;
                end
                S_RESPONSE: if (wr_done_i) begin
                    if (y_r == bottom_w[11:0])
                        state_r <= S_DONE;
                    else begin
                        y_r <= y_r + 12'd1;
                        state_r <= S_DESC;
                    end
                end
                S_DONE: state_r <= S_IDLE;
                default: state_r <= state_r;
            endcase
        end
    end
endmodule
