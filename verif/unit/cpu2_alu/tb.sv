// CV05 arithmetic/latency/cancel oracle drives only public interfaces.
module tb #(parameter ISSUE_WIDTH=2, parameter [31:0] FPU_FORMAT="NONE");
    localparam T=FPU_FORMAT=="NONE"?2:FPU_FORMAT=="F"?3:4;
    localparam B=FPU_FORMAT=="FD"?64:32;
    reg clk_i=0;
    reg rst_n_i=0;
    always #5 clk_i=~clk_i;
    reg [T-1:0] age=0;
    reg cancel=0;
    reg [T-1:0] cancel_tag=0;
    reg [1:0] valid=0;
    wire [1:0] ready;
    reg [1:0][T-1:0] tag;
    reg [1:0][31:0] instr;
    reg [1:0][31:0] pc;
    reg [1:0][31:0] a;
    reg [1:0][31:0] b;
    reg [1:0][31:0] imm;
    reg [1:0] late=0;
    reg [1:0][T-1:0] source1;
    reg [1:0][T-1:0] source2;
    reg [1:0] wait1=0;
    reg [1:0] wait2=0;
    wire [1:0] done;
    reg [1:0] accept=3;
    wire [1:0][T-1:0] done_tag;
    wire [1:0][B-1:0] data;
    wire [1:0][4:0] flags;
    wire [1:0] exception;
    wire [1:0][3:0] cause;
    wire [1:0][31:0] tval;
    reg other_done=0;
    reg [T-1:0] other_tag=1;
    reg [B-1:0] other_data=0;
    reg load_done=0;
    reg [T-1:0] load_tag=0;
    reg [B-1:0] load_data=0;
    // Model the registered issue ID/EX boundary at the public unit interface.
    reg [1:0] entry_valid;
    reg [1:0] entry_late;
    reg [1:0] entry_wait1;
    reg [1:0] entry_wait2;
    reg [1:0][T-1:0] entry_tag;
    reg [1:0][T-1:0] entry_source1;
    reg [1:0][T-1:0] entry_source2;
    reg [1:0][31:0] entry_pc;
    reg [1:0][31:0] entry_instr;
    reg [1:0][31:0] entry_a;
    reg [1:0][31:0] entry_b;
    reg [1:0][31:0] entry_imm;
    always @(posedge clk_i or negedge rst_n_i) begin
        if(!rst_n_i)entry_valid<=0;
        else entry_valid<=valid;
    end
    always @(posedge clk_i)begin
        entry_late<=late;
        entry_wait1<=wait1;
        entry_wait2<=wait2;
        entry_tag<=tag;
        entry_source1<=source1;
        entry_source2<=source2;
        entry_pc<=pc;
        entry_instr<=instr;
        entry_a<=a;
        entry_b<=b;
        entry_imm<=imm;
    end
    reg lsu_complete_device_i=0;
    reg wb0_valid_i=0;
    reg [T-1:0] wb0_tag_i=0;
    reg [31:0] wb0_data_i=0;
    reg wb1_valid_i=0;
    reg [T-1:0] wb1_tag_i=0;
    reg [31:0] wb1_data_i=0;
    edrv32_cpu2_alu #(.ISSUE_WIDTH(ISSUE_WIDTH),.FPU_FORMAT(FPU_FORMAT)) dut (
        .lsu_complete_device_i(lsu_complete_device_i),
        .wb0_valid_i(wb0_valid_i),
        .wb0_tag_i(wb0_tag_i),
        .wb0_data_i(wb0_data_i),
        .wb1_valid_i(wb1_valid_i),
        .wb1_tag_i(wb1_tag_i),
        .wb1_data_i(wb1_data_i),
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .age_head_i(age),
        .cancel_valid_i(cancel),
        .cancel_tag_i(cancel_tag),
        .execute0_valid_i(entry_valid[0]),
        .execute0_ready_o(ready[0]),
        .execute0_tag_i(entry_tag[0]),
        .execute0_pc_i(entry_pc[0]),
        .execute0_instr_i(entry_instr[0]),
        .execute0_src1_i(entry_a[0]),
        .execute0_src2_i(entry_b[0]),
        .execute0_imm_i(entry_imm[0]),
        .execute0_late_i(entry_late[0]),
        .execute0_source1_tag_i(entry_source1[0]),
        .execute0_source2_tag_i(entry_source2[0]),
        .execute0_source1_wait_i(entry_wait1[0]),
        .execute0_source2_wait_i(entry_wait2[0]),
        .execute1_valid_i(entry_valid[1]),
        .execute1_ready_o(ready[1]),
        .execute1_tag_i(entry_tag[1]),
        .execute1_pc_i(entry_pc[1]),
        .execute1_instr_i(entry_instr[1]),
        .execute1_src1_i(entry_a[1]),
        .execute1_src2_i(entry_b[1]),
        .execute1_imm_i(entry_imm[1]),
        .execute1_late_i(entry_late[1]),
        .execute1_source1_tag_i(entry_source1[1]),
        .execute1_source2_tag_i(entry_source2[1]),
        .execute1_source1_wait_i(entry_wait1[1]),
        .execute1_source2_wait_i(entry_wait2[1]),
        .alu0_complete_valid_i(done[0]),
        .alu0_complete_ready_i(accept[0]),
        .alu0_complete_tag_i(done_tag[0]),
        .alu0_complete_data_i(data[0]),
        .alu0_complete_valid_o(done[0]),
        .alu0_complete_tag_o(done_tag[0]),
        .alu0_complete_data_o(data[0]),
        .alu0_complete_flags_o(flags[0]),
        .alu0_complete_exception_o(exception[0]),
        .alu0_complete_cause_o(cause[0]),
        .alu0_complete_tval_o(tval[0]),
        .alu1_complete_valid_i(done[1]),
        .alu1_complete_ready_i(accept[1]),
        .alu1_complete_tag_i(done_tag[1]),
        .alu1_complete_data_i(data[1]),
        .alu1_complete_valid_o(done[1]),
        .alu1_complete_tag_o(done_tag[1]),
        .alu1_complete_data_o(data[1]),
        .alu1_complete_flags_o(flags[1]),
        .alu1_complete_exception_o(exception[1]),
        .alu1_complete_cause_o(cause[1]),
        .alu1_complete_tval_o(tval[1]),
        .branch_complete_valid_i(1'b0),
        .branch_complete_ready_i(1'b0),
        .branch_complete_tag_i({T{1'b0}}),
        .branch_complete_data_i({B{1'b0}}),
        .mul_complete_valid_i(other_done),
        .mul_complete_ready_i(1'b1),
        .mul_complete_tag_i(other_tag),
        .mul_complete_data_i(other_data),
        .div_complete_valid_i(1'b0),
        .div_complete_ready_i(1'b0),
        .div_complete_tag_i({T{1'b0}}),
        .div_complete_data_i({B{1'b0}}),
        .lsu_complete_valid_i(load_done),
        .lsu_complete_ready_i(1'b1),
        .lsu_complete_tag_i(load_tag),
        .lsu_complete_data_i(load_data),
        .csr_complete_valid_i(1'b0),
        .csr_complete_ready_i(1'b0),
        .csr_complete_tag_i({T{1'b0}}),
        .csr_complete_data_i({B{1'b0}}),
        .fp_resp_valid_i(1'b0),
        .fp_resp_ready_i(1'b0),
        .fp_resp_tag_i({T{1'b0}}),
        .fp_resp_data_i({B{1'b0}}),
        // I06 observation-only outputs.
        .debug_mem_valid_o()
    );
    task tick; @(posedge clk_i); #1; endtask
    function [31:0] op(input integer f7,input integer f3,input bit immediate_op);
        op=(32'(f7)<<25)|(32'(f3)<<12)|(immediate_op?32'h13:32'h33);
    endfunction
    task check(input integer p,input [31:0] expected,input [T-1:0] expected_tag);
        #1;
        if(!done[p] || data[p]!==B'(expected) || done_tag[p]!==expected_tag ||
            flags[p]!==0 || exception[p]!==0 || cause[p]!==0 || tval[p]!==0)
            $fatal(1,"ALU pipe%0d expected tag%0d data%h got valid%b tag%0d data%h time%0t",
                p,expected_tag,expected,done[p],done_tag[p],data[p],$time);
    endtask
    task arithmetic(input integer p,input [31:0] code,input [31:0] x,input [31:0] y,
                    input [31:0] immediate_value,input [31:0] expected);
        @(negedge clk_i);
        if(!ready[p]) $fatal(1,"unexpected full pipe%0d",p);
        if(p==0)begin
            valid[0]=1;instr[0]=code;a[0]=x;b[0]=y;imm[0]=immediate_value;tag[0]=0;
        end else begin
            valid[1]=1;instr[1]=code;a[1]=x;b[1]=y;imm[1]=immediate_value;tag[1]=0;
        end
        tick();valid[p]=0;check(p,expected,0);
        tick();if(done[p]) $fatal(1,"duplicate completion");
    endtask
    task late_arithmetic(input integer p,input [31:0] code,input [31:0] x,
        input [31:0] y,input [31:0] immediate_value,input [31:0] expected,input integer mask);
        @(negedge clk_i);
        valid[p]=1;late[p]=1;wait1[p]=1'(mask&1);wait2[p]=1'((mask>>1)&1);
        instr[p]=code;a[p]=(mask&1)!=0?0:x;b[p]=(mask&2)!=0?0:y;imm[p]=immediate_value;
        tag[p]=2;source1[p]=0;source2[p]=1;
        tick();valid[p]=0;
        if(done[p])$fatal(1,"late opcode completed in EX");
        load_done=(mask&1)!=0;load_tag=0;load_data=B'(x);
        other_done=(mask&2)!=0;other_tag=1;other_data=B'(y);
        tick();load_done=0;other_done=0;check(p,expected,2);
        tick();late[p]=0;wait1[p]=0;wait2[p]=0;
        if(done[p])$fatal(1,"late opcode completed twice");
    endtask
    reg [31:0] x,y,expected;
    integer f;
    initial begin
        for(integer p=0;p<2;p++) begin
            tag[p]=0;instr[p]=0;pc[p]=32'h100; a[p]=0;b[p]=0;imm[p]=0;
            source1[p]=0;source2[p]=0;
        end
        tick();rst_n_i=1; tick();
        for(integer p=0;p<ISSUE_WIDTH;p++) begin
            arithmetic(p,op('h10,2,0),32'h80000001,7,0,9);
            arithmetic(p,op('h10,4,0),32'h80000001,7,0,11);
            arithmetic(p,op('h10,6,0),32'h80000001,7,0,15);
            arithmetic(p,32'h37,0,0,32'h12345000,32'h12345000);
            arithmetic(p,32'h17,0,0,32'h12345000,32'h12345100);
            for(integer n=0;n<300;n++) begin
                x=$random;y=$random;f=n%8;
                case(f)
                    0: expected=x+y;
                    1: expected=x<<y[4:0];
                    2: expected=32'($signed(x)<$signed(y));
                    3: expected=32'(x<y);
                    4: expected=x^y;
                    5: expected=x>>y[4:0];
                    6: expected=x|y;
                    7: expected=x&y;
                    default: expected=0;
                endcase
                arithmetic(p,op(0,f,0),x,y,0,expected);
                if(f==0) arithmetic(p,op('h20,0,0),x,y,0,x-y);
                if(f==5) arithmetic(p,op('h20,5,0),x,y,0,$signed(x)>>>y[4:0]);
            end
        end
        if(ISSUE_WIDTH==2) begin
            for(integer p=0;p<2;p++)begin
                for(integer mask=1;mask<4;mask++)begin
                    for(integer function_code=0;function_code<8;function_code++)begin
                        if(function_code!=1 && function_code!=5)begin
                            x=32'h80000001;y=3;
                            case(function_code)
                                0:expected=x+y;
                                2:expected=32'($signed(x)<$signed(y));
                                3:expected=32'(x<y);
                                4:expected=x^y;
                                6:expected=x|y;
                                7:expected=x&y;
                                default:expected=0;
                            endcase
                            late_arithmetic(p,op(0,function_code,0),x,y,0,expected,mask);
                            late_arithmetic(p,op(0,function_code,1),x,y,y,expected,1);
                        end
                    end
                    late_arithmetic(p,op('h20,0,0),32'h80000001,3,0,32'h7ffffffe,mask);
                    late_arithmetic(p,op('h10,2,0),32'h80000001,3,0,5,mask);
                    late_arithmetic(p,op('h10,4,0),32'h80000001,3,0,7,mask);
                    late_arithmetic(p,op('h10,6,0),32'h80000001,3,0,11,mask);
                end
            end
            // Same-group early ALU -> late ALU: operands capture at the intervening edge.
            @(negedge clk_i);valid=3;late=2;wait1=2;
            tag[0]=0;tag[1]=1;instr[0]=op(0,0,0);instr[1]=op(0,0,0);
            a[0]=7;b[0]=6;a[1]=0;b[1]=3;source1[1]=0;
            tick();valid=0;check(0,13,0);if(done[1])$fatal(1,"late completed early");
            tick();check(1,16,1);tick();late=0;wait1=0;
            // Failed early load waits for the real accepted completion, without reissue.
            @(negedge clk_i);valid=1;late=1;wait1=1;
            tag[0]=2;instr[0]=op(0,0,0);source1[0]=1;a[0]=0;b[0]=9;
            tick();valid=0;tick();
            repeat(4) begin if(done[0])$fatal(1,"used incomplete load");tick();end
            load_done=1;load_tag=1;load_data=B'(33);tick();load_done=0;check(0,42,2);
            accept[0]=0; tick();check(0,42,2);tick();check(0,42,2);
            accept[0]=1;tick();if(done[0])$fatal(1,"late duplicate");
            late=0;wait1=0;
            // Device preparation carries no result; retirement's tagged WB releases the waiter.
            @(negedge clk_i);valid=1;late=1;wait1=1;tag[0]=2;
            instr[0]=op(0,0,0);source1[0]=1;a[0]=0;b[0]=9;
            tick();valid=0;tick();
            load_done=1;load_tag=1;load_data=B'(32'hbad);lsu_complete_device_i=1;
            tick();load_done=0;lsu_complete_device_i=0;
            if(done[0])$fatal(1,"device preparation used as load data");
            tick();if(done[0])$fatal(1,"device waiter completed before WB");
            wb0_valid_i=1;wb0_tag_i=1;wb0_data_i=33;tick();wb0_valid_i=0;
            check(0,42,2);tick();late=0;wait1=0;
            // An unrelated suffix cancel must not consult an invalid stale output-lock tag.
            // A blocked older MEM result becomes ready after a younger EX response was exposed.
            age=3;@(negedge clk_i);valid=1;late=1;wait1=1;
            tag[0]=0;instr[0]=op(0,0,0);source1[0]=3;a[0]=0;b[0]=10;
            tick();valid=0;tick();
            @(negedge clk_i);valid=1;late=0;wait1=0;
            tag[0]=1;a[0]=5;b[0]=6;accept[0]=0;
            tick();valid=0;check(0,11,1);
            cancel=1;cancel_tag=2;load_done=1;load_tag=3;load_data=B'(7);
            tick();cancel=0;load_done=0;check(0,11,1);
            tick();check(0,11,1);accept[0]=1;
            tick();check(0,17,0);tick();
            // I06: cancel a newly ready MEM result before it acquires a lock.
            age=0; @(negedge clk_i);valid=1;late=1;wait1=1;wait2=0;
            tag[0]=2;source1[0]=0;instr[0]=op(0,0,0);a[0]=0;b[0]=1;
            tick();valid=0;tick();
            wb0_valid_i=1;wb0_tag_i=0;wb0_data_i=7;tick();wb0_valid_i=0;
            accept[0]=0;cancel=1;cancel_tag=2;tick();cancel=0;
            late=0;wait1=0;accept[0]=1;
            arithmetic(0,op(0,0,0),9,8,0,17);
        end
        // Inclusive cancellation at a wrapped head leaves no old result after tag reuse.
        @(negedge clk_i);age=T'(-1);tag[0]=0;valid=1;instr[0]=op(0,0,0);a[0]=1;b[0]=2;
        accept[0]=0;tick();valid=0;check(0,3,0);
        cancel=1;cancel_tag=0;tick();cancel=0;
        if(done[0])$fatal(1,"canceled instance remained visible");
        accept[0]=1;arithmetic(0,op(0,0,0),9,8,0,17);
        $display("PASS CV05 ALU ISSUE_WIDTH=%0d FPU_FORMAT=%s",ISSUE_WIDTH,FPU_FORMAT);
        $finish;
    end
endmodule
