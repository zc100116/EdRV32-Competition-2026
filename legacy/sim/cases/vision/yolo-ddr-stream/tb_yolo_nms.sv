`timescale 1ns/1ps

module tb_yolo_nms;
    reg clk_i = 1'b0;
    reg rst_n_i = 1'b0;
    always #3.333 clk_i = !clk_i;
    reg start_i = 1'b0;
    reg in_valid_i = 1'b0;
    reg finish_i = 1'b0;
    reg [6:0] in_class_i = 7'd0;
    reg [15:0] in_score_i = 16'd0;
    reg [31:0] in_x1_i = 32'd0, in_y1_i = 32'd0;
    reg [31:0] in_x2_i = 32'd0, in_y2_i = 32'd0;
    reg [1:0] in_scale_i = 2'd0;
    reg [12:0] in_anchor_i = 13'd0;
    wire start_ready_w, in_ready_w, out_valid_w;
    wire [6:0] out_class_w, out_index_w, output_count_w;
    wire [15:0] out_score_w;
    wire [31:0] out_x1_w, out_y1_w, out_x2_w, out_y2_w;
    wire [1:0] out_scale_w;
    wire [12:0] out_anchor_w;
    wire [9:0] candidate_count_w;
    wire busy_w, done_w, error_w;
    integer emitted_r = 0;
    reg [6:0] classes_r [0:2];
    reg [15:0] scores_r [0:2];

    edrv32_yolo_nms dut (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(start_i), .start_ready_o(start_ready_w),
        .in_valid_i(in_valid_i), .in_ready_o(in_ready_w),
        .in_class_i(in_class_i), .in_score_i(in_score_i),
        .in_x1_i(in_x1_i), .in_y1_i(in_y1_i),
        .in_x2_i(in_x2_i), .in_y2_i(in_y2_i),
        .in_scale_i(in_scale_i), .in_anchor_i(in_anchor_i),
        .finish_i(finish_i),
        .out_valid_o(out_valid_w), .out_ready_i(1'b1),
        .out_class_o(out_class_w), .out_score_o(out_score_w),
        .out_x1_o(out_x1_w), .out_y1_o(out_y1_w),
        .out_x2_o(out_x2_w), .out_y2_o(out_y2_w),
        .out_scale_o(out_scale_w), .out_anchor_o(out_anchor_w),
        .out_index_o(out_index_w),
        .candidate_count_o(candidate_count_w),
        .output_count_o(output_count_w),
        .busy_o(busy_w), .done_o(done_w), .error_o(error_w)
    );

    always @(posedge clk_i) begin
        if (out_valid_w) begin
            if (emitted_r >= 3)
                $fatal(1, "too many NMS outputs");
            classes_r[emitted_r] <= out_class_w;
            scores_r[emitted_r] <= out_score_w;
            emitted_r <= emitted_r + 1;
        end
    end

    task automatic send_candidate(input [6:0] cls,
                                  input [15:0] score,
                                  input [31:0] x1, y1, x2, y2);
        begin
            @(negedge clk_i);
            if (!in_ready_w)
                $fatal(1, "NMS input not ready");
            in_class_i = cls;
            in_score_i = score;
            in_x1_i = x1;
            in_y1_i = y1;
            in_x2_i = x2;
            in_y2_i = y2;
            in_valid_i = 1'b1;
            @(negedge clk_i);
            in_valid_i = 1'b0;
        end
    endtask

    initial begin
        repeat (5) @(negedge clk_i);
        rst_n_i = 1'b1;
        @(negedge clk_i);
        start_i = 1'b1;
        @(negedge clk_i);
        start_i = 1'b0;
        send_candidate(7'd0, 16'd30000,
                       32'd2560, 32'd2560, 32'd7680, 32'd7680);
        send_candidate(7'd0, 16'd25000,
                       32'd2816, 32'd2816, 32'd7424, 32'd7424);
        send_candidate(7'd1, 16'd20000,
                       32'd2816, 32'd2816, 32'd7424, 32'd7424);
        send_candidate(7'd0, 16'd15000,
                       32'd15360, 32'd15360, 32'd20480, 32'd20480);
        @(negedge clk_i);
        finish_i = 1'b1;
        @(negedge clk_i);
        finish_i = 1'b0;
        wait (done_w);
        if (error_w || candidate_count_w != 10'd4 ||
            output_count_w != 7'd3 || emitted_r != 3 ||
            classes_r[0] != 7'd0 || scores_r[0] != 16'd30000 ||
            classes_r[1] != 7'd1 || scores_r[1] != 16'd20000 ||
            classes_r[2] != 7'd0 || scores_r[2] != 16'd15000)
            $fatal(1, "NMS result mismatch count=%0d emitted=%0d error=%0d",
                   output_count_w, emitted_r, error_w);
        $display("tb_yolo_nms PASS");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "NMS timeout");
    end
endmodule
