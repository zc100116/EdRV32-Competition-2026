// File: tb.sv
// Spec: rnd-spec 2.3; T-RND1 approved all-radius/all-row equivalence sweep.
// Description: Compare every 12-bit radius and every row of the maximum 65536-row
//              geometry against the original RTL, with both responses held until compared.
// Clock domain: clk_mem.
module tb_round_equivalence;
    localparam int LANES = 32;
    reg clk = 0;
    always #4 clk = ~clk;
    reg rst_n = 0;
    reg row_valid = 0;
    reg edge_ready = 0;
    reg [11:0] radius_value;
    reg [16:0] first_row_value;
    wire [LANES-1:0] actual_ready;
    wire [LANES-1:0] expected_ready;
    wire [LANES-1:0] actual_valid;
    wire [LANES-1:0] expected_valid;
    wire [15:0] actual_edge [0:LANES-1];
    wire [15:0] expected_edge [0:LANES-1];
    wire [11:0] actual_radius [0:LANES-1];
    wire [11:0] expected_radius [0:LANES-1];
    integer cases = 0;

    genvar lane;
    generate for (lane = 0; lane < LANES; lane = lane + 1) begin : g_lane
        wire [16:0] row_value_w;
        assign row_value_w = first_row_value + 17'(lane);
        edrv32_rnd_round_row u_actual (
            .clk_i(clk),
            .rst_n_i(rst_n),
            .clear_i(1'b0),
            .row_valid_i(row_valid),
            .row_ready_o(actual_ready[lane]),
            .width_i(17'd65536),
            .height_i(17'd65536),
            .row_y_i(row_value_w),
            .radius_i(radius_value),
            .edge_valid_o(actual_valid[lane]),
            .edge_ready_i(edge_ready),
            .edge_q4_o(actual_edge[lane]),
            .radius_o(actual_radius[lane])
        );
        edrv32_rnd_round_row_ref u_expected (
            .clk_i(clk),
            .rst_n_i(rst_n),
            .clear_i(1'b0),
            .row_valid_i(row_valid),
            .row_ready_o(expected_ready[lane]),
            .width_i(17'd65536),
            .height_i(17'd65536),
            .row_y_i(row_value_w),
            .radius_i(radius_value),
            .edge_valid_o(expected_valid[lane]),
            .edge_ready_i(edge_ready),
            .edge_q4_o(expected_edge[lane]),
            .radius_o(expected_radius[lane])
        );
    end endgenerate

    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        for (int r = 0; r < 4096; r++) begin
            for (int first_row = 0; first_row < 65536; first_row += LANES) begin
                while (!(&actual_ready && &expected_ready)) @(negedge clk);
                radius_value = 12'(r);
                first_row_value = 17'(first_row);
                row_valid = 1;
                @(negedge clk);
                row_valid = 0;
                while (!(&actual_valid && &expected_valid)) @(negedge clk);
                for (int i = 0; i < LANES; i++) begin
                    if (actual_edge[i] !== expected_edge[i] ||
                        actual_radius[i] !== expected_radius[i])
                        $fatal(1, "r=%0d y=%0d edge expected=%h actual=%h radius=%0d/%0d",
                            r, first_row+i, expected_edge[i], actual_edge[i],
                            expected_radius[i], actual_radius[i]);
                    cases++;
                end
                edge_ready = 1;
                @(negedge clk);
                edge_ready = 0;
            end
            if ((r & 511) == 511) $display("round equivalence radius=%0d cases=%0d", r, cases);
        end
        $display("PASS round equivalence %0d radius/row pairs", cases);
        $finish;
    end
endmodule
