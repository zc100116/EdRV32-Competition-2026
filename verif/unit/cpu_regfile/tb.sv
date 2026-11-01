// cpu_regfile/tb.sv
// cpu-testplan U-07; cpu-spec 2, 4, 5.
// Compare four reads and two ordered writes against the register model.
// Stop with a diagnostic on the first mismatch; print PASS on completion.
// Clock domain: clk_sys.
`timescale 1ns/1ps
module tb;
    reg clk_i=0;
    always #5 clk_i=~clk_i;
    reg [4:0] read_addr0_i;
    wire [31:0] read_data0_o;
    reg [4:0] read_addr1_i;
    wire [31:0] read_data1_o;
    reg [4:0] read_addr2_i;
    wire [31:0] read_data2_o;
    reg [4:0] read_addr3_i;
    wire [31:0] read_data3_o;
    reg write_valid0_i;
    reg [4:0] write_addr0_i;
    reg [31:0] write_data0_i;
    reg write_valid1_i;
    reg [4:0] write_addr1_i;
    reg [31:0] write_data1_i;
    reg [31:0] model[0:31];
    reg [31:0] expected;
    integer i;

    edrv32_cpu_regfile dut (
        .clk_i(clk_i),
        .read_addr0_i({4{read_addr0_i}}),
        .read_data0_o(read_data0_o),
        .read_addr1_i({4{read_addr1_i}}),
        .read_data1_o(read_data1_o),
        .read_addr2_i({4{read_addr2_i}}),
        .read_data2_o(read_data2_o),
        .read_addr3_i({4{read_addr3_i}}),
        .read_data3_o(read_data3_o),
        .write_valid0_i(write_valid0_i),
        .write_addr0_i(write_addr0_i),
        .write_data0_i(write_data0_i),
        .write_valid1_i(write_valid1_i),
        .write_addr1_i(write_addr1_i),
        .write_data1_i(write_data1_i)
    );
    initial begin
        write_valid0_i=0;write_valid1_i=0;
        write_addr0_i=0;write_addr1_i=0;
        write_data0_i=0;write_data1_i=0;
        read_addr0_i=0;read_addr1_i=0;read_addr2_i=0;read_addr3_i=0;
        for(i=0;i<32;i=i+1) begin
            @(negedge clk_i);
            write_valid0_i=1; write_addr0_i=5'(i); write_data0_i=32'(i);
            model[i]=32'(i);
            @(posedge clk_i); #1;
        end
        for(i=0;i<2000;i=i+1) begin
            @(negedge clk_i);
            write_valid0_i=1'(i);write_valid1_i=1'(i>>1);
            write_addr0_i=5'($urandom);write_addr1_i=5'($urandom);
            if(i%3==0) write_addr1_i=write_addr0_i;
            write_data0_i=$urandom;write_data1_i=$urandom;
            if(write_valid0_i && write_addr0_i!=0) model[write_addr0_i]=write_data0_i;
            if(write_valid1_i && write_addr1_i!=0) model[write_addr1_i]=write_data1_i;
            read_addr0_i=write_addr0_i;read_addr1_i=write_addr1_i;
            read_addr2_i=5'($urandom);read_addr3_i=0;
            #1;
            expected=model[read_addr0_i];
            if(read_data0_o!==expected)
                $fatal(1,"FAIL RF port 0 addr=%d exp=%h actual=%h time=%t",
                    read_addr0_i,expected,read_data0_o,$time);
            expected=model[read_addr1_i];
            if(read_data1_o!==expected)
                $fatal(1,"FAIL RF port 1 addr=%d exp=%h actual=%h time=%t",
                    read_addr1_i,expected,read_data1_o,$time);
            expected=model[read_addr2_i];
            if(read_data2_o!==expected)
                $fatal(1,"FAIL RF port 2 addr=%d exp=%h actual=%h time=%t",
                    read_addr2_i,expected,read_data2_o,$time);
            expected=model[read_addr3_i];
            if(read_data3_o!==expected)
                $fatal(1,"FAIL RF port 3 addr=%d exp=%h actual=%h time=%t",
                    read_addr3_i,expected,read_data3_o,$time);
            @(posedge clk_i);#1;
        end
        $display("PASS U-07");$finish;
    end
endmodule
