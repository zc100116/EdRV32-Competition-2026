`timescale 1ns/1ps
`include "edrv32_uop.vh"

module tb_mul_pango_equivalence;
    reg clk, rst_n, flush, start;
    reg [`EDRV32_MDU_OP_W-1:0] operation;
    reg [31:0] lhs, rhs;
    wire portable_valid, pango_valid;
    wire [31:0] portable_result, pango_result;
    integer checks;
    integer vector_index;
    integer operation_index;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    edrv32_mul_booth4_wallace u_portable (
        .clk_i(clk), .rst_n_i(rst_n), .flush_i(flush), .start_i(start),
        .operation_i(operation), .lhs_i(lhs), .rhs_i(rhs),
        .result_valid_o(portable_valid), .result_o(portable_result)
    );

    edrv32_mul_pango_apm u_pango (
        .clk_i(clk), .rst_n_i(rst_n), .flush_i(flush), .start_i(start),
        .operation_i(operation), .lhs_i(lhs), .rhs_i(rhs),
        .result_valid_o(pango_valid), .result_o(pango_result)
    );

    function automatic [31:0] expected_result;
        input [`EDRV32_MDU_OP_W-1:0] op_i;
        input [31:0] lhs_i;
        input [31:0] rhs_i;
        reg signed [32:0] signed_lhs;
        reg signed [32:0] signed_rhs;
        reg signed [65:0] signed_product;
        begin
            signed_lhs = ((op_i == `EDRV32_MDU_MULH) ||
                          (op_i == `EDRV32_MDU_MULHSU))
                ? {lhs_i[31], lhs_i} : {1'b0, lhs_i};
            signed_rhs = (op_i == `EDRV32_MDU_MULH)
                ? {rhs_i[31], rhs_i} : {1'b0, rhs_i};
            signed_product = signed_lhs * signed_rhs;
            expected_result = (op_i == `EDRV32_MDU_MUL)
                ? signed_product[31:0] : signed_product[63:32];
        end
    endfunction

    task automatic check_true;
        input condition;
        input [8*96-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                $display("FAIL: %0s", message);
                $fatal(1);
            end
        end
    endtask

    task automatic run_vector;
        input [`EDRV32_MDU_OP_W-1:0] op_i;
        input [31:0] lhs_i;
        input [31:0] rhs_i;
        reg [31:0] expected_i;
        begin
            expected_i = expected_result(op_i, lhs_i, rhs_i);
            @(negedge clk);
            operation = op_i;
            lhs = lhs_i;
            rhs = rhs_i;
            start = 1'b1;
            @(posedge clk); #1;
            start = 1'b0;
            while (!portable_valid || !pango_valid) begin
                @(posedge clk); #1;
            end
            if (!(portable_valid && pango_valid &&
                  portable_result == expected_i && pango_result == expected_i))
                $display("MISMATCH op=%0d lhs=%08x rhs=%08x expected=%08x portable(v=%b)=%08x pango(v=%b)=%08x",
                         op_i, lhs_i, rhs_i, expected_i,
                         portable_valid, portable_result, pango_valid, pango_result);
            check_true(portable_valid && pango_valid &&
                       portable_result == expected_i &&
                       pango_result == expected_i,
                       "Portable and Pango pipe3 multiply results agree");
            @(posedge clk); #1;
            check_true(!portable_valid && !pango_valid,
                       "Both multiplier completion tags are single-cycle");
        end
    endtask

    initial begin
        checks = 0;
        rst_n = 1'b0;
        flush = 1'b0;
        start = 1'b0;
        operation = `EDRV32_MDU_MUL;
        lhs = 32'd0;
        rhs = 32'd0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        run_vector(`EDRV32_MDU_MUL, 32'hffff_ffff, 32'hffff_ffff);
        run_vector(`EDRV32_MDU_MULH, 32'h8000_0000, 32'hffff_ffff);
        run_vector(`EDRV32_MDU_MULHSU, 32'h8000_0000, 32'hffff_ffff);
        run_vector(`EDRV32_MDU_MULHU, 32'hffff_ffff, 32'hffff_ffff);

        for (vector_index = 0; vector_index < 256; vector_index = vector_index + 1) begin
            for (operation_index = `EDRV32_MDU_MUL;
                 operation_index <= `EDRV32_MDU_MULHU;
                 operation_index = operation_index + 1) begin
                run_vector(operation_index[`EDRV32_MDU_OP_W-1:0],
                           $random, $random);
            end
        end

        // Flush before completion must remove both visibility tags.
        @(negedge clk);
        operation = `EDRV32_MDU_MULH;
        lhs = 32'h1234_5678;
        rhs = 32'h8765_4321;
        start = 1'b1;
        @(posedge clk); #1;
        start = 1'b0;
        flush = 1'b1;
        @(posedge clk); #1;
        flush = 1'b0;
        repeat (4) @(posedge clk);
        check_true(!portable_valid && !pango_valid,
                   "Flush removes portable and Pango in-flight completion");

        $display("PASS: portable/Pango multiplier equivalence (%0d checks)", checks);
        $finish;
    end
endmodule
