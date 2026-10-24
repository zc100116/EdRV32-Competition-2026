`timescale 1ns/1ps

module tb_yolo_mac_array;
    reg clk_i = 1'b0;
    always #5 clk_i = !clk_i;

    reg rst_n_i = 1'b0;
    reg in_valid_i = 1'b0;
    wire in_ready_o;
    reg in_first_i = 1'b0;
    reg in_last_i = 1'b0;
    reg [127:0] in_activation_i = 128'b0;
    reg [2047:0] in_weight_i = 2048'b0;
    wire out_valid_o;
    reg out_ready_i = 1'b0;
    wire out_last_o;
    wire [2047:0] out_accum_o;

    reg [2047:0] expected_r [0:127];
    reg expected_last_r [0:127];
    integer ref_acc_r [0:63];
    integer produced_r = 0;
    integer consumed_r = 0;
    integer cycle_r = 0;
    integer p;
    integer oc;
    integer k;
    integer term;
    integer value;
    reg signed [7:0] act;
    reg signed [7:0] weight;

    edrv32_yolo_mac_array dut (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .in_valid_i(in_valid_i), .in_ready_o(in_ready_o),
        .in_first_i(in_first_i), .in_last_i(in_last_i),
        .in_activation_i(in_activation_i), .in_weight_i(in_weight_i),
        .out_valid_o(out_valid_o), .out_ready_i(out_ready_i),
        .out_last_o(out_last_o), .out_accum_o(out_accum_o)
    );

    initial begin
        repeat (5) @(negedge clk_i);
        rst_n_i = 1'b1;
    end

    always @(negedge clk_i) begin
        if (rst_n_i) begin
            cycle_r = cycle_r + 1;
            out_ready_i = (cycle_r % 11 < 6);
            in_valid_i = produced_r < 80 && (cycle_r % 7 != 3);
            in_first_i = (produced_r % 5 == 0);
            in_last_i = (produced_r % 5 == 4);
            for (p = 0; p < 2; p = p + 1)
                for (k = 0; k < 8; k = k + 1) begin
                    if (produced_r == 0)
                        value = p == 0 ? -128 : 127;
                    else
                        value = ((produced_r*31 + p*57 + k*19) % 256) - 128;
                    in_activation_i[(p*8+k)*8 +: 8] = value[7:0];
                end
            for (oc = 0; oc < 32; oc = oc + 1)
                for (k = 0; k < 8; k = k + 1) begin
                    if (produced_r == 0)
                        value = k[0] ? 127 : -128;
                    else
                        value = ((produced_r*13 + oc*41 + k*23) % 256) - 128;
                    in_weight_i[(oc*8+k)*8 +: 8] = value[7:0];
                end
        end
    end

    always @(posedge clk_i) begin
        if (rst_n_i) begin
            if (out_valid_o && out_ready_i) begin
                if (consumed_r >= produced_r ||
                    out_accum_o !== expected_r[consumed_r] ||
                    out_last_o !== expected_last_r[consumed_r]) begin
                    $display("FAIL output beat=%0d cycle=%0d expected=%h actual=%h last=%b/%b",
                             consumed_r, cycle_r, expected_r[consumed_r],
                             out_accum_o, expected_last_r[consumed_r], out_last_o);
                    $fatal(1);
                end
                consumed_r = consumed_r + 1;
            end

            if (in_valid_i && in_ready_o) begin
                for (p = 0; p < 2; p = p + 1)
                    for (oc = 0; oc < 32; oc = oc + 1) begin
                        term = 0;
                        for (k = 0; k < 8; k = k + 1) begin
                            act = in_activation_i[(p*8+k)*8 +: 8];
                            weight = in_weight_i[(oc*8+k)*8 +: 8];
                            term = term + act * weight;
                        end
                        if (in_first_i)
                            ref_acc_r[p*32+oc] = term;
                        else
                            ref_acc_r[p*32+oc] = ref_acc_r[p*32+oc] + term;
                        expected_r[produced_r][(p*32+oc)*32 +: 32] =
                            ref_acc_r[p*32+oc];
                    end
                expected_last_r[produced_r] = in_last_i;
                produced_r = produced_r + 1;
            end

            if (consumed_r == 80) begin
                $display("PASS YOLO MAC array: 80 beats, 512 signed products/beat, bubbles and backpressure");
                $finish;
            end
            if (cycle_r > 1000)
                $fatal(1, "Timeout produced=%0d consumed=%0d", produced_r, consumed_r);
        end
    end
endmodule
