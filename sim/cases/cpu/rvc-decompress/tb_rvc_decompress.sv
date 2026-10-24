`timescale 1ns/1ps

module tb_rvc_decompress;

    localparam integer VECTOR_COUNT = 34;

    reg  [15:0] compressed;
    wire [31:0] canonical;
    wire        illegal;

    reg [15:0] c_vector [0:VECTOR_COUNT-1];
    reg [31:0] i_vector [0:VECTOR_COUNT-1];
    reg        illegal_vector [0:VECTOR_COUNT-1];
    integer index;

    edrv32_rvc_decompress u_dut (
        .c_instr_i(compressed),
        .instr_o(canonical),
        .illegal_o(illegal)
    );

    initial begin
        // Canonical encodings independently assembled in the previous RV32C
        // regression. They cover all integer data-processing forms plus stack
        // and compact-register memory operations.
        c_vector[0]  = 16'hc93d; i_vector[0]  = 32'h0605_0b63; illegal_vector[0]  = 1'b0;
        c_vector[1]  = 16'h10c8; i_vector[1]  = 32'h0641_0513; illegal_vector[1]  = 1'b0;
        c_vector[2]  = 16'h4a4c; i_vector[2]  = 32'h0146_2583; illegal_vector[2]  = 1'b0;
        c_vector[3]  = 16'hcf54; i_vector[3]  = 32'h00d7_2e23; illegal_vector[3]  = 1'b0;
        c_vector[4]  = 16'h17bd; i_vector[4]  = 32'hfef7_8793; illegal_vector[4]  = 1'b0;
        c_vector[5]  = 16'h585d; i_vector[5]  = 32'hff70_0813; illegal_vector[5]  = 1'b0;
        c_vector[6]  = 16'h7179; i_vector[6]  = 32'hfd01_0113; illegal_vector[6]  = 1'b0;
        c_vector[7]  = 16'h6895; i_vector[7]  = 32'h0000_58b7; illegal_vector[7]  = 1'b0;
        c_vector[8]  = 16'h801d; i_vector[8]  = 32'h0074_5413; illegal_vector[8]  = 1'b0;
        c_vector[9]  = 16'h84a5; i_vector[9]  = 32'h4094_d493; illegal_vector[9]  = 1'b0;
        c_vector[10] = 16'h9955; i_vector[10] = 32'hff55_7513; illegal_vector[10] = 1'b0;
        c_vector[11] = 16'h8d91; i_vector[11] = 32'h40c5_85b3; illegal_vector[11] = 1'b0;
        c_vector[12] = 16'h8e35; i_vector[12] = 32'h00d6_4633; illegal_vector[12] = 1'b0;
        c_vector[13] = 16'h8ed9; i_vector[13] = 32'h00e6_e6b3; illegal_vector[13] = 1'b0;
        c_vector[14] = 16'h8f7d; i_vector[14] = 32'h00f7_7733; illegal_vector[14] = 1'b0;
        c_vector[15] = 16'h0836; i_vector[15] = 32'h00d8_1813; illegal_vector[15] = 1'b0;
        c_vector[16] = 16'h58f2; i_vector[16] = 32'h03c1_2883; illegal_vector[16] = 1'b0;
        c_vector[17] = 16'h8082; i_vector[17] = 32'h0000_8067; illegal_vector[17] = 1'b0;
        c_vector[18] = 16'h842a; i_vector[18] = 32'h00a0_0433; illegal_vector[18] = 1'b0;
        c_vector[19] = 16'h9002; i_vector[19] = 32'h0010_0073; illegal_vector[19] = 1'b0;
        c_vector[20] = 16'h9082; i_vector[20] = 32'h0000_80e7; illegal_vector[20] = 1'b0;
        c_vector[21] = 16'h94ae; i_vector[21] = 32'h00b4_84b3; illegal_vector[21] = 1'b0;
        c_vector[22] = 16'hd632; i_vector[22] = 32'h02c1_2623; illegal_vector[22] = 1'b0;

        // Architectural HINTs remain legal and side-effect free after decode.
        c_vector[23] = 16'h0001; i_vector[23] = 32'h0000_0013; illegal_vector[23] = 1'b0; // C.NOP
        c_vector[24] = 16'h4401; i_vector[24] = 32'h0000_0413; illegal_vector[24] = 1'b0; // C.LI x8,0

        // Reserved, RV64-only, FP, and non-compressed encodings are illegal.
        c_vector[25] = 16'h0000; i_vector[25] = 32'd0; illegal_vector[25] = 1'b1; // ADDI4SPN imm=0
        c_vector[26] = 16'h0003; i_vector[26] = 32'd0; illegal_vector[26] = 1'b1; // quadrant 3
        c_vector[27] = 16'h4002; i_vector[27] = 32'd0; illegal_vector[27] = 1'b1; // LWSP x0
        c_vector[28] = 16'h2000; i_vector[28] = 32'd0; illegal_vector[28] = 1'b1; // C.FLD class
        c_vector[29] = 16'h6000; i_vector[29] = 32'd0; illegal_vector[29] = 1'b1; // C.FLW class
        c_vector[30] = 16'ha000; i_vector[30] = 32'd0; illegal_vector[30] = 1'b1; // C.FSD class
        c_vector[31] = 16'he000; i_vector[31] = 32'd0; illegal_vector[31] = 1'b1; // C.FSW class
        c_vector[32] = 16'h9c01; i_vector[32] = 32'd0; illegal_vector[32] = 1'b1; // RV64 SUBW/ADDW space
        c_vector[33] = 16'h9006; i_vector[33] = 32'h0010_0033; illegal_vector[33] = 1'b0; // C.ADD x0,x1 HINT

        for (index = 0; index < VECTOR_COUNT; index = index + 1) begin
            compressed = c_vector[index];
            #1;
            if (illegal !== illegal_vector[index]) begin
                $fatal(1, "RVC legality mismatch idx=%0d c=%04x expected=%b got=%b",
                       index, compressed, illegal_vector[index], illegal);
            end
            if (!illegal && (canonical !== i_vector[index])) begin
                $fatal(1, "RVC output mismatch idx=%0d c=%04x expected=%08x got=%08x",
                       index, compressed, i_vector[index], canonical);
            end
        end

        $display("PASS: RV32C decompressor (%0d vectors)", VECTOR_COUNT);
        $finish;
    end

endmodule
