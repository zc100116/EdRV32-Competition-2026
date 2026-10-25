// ============================================================================
// File        : edrv32_rvc_decompress.v
// Description : RV32C 16-bit instruction to canonical RV32I instruction.
// Notes       : Integer RV32C only. Encodings assigned to compressed floating
//               loads/stores or RV64 operations are unconditionally illegal.
//               Immediate bits are first placed by semantic bit number, then
//               passed through ordinary R/I/S/B/U/J encoders.
// ============================================================================
`include "edrv32_isa.vh"

module edrv32_rvc_decompress (
    input  wire [15:0] c_instr_i,
    output reg  [31:0] instr_o,
    output reg         illegal_o
);

    // Compressed register aliases and the primary opcode fields.
    wire [1:0] quadrant_w = c_instr_i[1:0];
    wire [2:0] funct3_w   = c_instr_i[15:13];
    wire [4:0] rd_w       = c_instr_i[11:7];
    wire [4:0] rs2_w      = c_instr_i[6:2];
    wire [4:0] rd_prime_w  = {2'b01, c_instr_i[4:2]};
    wire [4:0] rs1_prime_w = {2'b01, c_instr_i[9:7]};
    wire [4:0] rs2_prime_w = {2'b01, c_instr_i[4:2]};

    reg [31:0] imm_w;

    // Canonical RV32 instruction encoders. Immediate assembly stays in the
    // quadrant decoder so each compressed encoding can be audited in place.
    function [31:0] enc_r;
        input [6:0] funct7_i;
        input [4:0] rs2_i;
        input [4:0] rs1_i;
        input [2:0] funct3_i;
        input [4:0] rd_i;
        begin
            enc_r = {funct7_i, rs2_i, rs1_i, funct3_i, rd_i,
                     `EDRV32_OPCODE_OP};
        end
    endfunction

    function [31:0] enc_i;
        input [31:0] imm_i;
        input [4:0] rs1_i;
        input [2:0] funct3_i;
        input [4:0] rd_i;
        input [6:0] opcode_i;
        begin
            enc_i = {imm_i[11:0], rs1_i, funct3_i, rd_i, opcode_i};
        end
    endfunction

    function [31:0] enc_s;
        input [31:0] imm_i;
        input [4:0] rs2_i;
        input [4:0] rs1_i;
        input [2:0] funct3_i;
        begin
            enc_s = {imm_i[11:5], rs2_i, rs1_i, funct3_i, imm_i[4:0],
                     `EDRV32_OPCODE_STORE};
        end
    endfunction

    function [31:0] enc_b;
        input [31:0] imm_i;
        input [4:0] rs2_i;
        input [4:0] rs1_i;
        input [2:0] funct3_i;
        begin
            enc_b = {imm_i[12], imm_i[10:5], rs2_i, rs1_i, funct3_i,
                     imm_i[4:1], imm_i[11], `EDRV32_OPCODE_BRANCH};
        end
    endfunction

    function [31:0] enc_u;
        input [31:0] imm_i;
        input [4:0] rd_i;
        begin
            enc_u = {imm_i[31:12], rd_i, `EDRV32_OPCODE_LUI};
        end
    endfunction

    function [31:0] enc_j;
        input [31:0] imm_i;
        input [4:0] rd_i;
        begin
            enc_j = {imm_i[20], imm_i[10:1], imm_i[11], imm_i[19:12],
                     rd_i, `EDRV32_OPCODE_JAL};
        end
    endfunction

    // Decode one compressed instruction into a canonical 32-bit instruction.
    // Defaults are safe for illegal or reserved encodings.
    always @* begin
        instr_o   = 32'd0;
        illegal_o = 1'b0;
        imm_w     = 32'd0;

        case (quadrant_w)
            // Quadrant 0: stack-relative immediate and compact memory forms.
            2'b00: begin
                case (funct3_w)
                    3'b000: begin // C.ADDI4SPN
                        imm_w = {22'd0, c_instr_i[10:7], c_instr_i[12:11],
                                 c_instr_i[5], c_instr_i[6], 2'b00};
                        if (imm_w == 32'd0)
                            illegal_o = 1'b1;
                        instr_o = enc_i(imm_w, 5'd2, 3'b000, rd_prime_w,
                                        `EDRV32_OPCODE_OP_IMM);
                    end
                    3'b010: begin // C.LW
                        imm_w = {25'd0, c_instr_i[5], c_instr_i[12:10],
                                 c_instr_i[6], 2'b00};
                        instr_o = enc_i(imm_w, rs1_prime_w, 3'b010,
                                        rd_prime_w, `EDRV32_OPCODE_LOAD);
                    end
                    3'b110: begin // C.SW
                        imm_w = {25'd0, c_instr_i[5], c_instr_i[12:10],
                                 c_instr_i[6], 2'b00};
                        instr_o = enc_s(imm_w, rs2_prime_w, rs1_prime_w,
                                        3'b010);
                    end
                    // 001/011/101/111 are FP memory operations; 100 is reserved.
                    default: illegal_o = 1'b1;
                endcase
            end

            // Quadrant 1: immediate ALU, control-flow and compact register ALU.
            2'b01: begin
                case (funct3_w)
                    3'b000: begin // C.NOP / C.ADDI
                        imm_w = {{26{c_instr_i[12]}}, c_instr_i[12],
                                 c_instr_i[6:2]};
                        instr_o = enc_i(imm_w, rd_w, 3'b000, rd_w,
                                        `EDRV32_OPCODE_OP_IMM);
                    end
                    3'b001: begin // C.JAL (RV32 only)
                        imm_w = {{20{c_instr_i[12]}}, c_instr_i[12],
                                 c_instr_i[8], c_instr_i[10:9], c_instr_i[6],
                                 c_instr_i[7], c_instr_i[2], c_instr_i[11],
                                 c_instr_i[5:3], 1'b0};
                        instr_o = enc_j(imm_w, 5'd1);
                    end
                    3'b010: begin // C.LI
                        imm_w = {{26{c_instr_i[12]}}, c_instr_i[12],
                                 c_instr_i[6:2]};
                        instr_o = enc_i(imm_w, 5'd0, 3'b000, rd_w,
                                        `EDRV32_OPCODE_OP_IMM);
                    end
                    3'b011: begin
                        if (rd_w == 5'd2) begin // C.ADDI16SP
                            imm_w = {{22{c_instr_i[12]}}, c_instr_i[12],
                                     c_instr_i[4:3], c_instr_i[5],
                                     c_instr_i[2], c_instr_i[6], 4'b0000};
                            if (imm_w == 32'd0)
                                illegal_o = 1'b1;
                            instr_o = enc_i(imm_w, 5'd2, 3'b000, 5'd2,
                                            `EDRV32_OPCODE_OP_IMM);
                        end else begin // C.LUI or rd=x0 HINT
                            imm_w = {{14{c_instr_i[12]}}, c_instr_i[12],
                                     c_instr_i[6:2], 12'd0};
                            if (imm_w == 32'd0)
                                illegal_o = 1'b1;
                            instr_o = enc_u(imm_w, rd_w);
                        end
                    end
                    3'b100: begin
                        case (c_instr_i[11:10])
                            2'b00: begin // C.SRLI
                                imm_w = {26'd0, c_instr_i[12], c_instr_i[6:2]};
                                if (c_instr_i[12])
                                    illegal_o = 1'b1;
                                instr_o = enc_i(imm_w, rs1_prime_w, 3'b101,
                                                rs1_prime_w, `EDRV32_OPCODE_OP_IMM);
                            end
                            2'b01: begin // C.SRAI
                                imm_w = {20'd0, 6'b010000, c_instr_i[12],
                                         c_instr_i[6:2]};
                                if (c_instr_i[12])
                                    illegal_o = 1'b1;
                                instr_o = enc_i(imm_w, rs1_prime_w, 3'b101,
                                                rs1_prime_w, `EDRV32_OPCODE_OP_IMM);
                            end
                            2'b10: begin // C.ANDI
                                imm_w = {{26{c_instr_i[12]}}, c_instr_i[12],
                                         c_instr_i[6:2]};
                                instr_o = enc_i(imm_w, rs1_prime_w, 3'b111,
                                                rs1_prime_w, `EDRV32_OPCODE_OP_IMM);
                            end
                            2'b11: begin
                                if (c_instr_i[12]) begin
                                    // C.SUBW/C.ADDW are RV64-only.
                                    illegal_o = 1'b1;
                                end else begin
                                    case (c_instr_i[6:5])
                                        2'b00: instr_o = enc_r(7'b0100000, rs2_prime_w,
                                                               rs1_prime_w, 3'b000, rs1_prime_w);
                                        2'b01: instr_o = enc_r(7'b0000000, rs2_prime_w,
                                                               rs1_prime_w, 3'b100, rs1_prime_w);
                                        2'b10: instr_o = enc_r(7'b0000000, rs2_prime_w,
                                                               rs1_prime_w, 3'b110, rs1_prime_w);
                                        2'b11: instr_o = enc_r(7'b0000000, rs2_prime_w,
                                                               rs1_prime_w, 3'b111, rs1_prime_w);
                                    endcase
                                end
                            end
                        endcase
                    end
                    3'b101: begin // C.J
                        imm_w = {{20{c_instr_i[12]}}, c_instr_i[12],
                                 c_instr_i[8], c_instr_i[10:9], c_instr_i[6],
                                 c_instr_i[7], c_instr_i[2], c_instr_i[11],
                                 c_instr_i[5:3], 1'b0};
                        instr_o = enc_j(imm_w, 5'd0);
                    end
                    3'b110: begin // C.BEQZ
                        imm_w = {{23{c_instr_i[12]}}, c_instr_i[12],
                                 c_instr_i[6:5], c_instr_i[2],
                                 c_instr_i[11:10], c_instr_i[4:3], 1'b0};
                        instr_o = enc_b(imm_w, 5'd0, rs1_prime_w, 3'b000);
                    end
                    3'b111: begin // C.BNEZ
                        imm_w = {{23{c_instr_i[12]}}, c_instr_i[12],
                                 c_instr_i[6:5], c_instr_i[2],
                                 c_instr_i[11:10], c_instr_i[4:3], 1'b0};
                        instr_o = enc_b(imm_w, 5'd0, rs1_prime_w, 3'b001);
                    end
                endcase
            end

            // Quadrant 2: shifts, stack-pointer memory and register transfers.
            2'b10: begin
                case (funct3_w)
                    3'b000: begin // C.SLLI
                        imm_w = {26'd0, c_instr_i[12], c_instr_i[6:2]};
                        if (c_instr_i[12])
                            illegal_o = 1'b1;
                        instr_o = enc_i(imm_w, rd_w, 3'b001, rd_w,
                                        `EDRV32_OPCODE_OP_IMM);
                    end
                    3'b010: begin // C.LWSP
                        imm_w = {24'd0, c_instr_i[3:2], c_instr_i[12],
                                 c_instr_i[6:4], 2'b00};
                        if (rd_w == 5'd0)
                            illegal_o = 1'b1;
                        instr_o = enc_i(imm_w, 5'd2, 3'b010, rd_w,
                                        `EDRV32_OPCODE_LOAD);
                    end
                    3'b100: begin
                        if (!c_instr_i[12]) begin
                            if (rs2_w == 5'd0) begin // C.JR
                                if (rd_w == 5'd0)
                                    illegal_o = 1'b1;
                                instr_o = enc_i(32'd0, rd_w, 3'b000, 5'd0,
                                                `EDRV32_OPCODE_JALR);
                            end else begin // C.MV / rd=x0 HINT
                                instr_o = enc_r(7'b0000000, rs2_w, 5'd0,
                                                3'b000, rd_w);
                            end
                        end else begin
                            if ((rd_w == 5'd0) && (rs2_w == 5'd0)) begin
                                instr_o = `EDRV32_INSN_EBREAK;
                            end else if (rs2_w == 5'd0) begin // C.JALR
                                instr_o = enc_i(32'd0, rd_w, 3'b000, 5'd1,
                                                `EDRV32_OPCODE_JALR);
                            end else begin // C.ADD / rd=x0 HINT
                                instr_o = enc_r(7'b0000000, rs2_w, rd_w,
                                                3'b000, rd_w);
                            end
                        end
                    end
                    3'b110: begin // C.SWSP
                        imm_w = {24'd0, c_instr_i[8:7], c_instr_i[12:9],
                                 2'b00};
                        instr_o = enc_s(imm_w, rs2_w, 5'd2, 3'b010);
                    end
                    // 001/011/101/111 are compressed FP memory operations.
                    default: illegal_o = 1'b1;
                endcase
            end

            // 11 starts an ordinary 32-bit instruction and is not an RVC input.
            default: illegal_o = 1'b1;
        endcase
    end

endmodule
