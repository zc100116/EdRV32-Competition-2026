// File: tb_scale.sv
// Spec: gpu-v2-spec 2.4; M-6 final binary scaling, gradual underflow and packing.
// Description: Two-edge scale results checked against exact integer binary powers.
// Clock domain: clk_gpu.
module tb_scale;
    reg clk = 0;
    always #5 clk = ~clk;
    reg [31:0] data;
    reg signed [9:0] scale;
    reg sign;
    reg special;
    reg [31:0] special_data;
    wire [31:0] result;
    edrv32_gpu2_sfu_scale u_dut (
        .clk_i(clk),
        .data_i(data),
        .scale_i(scale),
        .sign_i(sign),
        .special_i(special),
        .special_data_i(special_data),
        .data_o(result)
    );
    reg [31:0] expected [0:1];
    reg [31:0] next_expected;
    reg [1:0] valid = 0;
    integer count;
    integer stream;
    integer scan;
    integer idx;
    string path;
    initial begin
        if (!$value$plusargs("VECTORS=%s", path)) $fatal(1, "missing VECTORS");
        stream = $fopen(path, "r");
        if (stream == 0) $fatal(1, "cannot open vectors");
        scan = $fscanf(stream, "%d\n", count);
        for (idx = 0; idx < count+2; idx++) begin
            @(negedge clk);
            if (idx < count) begin
                scan = $fscanf(stream, "%h %h %h %h %h %h\n", data, scale, sign,
                               special, special_data, next_expected);
                if (scan != 6) $fatal(1, "bad scale vector %0d", idx);
            end
            @(posedge clk);
            valid = {valid[0], idx < count};
            expected[1] = expected[0];
            expected[0] = next_expected;
            #1;
            if (valid[1] && result !== expected[1])
                $fatal(1, "scale %0d expected %h got %h", idx-1, expected[1], result);
        end
        $display("PASS SFU two-edge scale %0d exact integer vectors", count);
        $finish;
    end
endmodule
