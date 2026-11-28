// Self-checking CV04 RF/WB eligibility and actual-issue query association.
module tb #(parameter ISSUE_WIDTH = 2, parameter [31:0] FPU_FORMAT = "NONE");
    localparam T = ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3;
    reg clk_i=0;
    reg rst_n_i=0;
    always #5 clk_i=~clk_i;
    reg valid=0;
    reg load=0;
    reg store=0;
    reg pending=0;
    reg [4:0] rs=0;
    reg [4:0] candidates=0;
    reg [31:0] imm=0;
    reg [T-1:0] tag=0;
    reg wb0=0;
    reg wb1=0;
    reg [4:0] rd0=0;
    reg [4:0] rd1=0;
    reg [31:0] data0=0;
    reg [31:0] data1=0;
    wire eligible;
    wire [31:0] addr;
    wire early;
    wire [31:0] early_addr;
    wire [T-1:0] early_tag;
    edrv32_cpu2_id_agu #(.ISSUE_WIDTH(ISSUE_WIDTH), .FPU_FORMAT(FPU_FORMAT)) dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .id_valid_i(valid),
        .id_load_i(load),
        .id_store_i(store),
        .id_rs1_i(rs),
        .id_candidates_i(candidates),
        .id_imm_i(imm),
        .id_tag_i(tag),
        .rs1_pending_i(pending),
        .wb0_valid_i(wb0),
        .wb0_rd_i(rd0),
        .wb0_data_i(data0),
        .wb1_valid_i(wb1),
        .wb1_rd_i(rd1),
        .wb1_data_i(data1),
        .id_eligible_o(eligible),
        .id_addr_o(addr),
        .early_req_valid_o(early),
        .early_req_addr_o(early_addr),
        .early_req_tag_o(early_tag)
    );
    task tick; @(posedge clk_i); #1; endtask
    task check(input bit expected, input bit request, input [31:0] address);
        #1;
        if(eligible!==expected || early!==request || addr!==address ||
            early_addr!==address || early_tag!==tag)
            $fatal(1,"CV04 eligible %b/%b query %b/%b addr %h/%h time %0t",
                eligible,expected,early,request,addr,address,$time);
    endtask
    initial begin
        tick(); rst_n_i=1;
        wb0=1; rd0=5; data0=32'h20; tick(); wb0=0;
        rs=5; imm=4; load=1; tag=T'(3);
        check(1,0,32'h24); valid=1; check(1,1,32'h24);
        // The issue scoreboard supplies the union of same-group/EX/MEM/pending-MUL hazards.
        pending=1; check(0,0,32'h24); pending=0;
        store=1; check(0,0,32'h24); store=0;
        load=0; check(0,0,32'h24); load=1;
        wb0=1; wb1=1; rd0=5; rd1=5; data0=32'h100; data1=32'h200;
        check(1,1,ISSUE_WIDTH==2 ? 32'h204:32'h104);
        tick(); wb0=0; wb1=0; candidates=5'b00001;
        check(1,1,ISSUE_WIDTH==2 ? 32'h204:32'h104);
        candidates=5'b10100;
        check(1,1,ISSUE_WIDTH==2 ? 32'h204:32'h104);
        tag='1;
        rs=0; pending=1; wb0=1; wb1=1; rd0=0; rd1=0;
        data0='1; data1='1; check(1,1,4);
        valid=0; check(1,0,4);
        // Modulo address arithmetic and forwarding do not depend on RAM read-during-write.
        rs=5; pending=0; wb0=1; rd0=5; data0=32'hffff_fffc; imm=8;
        check(1,0,4);
        $display("PASS CV04 ID AGU ISSUE_WIDTH=%0d FPU_FORMAT=%s",ISSUE_WIDTH,FPU_FORMAT);
        $finish;
    end
endmodule
