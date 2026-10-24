`timescale 1ns/1ps
`include "edrv32_uop.vh"
module tb_dual_frontend #(parameter FETCH_WIDE=0);
    localparam [31:0] BASE=32'h80000000;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0;
    reg block_valid=0;
    wire block_ready;
    reg [31:0] block_addr,block_data;
    reg [31:0] block_upper=0;
    reg [1:0] block_words=1;
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
    edrv32_if2_stage #(.RESET_PC(BASE),.DUAL_WINDOW(1),.FETCH_WIDE(FETCH_WIDE)) u_if2 (
        .clk_i(clk),.rst_n_i(rst_n),
        .block_upper_i(block_upper),.block_words_i(block_words),
        .block_predicted_taken2_i(1'b0),.block_predicted_target2_i(block_addr+32'h84),
        .block_predictor_meta2_i((block_addr+32'd4)>>2),
        .block_predicted_taken3_i(1'b0),.block_predicted_target3_i(block_addr+32'h86),
        .block_predictor_meta3_i(~((block_addr+32'd4)>>2)),
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
        .prediction_redirect_valid_o(),.prediction_redirect_target_o(),
        .prediction_redirect_fast_o(),.prediction_redirect_fast_slot1_o(),
        .prediction_redirect_fire_i(1'b0),.prediction_redirect_epoch_i(2'd0),
        .hpm_consume_halfwords_o(consume_halfwords),
        .redirect_fire_i(redirect),.redirect_target_i(redirect_target),
        .redirect_epoch_i(redirect_epoch),.kill_i(redirect)
    );
    edrv32_align_pair_stage u_align (
        .clk_i(clk),.rst_n_i(rst_n),.kill_i(redirect),
        .window_valid_i(first_valid),.window_accept_o(first_accept),
        .second_window_valid_i(second_window_valid),.second_window_accept_o(second_accept),
        .halfword0_i(halfword0),.second_halfword0_i(second_halfword0),
        .halfword1_i(halfword1),.second_halfword1_i(second_halfword1),
        .halfword1_valid_i(halfword1_valid),.second_halfword1_valid_i(second_halfword1_valid),
        .pc_i(pc),.second_pc_i(second_pc),
        .halfword0_error_i(halfword0_error),.second_halfword0_error_i(second_halfword0_error),
        .halfword1_error_i(halfword1_error),.second_halfword1_error_i(second_halfword1_error),
        .epoch_i(epoch),.second_epoch_i(second_epoch),
        .predicted_taken_i(predicted_taken),.second_predicted_taken_i(second_predicted_taken),
        .predicted_target_i(predicted_target),.second_predicted_target_i(second_predicted_target),
        .predictor_meta_i(predictor_meta),.second_predictor_meta_i(second_predictor_meta),
        .valid_o(valid),.ready_i(ready),.second_valid_o(second_valid),.second_ready_i(second_ready),
        .pc_o(out_pc),.second_pc_o(out_second_pc),
        .instr_o(out_instr),.second_instr_o(out_second_instr),
        .raw_instr_o(out_raw_instr),.second_raw_instr_o(out_second_raw_instr),
        .is_compressed_o(out_is_compressed),.second_is_compressed_o(out_second_is_compressed),
        .fetch_fault_o(out_fetch_fault),.second_fetch_fault_o(out_second_fetch_fault),
        .compressed_illegal_o(out_compressed_illegal),.second_compressed_illegal_o(out_second_compressed_illegal),
        .epoch_o(out_epoch),.second_epoch_o(out_second_epoch),
        .predicted_taken_o(out_predicted_taken),.second_predicted_taken_o(out_second_predicted_taken),
        .predicted_target_o(out_predicted_target),.second_predicted_target_o(out_second_predicted_target),
        .predictor_meta_o(out_predictor_meta),.second_predictor_meta_o(out_second_predictor_meta)
    );
    reg [15:0] rom [0:8191];
    reg [31:0] instruction [0:4095];
    reg [31:0] instruction_pc [0:4095];
    reg is_c [0:4095];
    integer seed=1;
    reg [31:0] random_state;
    reg [1:0] current_epoch=0,old_epoch=0;
    integer expected_index=0,block_index=0,stale_budget=0;
    integer checks=0,delivered=0,paired=0,streak=0,max_streak=0,stale=0;
    integer first_only=0,redirects=0,consume3=0,consume4=0;
    integer i,h,j,pops,acked,was_stale,target_index;
    localparam PACKET_W=134+`EDRV32_EPOCH_W;
    wire [PACKET_W-1:0] output_packet={out_pc,out_instr,out_raw_instr,
        out_is_compressed,out_fetch_fault,out_compressed_illegal,out_epoch,
        out_predicted_taken,out_predicted_target,out_predictor_meta};
    wire [PACKET_W-1:0] second_output_packet={out_second_pc,out_second_instr,
        out_second_raw_instr,out_second_is_compressed,out_second_fetch_fault,
        out_second_compressed_illegal,out_second_epoch,out_second_predicted_taken,
        out_second_predicted_target,out_second_predictor_meta};
    function automatic block_fault;
        input integer index;
        begin block_fault=(FETCH_WIDE==0)&&(index%53==7);end
    endfunction
    function automatic [PACKET_W-1:0] gold;
        input integer index;
        integer lower,upper;
        reg fault;
        reg [31:0] canonical,raw,at_pc;
        reg [1:0] meta;
        begin
            at_pc=instruction_pc[index];lower=(at_pc-BASE)/4;
            upper=(at_pc-BASE+(is_c[index]?0:2))/4;
            fault=block_fault(lower)||block_fault(upper);
            raw=instruction[index];canonical=raw;
            if(is_c[index])canonical=(raw==32'h0085)?32'h00108093:32'h00000013;
            meta=at_pc[1]?~at_pc[3:2]:at_pc[3:2];
            gold={at_pc,canonical,raw,is_c[index],fault,1'b0,current_epoch,
                  1'b0,(at_pc+32'h80),meta};
        end
    endfunction
    task automatic verify;
        input condition;
        input [8*110-1:0] message;
        begin
            checks=checks+1;
            if(!condition)begin
                $display("FAIL seed=%0d expected_index=%0d pc=%08x second_pc=%08x",seed,expected_index,out_pc,out_second_pc);
                $fatal(1,"%0s",message);
            end
        end
    endtask
    task automatic drive_block;
        input force_valid;
        begin
            if(!block_valid)block_valid=force_valid;
            block_addr=BASE+block_index*4;
            block_words=(FETCH_WIDE!=0 && block_index%4!=3)?2:1;
            block_data={rom[block_index*2+1],rom[block_index*2]};
            block_upper={rom[block_index*2+3],rom[block_index*2+2]};
            block_error=block_fault(block_index);
            block_epoch=(stale_budget>0)?old_epoch:current_epoch;
        end
    endtask
    task automatic step;
        begin
            #1;
            if(valid)verify(output_packet===gold(expected_index),"Oldest instruction matches independent ROM parser");
            if(second_valid)verify(second_output_packet===gold(expected_index+1),"Second instruction matches independent ROM parser");
            verify(!second_accept||first_accept,"IF2 B cannot transfer without A");
            if(consume_halfwords==3)consume3=consume3+1;
            if(consume_halfwords==4)consume4=consume4+1;
            pops=(!redirect&&valid&&ready)?((second_valid&&second_ready)?2:1):0;
            acked=block_valid&&block_ready;was_stale=stale_budget>0;
            @(posedge clk);
            if(redirect)begin
                expected_index=target_index;
                block_index=(redirect_target-BASE)/4;
                old_epoch=current_epoch;current_epoch=redirect_epoch;
                stale_budget=2;redirects=redirects+1;
            end else begin
                expected_index=expected_index+pops;delivered=delivered+pops;
                if(acked)begin
                    if(was_stale)begin stale_budget=stale_budget-1;stale=stale+1;end
                    else block_index=block_index+block_words;
                end
            end
            if(pops==2)begin paired=paired+1;streak=streak+1;if(streak>max_streak)max_streak=streak;end
            else begin streak=0;if(pops==1)first_only=first_only+1;end
            if(acked)block_valid=0;
            @(negedge clk);
        end
    endtask
    initial begin
        if(!$value$plusargs("SEED=%d",seed))seed=1;
        random_state=seed;h=0;
        for(i=0;i<4096;i=i+1)begin
            is_c[i]=((i<128)&&(FETCH_WIDE==0))||((i>=128)&&((i%3==0)||(i%7==0)));
            instruction_pc[i]=BASE+h*2;
            instruction[i]=is_c[i]?((i%2==0)?32'h0001:32'h0085):(32'h00000293|(i[11:0]<<20));
            rom[h]=instruction[i][15:0];h=h+1;
            if(!is_c[i])begin rom[h]=instruction[i][31:16];h=h+1;end
        end
        for(i=h;i<8192;i=i+1)rom[i]=16'h0001;
        drive_block(0);repeat(2)@(posedge clk);@(negedge clk);rst_n=1;
        // 32-bit block bandwidth is sufficient for sustained two compressed instructions.
        ready=1;second_ready=1;
        for(j=0;j<58;j=j+1)begin drive_block(1);step();end
        verify(max_streak>=16,"Sustained two-instruction delivery reaches coverage");
        for(j=0;j<2600;j=j+1)begin
            random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            ready=random_state[0];second_ready=random_state[1];
            redirect=(j==120)||(j==400)||(j==900)||(j==1800);
            if(redirect)begin
                target_index=(j==120)?151:(j==400)?227:(j==900)?313:401;
                redirect_target=instruction_pc[target_index];redirect_epoch=current_epoch+1'b1;
            end
            drive_block(random_state[2]);step();redirect=0;
        end
        block_valid=0;ready=1;second_ready=1;
        for(j=0;j<12;j=j+1)step();
        verify(paired>40&&first_only>40&&stale==8&&redirects==4,"Pair, scalar, stale and epoch-wrap coverage");
        verify(consume3>0&&consume4>0,"Mixed-width double captures exercised");
        $display("PASS: dual frontend seed=%0d checks=%0d delivered=%0d paired=%0d longest_pair_run=%0d scalar=%0d stale=%0d redirects=%0d consume3=%0d consume4=%0d",seed,checks,delivered,paired,max_streak,first_only,stale,redirects,consume3,consume4);
        $finish;
    end
    initial begin #2000000;$fatal(1,"dual frontend watchdog");end
    reg [2047:0] wave_path;
    initial begin
        if ($test$plusargs("WAVE")) begin
            if (!$value$plusargs("WAVEFILE=%s",wave_path)) wave_path="wave.vcd";
            $dumpfile(wave_path);
            $dumpvars(0,tb_dual_frontend);
        end
    end
endmodule
