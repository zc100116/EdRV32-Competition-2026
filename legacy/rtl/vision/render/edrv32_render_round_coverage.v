// ============================================================================
// File        : edrv32_render_round_coverage.v
// Description : Two-pixel Q4 rounded-rectangle fill/border coverage.
// ============================================================================

module edrv32_render_round_coverage (
    input  wire [15:0] x_i,
    input  wire [15:0] width_i,
    input  wire [15:0] outer_edge_q4_i,
    input  wire [15:0] inner_edge_q4_i,
    input  wire        inner_active_i,
    output wire [15:0] outer_coverage_o,
    output wire [15:0] inner_coverage_o
);

    function [7:0] coverage;
        input [15:0] x;
        input [15:0] width;
        input [15:0] edge_q4;
        // Q4 coordinates need 22 signed bits even when x is outside the
        // rectangle. Wider arithmetic only lengthens the carry paths.
        reg signed [21:0] left_room;
        reg signed [21:0] right_room;
        reg signed [21:0] room;
        begin
            left_room = $signed({2'd0,x,4'd0}) + 22'sd16 -
                        $signed({6'd0,edge_q4});
            right_room = $signed({2'd0,width,4'd0}) -
                         $signed({6'd0,edge_q4}) -
                         $signed({2'd0,x,4'd0});
            room = left_room < right_room ? left_room : right_room;
            if (room <= 0)
                coverage = 8'd0;
            else if (room >= 16)
                coverage = 8'd255;
            else
                coverage = room[7:0] << 4;
        end
    endfunction

    assign outer_coverage_o = {
        coverage(x_i + 16'd1, width_i, outer_edge_q4_i),
        coverage(x_i, width_i, outer_edge_q4_i)};
    assign inner_coverage_o = inner_active_i ? {
        coverage(x_i + 16'd1, width_i, inner_edge_q4_i),
        coverage(x_i, width_i, inner_edge_q4_i)} : 16'b0;

endmodule
