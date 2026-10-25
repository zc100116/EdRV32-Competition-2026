// cpu_predictor/tb.sv
// cpu-testplan U-09; cpu-spec 3.2, 4.1, 4.4.
// Compare BTB, gshare and speculative RAS behavior with independent table models.
// Stop with a diagnostic on the first mismatch; print PASS on completion.
// Clock domain: clk_sys.
`timescale 1ns/1ps
module tb;
    reg clk_i=0;
    always #5 clk_i=~clk_i;
    reg rst_n_i=0;
    reg [31:1] query_pc_i=0;
    reg query_accept_i=0;
    wire predict_hit_o;
    wire predict_taken_o;
    wire [31:0] predict_target_o;
    wire [1:0] predict_position_o;
    wire predict_compressed_o;
    wire [8:0] predict_history_o;
    wire [36:0] predict_ras_o;
    reg update_valid_i=0;
    reg [31:1] update_pc_i=0;
    reg [31:0] update_target_i=0;
    reg [2:0] update_type_i=0;
    reg update_taken_i=0;
    reg update_compressed_i=0;
    reg [8:0] update_index_i=0;
    reg clear_valid_i=0;
    reg [4:0] clear_index_i=0;
    reg restore_valid_i=0;
    reg [36:0] restore_ras_i=0;
    reg restore_push_i=0;
    reg restore_pop_i=0;
    reg [31:0] restore_return_pc_i=0;
    reg valid[0:31];
    reg [23:0] tag[0:31];
    reg [31:0] target[0:31];
    reg [1:0] position[0:31];
    reg [2:0] kind[0:31];
    reg compressed[0:31];
    integer direction[0:511];
    reg [8:0] history=0;
    reg [31:0] stack[0:3];
    integer ptr=0;
    integer depth=0;
    integer i;
    integer j;
    integer q;
    integer slot;
    integer index_value;
    integer action;
    integer pc_value;
    reg expected_hit;
    reg expected_taken;
    reg [31:0] expected_target;
    reg [36:0] checkpoint;
    integer overflow_seen=0;
    integer restore_seen=0;
    integer alias_seen=0;
    integer saturate_seen=0;

    edrv32_cpu_predictor dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .query_pc_i(query_pc_i),
        .query_accept_i(query_accept_i),
        .predict_hit_o(predict_hit_o),
        .predict_taken_o(predict_taken_o),
        .predict_target_o(predict_target_o),
        .predict_position_o(predict_position_o),
        .predict_compressed_o(predict_compressed_o),
        .predict_history_o(predict_history_o),
        .predict_ras_o(predict_ras_o),
        .update_valid_i(update_valid_i),
        .update_pc_i(update_pc_i),
        .update_target_i(update_target_i),
        .update_type_i(update_type_i),
        .update_taken_i(update_taken_i),
        .update_compressed_i(update_compressed_i),
        .update_index_i(update_index_i),
        .clear_valid_i(clear_valid_i),
        .clear_index_i(clear_index_i),
        .restore_valid_i(restore_valid_i),
        .restore_ras_i(restore_ras_i),
        .restore_push_i(restore_push_i),
        .restore_pop_i(restore_pop_i),
        .restore_return_pc_i(restore_return_pc_i)
    );
    task automatic check;
        begin
            q=query_pc_i[7:3];
            index_value=({query_pc_i[9:3],position[q]} ^ history);
            expected_hit=valid[q] && tag[q]==query_pc_i[31:8] &&
                position[q]>=query_pc_i[2:1];
            expected_taken=expected_hit && (kind[q]!=0 || direction[index_value]>=2);
            expected_target=(kind[q]==4 && depth>0)?stack[(ptr+3)%4]:target[q];
            if(predict_hit_o!==expected_hit || predict_taken_o!==expected_taken ||
                predict_history_o!==history)
                $fatal(1,"FAIL predictor query=%h hit=%b/%b taken=%b/%b GHR=%h/%h time=%t",
                    {query_pc_i,1'b0},predict_hit_o,expected_hit,predict_taken_o,expected_taken,
                    predict_history_o,history,$time);
            if(expected_hit && (predict_target_o!==expected_target ||
                predict_position_o!==position[q] || predict_compressed_o!==compressed[q]))
                $fatal(1,"FAIL BTB target expected=%h actual=%h time=%t",
                    expected_target,predict_target_o,$time);
            if(predict_ras_o[36:34]!==3'(depth) || predict_ras_o[33:32]!==2'(ptr) ||
                (depth>0 && predict_ras_o[31:0]!==stack[(ptr+3)%4]))
                $fatal(1,"FAIL RAS expected ptr=%d depth=%d actual=%h time=%t",
                    ptr,depth,predict_ras_o,$time);
        end
    endtask
    task automatic cycle;
        begin
            #1;check();
            action=0;
            if(query_accept_i && expected_taken)begin
                if(kind[q]==3)action=1;
                if(kind[q]==4)action=2;
            end
            pc_value={query_pc_i[31:3],position[q],1'b0};
            if(restore_valid_i)begin
                ptr=integer'(restore_ras_i[33:32]);depth=integer'(restore_ras_i[36:34]);
                if(depth>0)stack[(ptr+3)%4]=restore_ras_i[31:0];
                if(restore_pop_i && depth>0)begin ptr=(ptr+3)%4;depth=depth-1;end
                if(restore_push_i)begin
                    stack[ptr]=restore_return_pc_i;ptr=(ptr+1)%4;
                    if(depth<4)depth=depth+1;
                end
                restore_seen=restore_seen+1;
            end else if(action==1)begin
                stack[ptr]=32'(pc_value)+(compressed[q]?2:4);ptr=(ptr+1)%4;
                if(depth<4)depth=depth+1;else overflow_seen=overflow_seen+1;
            end else if(action==2 && depth>0)begin ptr=(ptr+3)%4;depth=depth-1;end
            if(update_valid_i)begin
                slot=update_pc_i[7:3];
                if(valid[slot] && tag[slot]!=update_pc_i[31:8])alias_seen=alias_seen+1;
                valid[slot]=1;tag[slot]=update_pc_i[31:8];
                target[slot]=update_target_i;position[slot]=update_pc_i[2:1];
                kind[slot]=update_type_i;compressed[slot]=update_compressed_i;
                if(update_type_i==0)begin
                    history={history[7:0],update_taken_i};
                    if(update_taken_i && direction[update_index_i]<3)
                        direction[update_index_i]=direction[update_index_i]+1;
                    else if(!update_taken_i && direction[update_index_i]>0)
                        direction[update_index_i]=direction[update_index_i]-1;
                    else saturate_seen=saturate_seen+1;
                end
            end
            @(posedge clk_i);#1;check();@(negedge clk_i);
        end
    endtask
    initial begin
        for(i=0;i<32;i=i+1)begin
            valid[i]=0;tag[i]=0;position[i]=0;target[i]=0;kind[i]=0;compressed[i]=0;
        end
        for(i=0;i<512;i=i+1)direction[i]=1;
        repeat(2)@(negedge clk_i);rst_n_i=1;
        // BTB replacement and branch slot before/after query start.
        update_valid_i=1;update_pc_i=31'('h46>>1);update_target_i='h100;
        update_type_i=1;cycle();update_valid_i=0;query_pc_i=31'('h40>>1);cycle();
        query_pc_i=31'('h46>>1);cycle();
        update_valid_i=1;update_pc_i=31'('h144>>1);update_target_i='h200;cycle();
        update_valid_i=0;cycle();query_pc_i=31'('h146>>1);cycle();
        query_pc_i=31'('h140>>1);cycle();
        // Exercise both saturation ends at a fixed saved index despite changing GHR.
        update_valid_i=1;update_pc_i=31'('h20>>1);update_type_i=0;update_index_i=17;
        for(j=0;j<8;j=j+1)begin update_taken_i=1;cycle();end
        for(j=0;j<8;j=j+1)begin update_taken_i=0;cycle();end
        // Train call and return groups, push beyond depth and inspect LIFO returns.
        update_type_i=3;update_pc_i=31'('h80>>1);update_target_i='h88;cycle();
        update_type_i=4;update_pc_i=31'('h88>>1);update_target_i='h90;cycle();
        update_valid_i=0;query_pc_i=31'('h80>>1);query_accept_i=1;
        for(j=0;j<6;j=j+1)cycle();
        query_accept_i=0;checkpoint=predict_ras_o;
        query_pc_i=31'('h88>>1);query_accept_i=1;
        for(j=0;j<5;j=j+1)cycle();
        query_accept_i=0;restore_valid_i=1;restore_ras_i=checkpoint;cycle();
        restore_pop_i=1;restore_push_i=1;restore_return_pc_i='h1234;cycle();
        restore_valid_i=0;restore_pop_i=0;restore_push_i=0;
        // Independent model checks aliasing, gshare history and speculative recovery.
        for(i=0;i<3000;i=i+1)begin
            query_pc_i=31'($urandom_range(0,1023));
            update_valid_i=(i%3==0);query_accept_i=(i%3==1);
            restore_valid_i=(i%73==0);
            restore_ras_i=checkpoint;restore_push_i=i[0];restore_pop_i=i[1];
            restore_return_pc_i=$urandom;
            update_pc_i=31'($urandom_range(0,1023));update_target_i=$urandom & 32'hfffffffe;
            update_type_i=3'($urandom_range(0,4));update_compressed_i=i[0];
            update_taken_i=i[1];update_index_i=9'($urandom);
            cycle();
            if(i%61==0)checkpoint=predict_ras_o;
        end
        if(!overflow_seen || !restore_seen || !alias_seen || !saturate_seen)
            $fatal(1,"FAIL predictor missing coverage");
        $display("PASS U-09 overflow=%0d restore=%0d alias=%0d saturation=%0d",
            overflow_seen,restore_seen,alias_seen,saturate_seen);$finish;
    end
endmodule
