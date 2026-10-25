`timescale 1ns/1ps
`include "edrv32_pair.vh"
module tb_ex_second_resident;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,valid=0,out_ready=0,kill=0,late_mdu=0,mdu_ready=0,poison=0;
    reg [31:0] pc=0,tag_pc=0;
    reg [31:0] lhs=101;
    reg [`EDRV32_OP_CLASS_W-1:0] op_class=`EDRV32_OP_ALU;
    reg [`EDRV32_PAIR_DECODE_W-1:0] second=0;
    wire ready,out_valid,out_value_ready;
    wire [31:0] out_pc,out_value;
    wire [`EDRV32_PAIR_RESULT_W-1:0] out_second;
    integer scenario,checks=0;
    reg [1:0] lhs_source,rhs_source;
    reg [31:0] expected;
    function automatic [`EDRV32_PAIR_DECODE_W-1:0] pair;
        input [31:0] bpc,blhs,brhs;input [1:0] ls,rs;
        begin pair={1'b1,bpc,32'h00208333,1'b0,{`EDRV32_EPOCH_W{1'b0}},
            5'd6,1'b1,`EDRV32_ALU_ADD,blhs,brhs,ls,rs};end
    endfunction
    edrv32_ex_stage #(.DUAL_ISSUE(1)) u_ex (
        .clk_i(clk),.rst_n_i(rst_n),.second_i(second),.result_second_o(out_second),
        .resident_second_rs1_i(1'b0),.resident_second_rs2_i(1'b0),
        .valid_i(valid),.ready_o(ready),.pc_i(pc),.instr_i(32'h00000013),
        .is_compressed_i(1'b0),.epoch_i({`EDRV32_EPOCH_W{1'b0}}),
        .predicted_taken_i(1'b0),.predicted_target_i(32'd0),.rd_i(5'd5),.rd_write_i(1'b1),
        .op_class_i(op_class),.alu_op_i(`EDRV32_ALU_ADD),.branch_op_i(3'd0),
        .mem_size_i(2'd2),.mem_unsigned_i(1'b0),.mdu_op_i(3'd0),.csr_op_i(2'd0),
        .csr_addr_i(12'd0),.csr_src_i(32'd0),.lhs_i(lhs),.rhs_i(32'd0),.rs2_value_i(32'd0),
        .resident_bypass_rs1_i(1'b0),.resident_bypass_rs2_i(1'b0),.resident_bypass_pc_i(tag_pc),
        .late_mdu_rs1_i(late_mdu),.late_mdu_rs2_i(1'b0),
        .late_load_rs1_i(1'b0),.late_load_rs2_i(1'b0),
        .late_load_rs1_pc_i(32'd0),.late_load_rs2_pc_i(32'd0),
        .late_load_rs1_token_valid_i(1'b0),.late_load_rs2_token_valid_i(1'b0),
        .imm_i(32'd0),.fence_i(1'b0),.fencei_i(1'b0),.mret_i(1'b0),.wfi_i(1'b0),
        .exception_valid_i(1'b0),.exception_cause_i(4'd0),.exception_tval_i(32'd0),
        .load_bypass_valid_i(1'b0),.load_bypass_pc_i(32'd0),.load_bypass_value_i(32'd0),
        .load_queue_rs1_ready_i(1'b0),.load_queue_rs1_value_i(32'd0),
        .load_queue_rs1_stored_ready_i(1'b0),.load_queue_rs1_stored_value_i(32'd0),
        .load_queue_rs2_ready_i(1'b0),.load_queue_rs2_value_i(32'd0),
        .load_queue_rs2_stored_ready_i(1'b0),.load_queue_rs2_stored_value_i(32'd0),
        .result_bypass_valid_i(out_valid),.result_bypass_ready_i(out_value_ready),
        .result_bypass_pc_i(out_pc),.result_bypass_value_i(poison?32'hbad0bad0:out_value),
        .mdu_bypass_valid_i(mdu_ready),.mdu_bypass_value_i(32'd37),
        .redirect_ready_i(1'b1),.mdu_req_ready_i(1'b1),
        .result_valid_o(out_valid),.result_ready_i(out_ready),.result_pc_o(out_pc),
        .result_value_o(out_value),.result_value_ready_o(out_value_ready),.kill_i(kill)
    );
    task automatic tick;
        begin @(posedge clk);#1;end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst_n=1;
        for(scenario=0;scenario<5;scenario=scenario+1)begin
            @(negedge clk);kill=1;valid=0;tick;
            @(negedge clk);kill=0;valid=1;out_ready=0;late_mdu=0;mdu_ready=0;poison=0;
            op_class=(scenario==4)?`EDRV32_OP_LOAD:`EDRV32_OP_ALU;
            lhs=(scenario==4)?32'd0:32'd101;pc=32'h80000040;
            second=pair(pc+4,205,0,0,0);tick;
            if(!out_valid||!out_second[`EDRV32_PAIR_RESULT_W-1])$fatal(1,"Parent not seeded");
            lhs_source=(scenario==1||scenario==4)?2'd2:2'd1;
            rhs_source=(scenario==2)?2'd1:2'd2;
            expected=(lhs_source==2?205:101)+(rhs_source==2?205:101);
            @(negedge clk);pc=32'h80000048;op_class=`EDRV32_OP_ALU;late_mdu=1;
            tag_pc=32'h80000000;second=pair(pc+4,32'hbad1bad1,32'hbad2bad2,lhs_source,rhs_source);
            tick;
            if(u_ex.second_lhs_captured_r||u_ex.second_rhs_captured_r)
                $fatal(1,"Accepted wrong producer PC");
            checks=checks+1;
            @(negedge clk);tag_pc=32'h80000040;tick;
            if(!u_ex.second_lhs_captured_r||!u_ex.second_rhs_captured_r||
                u_ex.second_result_w!=expected||ready)
                $fatal(1,"Resident source capture failed scenario=%0d",scenario);
            checks=checks+1;
            @(negedge clk);out_ready=1;tick;
            if(out_valid)$fatal(1,"Parent did not drain while A waits");
            @(negedge clk);poison=1;
            repeat(4)begin
                tick;
                if(u_ex.second_result_w!=expected||!u_ex.second_operands_ready_w||ready)
                    $fatal(1,"B lost held data after producer departure");
                checks=checks+1;
            end
            if(scenario==3)begin
                @(negedge clk);kill=1;tick;
                if(u_ex.second_lhs_captured_r||u_ex.second_rhs_captured_r||out_valid)
                    $fatal(1,"Kill retained B ownership");
                @(negedge clk);kill=0;late_mdu=0;second=pair(pc+4,3,4,0,0);tick;
                if(out_second[31:0]!=7)$fatal(1,"Killed capture polluted next pair");
            end else begin
                @(negedge clk);mdu_ready=1;
                #1;if(!ready)$fatal(1,"Held B blocked ready after A completion");
                tick;
                if(!out_valid||out_value!=37||out_second[31:0]!=expected)
                    $fatal(1,"Pair result mismatch scenario=%0d",scenario);
            end
            checks=checks+1;
        end
        $display("PASS: EX B resident sources checks=%0d",checks);$finish;
    end
    initial begin #20000;$fatal(1,"EX B resident timeout");end
endmodule
