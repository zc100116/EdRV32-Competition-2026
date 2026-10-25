`timescale 1ns/1ps
`include "edrv32_uop.vh"

module tb_mul_equivalence;
    reg clk;
    reg rst_n;
    reg flush;
    reg start;
    reg [`EDRV32_MDU_OP_W-1:0] operation;
    reg [31:0] lhs;
    reg [31:0] rhs;
    wire result_valid;
    wire [31:0] result;

    integer checks;
    integer failures;
    integer vector_index;
    integer operation_index;
    reg [31:0] lfsr_lhs;
    reg [31:0] lfsr_rhs;

    reg signed [32:0] reference_lhs;
    reg signed [32:0] reference_rhs;
    reg signed [65:0] reference_product;
    reg [31:0] expected;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    edrv32_mul_booth4_wallace u_dut (
        .clk_i(clk), .rst_n_i(rst_n), .flush_i(flush), .start_i(start),
        .operation_i(operation), .lhs_i(lhs), .rhs_i(rhs),
        .result_valid_o(result_valid), .result_o(result)
    );

    function automatic [31:0] next_lfsr;
        input [31:0] state;
        begin
            next_lfsr = {state[30:0], state[31] ^ state[21] ^ state[1] ^ state[0]};
        end
    endfunction

    task automatic run_multiply;
        input [`EDRV32_MDU_OP_W-1:0] selected_operation;
        input [31:0] selected_lhs;
        input [31:0] selected_rhs;
        begin
            case (selected_operation)
                `EDRV32_MDU_MULH: begin
                    reference_lhs = {selected_lhs[31], selected_lhs};
                    reference_rhs = {selected_rhs[31], selected_rhs};
                end
                `EDRV32_MDU_MULHSU: begin
                    reference_lhs = {selected_lhs[31], selected_lhs};
                    reference_rhs = {1'b0, selected_rhs};
                end
                default: begin
                    reference_lhs = {1'b0, selected_lhs};
                    reference_rhs = {1'b0, selected_rhs};
                end
            endcase
            reference_product = reference_lhs * reference_rhs;
            expected = (selected_operation == `EDRV32_MDU_MUL)
                ? reference_product[31:0] : reference_product[63:32];

            @(negedge clk);
            operation = selected_operation;
            lhs = selected_lhs;
            rhs = selected_rhs;
            start = 1'b1;
            @(posedge clk); #1;
            start = 1'b0;
            while (!result_valid) @(posedge clk);
            #1;
            checks = checks + 1;
            if (result !== expected) begin
                failures = failures + 1;
                $display("FAIL MUL op=%0d lhs=%08x rhs=%08x actual=%08x expected=%08x",
                         selected_operation, selected_lhs, selected_rhs, result, expected);
            end
        end
    endtask

    initial begin
        checks = 0;
        failures = 0;
        rst_n = 1'b0;
        flush = 1'b0;
        start = 1'b0;
        operation = `EDRV32_MDU_MUL;
        lhs = 32'd0;
        rhs = 32'd0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        for (operation_index = `EDRV32_MDU_MUL;
             operation_index <= `EDRV32_MDU_MULHU;
             operation_index = operation_index + 1) begin
            run_multiply(operation_index, 32'd0, 32'd0);
            run_multiply(operation_index, 32'hffff_ffff, 32'd1);
            run_multiply(operation_index, 32'hffff_ffff, 32'hffff_ffff);
            run_multiply(operation_index, 32'h8000_0000, 32'hffff_ffff);
            run_multiply(operation_index, 32'h7fff_ffff, 32'h8000_0000);
        end

        lfsr_lhs = 32'h7a11_c0de;
        lfsr_rhs = 32'hcafe_1234;
        for (vector_index = 0; vector_index < 256; vector_index = vector_index + 1) begin
            lfsr_lhs = next_lfsr(lfsr_lhs);
            lfsr_rhs = next_lfsr(lfsr_rhs);
            for (operation_index = `EDRV32_MDU_MUL;
                 operation_index <= `EDRV32_MDU_MULHU;
                 operation_index = operation_index + 1)
                run_multiply(operation_index, lfsr_lhs, lfsr_rhs);
        end

        if (failures == 0)
            $display("PASS: structural Booth/Wallace multiplier equivalence (%0d checks)", checks);
        else
            $fatal(1, "FAIL: multiplier equivalence failures=%0d checks=%0d", failures, checks);
        $finish;
    end
endmodule
