`timescale 1ns/1ps

`include "edrv32_pair.vh"
module tb_operand_resolve #(parameter DUAL_ISSUE=0);
    reg [4:0] rs1_addr, rs2_addr;
    reg uses_rs1, uses_rs2;
    reg [31:0] rs1_reg_data, rs2_reg_data;
    wire [31:0] rs1_value, rs2_value;
    wire rs1_blocked, rs2_blocked;
    wire rs1_late_load, rs2_late_load;
    wire [31:0] rs1_late_load_pc, rs2_late_load_pc;

    reg mdu_valid, mdu_ready;
    reg [4:0] mdu_rd;
    reg [31:0] mdu_value;
    reg mdu_passed_mem1, mdu_passed_mem2, mdu_authorized;
    reg ex_mdu_token;
    wire rs1_mdu, rs2_mdu;
    reg ex_valid, ex_write, ex_ready, ex_is_load;
    reg [31:0] ex_pc;
    reg [4:0] ex_rd;
    reg [31:0] ex_value;
    reg mem1_valid, mem1_write, mem1_ready, mem1_is_load;
    reg [31:0] mem1_pc;
    reg [4:0] mem1_rd;
    reg [31:0] mem1_value;
    reg mem2_valid, mem2_write, mem2_ready;
    reg mem2_is_load;
    reg [31:0] mem2_pc;
    reg [4:0] mem2_rd;
    reg [31:0] mem2_value;
    reg commit_valid, commit_write, commit_ready;
    reg [4:0] commit_rd;
    reg [31:0] commit_value;
    integer checks;
    integer stage;
    reg [`EDRV32_PAIR_RESULT_W-1:0] ex_second,mem1_second,mem2_second,commit_second;
    function automatic [`EDRV32_PAIR_RESULT_W-1:0] second_packet;
        input [4:0] rd;
        input [31:0] value;
        begin second_packet={1'b1,32'h80000100,32'h00000013,1'b0,2'd0,rd,1'b1,value};end
    endfunction

    edrv32_operand_resolve #(.DUAL_ISSUE(DUAL_ISSUE)) u_dut (
        .ex_second_i(ex_second),.mem1_second_i(mem1_second),
        .mem2_second_i(mem2_second),.commit_second_i(commit_second),
        .rs1_addr_i(rs1_addr), .uses_rs1_i(uses_rs1),
        .rs1_reg_data_i(rs1_reg_data), .rs1_value_o(rs1_value),
        .rs1_blocked_o(rs1_blocked), .rs1_late_load_o(rs1_late_load),
        .rs1_mdu_o(rs1_mdu),
        .rs1_late_load_pc_o(rs1_late_load_pc),
        .rs1_late_load_token_valid_o(), .rs1_late_load_token_o(),
        .rs2_addr_i(rs2_addr), .uses_rs2_i(uses_rs2),
        .rs2_reg_data_i(rs2_reg_data), .rs2_value_o(rs2_value),
        .rs2_blocked_o(rs2_blocked), .rs2_late_load_o(rs2_late_load),
        .rs2_mdu_o(rs2_mdu),
        .rs2_late_load_pc_o(rs2_late_load_pc),
        .rs2_late_load_token_valid_o(), .rs2_late_load_token_o(),
        .mdu_valid_i(mdu_valid), .mdu_ready_i(mdu_ready),
        .mdu_rd_i(mdu_rd), .mdu_value_i(mdu_value),
        .mdu_passed_mem1_i(mdu_passed_mem1),
        .mdu_passed_mem2_i(mdu_passed_mem2), .mdu_authorized_i(mdu_authorized),
        .ex_valid_i(ex_valid), .ex_write_i(ex_write),
        .ex_ready_i(ex_ready), .ex_is_load_i(ex_is_load),
        .ex_mdu_token_i(ex_mdu_token),
        .ex_pc_i(ex_pc), .ex_rd_i(ex_rd), .ex_value_i(ex_value),
        .ex_lsu_token_valid_i(1'b0), .ex_lsu_token_i(3'd0),
        .mem1_valid_i(mem1_valid), .mem1_write_i(mem1_write),
        .mem1_ready_i(mem1_ready), .mem1_is_load_i(mem1_is_load),
        .mem1_pc_i(mem1_pc), .mem1_rd_i(mem1_rd),
        .mem1_value_i(mem1_value),
        .mem1_lsu_token_valid_i(1'b0), .mem1_lsu_token_i(3'd0),
        .mem2_valid_i(mem2_valid), .mem2_write_i(mem2_write),
        .mem2_ready_i(mem2_ready), .mem2_is_load_i(mem2_is_load),
        .mem2_pc_i(mem2_pc), .mem2_rd_i(mem2_rd),
        .mem2_value_i(mem2_value),
        .mem2_lsu_token_valid_i(1'b0), .mem2_lsu_token_i(3'd0),
        .commit_valid_i(commit_valid), .commit_write_i(commit_write),
        .commit_ready_i(commit_ready), .commit_rd_i(commit_rd),
        .commit_value_i(commit_value)
    );

    task automatic check_true;
        input condition;
        input [8*96-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                $display("FAIL: %0s", message);
                $fatal(1);
            end
        end
    endtask

    task automatic clear_producers;
        begin
            ex_second=0;mem1_second=0;mem2_second=0;commit_second=0;
            mdu_valid = 1'b0; mdu_ready = 1'b0;
            mdu_rd = 5'd0; mdu_value = 32'd0;
            mdu_passed_mem1 = 1'b0; mdu_passed_mem2 = 1'b0;
            mdu_authorized = 1'b0; ex_mdu_token = 1'b0;
            ex_valid = 1'b0; ex_write = 1'b0; ex_ready = 1'b0;
            ex_is_load = 1'b0; ex_pc = 32'd0;
            ex_rd = 5'd0; ex_value = 32'd0;
            mem1_valid = 1'b0; mem1_write = 1'b0; mem1_ready = 1'b0;
            mem1_is_load = 1'b0; mem1_pc = 32'd0;
            mem1_rd = 5'd0; mem1_value = 32'd0;
            mem2_valid = 1'b0; mem2_write = 1'b0; mem2_ready = 1'b0;
            mem2_is_load = 1'b0; mem2_pc = 32'd0;
            mem2_rd = 5'd0; mem2_value = 32'd0;
            commit_valid = 1'b0; commit_write = 1'b0; commit_ready = 1'b0;
            commit_rd = 5'd0; commit_value = 32'd0;
        end
    endtask

    initial begin
        checks = 0;
        rs1_addr = 5'd7; rs2_addr = 5'd9;
        uses_rs1 = 1'b1; uses_rs2 = 1'b1;
        rs1_reg_data = 32'h1111_1111;
        rs2_reg_data = 32'h2222_2222;
        clear_producers();
        #1;
        check_true(rs1_value == 32'h1111_1111 && !rs1_blocked &&
                   rs2_value == 32'h2222_2222 && !rs2_blocked,
                   "Register data is used when no producer matches");

        mdu_valid = 1'b1; mdu_ready = 1'b0;
        mdu_rd = 5'd7; mdu_value = 32'hdddd_0007; #1;
        check_true(rs1_value == 32'hdddd_0007 && rs1_blocked,
                   "Incomplete MDU producer blocks rs1");
        mdu_ready = 1'b1; #1;
        check_true(rs1_value == 32'hdddd_0007 && !rs1_blocked,
                   "Completed MDU producer bypasses rs1");

        // The MDU completion replaces its own travelling token, but an
        // ordinary writer after that token must shadow the completion.
        ex_valid = 1'b1; ex_write = 1'b1; ex_ready = 1'b0;
        ex_mdu_token = 1'b1;
        ex_rd = 5'd7; ex_value = 32'heeee_0007; #1;
        check_true(rs1_value == 32'hdddd_0007 && !rs1_blocked,
                   "Completed MDU value overrides its unready pipeline token");
        ex_mdu_token = 1'b0; #1;
        check_true(!rs1_mdu && rs1_blocked && rs1_value == 32'heeee_0007,
                   "Unready younger EX writer shadows ready MDU data");
        ex_is_load = 1'b1; ex_pc = 32'h8000_0240; #1;
        check_true(rs1_late_load && rs1_late_load_pc == 32'h8000_0240 && !rs1_mdu,
                   "Younger EX Load retains its exact producer identity");
        ex_ready = 1'b1; #1;
        check_true(!rs1_blocked && !rs1_mdu && rs1_value == 32'heeee_0007,
                   "Ready younger EX writer overrides MDU data");

        clear_producers();
        mdu_valid = 1'b1; mdu_ready = 1'b1;
        mdu_rd = 5'd7; mdu_value = 32'hdddd_0007;
        mem1_valid = 1'b1; mem1_write = 1'b1; mem1_ready = 1'b1;
        mem1_rd = 5'd7; mem1_value = 32'h1111_0007; #1;
        check_true(rs1_mdu && rs1_value == 32'hdddd_0007,
                   "MEM1 record before token crossing remains older than MDU");
        mdu_passed_mem1 = 1'b1; #1;
        check_true(!rs1_mdu && rs1_value == 32'h1111_0007,
                   "MEM1 record after token crossing is younger than MDU");
        mem1_ready = 1'b0; mem1_is_load = 1'b1; mem1_pc = 32'h8000_0280; #1;
        check_true(rs1_blocked && rs1_late_load && !rs1_mdu &&
                   rs1_late_load_pc == 32'h8000_0280,
                   "Unready younger MEM1 Load cannot fall back to old MDU");

        mem1_valid = 1'b0;
        mem2_valid = 1'b1; mem2_write = 1'b1; mem2_ready = 1'b1;
        mem2_rd = 5'd7; mem2_value = 32'h2222_0007; #1;
        check_true(rs1_mdu && rs1_value == 32'hdddd_0007,
                   "MEM2 token/older record cannot replace MDU data");
        mdu_passed_mem2 = 1'b1; #1;
        check_true(!rs1_mdu && rs1_value == 32'h2222_0007,
                   "Younger MEM2 record shadows MDU data after crossing");
        mem2_ready = 1'b0; #1;
        check_true(rs1_blocked && !rs1_mdu,
                   "Unready younger MEM2 writer prevents reading around");

        mem2_valid = 1'b0;
        commit_valid = 1'b1; commit_write = 1'b1; commit_ready = 1'b1;
        commit_rd = 5'd7; commit_value = 32'hcccc_0007; #1;
        check_true(rs1_mdu && rs1_value == 32'hdddd_0007,
                   "COMMIT record before authorization cannot shadow MDU");
        mdu_authorized = 1'b1; #1;
        check_true(!rs1_mdu && rs1_value == 32'hcccc_0007,
                   "Younger COMMIT writer shadows authorized MDU");
        commit_ready = 1'b0; #1;
        check_true(rs1_blocked && !rs1_mdu,
                   "Unready younger COMMIT writer blocks old MDU fallback");

        clear_producers();
        mdu_valid = 1'b1; mdu_ready = 1'b1;
        mdu_rd = 5'd9; mdu_value = 32'hdddd_0009;
        mem2_valid = 1'b1; mem2_write = 1'b1; mem2_ready = 1'b0;
        mem2_is_load = 1'b1; mem2_pc = 32'h8000_02c0;
        mem2_rd = 5'd9; mdu_passed_mem2 = 1'b1; #1;
        check_true(rs2_blocked && rs2_late_load && !rs2_mdu &&
                   rs2_late_load_pc == 32'h8000_02c0,
                   "Age selection applies symmetrically to rs2");

        clear_producers();
        ex_valid = 1'b1; ex_write = 1'b1; ex_ready = 1'b1;
        ex_rd = 5'd7; ex_value = 32'heeee_0007; #1;
        check_true(rs1_value == 32'heeee_0007 && !rs1_blocked,
                   "EX ready producer bypasses rs1");
        ex_ready = 1'b0; #1;
        check_true(rs1_value == 32'heeee_0007 && rs1_blocked,
                   "EX unready producer blocks rs1");

        clear_producers();
        mem1_valid = 1'b1; mem1_write = 1'b1; mem1_ready = 1'b1;
        mem1_rd = 5'd7; mem1_value = 32'h1111_0007; #1;
        check_true(rs1_value == 32'h1111_0007 && !rs1_blocked,
                   "MEM1 ready producer bypasses rs1");
        mem1_ready = 1'b0; #1;
        check_true(rs1_blocked, "MEM1 unready producer blocks rs1");

        clear_producers();
        mem2_valid = 1'b1; mem2_write = 1'b1; mem2_ready = 1'b1;
        mem2_rd = 5'd7; mem2_value = 32'h2222_0007; #1;
        check_true(rs1_value == 32'h2222_0007 && !rs1_blocked,
                   "MEM2 ready producer bypasses rs1");
        mem2_ready = 1'b0; #1;
        check_true(rs1_blocked && !rs1_late_load,
                   "MEM2 unready non-load producer hard-blocks rs1");
        mem2_is_load = 1'b1; #1;
        check_true(rs1_blocked && rs1_late_load,
                   "MEM2 unready load marks rs1 for late EX forwarding");
        check_true(rs1_late_load_pc == 32'd0,
                   "MEM2 load tag defaults to producer PC zero");

        // An unready load in EX or MEM1 also soft-releases the consumer and
        // carries the producer PC, so the EX-side capture can reject an older
        // same-rd load that completes earlier.
        clear_producers();
        ex_valid = 1'b1; ex_write = 1'b1; ex_ready = 1'b0;
        ex_is_load = 1'b1; ex_pc = 32'h8000_0004;
        ex_rd = 5'd7; ex_value = 32'hffff_0007;
        mem2_valid = 1'b1; mem2_write = 1'b1; mem2_ready = 1'b1;
        mem2_is_load = 1'b1; mem2_pc = 32'h8000_0000;
        mem2_rd = 5'd7; mem2_value = 32'h2222_0007; #1;
        check_true(rs1_blocked && rs1_late_load &&
                   rs1_late_load_pc == 32'h8000_0004,
                   "Youngest unready EX load tags rs1 with its own PC");
        ex_valid = 1'b0; #1;
        check_true(!rs1_blocked && !rs1_late_load &&
                   rs1_value == 32'h2222_0007,
                   "Ready MEM2 load bypasses once the younger load leaves");

        clear_producers();
        mem1_valid = 1'b1; mem1_write = 1'b1; mem1_ready = 1'b0;
        mem1_is_load = 1'b1; mem1_pc = 32'h8000_0008;
        mem1_rd = 5'd7; mem1_value = 32'h1111_0007; #1;
        check_true(rs1_blocked && rs1_late_load &&
                   rs1_late_load_pc == 32'h8000_0008,
                   "Unready MEM1 load tags rs1 with its producer PC");

        clear_producers();
        commit_valid = 1'b1; commit_write = 1'b1; commit_ready = 1'b1;
        commit_rd = 5'd7; commit_value = 32'hcccc_0007; #1;
        check_true(rs1_value == 32'hcccc_0007 && !rs1_blocked,
                   "COMMIT ready producer bypasses rs1");
        commit_ready = 1'b0; #1;
        check_true(rs1_blocked, "COMMIT unready producer blocks rs1");

        clear_producers();
        ex_valid = 1'b1; ex_write = 1'b1; ex_ready = 1'b1;
        ex_rd = 5'd9; ex_value = 32'heeee_0009; #1;
        check_true(rs2_value == 32'heeee_0009 && !rs2_blocked,
                   "EX ready producer bypasses rs2");
        clear_producers();
        mem1_valid = 1'b1; mem1_write = 1'b1; mem1_ready = 1'b1;
        mem1_rd = 5'd9; mem1_value = 32'h1111_0009; #1;
        check_true(rs2_value == 32'h1111_0009 && !rs2_blocked,
                   "MEM1 ready producer bypasses rs2");
        clear_producers();
        mem2_valid = 1'b1; mem2_write = 1'b1; mem2_ready = 1'b1;
        mem2_rd = 5'd9; mem2_value = 32'h2222_0009; #1;
        check_true(rs2_value == 32'h2222_0009 && !rs2_blocked,
                   "MEM2 ready producer bypasses rs2");
        mem2_ready = 1'b0; mem2_is_load = 1'b1; #1;
        check_true(rs2_blocked && rs2_late_load,
                   "MEM2 unready load marks rs2 for late EX forwarding");
        clear_producers();
        commit_valid = 1'b1; commit_write = 1'b1; commit_ready = 1'b0;
        commit_rd = 5'd9; commit_value = 32'hcccc_0009; #1;
        check_true(rs2_value == 32'hcccc_0009 && rs2_blocked,
                   "COMMIT unready producer blocks rs2");

        clear_producers();
        mdu_valid = 1'b1; mdu_ready = 1'b1;
        mdu_rd = 5'd9; mdu_value = 32'hdddd_0009; #1;
        check_true(rs2_value == 32'hdddd_0009 && !rs2_blocked,
                   "Completed MDU producer bypasses rs2");

        // Every residence matches rs1. The youngest match is authoritative,
        // even when an older residence has a ready value.
        clear_producers();
        ex_valid = 1'b1; ex_write = 1'b1; ex_ready = 1'b0;
        ex_rd = 5'd7; ex_value = 32'heeee_7000;
        mem1_valid = 1'b1; mem1_write = 1'b1; mem1_ready = 1'b1;
        mem1_rd = 5'd7; mem1_value = 32'h1111_7000;
        mem2_valid = 1'b1; mem2_write = 1'b1; mem2_ready = 1'b1;
        mem2_rd = 5'd7; mem2_value = 32'h2222_7000;
        commit_valid = 1'b1; commit_write = 1'b1; commit_ready = 1'b1;
        commit_rd = 5'd7; commit_value = 32'hcccc_7000; #1;
        check_true(rs1_blocked && rs1_value == 32'heeee_7000,
                   "Unready youngest match blocks instead of reading around");
        ex_valid = 1'b0; #1;
        check_true(!rs1_blocked && rs1_value == 32'h1111_7000,
                   "Next-youngest residence wins after EX leaves");
        mem1_ready = 1'b0; #1;
        check_true(rs1_blocked && rs1_value == 32'h1111_7000,
                   "Unready MEM1 blocks older MEM2 and COMMIT values");

        clear_producers();
        rs1_addr = 5'd0;
        ex_valid = 1'b1; ex_write = 1'b1; ex_ready = 1'b0;
        ex_rd = 5'd0; ex_value = 32'hffff_ffff; #1;
        check_true(rs1_value == 32'd0 && !rs1_blocked,
                   "x0 is never a producer dependency");
        rs1_addr = 5'd7;
        uses_rs1 = 1'b0;
        ex_rd = 5'd7; #1;
        check_true(rs1_value == rs1_reg_data && !rs1_blocked,
                   "Unused source ignores matching producer identities");

        if(DUAL_ISSUE!=0)begin
            rs1_addr=7;rs2_addr=7;uses_rs1=1;uses_rs2=1;
            for(stage=0;stage<4;stage=stage+1)begin
                clear_producers();
                case(stage)
                    0:begin ex_valid=1;ex_write=1;ex_rd=7;ex_value=32'h1111;ex_second=second_packet(7,32'h2222);end
                    1:begin mem1_valid=1;mem1_write=1;mem1_rd=7;mem1_value=32'h1111;mem1_second=second_packet(7,32'h2222);end
                    2:begin mem2_valid=1;mem2_write=1;mem2_rd=7;mem2_value=32'h1111;mem2_second=second_packet(7,32'h2222);end
                    3:begin commit_valid=1;commit_write=1;commit_rd=7;commit_value=32'h1111;commit_second=second_packet(7,32'h2222);end
                endcase
                #1;check_true(rs1_value==32'h2222&&rs2_value==32'h2222&&!rs1_blocked&&!rs2_blocked,
                    "B is the younger writer in every registered parent");
                mdu_valid=1;mdu_ready=1;mdu_rd=7;mdu_value=32'h3333;
                #1;check_true(rs1_value==(stage==0?32'h2222:32'h3333),
                    "MDU age precedes/ follows a secondary producer by crossing flags");
                mdu_passed_mem1=1;mdu_passed_mem2=1;mdu_authorized=1;
                #1;check_true(rs1_value==32'h2222&&!rs1_blocked,"Younger B shadows an older completed MDU");
                mdu_valid=0;
                ex_valid=0;mem1_valid=0;mem2_valid=0;commit_valid=0;
                #1;check_true(rs1_value==rs1_reg_data&&!rs1_blocked,"Invalid parent masks stale secondary payload");
            end
            clear_producers();
            mem1_valid=1;mem1_second=second_packet(7,32'h4444);
            ex_valid=1;ex_write=1;ex_ready=0;ex_is_load=1;ex_rd=7;ex_pc=32'h80000088;
            #1;check_true(rs1_blocked&&rs1_late_load&&rs1_late_load_pc==32'h80000088,
                "A younger unfinished load shadows older ready B");
            ex_valid=0;
            #1;check_true(rs1_value==32'h4444&&!rs1_blocked,"MEM1 B is independent of parent ready/write");
            uses_rs1=0;
            #1;check_true(rs1_value==rs1_reg_data&&!rs1_blocked,"Unused source ignores B");
            rs2_addr=0;mem1_second=second_packet(0,32'hffff);
            #1;check_true(rs2_value==0&&!rs2_blocked,"B writing x0 is never a dependency");
        end

        $display("PASS: age-ordered operand resolver (%0d checks)", checks);
        $finish;
    end
endmodule
