// File: tb_edrv32_reset_sync.sv
// Spec: infra-plan I-06; edrv32-soc-spec 5.2, 5.3
// Description: Self-checking directed primitive tests.
// Clock domain: test clocks below.
module tb_edrv32_reset_sync;
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

    reg clk = 0;
    reg rst_n = 1;
    wire rst_out_n;
    always #5 clk = ~clk;

    edrv32_reset_sync u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .rst_n_o(rst_out_n)
    );

    initial begin
        #1 rst_n = 0;
        #1 check(rst_out_n === 0, "asynchronous assertion");
        @(negedge clk);
        rst_n = 1;
        @(posedge clk);
        #1 check(rst_out_n === 0, "first release clock remains reset");
        @(posedge clk);
        #1 check(rst_out_n === 1, "second release clock releases reset");
        #2 rst_n = 0;
        #1 check(rst_out_n === 0, "reassert between clocks");
        $display("PASS");
        $finish;
    end
endmodule
