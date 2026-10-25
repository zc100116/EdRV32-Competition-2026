`timescale 1ns/1ps
module tb_mul_low1;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg flush = 0;
    reg start = 0;
    reg [31:0] lhs = 0;
    reg [31:0] rhs = 0;
    wire result_valid;
    wire [31:0] result;
    reg expected_v1;
    reg [31:0] expected_d1;
    wire [63:0] reference_product = {32'd0, lhs} * {32'd0, rhs};
    reg [31:0] state_a = 32'h725c_d123;
    reg [31:0] state_b = 32'h92a1_fca7;
    integer checks = 0;
    integer index;
    edrv32_mul_low32_pipe1 u_dut (
        .clk_i(clk), .rst_n_i(rst_n), .flush_i(flush), .start_i(start),
        .lhs_i(lhs), .rhs_i(rhs), .result_valid_o(result_valid), .result_o(result)
    );
    always @(posedge clk) begin
        if (!rst_n || flush) begin
            expected_v1 <= 0;
        end else begin
            expected_v1 <= start;
            if (start) expected_d1 <= reference_product[31:0];
        end
        #1;
        if (rst_n) begin
            if (result_valid !== expected_v1)
                $fatal(1, "one-stage valid/flush mismatch expected=%b actual=%b",
                       expected_v1, result_valid);
            if (expected_v1) begin
                checks = checks + 1;
                if (result !== expected_d1)
                    $fatal(1, "low product mismatch expected=%08x actual=%08x",
                           expected_d1, result);
            end
        end
    end
    task vector;
        input [31:0] a, b;
        input valid, kill;
        begin
            @(negedge clk);
            lhs = a; rhs = b; start = valid; flush = kill;
        end
    endtask
    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        vector(0, 32'hffff_ffff, 1, 0);
        vector(32'hffff_ffff, 32'hffff_ffff, 1, 0);
        vector(32'h8000_0000, 32'h8000_0000, 1, 0);
        vector(32'h7fff_ffff, 32'h8000_0000, 1, 0);
        vector(32'hffff_0000, 32'h0000_ffff, 1, 0);
        vector(32'hffff_ffff, 32'd3, 1, 0);
        vector(32'hffff_fff9, 32'd3, 1, 0);
        vector(32'h1234_5678, 32'h8765_4321, 1, 1);
        vector(32'h0001_0001, 32'h0001_0001, 1, 0);
        vector(0, 0, 0, 1);
        for (index = 0; index < 8192; index = index + 1) begin
            state_a = {state_a[30:0], state_a[31] ^ state_a[21] ^ state_a[1] ^ state_a[0]};
            state_b = {state_b[30:0], state_b[31] ^ state_b[21] ^ state_b[1] ^ state_b[0]};
            vector(state_a, state_b, state_a[3], state_b[7:0] == 0);
        end
        vector(0, 0, 0, 0);
        vector(0, 0, 0, 0);
        @(negedge clk);
        if (checks < 3000) $fatal(1, "insufficient product coverage checks=%0d", checks);
        $display("PASS: one-stage low multiplier (%0d products, streaming/bubbles/flush)", checks);
        $finish;
    end
endmodule
