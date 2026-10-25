// File: tb_edrv32_cdc_pulse.sv
// Spec: infra-plan I-06; edrv32-soc-spec 5.2, 5.3
// Description: Self-checking directed primitive tests.
// Clock domain: test clocks below.
module tb_edrv32_cdc_pulse;
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
    reg pulse = 0;
    wire received;
    integer count = 0;
    reg previous = 0;
    always #5 src_clk = ~src_clk;
    always #7 dst_clk = ~dst_clk;

    edrv32_cdc_pulse u_dut (
        .clk_src_i(src_clk),
        .rst_src_n_i(src_rst_n),
        .clk_dst_i(dst_clk),
        .rst_dst_n_i(dst_rst_n),
        .pulse_i(pulse),
        .pulse_o(received)
    );

    always @(posedge dst_clk) begin
        if (dst_rst_n) begin
            check(!(previous && received), "destination pulse is one cycle");
            if (received) count = count + 1;
            previous = received;
        end
    end

    initial begin
        #1 src_rst_n = 0;
        dst_rst_n = 0;
        repeat (3) @(negedge src_clk);
        src_rst_n = 1;
        @(negedge dst_clk);
        dst_rst_n = 1;
        for (integer index = 1; index <= 5; index = index + 1) begin
            @(negedge src_clk);
            pulse = 1;
            @(negedge src_clk);
            pulse = 0;
            repeat (6) @(negedge dst_clk);
            check(count == index, $sformatf("pulse count expected %0d actual %0d", index, count));
        end
        $display("PASS");
        $finish;
    end
endmodule
