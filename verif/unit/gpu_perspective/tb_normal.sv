// File: tb_normal.sv
// Spec: gpu-spec 2.13.8; microarch 4.13.
// Description: Model scoreboard for each normalization width and enable stalls.
// Clock domain: clk_gpu.
module tb_normal;
    reg clk_i = 0;
    always #5 clk_i = !clk_i;
    reg en_i = 0;
    reg [76:0] inputs_r [0:8191];
    reg [86:0] expected_r [0:8191];
    reg [76:0] source_r = 0;
    wire [86:0] actual_w;
    reg [2:0] valid_r = 0;
    integer count_r;
    integer stall_r;
    integer sent_r = 0;
    integer received_r = 0;
    integer cycle_r = 0;
    reg [4095:0] input_path_r;
    reg [4095:0] expected_path_r;
    edrv32_gpu_perspective_normal #(.WIDTH(23)) u_difference (
        .clk_i(clk_i), .en_i(en_i), .magnitude_i(source_r[22:0]),
        .sign_i(source_r[66]), .exponent_i(source_r[76:67]),
        .normal_o(actual_w[28:0])
    );
    edrv32_gpu_perspective_normal #(.WIDTH(36)) u_product (
        .clk_i(clk_i), .en_i(en_i), .magnitude_i(source_r[35:0]),
        .sign_i(source_r[66]), .exponent_i(source_r[76:67]),
        .normal_o(actual_w[57:29])
    );
    edrv32_gpu_perspective_normal #(.WIDTH(66)) u_plane (
        .clk_i(clk_i), .en_i(en_i), .magnitude_i(source_r[65:0]),
        .sign_i(source_r[66]), .exponent_i(source_r[76:67]),
        .normal_o(actual_w[86:58])
    );
    initial begin
        if (!$value$plusargs("INPUT=%s", input_path_r)) $fatal(1, "INPUT missing");
        if (!$value$plusargs("EXPECTED=%s", expected_path_r)) $fatal(1, "EXPECTED missing");
        if (!$value$plusargs("COUNT=%d", count_r)) $fatal(1, "COUNT missing");
        if (!$value$plusargs("STALL=%d", stall_r)) $fatal(1, "STALL missing");
        $readmemh(input_path_r, inputs_r, 0, count_r-1);
        $readmemh(expected_path_r, expected_r, 0, count_r-1);
    end
    always @(negedge clk_i) begin
        cycle_r = cycle_r + 1;
        en_i = !stall_r || cycle_r % 7 < 4;
        if (sent_r < count_r) source_r = inputs_r[sent_r];
    end
    always @(posedge clk_i) begin
        if (en_i) begin
            if (valid_r[2]) begin
                if (actual_w !== expected_r[received_r])
                    $fatal(1, "normal index=%0d got=%h expected=%h",
                        received_r, actual_w, expected_r[received_r]);
                received_r = received_r + 1;
                if (received_r == count_r) begin
                    $display("PASS normal widths=23/36/66 count=%0d stalls=%0d",
                        count_r, stall_r);
                    $finish;
                end
            end
            valid_r <= {valid_r[1:0], sent_r < count_r};
            if (sent_r < count_r) sent_r = sent_r + 1;
        end
    end
endmodule
