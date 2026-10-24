`timescale 1ns/1ps
module tb_dual_regfile;
    reg clk=0;
    always #5 clk=~clk;
    reg [4:0] r1=7,r2=9,r3=7,r4=9,wa=7,wb=9;
    reg ea=0,eb=0;
    reg [31:0] da=0,db=0;
    wire [31:0] q1,q2,q3,q4;
    edrv32_regfile #(.SECOND_ENABLE(1)) u_dut (
        .clk_i(clk),.rs1_addr_i(r1),.rs2_addr_i(r2),.rs1_data_o(q1),.rs2_data_o(q2),
        .rd_write_i(ea),.rd_addr_i(wa),.rd_data_i(da),
        .second_rs1_addr_i(r3),.second_rs2_addr_i(r4),.second_rs1_data_o(q3),.second_rs2_data_o(q4),
        .second_rd_write_i(eb),.second_rd_addr_i(wb),.second_rd_data_i(db)
    );
    task automatic check;
        input [31:0] v1,v2,v3,v4;
        begin #1;if({q1,q2,q3,q4}!=={v1,v2,v3,v4})$fatal(1,"4R2W collision or read sensitivity mismatch");end
    endtask
    initial begin
        @(negedge clk);ea=1;eb=1;da=32'haabb;db=32'hccdd;
        check(32'haabb,32'hccdd,32'haabb,32'hccdd);
        // Read addresses stay fixed while write-data and enables change.
        da=32'h1111;db=32'h2222;check(32'h1111,32'h2222,32'h1111,32'h2222);
        @(negedge clk);ea=0;eb=0;check(32'h1111,32'h2222,32'h1111,32'h2222);
        ea=1;eb=1;wa=7;wb=7;da=3;db=4;check(4,32'h2222,4,32'h2222);
        @(negedge clk);ea=0;eb=0;check(4,32'h2222,4,32'h2222);
        r1=0;r2=0;r3=0;r4=0;ea=1;eb=1;wa=0;wb=0;da=32'hffff;db=32'hffff;check(0,0,0,0);
        @(negedge clk);ea=0;eb=0;check(0,0,0,0);
        $display("PASS: 4R2W register file, write-through, younger priority and x0");$finish;
    end
endmodule
