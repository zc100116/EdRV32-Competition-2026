// File: edrv32_rnd_coverage.v
// Spec: rnd-spec 2.3.
// Description: Evaluate two adjacent signed local coordinates against a rounded row edge.
//              A separate row-inside input implements the required rectangle-exterior zero.
// Clock domain: combinational.
module edrv32_rnd_coverage (
    // Geometry and computed row edge.
    input wire signed [17:0] x_i,
    input wire [16:0] width_i,
    input wire [15:0] edge_q4_i,
    input wire row_inside_i,
    output wire [15:0] coverage_o
);
    function automatic [7:0] coverage;
        input signed [17:0] local_x_i;
        input [16:0] local_width_i;
        input [15:0] local_edge_q4_i;
        reg signed [22:0] left_room;
        reg signed [22:0] right_room;
        reg signed [22:0] room;
        begin
            left_room = ($signed({{5{local_x_i[17]}}, local_x_i}) << 4) + 23'sd16 -
                $signed({7'd0, local_edge_q4_i});
            right_room = $signed({2'd0, local_width_i, 4'd0}) -
                $signed({7'd0, local_edge_q4_i}) - ($signed({{5{local_x_i[17]}}, local_x_i}) << 4);
            room = left_room < right_room ? left_room : right_room;
            if (local_x_i < 0 || local_x_i >= $signed({1'd0, local_width_i}) || room <= 0)
                coverage = 8'd0;
            else if (room >= 16)
                coverage = 8'd255;
            else
                coverage = {room[3:0], 4'd0};
        end
    endfunction
    assign coverage_o = row_inside_i ? {
        coverage(x_i + 18'sd1, width_i, edge_q4_i),
        coverage(x_i, width_i, edge_q4_i)} : 16'd0;
endmodule
