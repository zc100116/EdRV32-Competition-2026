`timescale 1ns/1ps

module tb_yolo_result_quant_lut;
    reg clk_i = 1'b0;
    always #5 clk_i = !clk_i;

    reg rst_n_i = 1'b0;
    reg in_valid_i = 1'b0;
    wire in_ready_o;
    reg in_last_i = 1'b0;
    reg [11:0] in_pair_i = 12'd0;
    reg [2047:0] in_accum_i = 2048'd0;
    wire out_valid_o;
    wire out_last_o;
    wire [11:0] out_pair_o;
    wire [511:0] out_data_o;
    reg cfg_valid_i = 1'b0;
    wire cfg_ready_o;
    reg [4:0] cfg_channel_i = 5'd0;
    reg lut_cfg_valid_i = 1'b0;
    wire lut_cfg_ready_o;
    reg [7:0] lut_cfg_addr_i = 8'd0;
    reg [7:0] lut_cfg_data_i = 8'd0;
    integer idx;
    integer lane;
    integer received_r = 0;
    integer raw_value;
    reg [7:0] expected_byte;

    edrv32_yolo_result_quant dut (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .in_valid_i(in_valid_i), .in_ready_o(in_ready_o),
        .in_last_i(in_last_i), .in_pair_i(in_pair_i),
        .in_accum_i(in_accum_i),
        .out_valid_o(out_valid_o), .out_ready_i(1'b1),
        .out_last_o(out_last_o), .out_pair_o(out_pair_o),
        .out_data_o(out_data_o),
        .cfg_valid_i(cfg_valid_i), .cfg_ready_o(cfg_ready_o),
        .cfg_channel_i(cfg_channel_i), .cfg_bias_i(32'd0),
        .cfg_multiplier_i(16'd1), .cfg_shift_i(6'd0),
        .cfg_zero_point_i(8'd0),
        .lut_enable_i(1'b1), .lut_cfg_valid_i(lut_cfg_valid_i),
        .lut_cfg_ready_o(lut_cfg_ready_o),
        .lut_cfg_addr_i(lut_cfg_addr_i),
        .lut_cfg_data_i(lut_cfg_data_i)
    );

    always @(posedge clk_i) begin
        if (rst_n_i && out_valid_o) begin
            if (received_r >= 4 || out_pair_o !== received_r[11:0] ||
                out_last_o !== (received_r == 3))
                $fatal(1, "LUT output framing mismatch at pair %0d",
                       received_r);
            for (integer b = 0; b < 64; b = b + 1) begin
                expected_byte = (received_r*64 + b) ^ 8'h5a;
                if (out_data_o[b*8 +: 8] !== expected_byte)
                    $fatal(1, "LUT byte mismatch pair=%0d byte=%0d got=%h expected=%h",
                           received_r, b, out_data_o[b*8 +: 8],
                           expected_byte);
            end
            received_r <= received_r + 1;
        end
    end

    initial begin
        repeat (5) @(negedge clk_i);
        rst_n_i = 1'b1;
        for (idx = 0; idx < 32; idx = idx + 1) begin
            @(negedge clk_i);
            if (!cfg_ready_o)
                $fatal(1, "LUT test quant configuration not ready");
            cfg_valid_i = 1'b1;
            cfg_channel_i = idx[4:0];
        end
        @(negedge clk_i);
        cfg_valid_i = 1'b0;
        for (idx = 0; idx < 256; idx = idx + 1) begin
            @(negedge clk_i);
            if (!lut_cfg_ready_o)
                $fatal(1, "LUT configuration not ready at %0d", idx);
            lut_cfg_valid_i = 1'b1;
            lut_cfg_addr_i = idx[7:0];
            lut_cfg_data_i = idx[7:0] ^ 8'h5a;
        end
        @(negedge clk_i);
        lut_cfg_valid_i = 1'b0;
        for (idx = 0; idx < 4; idx = idx + 1) begin
            in_valid_i = 1'b1;
            in_last_i = idx == 3;
            in_pair_i = idx[11:0];
            for (lane = 0; lane < 64; lane = lane + 1) begin
                raw_value = idx*64 + lane;
                if (raw_value >= 128)
                    raw_value = raw_value - 256;
                in_accum_i[lane*32 +: 32] = raw_value;
            end
            do @(posedge clk_i); while (!in_ready_o);
            @(negedge clk_i);
        end
        in_valid_i = 1'b0;
        wait (received_r == 4);
        repeat (3) @(negedge clk_i);
        if (!cfg_ready_o || !lut_cfg_ready_o)
            $fatal(1, "Quantizer did not return to quiescent state");
        $display("PASS YOLO activation LUT: 256-byte map across four pairs");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "LUT test timeout");
    end
endmodule
