// ============================================================================
// File        : edrv32_decoder.v
// Description : Fixed RV32IM + Zicsr/Zifencei scalar decoder. RVC instructions
//               are converted to canonical 32-bit instructions in ALIGN first.
// Notes       : Defaults are side-effect free and illegal. A case arm must
//               explicitly clear illegal_o before it can write or issue.
// ============================================================================
`include "edrv32_isa.vh"
`include "edrv32_uop.vh"
`include "edrv32_bus.vh"

module edrv32_decoder (
    input  wire [31:0]                       instr_i,
    output wire [`EDRV32_REG_ADDR_W-1:0]     rs1_addr_o,
    output wire [`EDRV32_REG_ADDR_W-1:0]     rs2_addr_o,
    output wire [`EDRV32_REG_ADDR_W-1:0]     rd_addr_o,
    output reg                               uses_rs1_o,
    output reg                               uses_rs2_o,
    output reg                               rd_write_o,
    output reg  [`EDRV32_OP_CLASS_W-1:0]     op_class_o,
    output reg  [`EDRV32_ALU_OP_W-1:0]       alu_op_o,
    output reg  [`EDRV32_OP_A_SEL_W-1:0]     op_a_sel_o,
    output reg                               op_b_imm_o,
    output reg  [`EDRV32_IMM_SEL_W-1:0]      imm_sel_o,
    output reg  [`EDRV32_BRANCH_OP_W-1:0]    branch_op_o,
    output reg  [`BUS_SZ_W-1:0]              mem_size_o,
    output reg                               mem_unsigned_o,
    output reg  [`EDRV32_MDU_OP_W-1:0]       mdu_op_o,
    output reg  [`EDRV32_CSR_OP_W-1:0]       csr_op_o,
    output reg                               csr_imm_o,
    output reg                               fence_o,
    output reg                               fencei_o,
    output reg                               ecall_o,
    output reg                               ebreak_o,
    output reg                               mret_o,
    output reg                               wfi_o,
    output reg                               illegal_o
);

    // Canonical field extraction.  ALIGN has already expanded any RV32C
    // instruction before it reaches this decoder.
    wire [6:0] opcode_w = instr_i[6:0];
    wire [2:0] funct3_w = instr_i[14:12];
    wire [6:0] funct7_w = instr_i[31:25];

    assign rs1_addr_o = instr_i[19:15];
    assign rs2_addr_o = instr_i[24:20];
    assign rd_addr_o  = instr_i[11:7];

    // Safe illegal defaults prevent a partially decoded instruction from
    // writing architectural state.  Each legal encoding explicitly overrides
    // only the controls it owns.
    always @* begin
        uses_rs1_o    = 1'b0;
        uses_rs2_o    = 1'b0;
        rd_write_o    = 1'b0;
        op_class_o    = `EDRV32_OP_NONE;
        alu_op_o      = `EDRV32_ALU_ADD;
        op_a_sel_o    = `EDRV32_OP_A_RS1;
        op_b_imm_o    = 1'b0;
        imm_sel_o     = `EDRV32_IMM_NONE;
        branch_op_o   = `EDRV32_BRANCH_NONE;
        mem_size_o    = `BUS_SZ_WORD;
        mem_unsigned_o = 1'b0;
        mdu_op_o      = `EDRV32_MDU_MUL;
        csr_op_o      = `EDRV32_CSR_NONE;
        csr_imm_o     = 1'b0;
        fence_o       = 1'b0;
        fencei_o     = 1'b0;
        ecall_o       = 1'b0;
        ebreak_o      = 1'b0;
        mret_o        = 1'b0;
        wfi_o         = 1'b0;
        illegal_o     = 1'b1;

        case (opcode_w)
            // Upper-immediate and direct control-transfer instructions.
            `EDRV32_OPCODE_LUI: begin
                illegal_o  = 1'b0;
                rd_write_o = (rd_addr_o != 5'd0);
                op_class_o = `EDRV32_OP_ALU;
                alu_op_o   = `EDRV32_ALU_COPY_B;
                op_a_sel_o = `EDRV32_OP_A_ZERO;
                op_b_imm_o = 1'b1;
                imm_sel_o  = `EDRV32_IMM_U;
            end

            `EDRV32_OPCODE_AUIPC: begin
                illegal_o  = 1'b0;
                rd_write_o = (rd_addr_o != 5'd0);
                op_class_o = `EDRV32_OP_ALU;
                alu_op_o   = `EDRV32_ALU_ADD;
                op_a_sel_o = `EDRV32_OP_A_PC;
                op_b_imm_o = 1'b1;
                imm_sel_o  = `EDRV32_IMM_U;
            end

            `EDRV32_OPCODE_JAL: begin
                illegal_o  = 1'b0;
                rd_write_o = (rd_addr_o != 5'd0);
                op_class_o = `EDRV32_OP_JUMP;
                op_a_sel_o = `EDRV32_OP_A_PC;
                op_b_imm_o = 1'b1;
                imm_sel_o  = `EDRV32_IMM_J;
            end

            `EDRV32_OPCODE_JALR: begin
                if (funct3_w == 3'b000) begin
                    illegal_o  = 1'b0;
                    uses_rs1_o = 1'b1;
                    rd_write_o = (rd_addr_o != 5'd0);
                    op_class_o = `EDRV32_OP_JUMP;
                    op_a_sel_o = `EDRV32_OP_A_RS1;
                    op_b_imm_o = 1'b1;
                    imm_sel_o  = `EDRV32_IMM_I;
                end
            end

            `EDRV32_OPCODE_BRANCH: begin
                op_class_o = `EDRV32_OP_BRANCH;
                uses_rs1_o = 1'b1;
                uses_rs2_o = 1'b1;
                imm_sel_o  = `EDRV32_IMM_B;
                case (funct3_w)
                    3'b000: begin
                        illegal_o   = 1'b0;
                        branch_op_o = `EDRV32_BRANCH_EQ;
                    end
                    3'b001: begin
                        illegal_o   = 1'b0;
                        branch_op_o = `EDRV32_BRANCH_NE;
                    end
                    3'b100: begin
                        illegal_o   = 1'b0;
                        branch_op_o = `EDRV32_BRANCH_LT;
                    end
                    3'b101: begin
                        illegal_o   = 1'b0;
                        branch_op_o = `EDRV32_BRANCH_GE;
                    end
                    3'b110: begin
                        illegal_o   = 1'b0;
                        branch_op_o = `EDRV32_BRANCH_LTU;
                    end
                    3'b111: begin
                        illegal_o   = 1'b0;
                        branch_op_o = `EDRV32_BRANCH_GEU;
                    end
                    default: begin end
                endcase
            end

            // Loads and stores share EX address generation but retain distinct
            // size and sign-extension controls for the LSU.
            `EDRV32_OPCODE_LOAD: begin
                op_class_o = `EDRV32_OP_LOAD;
                uses_rs1_o = 1'b1;
                rd_write_o = (rd_addr_o != 5'd0);
                alu_op_o   = `EDRV32_ALU_ADD;
                op_b_imm_o = 1'b1;
                imm_sel_o  = `EDRV32_IMM_I;
                case (funct3_w)
                    3'b000: begin
                        illegal_o      = 1'b0;
                        mem_size_o     = `BUS_SZ_BYTE;
                        mem_unsigned_o = 1'b0;
                    end
                    3'b001: begin
                        illegal_o      = 1'b0;
                        mem_size_o     = `BUS_SZ_HALF;
                        mem_unsigned_o = 1'b0;
                    end
                    3'b010: begin
                        illegal_o      = 1'b0;
                        mem_size_o     = `BUS_SZ_WORD;
                        mem_unsigned_o = 1'b0;
                    end
                    3'b100: begin
                        illegal_o      = 1'b0;
                        mem_size_o     = `BUS_SZ_BYTE;
                        mem_unsigned_o = 1'b1;
                    end
                    3'b101: begin
                        illegal_o      = 1'b0;
                        mem_size_o     = `BUS_SZ_HALF;
                        mem_unsigned_o = 1'b1;
                    end
                    default: begin end
                endcase
                if (illegal_o)
                    rd_write_o = 1'b0;
            end

            `EDRV32_OPCODE_STORE: begin
                op_class_o = `EDRV32_OP_STORE;
                uses_rs1_o = 1'b1;
                uses_rs2_o = 1'b1;
                alu_op_o   = `EDRV32_ALU_ADD;
                op_b_imm_o = 1'b1;
                imm_sel_o  = `EDRV32_IMM_S;
                case (funct3_w)
                    3'b000: begin
                        illegal_o  = 1'b0;
                        mem_size_o = `BUS_SZ_BYTE;
                    end
                    3'b001: begin
                        illegal_o  = 1'b0;
                        mem_size_o = `BUS_SZ_HALF;
                    end
                    3'b010: begin
                        illegal_o  = 1'b0;
                        mem_size_o = `BUS_SZ_WORD;
                    end
                    default: begin end
                endcase
            end

            // Integer immediate operations.
            `EDRV32_OPCODE_OP_IMM: begin
                op_class_o = `EDRV32_OP_ALU;
                uses_rs1_o = 1'b1;
                rd_write_o = (rd_addr_o != 5'd0);
                op_b_imm_o = 1'b1;
                imm_sel_o  = `EDRV32_IMM_I;
                case (funct3_w)
                    3'b000: begin
                        illegal_o = 1'b0;
                        alu_op_o  = `EDRV32_ALU_ADD;
                    end
                    3'b010: begin
                        illegal_o = 1'b0;
                        alu_op_o  = `EDRV32_ALU_SLT;
                    end
                    3'b011: begin
                        illegal_o = 1'b0;
                        alu_op_o  = `EDRV32_ALU_SLTU;
                    end
                    3'b100: begin
                        illegal_o = 1'b0;
                        alu_op_o  = `EDRV32_ALU_XOR;
                    end
                    3'b110: begin
                        illegal_o = 1'b0;
                        alu_op_o  = `EDRV32_ALU_OR;
                    end
                    3'b111: begin
                        illegal_o = 1'b0;
                        alu_op_o  = `EDRV32_ALU_AND;
                    end
                    3'b001: begin
                        if (funct7_w == 7'b0000000) begin
                            illegal_o = 1'b0;
                            alu_op_o  = `EDRV32_ALU_SLL;
                        end
                    end
                    3'b101: begin
                        if (funct7_w == 7'b0000000) begin
                            illegal_o = 1'b0;
                            alu_op_o  = `EDRV32_ALU_SRL;
                        end else if (funct7_w == 7'b0100000) begin
                            illegal_o = 1'b0;
                            alu_op_o  = `EDRV32_ALU_SRA;
                        end
                    end
                    default: begin end
                endcase
                if (illegal_o)
                    rd_write_o = 1'b0;
            end

            // Register-register ALU and RV32M operations.  funct7=0000001
            // redirects the complete funct3 space to the decoupled MDU.
            `EDRV32_OPCODE_OP: begin
                uses_rs1_o = 1'b1;
                uses_rs2_o = 1'b1;
                rd_write_o = (rd_addr_o != 5'd0);
                if (funct7_w == 7'b0000001) begin
                    illegal_o  = 1'b0;
                    op_class_o = `EDRV32_OP_MDU;
                    mdu_op_o   = funct3_w;
                end else begin
                    op_class_o = `EDRV32_OP_ALU;
                    case (funct3_w)
                        3'b000: begin
                            if (funct7_w == 7'b0000000) begin
                                illegal_o = 1'b0;
                                alu_op_o  = `EDRV32_ALU_ADD;
                            end else if (funct7_w == 7'b0100000) begin
                                illegal_o = 1'b0;
                                alu_op_o  = `EDRV32_ALU_SUB;
                            end
                        end
                        3'b001: begin
                            if (funct7_w == 7'b0000000) begin
                                illegal_o = 1'b0;
                                alu_op_o  = `EDRV32_ALU_SLL;
                            end
                        end
                        3'b010: begin
                            if (funct7_w == 7'b0000000) begin
                                illegal_o = 1'b0;
                                alu_op_o  = `EDRV32_ALU_SLT;
                            end
                        end
                        3'b011: begin
                            if (funct7_w == 7'b0000000) begin
                                illegal_o = 1'b0;
                                alu_op_o  = `EDRV32_ALU_SLTU;
                            end
                        end
                        3'b100: begin
                            if (funct7_w == 7'b0000000) begin
                                illegal_o = 1'b0;
                                alu_op_o  = `EDRV32_ALU_XOR;
                            end
                        end
                        3'b101: begin
                            if (funct7_w == 7'b0000000) begin
                                illegal_o = 1'b0;
                                alu_op_o  = `EDRV32_ALU_SRL;
                            end else if (funct7_w == 7'b0100000) begin
                                illegal_o = 1'b0;
                                alu_op_o  = `EDRV32_ALU_SRA;
                            end
                        end
                        3'b110: begin
                            if (funct7_w == 7'b0000000) begin
                                illegal_o = 1'b0;
                                alu_op_o  = `EDRV32_ALU_OR;
                            end
                        end
                        3'b111: begin
                            if (funct7_w == 7'b0000000) begin
                                illegal_o = 1'b0;
                                alu_op_o  = `EDRV32_ALU_AND;
                            end
                        end
                        default: begin end
                    endcase
                end
                if (illegal_o)
                    rd_write_o = 1'b0;
            end

            // Memory ordering instructions have no GPR result.
            `EDRV32_OPCODE_MISC_MEM: begin
                if (funct3_w == 3'b000) begin
                    illegal_o  = 1'b0;
                    op_class_o = `EDRV32_OP_FENCE;
                    fence_o    = 1'b1;
                end else if (funct3_w == 3'b001) begin
                    illegal_o  = 1'b0;
                    op_class_o = `EDRV32_OP_FENCE;
                    fencei_o  = 1'b1;
                end
            end

            // Privileged SYSTEM encodings and the six Zicsr instruction forms.
            `EDRV32_OPCODE_SYSTEM: begin
                if (funct3_w == 3'b000) begin
                    op_class_o = `EDRV32_OP_SYSTEM;
                    case (instr_i)
                        `EDRV32_INSN_ECALL: begin
                            illegal_o = 1'b0;
                            ecall_o   = 1'b1;
                        end
                        `EDRV32_INSN_EBREAK: begin
                            illegal_o = 1'b0;
                            ebreak_o  = 1'b1;
                        end
                        `EDRV32_INSN_MRET: begin
                            illegal_o = 1'b0;
                            mret_o    = 1'b1;
                        end
                        `EDRV32_INSN_WFI: begin
                            illegal_o = 1'b0;
                            wfi_o     = 1'b1;
                        end
                        default: begin end
                    endcase
                end else begin
                    op_class_o = `EDRV32_OP_CSR;
                    rd_write_o = (rd_addr_o != 5'd0);
                    case (funct3_w)
                        3'b001: begin
                            illegal_o  = 1'b0;
                            uses_rs1_o = 1'b1;
                            csr_op_o   = `EDRV32_CSR_WRITE;
                        end
                        3'b010: begin
                            illegal_o  = 1'b0;
                            uses_rs1_o = 1'b1;
                            csr_op_o   = `EDRV32_CSR_SET;
                        end
                        3'b011: begin
                            illegal_o  = 1'b0;
                            uses_rs1_o = 1'b1;
                            csr_op_o   = `EDRV32_CSR_CLEAR;
                        end
                        3'b101: begin
                            illegal_o = 1'b0;
                            csr_imm_o = 1'b1;
                            imm_sel_o = `EDRV32_IMM_Z;
                            csr_op_o  = `EDRV32_CSR_WRITE;
                        end
                        3'b110: begin
                            illegal_o = 1'b0;
                            csr_imm_o = 1'b1;
                            imm_sel_o = `EDRV32_IMM_Z;
                            csr_op_o  = `EDRV32_CSR_SET;
                        end
                        3'b111: begin
                            illegal_o = 1'b0;
                            csr_imm_o = 1'b1;
                            imm_sel_o = `EDRV32_IMM_Z;
                            csr_op_o  = `EDRV32_CSR_CLEAR;
                        end
                        default: begin end
                    endcase
                    if (illegal_o)
                        rd_write_o = 1'b0;
                end
            end

            default: begin end
        endcase
    end

endmodule
