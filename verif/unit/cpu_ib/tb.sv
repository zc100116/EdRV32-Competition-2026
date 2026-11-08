// cpu_ib/tb.sv
// cpu-testplan U-08; cpu-spec 3.2, 4.1, 4.4.
// Compare dual enqueue/dequeue and redirect flush with an independent queue model.
// Stop with a diagnostic on the first mismatch; print PASS on completion.
// Clock domain: clk_sys.
`timescale 1ns/1ps
module tb;
    reg clk_i=0;
    always #5 clk_i=~clk_i;
    reg rst_n_i=0;
    reg [1:0] push_count_i=0;
    reg [357:0] push_data_i=0;
    reg [1:0] pop_count_i=0;
    wire [357:0] data_o;
    wire [139:0] predecode_o;
    wire [1:0] valid_count_o;
    reg flush_i=0;
    reg keep_head_i=0;
    reg keep_pair_i=0;
    reg [5:0] push_index_hi_i=0;
    wire [5:0] index_hi_o;
    reg [2:0] model_index[0:dut.DEPTH-1];
    integer keep_pair_seen=0;
    wire [2:0] count_o;
    reg [178:0] model[0:dut.DEPTH-1];
    integer count=0;
    integer i;
    integer j;
    integer pops;
    integer pushes;
    integer space;
    integer full_seen=0;
    integer empty_seen=0;
    integer simultaneous_seen=0;
    integer flush_seen=0;
    integer keep_seen=0;
    integer delayed_space_seen=0;

    wire [79:0] operand_addr_w;
    wire [23:0] unused_tournament_w;
    edrv32_cpu_ib dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .push_count_i(push_count_i),
        .push_data_i(push_data_i),
        .push_index_hi_i(push_index_hi_i),
        .push_tournament_i(24'b0),
        .tournament_o(unused_tournament_w),
        .index_hi_o(index_hi_o),
        .pop_count_i(pop_count_i),
        .data_o(data_o),
        .predecode_o(predecode_o),
        .operand_addr_o(operand_addr_w),
        .valid_count_o(valid_count_o),
        .flush_i(flush_i),
        .keep_head_i(keep_head_i),
        .keep_pair_i(keep_pair_i),
        .count_o(count_o)
    );
    task automatic check;
        integer slice;
        integer slot;
        reg [31:0] instr;
        reg [69:0] decoded;
        begin
            if(count_o!==3'(count) || valid_count_o!==2'(count>=2?2:count))
                $fatal(1,"FAIL IB count expected=%d actual=%d time=%t",count,count_o,$time);
            if ((count>0 && index_hi_o[2:0]!==model_index[0]) ||
                (count>1 && index_hi_o[5:3]!==model_index[1]))
                $fatal(1,"FAIL IB index metadata");
            if(count>0 && data_o[178:0]!==model[0])
                $fatal(1,"FAIL IB head expected=%h actual=%h time=%t",
                    model[0],data_o[178:0],$time);
            for (slice=0;slice<4;slice=slice+1) begin
                if (count>0 && operand_addr_w[slice*20 +: 10]!==model[0][56:47])
                    $fatal(1,"FAIL IB operand head slice=%0d expected=%h actual=%h time=%t",
                        slice,model[0][56:47],operand_addr_w[slice*20 +: 10],$time);
                if (count>1 && operand_addr_w[slice*20+10 +: 10]!==model[1][56:47])
                    $fatal(1,"FAIL IB operand second slice=%0d expected=%h actual=%h time=%t",
                        slice,model[1][56:47],operand_addr_w[slice*20+10 +: 10],$time);
            end
            for (slot=0;slot<2;slot++) begin
                if (count>slot) begin
                    instr=model[slot][63:32];
                    decoded=predecode_o[slot*70 +: 70];
                    if (decoded[14:0]!=={instr[11:7],instr[24:20],instr[19:15]} ||
                        decoded[61]!== (instr[6:0]==7'h03) ||
                        decoded[64]!== (instr[6:0]==7'h6f || instr[6:0]==7'h67 ||
                            instr[6:0]==7'h63) ||
                        decoded[65]!== (instr[6:0]==7'h03 || instr[6:0]==7'h23) ||
                        decoded[66]!== (instr[6:0]==7'h73 || instr[6:0]==7'h0f) ||
                        decoded[69]!== (instr[6:0]==7'h6f))
                        $fatal(1,"FAIL IB predecode slot=%0d instruction=%h",slot,instr);
                    if (instr[6:0]==7'h03 &&
                        (decoded[24:21]!==4'd6 ||
                        decoded[60:29]!=={{20{instr[31]}},instr[31:20]} ||
                        decoded[17:15]!==3'b101 ||
                        decoded[67]!== (instr[11:7]!=0)))
                        $fatal(1,"FAIL IB load predecode slot=%0d instruction=%h",slot,instr);
                end
            end
            if(count>1 && data_o[357:179]!==model[1])
                $fatal(1,"FAIL IB second expected=%h actual=%h time=%t",
                    model[1],data_o[357:179],$time);
        end
    endtask
    initial begin
        repeat(2)@(negedge clk_i);rst_n_i=1;#1;check();
        for(i=0;i<4000;i=i+1)begin
            @(negedge clk_i);
            pops=(i<2)?0:(i<4)?2:integer'($urandom_range(0,count>=2?2:count));
            space=integer'(dut.DEPTH)-count;
            pushes=(i<2)?2:(i<4)?0:integer'($urandom_range(0,space>=2?2:space));
            push_count_i=2'(pushes);pop_count_i=2'(pops);
            push_data_i={19'($urandom),$urandom,$urandom,$urandom,$urandom,$urandom,
                19'($urandom),$urandom,$urandom,$urandom,$urandom,$urandom};
            if (i==0) begin
                push_data_i[32 +: 32]=32'h00c12303;
                push_data_i[211 +: 32]=32'hfff08293;
            end
            push_index_hi_i=6'($urandom);
            flush_i=(i%29==0 && i>4);
            keep_head_i=flush_i && count>0 && (i%2==0);
            keep_pair_i=keep_head_i && count>=2 && (i%3==0);
            #1;
            if(count==integer'(dut.DEPTH) && pops>0)begin
                if(pushes!=0)$fatal(1,"FAIL IB full accepts same-cycle slots");
                delayed_space_seen++;
            end
            if(flush_i)begin
                count=keep_head_i?(keep_pair_i?2:1):0;
                if(keep_pair_i)keep_pair_seen++;
                flush_seen=flush_seen+1;
                if(keep_head_i)keep_seen=keep_seen+1;
            end
            else begin
                for(j=0;j<count-pops;j=j+1)begin
                    model[j]=model[j+pops];model_index[j]=model_index[j+pops];
                end
                count=count-pops;
                if(pushes>0)begin
                    model[count]=push_data_i[178:0];model_index[count]=push_index_hi_i[2:0];
                end
                if(pushes==2)begin
                    model[count+1]=push_data_i[357:179];model_index[count+1]=push_index_hi_i[5:3];
                end
                count=count+pushes;
                if(pushes>0 && pops>0)simultaneous_seen=simultaneous_seen+1;
            end
            @(posedge clk_i);#1;check();
            if(count==0)empty_seen=empty_seen+1;
            if(count==integer'(dut.DEPTH))full_seen=full_seen+1;
        end
        if((full_seen==0) || (empty_seen==0) || (simultaneous_seen==0) ||
            (flush_seen==0) || (keep_seen==0) || (keep_pair_seen==0) || (delayed_space_seen==0))
            $fatal(1,"FAIL IB missing coverage");
        $display("PASS U-08 full=%0d empty=%0d simultaneous=%0d flush=%0d",
            full_seen,empty_seen,simultaneous_seen,flush_seen);$finish;
    end
endmodule
