// File: edrv32_cpu_predecode.v
// Spec: cpu-spec 4.1; cache-spec 2.2, 5.1.
// Description: Compute instruction-only controls before I$ storage.
// Direct instruction fields remain in the instruction word, not in this payload.
// Clock domain: combinational.
module edrv32_cpu_predecode (
    // Canonical fixed-width instruction.
    input wire [31:0] instr_i,
    // {S,B,U,jal,slow,serial,memory,control,csr,mul,load,class,alu_high,
    // pipe1,illegal,operand_imm,write,use2,use1}.
    output wire [21:0] predecode_o
);
    wire [4:0] unused_rs1_w;
    wire [4:0] unused_rs2_w;
    wire [4:0] unused_rd_w;
    wire [31:0] unused_immediate_w;
    wire use1_w;
    wire use2_w;
    wire write_w;
    wire [3:0] class_w;
    wire [3:0] operation_w;
    wire operand_imm_w;
    wire illegal_w;
    wire pipe1_w;
    wire unused_operation_w;
    assign unused_operation_w = &{1'b0, operation_w[2:0]};
    edrv32_cpu_decode u_decode (
        .instr_i(instr_i),
        .rs1_o(unused_rs1_w),
        .rs2_o(unused_rs2_w),
        .rd_o(unused_rd_w),
        .rs1_used_o(use1_w),
        .rs2_used_o(use2_w),
        .rd_write_o(write_w),
        .imm_o(unused_immediate_w),
        .class_o(class_w),
        .alu_operation_o(operation_w),
        .operand_imm_o(operand_imm_w),
        .illegal_o(illegal_w)
    );
    // Capability includes illegal encodings in the same opcode families.
    assign pipe1_w = instr_i[6:0] == 7'h13 || instr_i[6:0] == 7'h37 ||
        instr_i[6:0] == 7'h17 ||
        (instr_i[6:0] == 7'h33 && instr_i[31:25] != 1) ||
        instr_i[6:0] == 7'h63 || instr_i[6:0] == 7'h6f;
    assign predecode_o = {instr_i[6:0] == 7'h23, instr_i[6:0] == 7'h63,
        class_w == 4'd1 || class_w == 4'd2, class_w == 4'd3,
        class_w == 4'd6 || class_w == 4'd8 || class_w == 4'd10,
        class_w >= 4'd10, class_w == 4'd6 || class_w == 4'd7,
        class_w >= 4'd3 && class_w <= 4'd5, class_w == 4'd10,
        class_w == 4'd8, class_w == 4'd6, class_w, operation_w[3],
        pipe1_w, illegal_w, operand_imm_w, write_w, use2_w, use1_w};
endmodule
