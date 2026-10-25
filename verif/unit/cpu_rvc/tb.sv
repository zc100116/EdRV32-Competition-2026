// cpu_rvc/tb.sv
// cpu-testplan U-02; cpu-spec 2, 4, 5.
// Exhaustively compare compressed expansion with generated encoding-table vectors.
// Stop with a diagnostic on the first mismatch; print PASS on completion.
// Clock domain: 组合逻辑.
`timescale 1ns/1ps
module tb;
    reg [15:0] instr_i;
    wire [31:0] instr_o;
    wire illegal_o;
    reg [32:0] vectors[0:65535];
    integer i;

    edrv32_cpu_rvc dut (
        .instr_i(instr_i),
        .instr_o(instr_o),
        .illegal_o(illegal_o)
    );
    integer generator_status;
    initial begin
        generator_status=$system("python3 verif/unit/cpu_rvc/vectors.py");
        if(generator_status!=0)$fatal(1,"FAIL RVC vector generator status=%0d",generator_status);
        $readmemh("build/unit/cpu_rvc_vectors.hex",vectors);
        for(i=0;i<65536;i=i+1) begin
            instr_i=16'(i);#1;
            if(illegal_o!==vectors[i][32] ||
                (!illegal_o && instr_o!==vectors[i][31:0]))
                $fatal(1,"FAIL RVC compressed=%h expected=%h actual=%b_%h time=%t",
                    instr_i,vectors[i],illegal_o,instr_o,$time);
        end
        $display("PASS U-02 65536 compressed encodings");$finish;
    end
endmodule
