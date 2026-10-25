// edrv32_cpu_rvc.v
// cpu-spec 2.1, 4.1
// Expand RV32C halfwords into canonical RV32 instructions.
// Identify reserved encodings and preserve the harmless effects of HINTs.
// Clock domain: 组合逻辑.
module edrv32_cpu_rvc (
    // One compressed halfword. Quadrant 3 belongs to the 32-bit fetch path.
    input wire [15:0] instr_i,
    // Canonical RV32 instruction; legal HINTs retain their harmless operation.
    output reg [31:0] instr_o,
    output reg illegal_o
);
    wire [4:0] rd_w;
    wire [4:0] rs2_w;
    wire [4:0] compact_rs1_w;
    wire [4:0] compact_rs2_w;
    wire [11:0] immediate_w;
    wire [20:0] unused_jump_w;
    wire [12:0] unused_branch_w;
    reg [11:0] offset_w;
    assign rd_w = instr_i[11:7];
    assign rs2_w = instr_i[6:2];
    assign compact_rs1_w = {2'b01, instr_i[9:7]};
    assign compact_rs2_w = {2'b01, instr_i[4:2]};
    assign immediate_w = {{7{instr_i[12]}}, instr_i[6:2]};
    assign unused_jump_w = {{10{instr_i[12]}}, instr_i[8], instr_i[10:9],
        instr_i[6], instr_i[7], instr_i[2], instr_i[11], instr_i[5:3], 1'b0};
    assign unused_branch_w = {{5{instr_i[12]}}, instr_i[6:5], instr_i[2],
        instr_i[11:10], instr_i[4:3], 1'b0};
    always @(*) begin
        instr_o = 32'h00000013;
        illegal_o = 1'b0;
        offset_w = 0;
        case (instr_i[1:0])
            2'b00: begin
                case (instr_i[15:13])
                    3'b000: begin // ADDI4SPN
                        offset_w = {2'b0, instr_i[10:7], instr_i[12:11],
                            instr_i[5], instr_i[6], 2'b0};
                        instr_o = {offset_w, 5'd2, 3'b000, compact_rs2_w, 7'h13};
                        illegal_o = offset_w == 0;
                    end
                    3'b010: begin // LW
                        offset_w = {5'b0, instr_i[5], instr_i[12:10], instr_i[6], 2'b0};
                        instr_o = {offset_w, compact_rs1_w, 3'b010, compact_rs2_w, 7'h03};
                    end
                    3'b110: begin // SW
                        offset_w = {5'b0, instr_i[5], instr_i[12:10], instr_i[6], 2'b0};
                        instr_o = {offset_w[11:5], compact_rs2_w, compact_rs1_w,
                            3'b010, offset_w[4:0], 7'h23};
                    end
                    default: illegal_o = 1'b1;
                endcase
            end
            2'b01: begin
                case (instr_i[15:13])
                    3'b000: instr_o = {immediate_w, rd_w, 3'b000, rd_w, 7'h13};
                    3'b001, 3'b101: begin // JAL / J
                        instr_o = {unused_jump_w[20], unused_jump_w[10:1],
                            unused_jump_w[11], unused_jump_w[19:12],
                            4'b0, !instr_i[15], 7'h6f};
                    end
                    3'b010: instr_o = {immediate_w, 5'b0, 3'b000, rd_w, 7'h13};
                    3'b011: begin
                        if (rd_w == 2) begin // ADDI16SP
                            offset_w = {{3{instr_i[12]}}, instr_i[4:3], instr_i[5],
                                instr_i[2], instr_i[6], 4'b0};
                            instr_o = {offset_w, 5'd2, 3'b000, 5'd2, 7'h13};
                            illegal_o = offset_w == 0;
                        end else begin
                            instr_o = {{15{instr_i[12]}}, instr_i[6:2], rd_w, 7'h37};
                            illegal_o = immediate_w == 0;
                        end
                    end
                    3'b100: begin
                        case (instr_i[11:10])
                            2'b00, 2'b01: begin // SRLI / SRAI
                                instr_o = {1'b0, instr_i[10], 5'b0, instr_i[6:2],
                                    compact_rs1_w, 3'b101, compact_rs1_w, 7'h13};
                                illegal_o = instr_i[12];
                            end
                            2'b10: instr_o = {immediate_w, compact_rs1_w, 3'b111,
                                compact_rs1_w, 7'h13};
                            2'b11: begin
                                illegal_o = instr_i[12]; // RV64 SUBW/ADDW and reserved.
                                case (instr_i[6:5])
                                    2'b00: instr_o = {7'h20, compact_rs2_w, compact_rs1_w,
                                        3'b000, compact_rs1_w, 7'h33};
                                    2'b01: instr_o = {7'b0, compact_rs2_w, compact_rs1_w,
                                        3'b100, compact_rs1_w, 7'h33};
                                    2'b10: instr_o = {7'b0, compact_rs2_w, compact_rs1_w,
                                        3'b110, compact_rs1_w, 7'h33};
                                    2'b11: instr_o = {7'b0, compact_rs2_w, compact_rs1_w,
                                        3'b111, compact_rs1_w, 7'h33};
                                    default: instr_o = 32'h00000013;
                                endcase
                            end
                            default: illegal_o = 1'b1;
                        endcase
                    end
                    3'b110, 3'b111: begin
                        instr_o = {unused_branch_w[12], unused_branch_w[10:5], 5'b0, compact_rs1_w,
                            2'b00, instr_i[13], unused_branch_w[4:1], unused_branch_w[11], 7'h63};
                    end
                    default: illegal_o = 1'b1;
                endcase
            end
            2'b10: begin
                case (instr_i[15:13])
                    3'b000: begin
                        instr_o = {7'b0, instr_i[6:2], rd_w, 3'b001, rd_w, 7'h13};
                        illegal_o = instr_i[12];
                    end
                    3'b010: begin
                        offset_w = {4'b0, instr_i[3:2], instr_i[12], instr_i[6:4], 2'b0};
                        instr_o = {offset_w, 5'd2, 3'b010, rd_w, 7'h03};
                        illegal_o = rd_w == 0;
                    end
                    3'b100: begin
                        if (rs2_w == 0) begin
                            if (instr_i[12] && rd_w == 0)
                                instr_o = 32'h00100073;
                            else begin
                                instr_o = {12'b0, rd_w, 3'b000, 4'b0, instr_i[12], 7'h67};
                                illegal_o = rd_w == 0;
                            end
                        end else begin
                            instr_o = {7'b0, rs2_w, instr_i[12] ? rd_w : 5'b0,
                                3'b000, rd_w, 7'h33};
                        end
                    end
                    3'b110: begin
                        offset_w = {4'b0, instr_i[8:7], instr_i[12:9], 2'b0};
                        instr_o = {offset_w[11:5], rs2_w, 5'd2, 3'b010,
                            offset_w[4:0], 7'h23};
                    end
                    default: illegal_o = 1'b1;
                endcase
            end
            default: illegal_o = 1'b1;
        endcase
    end
endmodule
