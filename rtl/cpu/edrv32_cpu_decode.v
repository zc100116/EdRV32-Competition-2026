// edrv32_cpu_decode.v
// cpu-spec 2, 4: decode datapath.
// Clock domain: clk_sys (combinational where no clock port).
module edrv32_cpu_decode (
    // Canonical instruction from F2.
    input wire [31:0] instr_i,
    // Register dependencies and immediate for D/E.
    output wire [4:0] rs1_o,
    output wire [4:0] rs2_o,
    output wire [4:0] rd_o,
    output reg rs1_used_o,
    output reg rs2_used_o,
    output reg rd_write_o,
    output reg [31:0] imm_o,
    // Class: ALU=0,LUI=1,AUIPC=2,JAL=3,JALR=4,BRANCH=5,
    // LOAD=6,STORE=7,MUL=8,DIV=9,CSR=10,SYSTEM=11,FENCE=12,FENCE.I=13.
    output reg [3:0] class_o,
    output reg [3:0] alu_operation_o,
    output reg operand_imm_o,
    output reg illegal_o
);
    wire [6:0] opcode_w;
    wire [2:0] function_w;
    wire [6:0] extension_w;
    assign opcode_w = instr_i[6:0];
    assign function_w = instr_i[14:12];
    assign extension_w = instr_i[31:25];
    assign rs1_o = instr_i[19:15];
    assign rs2_o = instr_i[24:20];
    assign rd_o = instr_i[11:7];
    always @(*) begin
        rs1_used_o = 1'b0;
        rs2_used_o = 1'b0;
        rd_write_o = 1'b0;
        imm_o = {{20{instr_i[31]}}, instr_i[31:20]};
        class_o = 0;
        alu_operation_o = {1'b0, function_w};
        operand_imm_o = 1'b0;
        illegal_o = 1'b0;
        case (opcode_w)
            7'h37, 7'h17: begin
                class_o = opcode_w == 7'h37 ? 4'd1 : 4'd2;
                rd_write_o = 1'b1;
                imm_o = {instr_i[31:12], 12'b0};
            end
            7'h6f: begin
                class_o = 3;
                rd_write_o = 1'b1;
                imm_o = {{11{instr_i[31]}}, instr_i[31], instr_i[19:12],
                    instr_i[20], instr_i[30:21], 1'b0};
            end
            7'h67: begin
                class_o = 4;
                rd_write_o = 1'b1;
                rs1_used_o = 1'b1;
                illegal_o = function_w != 0;
            end
            7'h63: begin
                class_o = 5;
                rs1_used_o = 1'b1;
                rs2_used_o = 1'b1;
                imm_o = {{19{instr_i[31]}}, instr_i[31], instr_i[7],
                    instr_i[30:25], instr_i[11:8], 1'b0};
                illegal_o = function_w == 2 || function_w == 3;
            end
            7'h03: begin
                class_o = 6;
                rs1_used_o = 1'b1;
                rd_write_o = 1'b1;
                illegal_o = function_w == 3 || function_w >= 6;
            end
            7'h23: begin
                class_o = 7;
                rs1_used_o = 1'b1;
                rs2_used_o = 1'b1;
                imm_o = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
                illegal_o = function_w > 2;
            end
            7'h13: begin
                rs1_used_o = 1'b1;
                rd_write_o = 1'b1;
                operand_imm_o = 1'b1;
                if (function_w == 1)
                    illegal_o = extension_w != 0;
                if (function_w == 5) begin
                    illegal_o = extension_w != 0 && extension_w != 7'h20;
                    alu_operation_o[3] = instr_i[30];
                end
            end
            7'h33: begin
                rs1_used_o = 1'b1;
                rs2_used_o = 1'b1;
                rd_write_o = 1'b1;
                if (extension_w == 1)
                    class_o = function_w[2] ? 4'd9 : 4'd8;
                else begin
                    illegal_o = extension_w != 0 &&
                        !(extension_w == 7'h20 && (function_w == 0 || function_w == 5));
                    alu_operation_o[3] = instr_i[30];
                end
            end
            7'h0f: begin
                class_o = function_w == 0 ? 4'd12 : 4'd13;
                illegal_o = function_w > 1;
            end
            7'h73: begin
                if (function_w == 0) begin
                    class_o = 11;
                    case (instr_i)
                        32'h00000073, 32'h00100073, 32'h30200073,
                        32'h10500073: illegal_o = 1'b0;
                        default: illegal_o = 1'b1;
                    endcase
                end else begin
                    class_o = 10;
                    rs1_used_o = !function_w[2];
                    rd_write_o = 1'b1;
                    illegal_o = function_w == 4;
                end
            end
            default: illegal_o = 1'b1;
        endcase
    end
endmodule
