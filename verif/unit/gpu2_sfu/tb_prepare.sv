// File: tb_prepare.sv
// Spec: gpu-v2-spec 2.4; VT06 M5/M6 scalar front-end fields.
// Description: Public numerical fields and table indices compared with independent vectors.
// Clock domain: clk_gpu.
module tb_prepare;
    reg clk = 0;
    always #5 clk = ~clk;
    reg [1:0] op;
    reg [31:0] x;
    wire [5:0] index;
    wire [31:0] field0;
    wire [31:0] field3;
    wire signed [9:0] scale;
    wire sign;
    wire exp_fma;
    wire special;
    wire [31:0] special_data;
    edrv32_gpu2_sfu_prepare u_dut (
        .clk_i(clk),
        .op_i(op),
        .x_i(x),
        .index_o(index),
        .field0_o(field0),
        .field3_o(field3),
        .scale_o(scale),
        .sign_o(sign),
        .exp_fma_o(exp_fma),
        .special_o(special),
        .special_data_o(special_data)
    );
    reg [31:0] expected0 [0:2];
    reg [31:0] expected3 [0:2];
    reg [9:0] expected_scale [0:2];
    reg [31:0] expected_special_data [0:2];
    reg [4:0] expected_ctrl [0:2];
    reg [31:0] next0;
    reg [31:0] next3;
    reg [9:0] next_scale;
    reg [31:0] next_special_data;
    reg [4:0] next_ctrl;
    reg [5:0] next_index;
    reg [2:0] valid = 0;
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
        for (idx = 0; idx < count+3; idx++) begin
            @(negedge clk);
            if (idx < count) begin
                scan = $fscanf(stream, "%h %h %h %h %h %h %h %h\n", op, x,
                               next_index, next0, next3, next_scale, next_ctrl,
                               next_special_data);
                if (scan != 8) $fatal(1, "bad prepare vector %0d", idx);
                #1;
                if (!next_ctrl[0] && index !== next_index)
                    $fatal(1, "index input %h op %d expected %d got %d", x, op,
                           next_index, index);
            end
            @(posedge clk);
            valid = {valid[1:0], idx < count};
            for (int j = 2; j > 0; j--) begin
                expected0[j] = expected0[j-1];
                expected3[j] = expected3[j-1];
                expected_scale[j] = expected_scale[j-1];
                expected_special_data[j] = expected_special_data[j-1];
                expected_ctrl[j] = expected_ctrl[j-1];
            end
            expected0[0] = next0;
            expected3[0] = next3;
            expected_scale[0] = next_scale;
            expected_special_data[0] = next_special_data;
            expected_ctrl[0] = next_ctrl;
            #1;
            if (valid[2]) begin
                if (special !== expected_ctrl[2][0]) $fatal(1, "special mismatch %0d", idx-2);
                if (special) begin
                    if (special_data !== expected_special_data[2])
                        $fatal(1, "special result mismatch %0d", idx-2);
                end else begin
                    if ((!expected_ctrl[2][4] && field0 !== expected0[2])
                            || (!expected_ctrl[2][3] && field3 !== expected3[2])
                            || scale !== expected_scale[2]
                            || sign !== expected_ctrl[2][1] || exp_fma !== expected_ctrl[2][2])
                        $fatal(1, "prepare %0d f0 %h/%h f3 %h/%h scale %h/%h ctrl %b/%b",
                               idx-2, field0, expected0[2], field3, expected3[2], scale,
                               expected_scale[2], {exp_fma, sign}, expected_ctrl[2][2:1]);
                end
            end
        end
        $display("PASS SFU three-edge front end %0d M5/M6 inputs", count);
        $finish;
    end
endmodule
