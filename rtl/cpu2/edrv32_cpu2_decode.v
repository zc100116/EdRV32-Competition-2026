// File: edrv32_cpu2_decode.v
// Spec: cpu-v2-spec 2.1-2.3, 5.3, 6.1; fpu-spec 2, 4.2, 6.2.
// Description: One program-slot decoder with domain-qualified dependencies.
// Internal class encoding A=0 B=1 J=2 L=3 M=4 D=5 P=6 S=7; dest none=0 x=1 f=2.
// Clock domain: clk_sys (combinational ID logic).
module edrv32_cpu2_decode #(
    parameter [31:0] FPU_FORMAT = "NONE"
) (
    // Required module clock/reset; this ID decoder has no state.
    input wire clk_i,
    input wire rst_n_i,
    // Original instruction and committed FP control.
    input wire [31:0] instr_i,
    input wire [31:0] pc_i,
    input wire error_i,
    input wire [1:0] csr_fs_i,
    input wire [2:0] csr_frm_i,
    // I02 internal metadata; source domain 0=x, 1=f (including f0).
    output reg [2:0] class_o,
    output wire [4:0] rs1_o,
    output wire [4:0] rs2_o,
    output wire [4:0] rs3_o,
    output reg rs1_used_o,
    output reg rs2_used_o,
    output reg rs3_used_o,
    output reg rs1_domain_o,
    output reg rs2_domain_o,
    output reg rs3_domain_o,
    output wire [4:0] rd_o,
    output reg [1:0] dest_o,
    output reg [31:0] imm_o,
    output reg load_o,
    output reg store_o,
    output reg double_beat_o,
    output reg late_supported_o,
    output reg [2:0] rm_o,
    output reg exception_o,
    output reg [3:0] cause_o,
    output reg [31:0] tval_o
);
    wire [6:0] opcode_w;
    wire [6:0] funct7_w;
    wire [2:0] funct3_w;
    reg legal_w;
    reg fp_w;
    reg rounding_w;
    assign opcode_w = instr_i[6:0];
    assign funct7_w = instr_i[31:25];
    assign funct3_w = instr_i[14:12];
    assign rs1_o = instr_i[19:15];
    assign rs2_o = instr_i[24:20];
    assign rs3_o = instr_i[31:27];
    assign rd_o = instr_i[11:7];
    always @(*) begin
        class_o = 3'd0;
        rs1_used_o = 1'b0;
        rs2_used_o = 1'b0;
        rs3_used_o = 1'b0;
        rs1_domain_o = 1'b0;
        rs2_domain_o = 1'b0;
        rs3_domain_o = 1'b0;
        dest_o = 2'd0;
        imm_o = {{20{instr_i[31]}}, instr_i[31:20]};
        load_o = 1'b0;
        store_o = 1'b0;
        double_beat_o = 1'b0;
        late_supported_o = 1'b0;
        rm_o = (funct3_w == 3'd7) ? csr_frm_i : funct3_w;
        exception_o = 1'b0;
        cause_o = 4'd0;
        tval_o = 32'd0;
        legal_w = 1'b1;
        fp_w = 1'b0;
        rounding_w = 1'b0;
        case (opcode_w)
            7'h37, 7'h17: begin
                dest_o = 2'd1;
                imm_o = {instr_i[31:12], 12'd0};
            end
            7'h6f: begin
                class_o = 3'd1;
                dest_o = 2'd1;
                imm_o = {{11{instr_i[31]}}, instr_i[31], instr_i[19:12],
                    instr_i[20], instr_i[30:21], 1'b0};
            end
            7'h67: begin
                class_o = 3'd2;
                dest_o = 2'd1;
                rs1_used_o = 1'b1;
                legal_w = funct3_w == 3'd0;
            end
            7'h63: begin
                class_o = 3'd1;
                rs1_used_o = 1'b1;
                rs2_used_o = 1'b1;
                late_supported_o = 1'b1;
                imm_o = {{19{instr_i[31]}}, instr_i[31], instr_i[7],
                    instr_i[30:25], instr_i[11:8], 1'b0};
                legal_w = (funct3_w != 3'd2) && (funct3_w != 3'd3);
            end
            7'h03: begin
                class_o = 3'd3;
                dest_o = 2'd1;
                rs1_used_o = 1'b1;
                load_o = 1'b1;
                legal_w = (funct3_w != 3'd3) && (funct3_w < 3'd6);
            end
            7'h23: begin
                class_o = 3'd3;
                rs1_used_o = 1'b1;
                rs2_used_o = 1'b1;
                store_o = 1'b1;
                imm_o = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
                legal_w = funct3_w <= 3'd2;
            end
            7'h13: begin
                dest_o = 2'd1;
                rs1_used_o = 1'b1;
                late_supported_o = (funct3_w != 3'd1) && (funct3_w != 3'd5);
                if (funct3_w == 3'd1)
                    legal_w = funct7_w == 7'd0;
                if (funct3_w == 3'd5)
                    legal_w = (funct7_w == 7'd0) || (funct7_w == 7'h20);
            end
            7'h33: begin
                dest_o = 2'd1;
                rs1_used_o = 1'b1;
                rs2_used_o = 1'b1;
                if (funct7_w == 7'd1) begin
                    class_o = funct3_w[2] ? 3'd5 : 3'd4;
                end else if (funct7_w == 7'h10) begin
                    legal_w = (funct3_w == 3'd2) || (funct3_w == 3'd4) ||
                        (funct3_w == 3'd6);
                    late_supported_o = legal_w;
                end else begin
                    legal_w = (funct7_w == 7'd0) || ((funct7_w == 7'h20) &&
                        ((funct3_w == 3'd0) || (funct3_w == 3'd5)));
                    late_supported_o = (funct3_w != 3'd1) && (funct3_w != 3'd5);
                end
            end
            7'h0f: begin
                class_o = 3'd7;
                // FENCE reserved operands and FENCE.I immediate fields are ignored by RV32.
                legal_w = funct3_w <= 3'd1;
            end
            7'h73: begin
                class_o = 3'd7;
                if (funct3_w == 3'd0) begin
                    case (instr_i)
                        32'h00000073: begin
                            exception_o = 1'b1;
                            cause_o = 4'd11;
                        end
                        32'h00100073: begin
                            exception_o = 1'b1;
                            cause_o = 4'd3;
                            tval_o = pc_i;
                        end
                        32'h30200073, 32'h10500073: legal_w = 1'b1;
                        default: legal_w = 1'b0;
                    endcase
                end else begin
                    legal_w = funct3_w != 3'd4;
                    rs1_used_o = !funct3_w[2];
                    dest_o = 2'd1;
                    if ((instr_i[31:20] >= 12'h001) && (instr_i[31:20] <= 12'h003))
                        fp_w = 1'b1;
                end
            end
            7'h07, 7'h27: begin
                class_o = 3'd6;
                fp_w = 1'b1;
                rs1_used_o = 1'b1;
                load_o = opcode_w == 7'h07;
                store_o = opcode_w == 7'h27;
                double_beat_o = funct3_w == 3'd3;
                legal_w = (funct3_w == 3'd2) ||
                    ((FPU_FORMAT == "FD") && (funct3_w == 3'd3));
                if (store_o) begin
                    rs2_used_o = 1'b1;
                    rs2_domain_o = 1'b1;
                    imm_o = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
                end else begin
                    dest_o = 2'd2;
                end
            end
            7'h43, 7'h47, 7'h4b, 7'h4f: begin
                class_o = 3'd6;
                fp_w = 1'b1;
                rounding_w = 1'b1;
                dest_o = 2'd2;
                rs1_used_o = 1'b1;
                rs2_used_o = 1'b1;
                rs3_used_o = 1'b1;
                rs1_domain_o = 1'b1;
                rs2_domain_o = 1'b1;
                rs3_domain_o = 1'b1;
                legal_w = (instr_i[26:25] == 2'd0) ||
                    ((FPU_FORMAT == "FD") && (instr_i[26:25] == 2'd1));
            end
            7'h53: begin
                class_o = 3'd6;
                fp_w = 1'b1;
                dest_o = 2'd2;
                rs1_used_o = 1'b1;
                rs2_used_o = 1'b1;
                rs1_domain_o = 1'b1;
                rs2_domain_o = 1'b1;
                legal_w = (instr_i[26:25] == 2'd0) ||
                    ((FPU_FORMAT == "FD") && (instr_i[26:25] == 2'd1));
                case (instr_i[31:27])
                    5'b00000, 5'b00001, 5'b00010, 5'b00011: rounding_w = 1'b1;
                    5'b01011: begin
                        rounding_w = 1'b1;
                        rs2_used_o = 1'b0;
                        legal_w = legal_w && (rs2_o == 5'd0);
                    end
                    5'b00100: legal_w = legal_w && (funct3_w <= 3'd2);
                    5'b00101: legal_w = legal_w && (funct3_w <= 3'd1);
                    5'b10100: begin
                        dest_o = 2'd1;
                        legal_w = legal_w && (funct3_w <= 3'd2);
                    end
                    5'b11000, 5'b11010: begin
                        rounding_w = 1'b1;
                        rs2_used_o = 1'b0;
                        legal_w = legal_w && (rs2_o <= 5'd1);
                        if (instr_i[28])
                            rs1_domain_o = 1'b0;
                        else
                            dest_o = 2'd1;
                    end
                    5'b01000: begin
                        rounding_w = 1'b1;
                        rs2_used_o = 1'b0;
                        legal_w = (FPU_FORMAT == "FD") &&
                            (((instr_i[26:25] == 2'd0) && (rs2_o == 5'd1)) ||
                            ((instr_i[26:25] == 2'd1) && (rs2_o == 5'd0)));
                    end
                    5'b11100: begin
                        dest_o = 2'd1;
                        rs2_used_o = 1'b0;
                        legal_w = legal_w && (rs2_o == 5'd0) &&
                            ((funct3_w == 3'd1) ||
                            ((funct3_w == 3'd0) && (instr_i[26:25] == 2'd0)));
                    end
                    5'b11110: begin
                        rs1_domain_o = 1'b0;
                        rs2_used_o = 1'b0;
                        legal_w = (instr_i[26:25] == 2'd0) &&
                            (rs2_o == 5'd0) && (funct3_w == 3'd0);
                    end
                    default: legal_w = 1'b0;
                endcase
            end
            default: legal_w = 1'b0;
        endcase
        begin
        if (fp_w && ((FPU_FORMAT == "NONE") || (csr_fs_i == 2'd0)))
            legal_w = 1'b0;
        if (rounding_w && (rm_o > 3'd4))
            legal_w = 1'b0;
        if ((dest_o == 2'd1) && (rd_o == 5'd0))
            dest_o = 2'd0;
        if (!legal_w) begin
            exception_o = 1'b1;
            cause_o = 4'd2;
            tval_o = instr_i;
        end
        if (pc_i[1:0] != 2'd0) begin
            exception_o = 1'b1;
            cause_o = 4'd0;
            tval_o = pc_i;
        end else if (error_i) begin
            exception_o = 1'b1;
            cause_o = 4'd1;
            tval_o = pc_i;
        end
        end
        if (exception_o) begin
            dest_o = 2'd0;
            rs1_used_o = 1'b0;
            rs2_used_o = 1'b0;
            rs3_used_o = 1'b0;
            load_o = 1'b0;
            store_o = 1'b0;
            double_beat_o = 1'b0;
            late_supported_o = 1'b0;
        end
    end
    /* verilator lint_off UNUSEDSIGNAL */
    wire unused_w = ^{clk_i, rst_n_i};
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
