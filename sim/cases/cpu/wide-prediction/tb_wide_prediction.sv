`timescale 1ns/1ps
`include "edrv32_uop.vh"
module tb_wide_prediction;
    localparam [31:0] BASE=32'h80000000;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0;
    reg block_valid=0;
    wire block_ready;
    reg [31:0] block_addr,block_data;
    reg [31:0] block_upper=0;
    reg block_error;
    reg [1:0] block_epoch;
    reg ready=0,second_ready=0;
    reg redirect=0;
    reg [31:0] redirect_target=BASE;
    reg [1:0] redirect_epoch=0;
    wire first_valid,second_window_valid,first_accept,second_accept;
    wire valid,second_valid;
    wire [2:0] consume_halfwords;
    wire [15:0] halfword0;
    wire [15:0] second_halfword0;
    wire [15:0] halfword1;
    wire [15:0] second_halfword1;
    wire  halfword1_valid;
    wire  second_halfword1_valid;
    wire [31:0] pc;
    wire [31:0] second_pc;
    wire  halfword0_error;
    wire  second_halfword0_error;
    wire  halfword1_error;
    wire  second_halfword1_error;
    wire [`EDRV32_EPOCH_W-1:0] epoch;
    wire [`EDRV32_EPOCH_W-1:0] second_epoch;
    wire  predicted_taken;
    wire  second_predicted_taken;
    wire [31:0] predicted_target;
    wire [31:0] second_predicted_target;
    wire [1:0] predictor_meta;
    wire [1:0] second_predictor_meta;
    wire [31:0] out_pc;
    wire [31:0] out_second_pc;
    wire [31:0] out_instr;
    wire [31:0] out_second_instr;
    wire [31:0] out_raw_instr;
    wire [31:0] out_second_raw_instr;
    wire  out_is_compressed;
    wire  out_second_is_compressed;
    wire  out_fetch_fault;
    wire  out_second_fetch_fault;
    wire  out_compressed_illegal;
    wire  out_second_compressed_illegal;
    wire [`EDRV32_EPOCH_W-1:0] out_epoch;
    wire [`EDRV32_EPOCH_W-1:0] out_second_epoch;
    wire  out_predicted_taken;
    wire  out_second_predicted_taken;
    wire [31:0] out_predicted_target;
    wire [31:0] out_second_predicted_target;
    wire [1:0] out_predictor_meta;
    wire [1:0] out_second_predictor_meta;
    wire pred_redirect;
    wire [31:0] pred_target;
    wire [1:0] next_epoch=u_if2.active_epoch_r+2'd1;
    edrv32_if2_stage #(.RESET_PC(BASE),.DUAL_WINDOW(1),.FETCH_WIDE(1)) u_if2 (
        .clk_i(clk),.rst_n_i(rst_n),
        .block_upper_i(block_upper),.block_words_i(2'd2),
        .block_predicted_taken2_i(1'b0),.block_predicted_target2_i(32'd0),.block_predictor_meta2_i(2'd0),
        .block_predicted_taken3_i(1'b0),.block_predicted_target3_i(32'd0),.block_predictor_meta3_i(2'd0),
        .block_valid_i(block_valid),.block_ready_o(block_ready),
        .block_addr_i(block_addr),.block_data_i(block_data),
        .block_error_i(block_error),.block_epoch_i(block_epoch),
        .block_predicted_taken0_i(1'b0),.block_predicted_target0_i(block_addr+32'h80),
        .block_predictor_meta0_i(block_addr[3:2]),
        .block_predicted_taken1_i(1'b0),.block_predicted_target1_i(block_addr+32'h82),
        .block_predictor_meta1_i(~block_addr[3:2]),
        .preview_valid_i(1'b0),.preview_addr_i(32'd0),.preview_epoch_i(2'd0),
        .preview_target0_i(32'd0),.preview_target1_i(32'd0),
        .window_valid_o(first_valid),.window_ready_i(first_accept),
        .second_window_valid_o(second_window_valid),.second_window_accept_i(second_accept),
        .halfword0_o(halfword0),.second_halfword0_o(second_halfword0),
        .halfword1_o(halfword1),.second_halfword1_o(second_halfword1),
        .halfword1_valid_o(halfword1_valid),.second_halfword1_valid_o(second_halfword1_valid),
        .window_pc_o(pc),.second_window_pc_o(second_pc),
        .halfword0_error_o(halfword0_error),.second_halfword0_error_o(second_halfword0_error),
        .halfword1_error_o(halfword1_error),.second_halfword1_error_o(second_halfword1_error),
        .window_epoch_o(epoch),.second_window_epoch_o(second_epoch),
        .window_predicted_taken_o(predicted_taken),.second_window_predicted_taken_o(second_predicted_taken),
        .window_predicted_target_o(predicted_target),.second_window_predicted_target_o(second_predicted_target),
        .window_predictor_meta_o(predictor_meta),.second_window_predictor_meta_o(second_predictor_meta),
        .prediction_redirect_valid_o(pred_redirect),.prediction_redirect_target_o(pred_target),
        .prediction_redirect_fast_o(),.prediction_redirect_fast_slot1_o(),
        .prediction_redirect_fire_i(pred_redirect),.prediction_redirect_epoch_i(next_epoch),
        .hpm_consume_halfwords_o(consume_halfwords),
        .redirect_fire_i(redirect),.redirect_target_i(redirect_target),
        .redirect_epoch_i(redirect_epoch),.kill_i(redirect)
    );
    assign first_accept=ready;
    assign second_accept=second_ready;
    reg [31:0] expected_pc[0:31];
    reg verify_payload=0;
    wire [31:0] jump32=jal32(32);
    integer expected_count=0,seen=0,predictions=0;
    reg [31:0] expected_target;
    function automatic [31:0] jal32;
        input [20:0] imm;
        begin jal32={imm[20],imm[10:1],imm[11],imm[19:12],5'd0,7'h6f};end
    endfunction
    task automatic send;
        input [31:0] address,low,high;
        begin
            @(negedge clk);block_valid=1;block_addr=address;block_data=low;block_upper=high;
            block_epoch=u_if2.active_epoch_r;
            do @(posedge clk);while(!block_ready);
            @(negedge clk);block_valid=0;
        end
    endtask
    task automatic begin_case;
        input integer n;
        begin
            @(negedge clk);ready=0;second_ready=0;redirect=1;
            redirect_target=BASE;redirect_epoch=next_epoch;
            @(negedge clk);redirect=0;seen=0;predictions=0;expected_count=n;
        end
    endtask
    task automatic drain;
        integer n;
        begin
            ready=1;second_ready=1;
            for(n=0;n<12;n=n+1)@(negedge clk);
            if(seen!=expected_count||predictions!=1)$fatal(1,"prediction stream missing or duplicated %0d/%0d pred=%0d",seen,expected_count,predictions);
        end
    endtask
    always @(posedge clk)if(rst_n&&!redirect)begin
        if(pred_redirect)begin
            if(pred_target!==expected_target)$fatal(1,"wrong wide prediction target %h/%h",pred_target,expected_target);
            predictions=predictions+1;
        end
        if(first_valid&&ready)begin
            if(pc!==expected_pc[seen])$fatal(1,"wrong first predicted stream PC %h/%h",pc,expected_pc[seen]);
            if(verify_payload && halfword0 !== ((seen==16) ? 16'ha005 : 16'h0001))
                $fatal(1,"older FIFO payload overwritten at PC %h",pc);
            seen=seen+1;
            if(second_window_valid&&second_ready)begin
                if(second_pc!==expected_pc[seen])$fatal(1,"wrong second predicted stream PC");
                if(verify_payload && second_halfword0 !== ((seen==16) ? 16'ha005 : 16'h0001))
                    $fatal(1,"older second FIFO payload overwritten at PC %h",second_pc);
                seen=seen+1;
            end
        end
    end
    integer fill_index;
    initial begin
        block_addr=BASE;block_data=0;block_upper=0;block_error=0;block_epoch=0;
        repeat(3)@(negedge clk);rst_n=1;
        // Upper word: a complete 32-bit direct jump.
        begin_case(2);expected_pc[0]=BASE;expected_pc[1]=BASE+4;expected_target=BASE+68;
        send(BASE,32'h00000013,jal32(64));drain();
        // 32-bit jump begins in halfword 1 and completes in the upper word.
        begin_case(2);expected_pc[0]=BASE;expected_pc[1]=BASE+2;expected_target=BASE+34;
        send(BASE,{jump32[15:0],16'h0001},{16'h0001,jump32[31:16]});drain();
        // A compressed jump in the fourth halfword follows three C.NOPs.
        begin_case(4);expected_pc[0]=BASE;expected_pc[1]=BASE+2;expected_pc[2]=BASE+4;expected_pc[3]=BASE+6;
        expected_target=BASE+38;send(BASE,32'h00010001,32'ha0050001);drain();
        // Fourth halfword is a 32-bit jump: continuation must arrive before redirect.
        begin_case(4);expected_target=BASE+38;
        send(BASE,32'h00010001,{jump32[15:0],16'h0001});
        if(predictions!=0)$fatal(1,"redirect before cross-block continuation");
        send(BASE+8,{16'h0001,jump32[31:16]},32'h00010001);drain();
        // Only one slot is free: accept a one-halfword predicted prefix of
        // a four-halfword block without corrupting older FIFO instructions.
        begin_case(17);verify_payload=1;expected_target=BASE+64;
        for(fill_index=0;fill_index<17;fill_index=fill_index+1)
            expected_pc[fill_index]=BASE+fill_index*2;
        for(fill_index=0;fill_index<4;fill_index=fill_index+1)
            send(BASE+fill_index*8,32'h00010001,32'h00010001);
        if(u_if2.count_r!==4'd12)$fatal(1,"near-full prediction setup did not fill FIFO");
        @(negedge clk);ready=1;
        @(negedge clk);ready=0;
        repeat(2)@(negedge clk);
        if(u_if2.count_r!==4'd11)$fatal(1,"near-full prediction setup did not free one slot");
        send(BASE+32,32'h006fa005,32'h00000013);drain();verify_payload=0;
        $display("PASS: wide prediction lanes 1/2/3, cross-block continuation and near-full prefix preservation");$finish;
    end
endmodule
