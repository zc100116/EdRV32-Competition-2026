// cpu_decode/tb.sv
// cpu-testplan U-01; cpu-spec 2, 4, 5.
// Check instruction legality against the encoding table and directed controls.
// Stop with a diagnostic on the first mismatch; print PASS on completion.
// Clock domain: 组合逻辑.
`timescale 1ns/1ps
module tb;
    reg [31:0] instr_i;
    wire [4:0] rs1_o;
    wire [4:0] rs2_o;
    wire [4:0] rd_o;
    wire rs1_used_o;
    wire rs2_used_o;
    wire rd_write_o;
    wire [31:0] imm_o;
    wire [3:0] class_o;
    wire [3:0] alu_operation_o;
    wire operand_imm_o;
    wire illegal_o;
    reg legal;
    integer op;
    integer f;
    integer ext;
    integer sample;
    integer count=0;
    function automatic bit encoding_legal(input logic [31:0] ins);
        case(ins[6:0])
            'h37,'h17,'h6f: encoding_legal=1;
            'h67: encoding_legal=ins[14:12]==0;
            'h63: encoding_legal=(ins[14:12] inside {0,1,4,5,6,7}); // replaced below
            'h03: encoding_legal=(ins[14:12] inside {0,1,2,4,5});
            'h23: encoding_legal=(ins[14:12] inside {0,1,2});
            'h13: case(ins[14:12])
                1: encoding_legal=ins[31:25]==0;
                5: encoding_legal=(ins[31:25] inside {0,'h20});
                default: encoding_legal=1;
            endcase
            'h33: encoding_legal=(ins[31:25] inside {0,1}) ||
                (ins[31:25]=='h20 && (ins[14:12] inside {0,5}));
            'h0f: encoding_legal=ins[14:12]<2;
            'h73: encoding_legal=(ins[14:12] inside {1,2,3,5,6,7}) ||
                (ins inside {32'h00000073,32'h00100073,32'h30200073,32'h10500073});
            default: encoding_legal=0;
        endcase
    endfunction

    edrv32_cpu_decode dut (
        .instr_i(instr_i),
        .rs1_o(rs1_o),
        .rs2_o(rs2_o),
        .rd_o(rd_o),
        .rs1_used_o(rs1_used_o),
        .rs2_used_o(rs2_used_o),
        .rd_write_o(rd_write_o),
        .imm_o(imm_o),
        .class_o(class_o),
        .alu_operation_o(alu_operation_o),
        .operand_imm_o(operand_imm_o),
        .illegal_o(illegal_o)
    );
    task automatic controls(input reg [31:0] instruction,
        input reg [3:0] kind, input reg [3:0] alu,
        input reg use1, input reg use2, input reg write_rd, input reg immediate,
        input reg [31:0] value);
        begin
            instr_i=instruction;#1;
            if(illegal_o || class_o!==kind || alu_operation_o!==alu ||
                rs1_used_o!==use1 || rs2_used_o!==use2 || rd_write_o!==write_rd ||
                operand_imm_o!==immediate || imm_o!==value)
                $fatal(1,"FAIL decode controls instruction=%h class=%d alu=%d imm=%h time=%t",
                    instruction,class_o,alu_operation_o,imm_o,$time);
        end
    endtask
    initial begin
        for(op=0;op<128;op=op+1)
            for(f=0;f<8;f=f+1)
                for(ext=0;ext<128;ext=ext+1)
                    for(sample=0;sample<3;sample=sample+1) begin
                        instr_i={7'(ext),5'(sample==0?0:sample==1?31:$urandom),
                            5'(sample==0?0:sample==1?31:$urandom),3'(f),
                            5'(sample==0?0:sample==1?31:$urandom),7'(op)};
                        legal=encoding_legal(instr_i); #1;
                        if(illegal_o!==!legal)
                            $fatal(1,"FAIL decode instruction=%h expected illegal=%b actual=%b time=%t",
                                instr_i,!legal,illegal_o,$time);
                        if(rs1_o!==instr_i[19:15] || rs2_o!==instr_i[24:20] ||
                            rd_o!==instr_i[11:7]) $fatal(1,"FAIL register fields %h",instr_i);
                        count=count+1;
                    end
        instr_i=32'h00100073;#1;if(illegal_o)$fatal(1,"FAIL EBREAK");
        instr_i=32'h30200073;#1;if(illegal_o)$fatal(1,"FAIL MRET");
        instr_i=32'h10500073;#1;if(illegal_o)$fatal(1,"FAIL WFI");
        controls(32'hfff10093,0,0,1,0,1,1,32'hffffffff); // ADDI
        controls(32'h40215093,0,13,1,0,1,1,32'h402); // SRAI
        controls(32'h402100b3,0,8,1,1,1,0,32'h402); // SUB
        controls(32'h800000b7,1,0,0,0,1,0,32'h80000000); // LUI
        controls(32'h80000097,2,0,0,0,1,0,32'h80000000); // AUIPC
        controls(32'hfff100e7,4,0,1,0,1,0,32'hffffffff); // JALR
        controls(32'hfe208ee3,5,0,1,1,0,0,32'hfffffffc); // BEQ -4
        controls(32'hffc12083,6,2,1,0,1,0,32'hfffffffc); // LW
        controls(32'hfe112e23,7,2,1,1,0,0,32'hfffffffc); // SW
        controls(32'h022100b3,8,0,1,1,1,0,32'h22); // MUL
        controls(32'h022140b3,9,4,1,1,1,0,32'h22); // DIV
        controls(32'h300110f3,10,1,1,0,1,0,32'h300); // CSRRW
        controls(32'h300150f3,10,5,0,0,1,0,32'h300); // CSRRWI
        $display("PASS U-01 %0d encoding combinations",count);$finish;
    end
endmodule
