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
        reg signed [17:0] left_limit;
        reg signed [17:0] right_limit;
        reg signed [17:0] next_x;
        reg [3:0] fractional;
        begin
            // room = 16*min(x+1,width-x)-edge. Only the two boundary pixels are partial.
            left_limit = $signed({6'd0, local_edge_q4_i[15:4]});
            right_limit = $signed({1'b0, local_width_i}) - left_limit;
            next_x = local_x_i + 18'sd1;
            fractional = 4'd0 - local_edge_q4_i[3:0];
            if (local_x_i < left_limit || local_x_i >= right_limit)
                coverage = 8'd0;
            else if (local_edge_q4_i[3:0] != 0 &&
                (local_x_i == left_limit || next_x == right_limit))
                coverage = {fractional, 4'd0};
            else
                coverage = 8'd255;
        end
    endfunction
    assign coverage_o = row_inside_i ? {
        coverage(x_i + 18'sd1, width_i, edge_q4_i),
        coverage(x_i, width_i, edge_q4_i)} : 16'd0;
endmodule
