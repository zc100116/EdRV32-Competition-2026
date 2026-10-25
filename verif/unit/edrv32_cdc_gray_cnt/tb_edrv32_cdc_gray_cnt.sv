// File: tb_edrv32_cdc_gray_cnt.sv
// Spec: infra-plan I-06; edrv32-soc-spec 5.2, 5.3
// Description: Self-checking directed primitive tests.
// Clock domain: test clocks below.
module tb_edrv32_cdc_gray_cnt;
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
    reg [3:0] count = 0;
    wire [3:0] snapshot;
    always #5 src_clk = ~src_clk;
    always #7 dst_clk = ~dst_clk;

    edrv32_cdc_gray_cnt #(.WIDTH(4)) u_dut (
        .clk_src_i(src_clk),
        .rst_src_n_i(src_rst_n),
        .clk_dst_i(dst_clk),
        .rst_dst_n_i(dst_rst_n),
        .count_i(count),
        .count_o(snapshot)
    );

    initial begin
        #1 src_rst_n = 0;
        dst_rst_n = 0;
        repeat (3) @(negedge src_clk);
        src_rst_n = 1;
        @(negedge dst_clk);
        dst_rst_n = 1;
        for (integer index = 1; index <= 34; index = index + 1) begin
            @(negedge src_clk);
            count = count + 1'b1;
            repeat (5) @(negedge dst_clk);
            check(snapshot === count,
                  $sformatf("snapshot expected %0d actual %0d", count, snapshot));
        end
        // A faster sequence may skip intermediate counts but must settle correctly.
        repeat (20) begin
            @(negedge src_clk);
            count = count + 1'b1;
        end
        repeat (5) @(negedge dst_clk);
        check(snapshot === count, "fast count settles after wrap");
        $display("PASS");
        $finish;
    end
endmodule
