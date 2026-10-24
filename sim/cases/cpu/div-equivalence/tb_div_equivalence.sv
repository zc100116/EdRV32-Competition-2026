`timescale 1ns/1ps
`include "edrv32_uop.vh"

module tb_div_equivalence;

    reg clk;
    reg rst_n;
    reg req_valid;
    wire req_ready;
    reg [`EDRV32_MDU_OP_W-1:0] req_op;
    reg [31:0] req_lhs;
    reg [31:0] req_rhs;
    reg cancel;
    wire result_valid;
    reg result_ready;
    wire [31:0] result_data;
    wire busy;

    integer checks;
    integer operation_index;
    integer random_index;
    reg [`EDRV32_MDU_OP_W-1:0] random_operation;

    edrv32_div_nonrestoring u_dut (
        .clk_i          (clk),
        .rst_n_i        (rst_n),
        .req_valid_i    (req_valid),
        .req_ready_o    (req_ready),
        .req_op_i       (req_op),
        .req_lhs_i      (req_lhs),
        .req_rhs_i      (req_rhs),
        .cancel_i       (cancel),
        .result_valid_o (result_valid),
        .result_ready_i (result_ready),
        .result_data_o  (result_data),
        .busy_o         (busy)
    );

    always #5 clk = ~clk;

    function automatic [31:0] reference_result;
        input [`EDRV32_MDU_OP_W-1:0] operation;
        input [31:0] lhs;
        input [31:0] rhs;
        reg signed [31:0] signed_lhs;
        reg signed [31:0] signed_rhs;
        begin
            signed_lhs = lhs;
            signed_rhs = rhs;
            if (rhs == 32'd0) begin
                reference_result = ((operation == `EDRV32_MDU_REM) ||
                                    (operation == `EDRV32_MDU_REMU))
                    ? lhs : 32'hffff_ffff;
            end else begin
                case (operation)
                    `EDRV32_MDU_DIV: begin
                        if ((lhs == 32'h8000_0000) &&
                            (rhs == 32'hffff_ffff))
                            reference_result = 32'h8000_0000;
                        else
                            reference_result = signed_lhs / signed_rhs;
                    end
                    `EDRV32_MDU_DIVU:
                        reference_result = lhs / rhs;
                    `EDRV32_MDU_REM: begin
                        if ((lhs == 32'h8000_0000) &&
                            (rhs == 32'hffff_ffff))
                            reference_result = 32'd0;
                        else
                            reference_result = signed_lhs % signed_rhs;
                    end
                    default:
                        reference_result = lhs % rhs;
                endcase
            end
        end
    endfunction

    task automatic run_case;
        input [`EDRV32_MDU_OP_W-1:0] operation;
        input [31:0] lhs;
        input [31:0] rhs;
        integer wait_cycles;
        reg [31:0] expected;
        reg [31:0] held_result;
        begin
            expected = reference_result(operation, lhs, rhs);

            while (!req_ready)
                @(negedge clk);
            req_op    = operation;
            req_lhs   = lhs;
            req_rhs   = rhs;
            req_valid = 1'b1;
            @(negedge clk);
            req_valid = 1'b0;

            wait_cycles = 0;
            while (!result_valid) begin
                @(negedge clk);
                wait_cycles = wait_cycles + 1;
                if (wait_cycles > 40)
                    $fatal(1, "divider timeout op=%0d lhs=%08x rhs=%08x",
                           operation, lhs, rhs);
            end

            if (result_data !== expected)
                $fatal(1, "divider mismatch op=%0d lhs=%08x rhs=%08x got=%08x expected=%08x",
                       operation, lhs, rhs, result_data, expected);

            // The adapted implementation preserves the legacy hold-until-taken
            // contract even though the outer MDU normally accepts immediately.
            held_result = result_data;
            @(negedge clk);
            if (!result_valid || (result_data !== held_result))
                $fatal(1, "divider result did not hold under backpressure");
            result_ready = 1'b1;
            @(negedge clk);
            result_ready = 1'b0;
            if (result_valid)
                $fatal(1, "divider result_valid did not clear after acceptance");
            checks = checks + 1;
        end
    endtask

    task automatic run_cancel_case;
        begin
            while (!req_ready)
                @(negedge clk);
            req_op = `EDRV32_MDU_DIVU;
            req_lhs = 32'hfedc_ba98;
            req_rhs = 32'h0000_0123;
            req_valid = 1'b1;
            @(negedge clk);
            req_valid = 1'b0;
            repeat (5) @(negedge clk);
            cancel = 1'b1;
            @(negedge clk);
            cancel = 1'b0;
            if (busy || result_valid || !req_ready)
                $fatal(1, "divider cancel did not return the engine to IDLE");
            checks = checks + 1;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        req_valid = 1'b0;
        req_op = `EDRV32_MDU_DIV;
        req_lhs = 32'd0;
        req_rhs = 32'd0;
        cancel = 1'b0;
        result_ready = 1'b0;
        checks = 0;

        repeat (4) @(negedge clk);
        rst_n = 1'b1;

        // Architectural boundaries and fast-path cases.
        run_case(`EDRV32_MDU_DIV,  32'h8000_0000, 32'hffff_ffff);
        run_case(`EDRV32_MDU_REM,  32'h8000_0000, 32'hffff_ffff);
        run_case(`EDRV32_MDU_DIV,  32'h8000_0000, 32'd1);
        run_case(`EDRV32_MDU_DIV,  32'h7fff_ffff, 32'hffff_ffff);
        run_case(`EDRV32_MDU_DIVU, 32'hffff_ffff, 32'd1);
        run_case(`EDRV32_MDU_REMU, 32'hffff_ffff, 32'd1);
        run_case(`EDRV32_MDU_DIV,  32'h1234_5678, 32'd0);
        run_case(`EDRV32_MDU_REM,  32'h89ab_cdef, 32'd0);
        run_case(`EDRV32_MDU_DIVU, 32'd0, 32'hffff_ffff);
        run_case(`EDRV32_MDU_REMU, 32'd0, 32'hffff_ffff);

        // Deterministic pseudo-random equivalence against SystemVerilog's
        // arithmetic reference: 1024 vectors for every RV32M divide operation.
        for (operation_index = 0; operation_index < 4;
             operation_index = operation_index + 1) begin
            case (operation_index)
                0: random_operation = `EDRV32_MDU_DIV;
                1: random_operation = `EDRV32_MDU_DIVU;
                2: random_operation = `EDRV32_MDU_REM;
                default: random_operation = `EDRV32_MDU_REMU;
            endcase
            for (random_index = 0; random_index < 1024;
                 random_index = random_index + 1)
                run_case(random_operation, $urandom, $urandom);
        end

        run_cancel_case();
        $display("PASS: legacy-derived non-restoring divider equivalence (%0d checks)",
                 checks);
        $finish;
    end

endmodule
