// File: tb_edrv32_cdc_handshake.sv
// Spec: infra-plan I-06; edrv32-soc-spec 5.2, 5.3
// Description: Self-checking directed primitive tests.
// Clock domain: test clocks below.
module tb_edrv32_cdc_handshake;
    task automatic check(input bit condition, input string message);
        if (!condition) begin
            $display("FAIL: %s (expected true, actual false) at %0t", message, $time);
            $fatal(1);
        end
    endtask

    initial begin
        #100000;
        $fatal(1, "FAIL: timeout at %0t", $time);
    end

    reg src_clk = 0;
    reg dst_clk = 0;
    reg src_rst_n = 1;
    reg dst_rst_n = 1;
    reg valid = 0;
    wire ready;
    reg [7:0] data = 0;
    wire out_valid;
    reg out_ready = 0;
    wire [7:0] out_data;
    always #5 src_clk = ~src_clk;
    always #7 dst_clk = ~dst_clk;

    edrv32_cdc_handshake #(.WIDTH(8)) u_dut (
        .clk_src_i(src_clk),
        .rst_src_n_i(src_rst_n),
        .clk_dst_i(dst_clk),
        .rst_dst_n_i(dst_rst_n),
        .valid_i(valid),
        .ready_o(ready),
        .data_i(data),
        .valid_o(out_valid),
        .ready_i(out_ready),
        .data_o(out_data)
    );

    initial begin
        #1 src_rst_n = 0;
        dst_rst_n = 0;
        repeat (3) @(negedge src_clk);
        src_rst_n = 1;
        @(negedge dst_clk);
        dst_rst_n = 1;
        for (integer index = 1; index <= 8; index = index + 1) begin
            @(negedge src_clk);
            while (!ready) @(negedge src_clk);
            data = 8'(index);
            valid = 1;
            @(negedge src_clk);
            valid = 0;
            check(!ready, "source holds request until acknowledgement");
            @(negedge dst_clk);
            while (!out_valid) @(negedge dst_clk);
            repeat (3) begin
                check(out_valid && out_data == 8'(index),
                      $sformatf("held payload expected %0d actual %0d", index, out_data));
                @(negedge dst_clk);
            end
            out_ready = 1;
            @(negedge dst_clk);
            out_ready = 0;
            check(!out_valid, "destination consumes request once");
            repeat (4) @(negedge src_clk);
            check(ready, "acknowledgement returns source ready");
        end
        $display("PASS");
        $finish;
    end
endmodule
