// File: tb.sv
// Spec: gpu-v2-spec 2.4; VT04.
// Description: Independent integer-reference FP32 scalar scoreboard.
// Clock domain: clk_gpu.
module tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg mul;
    reg [31:0] a;
    reg [31:0] b;
    reg [31:0] c;
    wire [31:0] result;
    wire [31:0] product;
    edrv32_gpu2_fp32_scalar u_dut (
        .clk_i(clk),
        .mul_i(mul),
        .a_i(a),
        .b_i(b),
        .c_i(c),
        .product_o(product),
        .result_o(result)
    );
    wire [31:0] add_result;
    wire [31:0] unused_rounded;
    edrv32_gpu2_fp32_add u_add (
        .clk_i(clk),
        .a_i(a),
        .b_i(b),
        .rounded_o(unused_rounded),
        .result_o(add_result)
    );
    reg [31:0] product_expected [0:9];
    reg [31:0] add_expected [0:9];
    reg [31:0] next_product;
    reg [31:0] next_add;
    integer stream;
    integer count;
    integer scan;
    integer sent = 0;
    integer checked = 0;
    integer idx;
    reg [31:0] expected [0:9];
    reg [9:0] valid = 0;
    reg [31:0] next_expected;
    string vector_path;
    initial begin
        if (!$value$plusargs("VECTORS=%s", vector_path)) $fatal(1, "missing VECTORS");
        stream = $fopen(vector_path, "r");
        if (stream == 0) $fatal(1, "cannot open vectors");
        scan = $fscanf(stream, "%d\n", count);
        for (idx = 0; idx < count + 10; idx = idx + 1) begin
            @(negedge clk);
            if (idx < count) begin
                scan = $fscanf(stream, "%h %h %h %h %h %h %h\n",
                                mul, a, b, c, next_expected, next_product, next_add);
                if (scan != 7) $fatal(1, "bad vector %0d", idx);
                sent = sent + 1;
            end
            @(posedge clk);
            valid = {valid[8:0], idx < count};
            for (int j = 9; j > 0; j--) begin
                expected[j] = expected[j-1];
                product_expected[j] = product_expected[j-1];
                add_expected[j] = add_expected[j-1];
            end
            product_expected[0] = next_product;
            add_expected[0] = next_add;
            expected[0] = next_expected;
            #1;
            if (valid[6] && product !== product_expected[6])
                $fatal(1, "product vector %0d expected %h got %h", idx-6,
                       product_expected[6], product);
            if (valid[2] && add_result !== add_expected[2])
                $fatal(1, "add vector %0d expected %h got %h", idx-2,
                       add_expected[2], add_result);
            if (valid[9]) begin
                if (result !== expected[9])
                    $fatal(1, "vector %0d expected %h got %h time %t",
                           checked, expected[9], result, $time);
                checked = checked + 1;
            end
        end
        if (checked != sent) $fatal(1, "checked %0d sent %0d", checked, sent);
        $display("PASS scalar FP32 %0d ten-edge results", checked);
        $finish;
    end
endmodule
