// File: mul_ip_check.sv
// Spec: cpu-spec 4.8.
// Description: Check two enabled stages, signed extremes and clock-enable hold.
// Clock domain: clk_sys (test clock).
module mul_ip_check;
    GTP_GRS GRS_INST (.GRS_N(1'b1));
    reg clk = 0;
    always #5 clk = ~clk;
    reg ce = 0;
    reg signed [32:0] a = 0;
    reg signed [32:0] b = 0;
    wire [65:0] p;
    reg signed [65:0] stage;
    reg signed [65:0] expected;
    integer enabled = 0;
    integer checks = 0;
    bit test_passed = 0;
    integer i;
    edrv32_mul_s33x33 dut (
        .clk_i(clk),
        .enable_i(ce),
        .operand_a_i(a),
        .operand_b_i(b),
        .product_o(p)
    );
    always @(posedge clk) begin
        if (ce) begin
            expected = stage;
            stage = a * b;
            enabled = enabled + 1;
        end
        #1;
        if (enabled >= 2) begin
            if (p !== expected) begin
                $fatal(1, "FAIL multiplier ce=%b expected=%h actual=%h time=%0t",
                    ce, expected, p, $time);
            end
            checks = checks + 1;
        end
    end
    initial begin
        for (i=0; i<24; i=i+1) begin
            @(negedge clk);
            ce = (i % 4 != 2);
            case (i % 6)
                0: begin a = 33'sd3; b = -33'sd7; end
                1: begin a = -33'sd4294967296; b = -33'sd4294967296; end
                2: begin a = 33'sd4294967295; b = -33'sd1; end
                3: begin a = -33'sd123456; b = 33'sd987654; end
                4: begin a = 0; b = 33'sd4294967295; end
                5: begin a = 33'sd4294967295; b = 33'sd4294967295; end
            endcase
        end
        @(negedge clk);
        test_passed = 1;
        $display("PASS multiplier checks=%0d", checks);
        $finish;
    end
endmodule
