`timescale 1ns/1ps
`include "edrv32_uop.vh"
module tb_dual_align;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0;
    reg kill=0;
    reg window_valid=0;
    reg second_window_valid=0;
    reg ready=0;
    reg second_ready=0;
    wire window_accept;
    wire second_window_accept;
    wire valid;
    wire second_valid;
    reg [15:0] halfword0;
    reg [15:0] second_halfword0;
    reg [15:0] halfword1;
    reg [15:0] second_halfword1;
    reg  halfword1_valid;
    reg  second_halfword1_valid;
    reg [31:0] pc;
    reg [31:0] second_pc;
    reg  halfword0_error;
    reg  second_halfword0_error;
    reg  halfword1_error;
    reg  second_halfword1_error;
    reg [`EDRV32_EPOCH_W-1:0] epoch;
    reg [`EDRV32_EPOCH_W-1:0] second_epoch;
    reg  predicted_taken;
    reg  second_predicted_taken;
    reg [31:0] predicted_target;
    reg [31:0] second_predicted_target;
    reg [1:0] predictor_meta;
    reg [1:0] second_predictor_meta;
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
    edrv32_align_pair_stage u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .kill_i(kill),
        .window_valid_i(window_valid),
        .window_accept_o(window_accept),
        .second_window_valid_i(second_window_valid),
        .second_window_accept_o(second_window_accept),
        .halfword0_i(halfword0),
        .second_halfword0_i(second_halfword0),
        .halfword1_i(halfword1),
        .second_halfword1_i(second_halfword1),
        .halfword1_valid_i(halfword1_valid),
        .second_halfword1_valid_i(second_halfword1_valid),
        .pc_i(pc),
        .second_pc_i(second_pc),
        .halfword0_error_i(halfword0_error),
        .second_halfword0_error_i(second_halfword0_error),
        .halfword1_error_i(halfword1_error),
        .second_halfword1_error_i(second_halfword1_error),
        .epoch_i(epoch),
        .second_epoch_i(second_epoch),
        .predicted_taken_i(predicted_taken),
        .second_predicted_taken_i(second_predicted_taken),
        .predicted_target_i(predicted_target),
        .second_predicted_target_i(second_predicted_target),
        .predictor_meta_i(predictor_meta),
        .second_predictor_meta_i(second_predictor_meta),
        .valid_o(valid),
        .ready_i(ready),
        .second_valid_o(second_valid),
        .second_ready_i(second_ready),
        .pc_o(out_pc),
        .second_pc_o(out_second_pc),
        .instr_o(out_instr),
        .second_instr_o(out_second_instr),
        .raw_instr_o(out_raw_instr),
        .second_raw_instr_o(out_second_raw_instr),
        .is_compressed_o(out_is_compressed),
        .second_is_compressed_o(out_second_is_compressed),
        .fetch_fault_o(out_fetch_fault),
        .second_fetch_fault_o(out_second_fetch_fault),
        .compressed_illegal_o(out_compressed_illegal),
        .second_compressed_illegal_o(out_second_compressed_illegal),
        .epoch_o(out_epoch),
        .second_epoch_o(out_second_epoch),
        .predicted_taken_o(out_predicted_taken),
        .second_predicted_taken_o(out_second_predicted_taken),
        .predicted_target_o(out_predicted_target),
        .second_predicted_target_o(out_second_predicted_target),
        .predictor_meta_o(out_predictor_meta),
        .second_predictor_meta_o(out_second_predictor_meta)
    );
    localparam PACKET_W=134+`EDRV32_EPOCH_W;
    reg [PACKET_W-1:0] reference [0:20000];
    wire [PACKET_W-1:0] output_packet={out_pc,out_instr,out_raw_instr,
        out_is_compressed,out_fetch_fault,out_compressed_illegal,out_epoch,
        out_predicted_taken,out_predicted_target,out_predictor_meta};
    wire [PACKET_W-1:0] second_output_packet={out_second_pc,out_second_instr,
        out_second_raw_instr,out_second_is_compressed,out_second_fetch_fault,
        out_second_compressed_illegal,out_second_epoch,out_second_predicted_taken,
        out_second_predicted_target,out_second_predictor_meta};
    integer head=0,tail=0,checks=0,pair_capture=0,pair_pop=0;
    integer one_pop=0,full_checks=0,kills=0,i,j,pops,takes;
    reg [31:0] random_state;
    integer seed=1;
    reg [PACKET_W-1:0] input_packet,second_input_packet;

    function automatic [PACKET_W-1:0] gold;
        input [15:0] low,high;
        input [31:0] at_pc;
        input err0,err1;
        input [`EDRV32_EPOCH_W-1:0] at_epoch;
        input taken;
        input [31:0] target;
        input [1:0] meta;
        reg c,illegal;
        reg [31:0] canonical,raw;
        begin
            c=low[1:0]!=2'b11;illegal=0;raw=c?{16'd0,low}:{high,low};
            canonical=raw;
            if(c) begin
                case(low)
                    16'h0001: canonical=32'h00000013;
                    16'h0085: canonical=32'h00108093;
                    16'h0000: begin canonical=32'h00010413;illegal=1;end
                    default: $fatal(1,"Gold only accepts specified compressed vectors");
                endcase
            end
            gold={at_pc,canonical,raw,c,(err0||(!c&&err1)),illegal,
                  at_epoch,taken,target,meta};
        end
    endfunction
    task automatic verify;
        input condition;
        input [8*100-1:0] message;
        begin checks=checks+1;if(!condition)$fatal(1,"%0s seed=%0d check=%0d",message,seed,checks);end
    endtask
    task automatic step;
        begin
            #1;
            verify(valid==((tail-head)>0),"Head validity matches reference FIFO");
            verify(second_valid==((tail-head)>1),"Second validity matches reference FIFO");
            if(valid)verify(output_packet===reference[head],"Head payload and metadata preserved");
            if(second_valid)verify(second_output_packet===reference[head+1],"Second payload preserved");
            if((tail-head)==4)begin
                verify(!window_accept&&!second_window_accept,"Full capacity cannot reuse output ready combinationally");
                full_checks=full_checks+1;
            end
            if(kill)verify(!window_accept&&!second_window_accept,"Kill closes both input captures");
            verify(!second_window_accept||window_accept,"Younger input cannot advance alone");
            input_packet=gold(halfword0,halfword1,pc,halfword0_error,halfword1_error,
                              epoch,predicted_taken,predicted_target,predictor_meta);
            second_input_packet=gold(second_halfword0,second_halfword1,second_pc,
                second_halfword0_error,second_halfword1_error,second_epoch,
                second_predicted_taken,second_predicted_target,second_predictor_meta);
            pops=(!kill&&valid&&ready)?((second_valid&&second_ready)?2:1):0;
            takes=window_accept?(second_window_accept?2:1):0;
            if(pops==2)pair_pop=pair_pop+1;
            if(pops==1)one_pop=one_pop+1;
            if(takes==2)pair_capture=pair_capture+1;
            @(posedge clk);
            if(kill)begin head=0;tail=0;kills=kills+1;end
            else begin
                head=head+pops;
                if(takes>0)begin reference[tail]=input_packet;tail=tail+1;end
                if(takes>1)begin reference[tail]=second_input_packet;tail=tail+1;end
            end
            verify((tail-head)<=4,"Reference occupancy stays within capacity");
            @(negedge clk);
        end
    endtask
    task automatic offer;
        input integer index;
        input first_compressed,second_compressed;
        begin
            window_valid=1;second_window_valid=1;
            halfword0=first_compressed?16'h0085:16'h0093;halfword1=16'h0020;
            halfword1_valid=1;pc=32'h80000000+index*8;
            halfword0_error=0;halfword1_error=0;epoch=2'd1;
            predicted_taken=0;predicted_target=pc+32'h80;predictor_meta=index[1:0];
            second_halfword0=second_compressed?16'h0001:16'h0113;second_halfword1=16'h0030;
            second_halfword1_valid=1;second_pc=pc+(first_compressed?2:4);
            second_halfword0_error=0;second_halfword1_error=0;second_epoch=epoch;
            second_predicted_taken=0;second_predicted_target=pc+32'h100;
            second_predictor_meta=~index[1:0];
        end
    endtask
    task automatic drain;
        begin
            window_valid=0;second_window_valid=0;ready=1;second_ready=1;
            while(tail!=head)step();
        end
    endtask
    initial begin
        if(!$value$plusargs("SEED=%d",seed))seed=1;
        random_state=seed;offer(0,1,1);window_valid=0;second_window_valid=0;
        repeat(2)@(posedge clk);@(negedge clk);rst_n=1;
        // All four length combinations and independent metadata.
        for(i=0;i<4;i=i+1)begin offer(i,i[1],i[0]);ready=0;second_ready=0;
            #1;verify(window_accept&&second_window_accept,"Both complete lengths capture");step();drain();end
        // A missing continuation cannot consume a 32-bit first instruction.
        offer(10,0,1);halfword1_valid=0;#1;verify(!window_accept,"Incomplete A waits");step();drain();
        offer(11,1,0);second_halfword1_valid=0;#1;verify(window_accept&&!second_window_accept,"Incomplete B consumes only A");step();drain();
        // Predicted stream, epoch and PC boundaries are never joined.
        offer(12,1,1);predicted_taken=1;#1;verify(!second_window_accept,"Taken A splits pair");step();drain();
        offer(13,1,1);second_epoch=2'd2;#1;verify(!second_window_accept,"Epoch mismatch splits pair");step();drain();
        offer(14,1,1);second_pc=second_pc+2;#1;verify(!second_window_accept,"Nonsequential PC splits pair");step();drain();
        offer(15,1,1);halfword0_error=1;#1;verify(!second_window_accept,"Fault A splits pair");step();drain();
        offer(16,1,1);halfword0=16'h0000;#1;verify(!second_window_accept,"Illegal A splits pair");step();drain();
        offer(17,0,0);second_halfword1_error=1;step();drain();
        // Fill all slots, deny combinational reclaim, and pop only A.
        ready=0;second_ready=0;offer(20,1,1);step();offer(21,0,0);step();
        offer(22,1,1);ready=1;second_ready=0;step();
        // Only one registered free slot: B stays upstream.
        #1;verify(window_accept&&!second_window_accept,"One free slot captures only A");step();drain();
        offer(23,1,1);ready=0;second_ready=1;step();window_valid=0;second_window_valid=0;step();
        verify(tail-head==2,"B ready alone cannot advance");kill=1;step();kill=0;drain();
        // Reset with occupancy, then prove no stale payload is valid.
        offer(24,0,1);ready=0;second_ready=0;step();rst_n=0;#1;head=0;tail=0;
        window_valid=0;second_window_valid=0;@(posedge clk);@(negedge clk);rst_n=1;step();
        for(j=0;j<3000;j=j+1)begin
            random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            offer(j+100,random_state[0],random_state[1]);
            window_valid=random_state[2];second_window_valid=random_state[3];
            ready=random_state[4];second_ready=random_state[5];kill=(random_state[10:6]==0);
            if(random_state[11])second_epoch=2'd2;
            if(random_state[12])predicted_taken=1;
            if(random_state[13])second_halfword0_error=1;
            step();
        end
        kill=0;drain();
        verify(pair_capture>20&&pair_pop>10&&one_pop>20&&full_checks>0&&kills>0,"Coverage reached");
        $display("PASS: dual ALIGN seed=%0d checks=%0d pair_capture=%0d pair_pop=%0d one_pop=%0d full=%0d kills=%0d",seed,checks,pair_capture,pair_pop,one_pop,full_checks,kills);
        $finish;
    end
    initial begin #2000000;$fatal(1,"dual ALIGN watchdog");end
    reg [2047:0] wave_path;
    initial begin
        if ($test$plusargs("WAVE")) begin
            if (!$value$plusargs("WAVEFILE=%s",wave_path)) wave_path="wave.vcd";
            $dumpfile(wave_path);
            $dumpvars(0,tb_dual_align);
        end
    end
endmodule
