`timescale 1ns/1ps
`include "edrv32_uop.vh"

module tb_mdu;
`ifdef EDRV32_TEST_ONE_STAGE_MUL
    localparam integer MUL_LOW_PIPE_STAGES = 1;
`else
    localparam integer MUL_LOW_PIPE_STAGES = 2;
`endif
`ifdef EDRV32_TEST_PANGO_MUL
    localparam integer MUL_USE_PANGO_APM = 1;
`else
    localparam integer MUL_USE_PANGO_APM = 0;
`endif
`ifdef EDRV32_TEST_LEGACY_LOW_MUL
    localparam integer MUL_FAST_LOW = 0;
`else
    localparam integer MUL_FAST_LOW = 1;
`endif
    reg clk;
    reg rst_n;
    reg req_valid;
    wire req_ready;
    reg [`EDRV32_MDU_OP_W-1:0] req_op;
    reg [31:0] req_lhs;
    reg [31:0] req_rhs;
    reg [4:0] req_rd;
    reg authorize;
    reg cancel;
    wire result_valid;
    reg result_ready;
    wire [4:0] result_rd;
    wire [31:0] result_data;
    wire slot_valid;
    wire result_complete;
    wire authorized;
    integer checks;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    edrv32_mdu #(.MUL_USE_PANGO_APM(MUL_USE_PANGO_APM), .MUL_FAST_LOW(MUL_FAST_LOW),
                 .MUL_LOW_PIPE_STAGES(MUL_LOW_PIPE_STAGES)) u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .req_valid_i(req_valid), .req_ready_o(req_ready),
        .req_op_i(req_op), .req_lhs_i(req_lhs), .req_rhs_i(req_rhs),
        .req_mul_lhs_i(req_lhs), .req_mul_rhs_i(req_rhs),
        .req_div_lhs_i(req_lhs), .req_div_rhs_i(req_rhs),
        .req_rd_i(req_rd), .authorize_i(authorize), .cancel_i(cancel),
        .result_valid_o(result_valid), .result_ready_i(result_ready),
        .result_rd_o(result_rd), .result_data_o(result_data),
        .slot_valid_o(slot_valid), .result_complete_o(result_complete),
        .authorized_o(authorized)
    );

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

    task automatic run_same_edge_writeback;
        input [`EDRV32_MDU_OP_W-1:0] operation;
        input [31:0] lhs;
        input [31:0] rhs;
        input [31:0] expected;
        begin
            while (!req_ready) @(posedge clk);
            @(negedge clk);
            req_op = operation;
            req_lhs = lhs;
            req_rhs = rhs;
            req_rd = 5'd17;
            req_valid = 1'b1;
            @(posedge clk); #1;
            req_valid = 1'b0;
            result_ready = 1'b1;
            while (!result_complete) @(negedge clk);
            check_true(!result_valid && slot_valid,
                       "completed speculative result cannot write before retirement");
            authorize = 1'b1;
            #1;
            check_true(result_valid && result_rd == 5'd17 &&
                       result_data == expected && !req_ready,
                       "retirement exposes ready result without transparent slot reuse");
            @(posedge clk); #1;
            authorize = 1'b0;
            result_ready = 1'b0;
            check_true(!slot_valid && !authorized && !result_valid && req_ready,
                       "retirement and writeback release the slot on one edge");
        end
    endtask

    task automatic run_operation;
        input [`EDRV32_MDU_OP_W-1:0] operation;
        input [31:0] lhs;
        input [31:0] rhs;
        input [31:0] expected;
        input authorize_early;
        begin
            while (!req_ready) @(posedge clk);
            @(negedge clk);
            req_op = operation;
            req_lhs = lhs;
            req_rhs = rhs;
            req_rd = 5'd13;
            req_valid = 1'b1;
            @(posedge clk); #1;
            req_valid = 1'b0;
            check_true(slot_valid && !req_ready, "request allocates the sole slot");

            if (authorize_early) begin
                authorize = 1'b1;
                @(posedge clk); #1;
                authorize = 1'b0;
                check_true(authorized, "early COMMIT authorization is retained");
            end else begin
                while (!result_complete) @(posedge clk);
                #1;
                check_true(!result_valid, "early result waits for COMMIT authorization");
                authorize = 1'b1;
                @(posedge clk); #1;
                authorize = 1'b0;
            end

            while (!result_valid) @(posedge clk);
            #1;
            check_true(result_rd == 5'd13 && result_data == expected,
                       "authorized MDU result matches expected value");
            result_ready = 1'b1;
            @(posedge clk); #1;
            result_ready = 1'b0;
            check_true(!slot_valid && req_ready, "writeback releases slot without reuse path");
        end
    endtask

    initial begin
        checks = 0;
        rst_n = 1'b0;
        req_valid = 1'b0;
        req_op = 0;
        req_lhs = 0;
        req_rhs = 0;
        req_rd = 0;
        authorize = 1'b0;
        cancel = 1'b0;
        result_ready = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        run_operation(`EDRV32_MDU_MUL,    32'hffff_fffe, 32'd3, 32'hffff_fffa, 1'b0);
        run_operation(`EDRV32_MDU_MULH,   32'hffff_fffe, 32'd3, 32'hffff_ffff, 1'b1);
        run_operation(`EDRV32_MDU_MULHSU, 32'hffff_fffe, 32'hffff_ffff,
                      32'hffff_fffe, 1'b1);
        run_operation(`EDRV32_MDU_MULHU,  32'hffff_ffff, 32'd2, 32'd1, 1'b1);
        run_operation(`EDRV32_MDU_DIV,    -32'sd7, 32'd3, -32'sd2, 1'b1);
        run_operation(`EDRV32_MDU_DIVU,   32'hffff_fffe, 32'd3, 32'h5555_5554, 1'b1);
        run_operation(`EDRV32_MDU_REM,    -32'sd7, 32'd3, 32'hffff_ffff, 1'b1);
        run_operation(`EDRV32_MDU_REMU,   32'hffff_fffe, 32'd3, 32'd2, 1'b1);
        run_operation(`EDRV32_MDU_DIV,    32'h1234_5678, 32'd0, 32'hffff_ffff, 1'b0);
        run_operation(`EDRV32_MDU_REMU,   32'h1234_5678, 32'd0, 32'h1234_5678, 1'b1);
        run_operation(`EDRV32_MDU_DIV,    32'h8000_0000, 32'hffff_ffff,
                      32'h8000_0000, 1'b1);
        run_operation(`EDRV32_MDU_REM,    32'h8000_0000, 32'hffff_ffff,
                      32'd0, 1'b1);

        run_same_edge_writeback(`EDRV32_MDU_MUL, 32'd7, 32'd9, 32'd63);
        run_same_edge_writeback(`EDRV32_MDU_MULH, 32'hffff_fffe, 32'd3,
                               32'hffff_ffff);
        run_same_edge_writeback(`EDRV32_MDU_DIVU, 32'd100, 32'd7, 32'd14);
        run_same_edge_writeback(`EDRV32_MDU_REMU, 32'd100, 32'd7, 32'd2);

        // A canceled un-authorized operation cannot leak a late result.
        @(negedge clk);
        req_valid = 1'b1; req_op = `EDRV32_MDU_DIVU;
        req_lhs = 32'hffff_ffff; req_rhs = 32'd7; req_rd = 5'd3;
        @(posedge clk); #1;
        req_valid = 1'b0; cancel = 1'b1;
        @(posedge clk); #1;
        cancel = 1'b0;
        check_true(!slot_valid && !result_valid, "cancel discards an in-flight division");

        $display("PASS: decoupled MDU (%0d checks)", checks);
        $finish;
    end
endmodule
