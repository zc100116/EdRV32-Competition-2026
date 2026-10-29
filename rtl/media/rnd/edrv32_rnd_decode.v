// File: edrv32_rnd_decode.v
// Spec: rnd-spec 2.5, 2.6, 6 (error 3).
// Description: Validate only the specified OP/source-format/mode combinations and intersect
//              signed primitives with the inclusive, unsigned clip rectangle.
// Clock domain: combinational.
module edrv32_rnd_decode (
    // Complete 64-byte command.
    input wire [511:0] command_i,
    output wire illegal_o,
    output wire empty_o,
    output wire [7:0] op_o,
    output wire argb_o,
    output wire [3:0] src_fmt_o,
    output wire [15:0] flags_o,
    output wire signed [17:0] left_o,
    output wire signed [17:0] top_o,
    output wire signed [17:0] right_o,
    output wire signed [17:0] bottom_o,
    output wire [16:0] width_o,
    output wire [16:0] height_o,
    output wire fast_fill_o
);
    wire signed [17:0] x0_w;
    wire signed [17:0] y0_w;
    wire signed [17:0] x1_w;
    wire signed [17:0] y1_w;
    wire signed [17:0] expansion_w;
    wire signed [17:0] rect_left_w;
    wire signed [17:0] rect_top_w;
    wire signed [17:0] rect_right_w;
    wire signed [17:0] rect_bottom_w;
    wire signed [17:0] clip_left_w;
    wire signed [17:0] clip_top_w;
    wire signed [17:0] clip_right_w;
    wire signed [17:0] clip_bottom_w;
    wire [17:0] width_w;
    wire [17:0] height_w;
    wire unused_command_w;
    reg allowed_w;

    assign op_o = command_i[7:0];
    assign argb_o = command_i[8];
    assign src_fmt_o = command_i[15:12];
    assign flags_o = command_i[31:16];
    assign x0_w = {{2{command_i[175]}}, command_i[175:160]};
    assign y0_w = {{2{command_i[191]}}, command_i[191:176]};
    assign x1_w = {{2{command_i[207]}}, command_i[207:192]};
    assign y1_w = {{2{command_i[223]}}, command_i[223:208]};
    assign expansion_w = op_o == 8'h06 ? $signed({13'd0, command_i[292:288]}) : 18'sd0;
    assign rect_left_w = x0_w - expansion_w;
    assign rect_top_w = y0_w - expansion_w;
    assign rect_right_w = x1_w + expansion_w;
    assign rect_bottom_w = y1_w + expansion_w;
    assign clip_left_w = $signed({6'd0, command_i[107:96]});
    assign clip_top_w = $signed({6'd0, command_i[123:112]});
    assign clip_right_w = $signed({6'd0, command_i[139:128]});
    assign clip_bottom_w = $signed({6'd0, command_i[155:144]});
    assign left_o = rect_left_w > clip_left_w ? rect_left_w : clip_left_w;
    assign top_o = rect_top_w > clip_top_w ? rect_top_w : clip_top_w;
    assign right_o = rect_right_w < clip_right_w ? rect_right_w : clip_right_w;
    assign bottom_o = rect_bottom_w < clip_bottom_w ? rect_bottom_w : clip_bottom_w;
    assign empty_o = x1_w < x0_w || y1_w < y0_w || right_o < left_o || bottom_o < top_o;
    assign width_w = x1_w - x0_w + 18'd1;
    assign height_w = y1_w - y0_w + 18'd1;
    assign width_o = width_w[16:0];
    assign height_o = height_w[16:0];
    assign fast_fill_o = op_o == 8'h01 && !flags_o[0] &&
        command_i[267:256] == 0 && command_i[255:248] == 8'd255;
    assign illegal_o = !allowed_w;
    assign unused_command_w = ^{command_i[511:293], command_i[287:268],
        command_i[247:224], command_i[159:156], command_i[143:140],
        command_i[127:124], command_i[111:108], command_i[95:32], command_i[11:9],
        width_w[17], height_w[17]};
    always @(*) begin
        allowed_w = 1'b0;
        case (op_o)
            8'h01, 8'h02, 8'h06, 8'h07: allowed_w = 1'b1;
            8'h03: allowed_w = src_fmt_o >= 4'd2 && src_fmt_o <= 4'd5;
            8'h04: allowed_w = (src_fmt_o <= 4'd1 ||
                (src_fmt_o >= 4'd6 && src_fmt_o <= 4'd9)) && flags_o[6:4] < 3'd4;
            8'h05: allowed_w = src_fmt_o == {3'd0, argb_o};
            8'h08: allowed_w = src_fmt_o <= 4'd1 || src_fmt_o == 4'd6 || src_fmt_o == 4'd7;
            default: allowed_w = 1'b0;
        endcase
    end
endmodule
