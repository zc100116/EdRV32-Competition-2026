// File: tb_edrv32_cdc_sync_bit.sv
// Spec: infra-plan I-06; edrv32-soc-spec 5.2, 5.3
// Description: Self-checking directed primitive tests.
// Clock domain: test clocks below.
module tb_edrv32_cdc_sync_bit;
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
    reg level = 0;
    wire synced;
    always #7 clk = ~clk;

    edrv32_cdc_sync_bit u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .bit_i(level),
        .bit_o(synced)
    );

    initial begin
        #1 rst_n = 0;
        #1 check(synced === 0, "reset level");
        @(negedge clk);
        rst_n = 1;
        for (integer index = 0; index < 4; index = index + 1) begin
            #3 level = ~level;
            @(posedge clk);
            #1 check(synced === ~level, "first stage latency");
            @(posedge clk);
            #1 check(synced === level, "second stage follows input");
            @(negedge clk);
        end
        $display("PASS");
        $finish;
    end
endmodule
