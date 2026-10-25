`timescale 1ns/1ps
`include "edrv32_uop.vh"

module tb_alu_equivalence;

    reg  [`EDRV32_ALU_OP_W-1:0] alu_operation;
    reg  [31:0]                  lhs;
    reg  [31:0]                  rhs;
    wire [31:0]                  structural_result;
    wire [31:0]                  behavioral_result;

    reg  [`EDRV32_BRANCH_OP_W-1:0] branch_operation;
    wire                            branch_taken;

    integer checks;
    integer failures;
    integer operation_index;
    integer vector_index;
    integer shift_index;
    reg [31:0] lfsr_lhs;
    reg [31:0] lfsr_rhs;

    edrv32_alu u_structural (
        .op_i     (alu_operation),
        .lhs_i    (lhs),
        .rhs_i    (rhs),
        .result_o (structural_result)
    );

    edrv32_alu_behavioral u_behavioral (
        .op_i     (alu_operation),
        .lhs_i    (lhs),
        .rhs_i    (rhs),
        .result_o (behavioral_result)
    );

    edrv32_branch_unit u_branch (
        .branch_op_i (branch_operation),
        .lhs_i       (lhs),
        .rhs_i       (rhs),
        .taken_o     (branch_taken)
    );

    task automatic check_alu;
        input [`EDRV32_ALU_OP_W-1:0] operation;
        input [31:0] lhs_value;
        input [31:0] rhs_value;
        begin
            alu_operation = operation;
            lhs = lhs_value;
            rhs = rhs_value;
            #1;
            checks = checks + 1;
            if (structural_result !== behavioral_result) begin
                failures = failures + 1;
                $display("FAIL ALU op=%0d lhs=%08x rhs=%08x structural=%08x behavioral=%08x",
                         operation, lhs_value, rhs_value,
                         structural_result, behavioral_result);
            end
        end
    endtask

    task automatic check_branch;
        input [`EDRV32_BRANCH_OP_W-1:0] operation;
        input [31:0] lhs_value;
        input [31:0] rhs_value;
        reg expected;
        begin
            branch_operation = operation;
            lhs = lhs_value;
            rhs = rhs_value;
            case (operation)
                `EDRV32_BRANCH_EQ:  expected = (lhs_value == rhs_value);
                `EDRV32_BRANCH_NE:  expected = (lhs_value != rhs_value);
                `EDRV32_BRANCH_LT:  expected = ($signed(lhs_value) < $signed(rhs_value));
                `EDRV32_BRANCH_GE:  expected = ($signed(lhs_value) >= $signed(rhs_value));
                `EDRV32_BRANCH_LTU: expected = (lhs_value < rhs_value);
                `EDRV32_BRANCH_GEU: expected = (lhs_value >= rhs_value);
                default:            expected = 1'b0;
            endcase
            #1;
            checks = checks + 1;
            if (branch_taken !== expected) begin
                failures = failures + 1;
                $display("FAIL BRANCH op=%0d lhs=%08x rhs=%08x actual=%b expected=%b",
                         operation, lhs_value, rhs_value, branch_taken, expected);
            end
        end
    endtask

    function automatic [31:0] next_lfsr;
        input [31:0] state;
        begin
            next_lfsr = {state[30:0], state[31] ^ state[21] ^ state[1] ^ state[0]};
        end
    endfunction

    initial begin
        checks = 0;
        failures = 0;
        alu_operation = `EDRV32_ALU_ADD;
        branch_operation = `EDRV32_BRANCH_NONE;
        lhs = 32'd0;
        rhs = 32'd0;

        // Directed arithmetic, sign and bit-pattern corner cases for every op.
        for (operation_index = 0; operation_index <= `EDRV32_ALU_COPY_B;
             operation_index = operation_index + 1) begin
            check_alu(operation_index, 32'h0000_0000, 32'h0000_0000);
            check_alu(operation_index, 32'hffff_ffff, 32'h0000_0001);
            check_alu(operation_index, 32'h7fff_ffff, 32'h8000_0000);
            check_alu(operation_index, 32'h8000_0000, 32'h7fff_ffff);
            check_alu(operation_index, 32'ha5a5_5a5a, 32'h5a5a_a5a5);
        end

        // Exercise every legal RV32 shift amount with sign bit clear and set.
        for (shift_index = 0; shift_index < 32; shift_index = shift_index + 1) begin
            check_alu(`EDRV32_ALU_SLL, 32'h8123_4567, shift_index);
            check_alu(`EDRV32_ALU_SRL, 32'h8123_4567, shift_index);
            check_alu(`EDRV32_ALU_SRA, 32'h8123_4567, shift_index);
            check_alu(`EDRV32_ALU_SRA, 32'h7123_4567, shift_index);
        end

        // Deterministic pseudo-random cross-product across all operations.
        lfsr_lhs = 32'h1ace_b00c;
        lfsr_rhs = 32'hc001_d00d;
        for (vector_index = 0; vector_index < 512; vector_index = vector_index + 1) begin
            lfsr_lhs = next_lfsr(lfsr_lhs);
            lfsr_rhs = next_lfsr(lfsr_rhs);
            for (operation_index = 0; operation_index <= `EDRV32_ALU_COPY_B;
                 operation_index = operation_index + 1)
                check_alu(operation_index, lfsr_lhs, lfsr_rhs);

            check_branch(`EDRV32_BRANCH_EQ,  lfsr_lhs, lfsr_rhs);
            check_branch(`EDRV32_BRANCH_NE,  lfsr_lhs, lfsr_rhs);
            check_branch(`EDRV32_BRANCH_LT,  lfsr_lhs, lfsr_rhs);
            check_branch(`EDRV32_BRANCH_GE,  lfsr_lhs, lfsr_rhs);
            check_branch(`EDRV32_BRANCH_LTU, lfsr_lhs, lfsr_rhs);
            check_branch(`EDRV32_BRANCH_GEU, lfsr_lhs, lfsr_rhs);
        end

        if (failures == 0)
            $display("PASS: structural/behavioral ALU and branch equivalence (%0d checks)", checks);
        else
            $fatal(1, "FAIL: structural datapath equivalence failures=%0d checks=%0d", failures, checks);
        $finish;
    end

endmodule
