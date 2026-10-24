`timescale 1ns/1ps

module tb_yolo_dfl16;
    reg clk_i = 1'b0;
    reg rst_n_i = 1'b0;
    always #3.333 clk_i = !clk_i;
    reg start_i = 1'b0;
    reg [1:0] scale_i = 2'd0;
    reg [127:0] logits_i = 128'd0;
    wire start_ready_w, busy_w, done_w;
    wire [11:0] distance_w;
    integer index;

    edrv32_yolo_dfl16 dut (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(start_i), .start_ready_o(start_ready_w),
        .scale_i(scale_i), .logits_i(logits_i),
        .busy_o(busy_w), .done_o(done_w), .distance_o(distance_w)
    );

    task automatic run_case(input [1:0] scale,
                            input [127:0] logits,
                            input [11:0] expected);
        begin
            @(negedge clk_i);
            if (!start_ready_w)
                $fatal(1, "DFL not ready");
            scale_i = scale;
            logits_i = logits;
            start_i = 1'b1;
            @(negedge clk_i);
            start_i = 1'b0;
            wait (done_w);
            if (distance_w !== expected)
                $fatal(1, "DFL scale=%0d got=%0d expected=%0d",
                       scale, distance_w, expected);
        end
    endtask

    initial begin
        repeat (5) @(negedge clk_i);
        rst_n_i = 1'b1;
        run_case(2'd0, 128'd0, 12'd1920);
        run_case(2'd1, 128'd0, 12'd1920);
        logits_i = 128'd0;
        for (index = 0; index < 16; index = index + 1)
            logits_i[index*8 +: 8] = index[7:0];
        run_case(2'd0, logits_i, 12'd2576);
        run_case(2'd1, logits_i, 12'd2408);
        run_case(2'd2, logits_i, 12'd2366);
        logits_i = {16{8'h80}};
        logits_i[15*8 +: 8] = 8'h7f;
        run_case(2'd0, logits_i, 12'd3840);
        logits_i = {16{8'h80}};
        logits_i[0 +: 8] = 8'h7f;
        run_case(2'd2, logits_i, 12'd0);
        $display("tb_yolo_dfl16 PASS");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "DFL timeout");
    end
endmodule
