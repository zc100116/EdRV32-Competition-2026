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
    wire [2:0] free_count_o;
    reg [1:0] pop_count_i=0;
    wire [357:0] data_o;
    wire [1:0] valid_count_o;
    reg flush_i=0;
    reg keep_head_i=0;
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

    edrv32_cpu_ib dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .push_count_i(push_count_i),
        .push_data_i(push_data_i),
        .free_count_o(free_count_o),
        .pop_count_i(pop_count_i),
        .data_o(data_o),
        .valid_count_o(valid_count_o),
        .flush_i(flush_i),
        .keep_head_i(keep_head_i),
        .count_o(count_o)
    );
    task automatic check;
        begin
            if(count_o!==3'(count) || valid_count_o!==2'(count>=2?2:count))
                $fatal(1,"FAIL IB count expected=%d actual=%d time=%t",count,count_o,$time);
            if(free_count_o!==3'(integer'(dut.DEPTH)-count))
                $fatal(1,"FAIL IB next-cycle free expected=%d actual=%d time=%t",
                    integer'(dut.DEPTH)-count,free_count_o,$time);
            if(count>0 && data_o[178:0]!==model[0])
                $fatal(1,"FAIL IB head expected=%h actual=%h time=%t",
                    model[0],data_o[178:0],$time);
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
            flush_i=(i%29==0 && i>4);
            keep_head_i=flush_i && count>0 && (i%2==0);
            #1;
            if(free_count_o!==3'(space))$fatal(1,"FAIL IB free slots");
            // U-08: changing same-cycle D consumption cannot create F2 space.
            pop_count_i=0;#1;
            if(free_count_o!==3'(space))$fatal(1,"FAIL IB free depends on pop=0");
            pop_count_i=2'(pops);#1;
            if(free_count_o!==3'(space))$fatal(1,"FAIL IB free depends on pop");
            if(count==integer'(dut.DEPTH) && pops>0)begin
                if(pushes!=0)$fatal(1,"FAIL IB full accepts same-cycle slots");
                delayed_space_seen++;
            end
            if(flush_i)begin
                count=keep_head_i?1:0;
                flush_seen=flush_seen+1;
                if(keep_head_i)keep_seen=keep_seen+1;
            end
            else begin
                for(j=0;j<count-pops;j=j+1)model[j]=model[j+pops];
                count=count-pops;
                if(pushes>0)model[count]=push_data_i[178:0];
                if(pushes==2)model[count+1]=push_data_i[357:179];
                count=count+pushes;
                if(pushes>0 && pops>0)simultaneous_seen=simultaneous_seen+1;
            end
            @(posedge clk_i);#1;check();
            if(count==0)empty_seen=empty_seen+1;
            if(count==integer'(dut.DEPTH))full_seen=full_seen+1;
        end
        if((full_seen==0) || (empty_seen==0) || (simultaneous_seen==0) ||
            (flush_seen==0) || (keep_seen==0) || (delayed_space_seen==0))
            $fatal(1,"FAIL IB missing coverage");
        $display("PASS U-08 full=%0d empty=%0d simultaneous=%0d flush=%0d",
            full_seen,empty_seen,simultaneous_seen,flush_seen);$finish;
    end
endmodule
