`timescale 1ns/1ps

module tb_yolo_c16_residual_add;
    reg clk_i = 1'b0;
    reg rst_n_i = 1'b0;
    always #5 clk_i = !clk_i;

    reg in_valid_i = 1'b0;
    wire in_ready_w;
    reg [255:0] in_a_data_i = 256'd0;
    reg [255:0] in_b_data_i = 256'd0;
    reg [7:0] zero_point_i = 8'd0;
    wire out_valid_w;
    reg out_ready_i = 1'b0;
    wire [255:0] out_data_w;

    integer cycle_r = 0;
    integer sent_r = 0;
    integer received_r = 0;
    integer run_r = 0;
    integer max_run_r = 0;
    integer lane;
    reg [7:0] expected_w;

    function [7:0] a_byte;
        input integer beat_i;
        input integer lane_i;
        integer value;
        begin
            value = (beat_i*19 + lane_i*23) % 256 - 128;
            a_byte = value[7:0];
        end
    endfunction

    function [7:0] b_byte;
        input integer beat_i;
        input integer lane_i;
        integer value;
        begin
            value = (beat_i*31 + lane_i*17) % 256 - 128;
            b_byte = value[7:0];
        end
    endfunction

    function [7:0] zero_byte;
        input integer beat_i;
        begin
            case (beat_i % 3)
                0: zero_byte = 8'd0;
                1: zero_byte = 8'hfb;
                default: zero_byte = 8'd7;
            endcase
        end
    endfunction

    function [7:0] golden_byte;
        input integer beat_i;
        input integer lane_i;
        integer sum;
        begin
            sum = $signed(a_byte(beat_i, lane_i)) +
                  $signed(b_byte(beat_i, lane_i)) -
                  $signed(zero_byte(beat_i));
            if (sum > 127)
                golden_byte = 8'h7f;
            else if (sum < -128)
                golden_byte = 8'h80;
            else
                golden_byte = sum[7:0];
        end
    endfunction

    edrv32_yolo_c16_residual_add dut (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .in_valid_i(in_valid_i), .in_ready_o(in_ready_w),
        .in_a_data_i(in_a_data_i), .in_b_data_i(in_b_data_i),
        .zero_point_i(zero_point_i),
        .out_valid_o(out_valid_w), .out_ready_i(out_ready_i),
        .out_data_o(out_data_w)
    );

    always @(negedge clk_i) begin
        if (rst_n_i) begin
            in_valid_i = sent_r < 100;
            out_ready_i = cycle_r < 32 || cycle_r % 7 >= 3;
            zero_point_i = zero_byte(sent_r);
            for (lane = 0; lane < 32; lane = lane + 1) begin
                in_a_data_i[lane*8 +: 8] = a_byte(sent_r, lane);
                in_b_data_i[lane*8 +: 8] = b_byte(sent_r, lane);
            end
        end
    end

    always @(posedge clk_i) begin
        if (rst_n_i) begin
            cycle_r <= cycle_r + 1;
            if (in_valid_i && in_ready_w)
                sent_r <= sent_r + 1;
            if (out_valid_w && out_ready_i) begin
                for (lane = 0; lane < 32; lane = lane + 1) begin
                    expected_w = golden_byte(received_r, lane);
                    if (out_data_w[lane*8 +: 8] !== expected_w)
                        $fatal(1, "Residual mismatch beat=%0d lane=%0d got=%h expected=%h",
                               received_r, lane,
                               out_data_w[lane*8 +: 8], expected_w);
                end
                received_r <= received_r + 1;
                run_r <= run_r + 1;
                if (run_r + 1 > max_run_r)
                    max_run_r <= run_r + 1;
            end else
                run_r <= 0;
        end
    end

    initial begin
        repeat (4) @(negedge clk_i);
        rst_n_i = 1'b1;
        wait (received_r == 100);
        #1;
        if (sent_r != 100 || max_run_r < 20)
            $fatal(1, "Residual throughput sent=%0d received=%0d max_run=%0d",
                   sent_r, received_r, max_run_r);
        $display("PASS YOLO C16 residual add: beats=%0d max_contiguous=%0d",
                 received_r, max_run_r);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Residual add timeout sent=%0d received=%0d",
               sent_r, received_r);
    end
endmodule
