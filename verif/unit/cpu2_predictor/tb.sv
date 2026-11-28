// Independent CV07/CV08 public-interface state model.
module tb #(
    parameter ISSUE_WIDTH = 2,
    parameter [31:0] FPU_FORMAT = "NONE"
);
    localparam TAG_BITS = FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2;
    localparam RAS_BITS = ISSUE_WIDTH == 2 ? 256 : 128;
    localparam RAS_PTR_BITS = ISSUE_WIDTH == 2 ? 3 : 2;
    localparam RAS_COUNT_BITS = RAS_PTR_BITS+1;
    reg clk_i;
    reg rst_n_i;
    reg predict_req_valid_i;
    reg [32-1:0] predict_req_pc_i;
    reg query_skip0_i;
    wire fast0_hit_o;
    wire fast0_taken_o;
    wire [32-1:0] fast0_target_o;
    wire [3-1:0] fast0_type_o;
    wire [12-1:0] fast0_fast_index_o;
    wire [RAS_BITS-1:0] fast0_ras_data_o;
    wire [RAS_PTR_BITS-1:0] fast0_ras_ptr_o;
    wire [RAS_COUNT_BITS-1:0] fast0_ras_count_o;
    wire fast1_hit_o;
    wire fast1_taken_o;
    wire [32-1:0] fast1_target_o;
    wire [3-1:0] fast1_type_o;
    wire [12-1:0] fast1_fast_index_o;
    wire [RAS_BITS-1:0] fast1_ras_data_o;
    wire [RAS_PTR_BITS-1:0] fast1_ras_ptr_o;
    wire [RAS_COUNT_BITS-1:0] fast1_ras_count_o;
    reg ras_restore_valid_i;
    reg [RAS_BITS-1:0] ras_restore_data_i;
    reg [RAS_PTR_BITS-1:0] ras_restore_ptr_i;
    reg [RAS_COUNT_BITS-1:0] ras_restore_count_i;
    reg ras_restore_pop_i;
    reg ras_restore_push_i;
    reg [32-1:0] ras_restore_link_i;
    reg ex_predict_train_valid_i;
    reg [TAG_BITS-1:0] ex_predict_train_tag_i;
    reg [32-1:0] ex_predict_train_pc_i;
    reg ex_predict_train_taken_i;
    reg [32-1:0] ex_predict_train_target_i;
    reg [3-1:0] ex_predict_train_type_i;
    reg [12-1:0] ex_predict_train_fast_index_i;
    reg mem_predict_train_valid_i;
    reg [TAG_BITS-1:0] mem_predict_train_tag_i;
    reg [32-1:0] mem_predict_train_pc_i;
    reg mem_predict_train_taken_i;
    reg [32-1:0] mem_predict_train_target_i;
    reg [3-1:0] mem_predict_train_type_i;
    reg [12-1:0] mem_predict_train_fast_index_i;
    reg [TAG_BITS-1:0] age_head_i;
    reg cancel_valid_i;
    reg [TAG_BITS-1:0] cancel_tag_i;
    reg clear0_valid_i = 0;
    reg [31:0] clear0_pc_i = 0;
    reg clear1_valid_i = 0;
    reg [31:0] clear1_pc_i = 0;
    wire [31:0] fast0_ras_top_o;
    edrv32_cpu2_predictor #(
        .ISSUE_WIDTH(ISSUE_WIDTH),
        .FPU_FORMAT(FPU_FORMAT)
    ) dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .predict_req_valid_i(predict_req_valid_i),
        .predict_req_pc_i(predict_req_pc_i),
        .query_skip0_i(query_skip0_i),
        .clear0_valid_i(clear0_valid_i),
        .clear0_pc_i(clear0_pc_i),
        .clear1_valid_i(clear1_valid_i),
        .clear1_pc_i(clear1_pc_i),
        .fast0_hit_o(fast0_hit_o),
        .fast0_taken_o(fast0_taken_o),
        .fast0_target_o(fast0_target_o),
        .fast0_type_o(fast0_type_o),
        .fast0_fast_index_o(fast0_fast_index_o),
        .fast0_ras_data_o(fast0_ras_data_o),
        .fast0_ras_ptr_o(fast0_ras_ptr_o),
        .fast0_ras_count_o(fast0_ras_count_o),
        .fast0_ras_top_o(fast0_ras_top_o),
        .fast1_hit_o(fast1_hit_o),
        .fast1_taken_o(fast1_taken_o),
        .fast1_target_o(fast1_target_o),
        .fast1_type_o(fast1_type_o),
        .fast1_fast_index_o(fast1_fast_index_o),
        .fast1_ras_data_o(fast1_ras_data_o),
        .fast1_ras_ptr_o(fast1_ras_ptr_o),
        .fast1_ras_count_o(fast1_ras_count_o),
        .ras_restore_valid_i(ras_restore_valid_i),
        .ras_restore_data_i(ras_restore_data_i),
        .ras_restore_ptr_i(ras_restore_ptr_i),
        .ras_restore_count_i(ras_restore_count_i),
        .ras_restore_pop_i(ras_restore_pop_i),
        .ras_restore_push_i(ras_restore_push_i),
        .ras_restore_link_i(ras_restore_link_i),
        .ex_predict_train_valid_i(ex_predict_train_valid_i),
        .ex_predict_train_tag_i(ex_predict_train_tag_i),
        .ex_predict_train_pc_i(ex_predict_train_pc_i),
        .ex_predict_train_taken_i(ex_predict_train_taken_i),
        .ex_predict_train_target_i(ex_predict_train_target_i),
        .ex_predict_train_type_i(ex_predict_train_type_i),
        .ex_predict_train_fast_index_i(ex_predict_train_fast_index_i),
        .mem_predict_train_valid_i(mem_predict_train_valid_i),
        .mem_predict_train_tag_i(mem_predict_train_tag_i),
        .mem_predict_train_pc_i(mem_predict_train_pc_i),
        .mem_predict_train_taken_i(mem_predict_train_taken_i),
        .mem_predict_train_target_i(mem_predict_train_target_i),
        .mem_predict_train_type_i(mem_predict_train_type_i),
        .mem_predict_train_fast_index_i(mem_predict_train_fast_index_i),
        .age_head_i(age_head_i),
        .cancel_valid_i(cancel_valid_i),
        .cancel_tag_i(cancel_tag_i)
    );
    always #5 clk_i = ~clk_i;
    task tick; begin @(posedge clk_i); #1; end endtask
    task initialize; begin
        clk_i = '0;
        rst_n_i = '0;
        predict_req_valid_i = '0;
        predict_req_pc_i = '0;
        query_skip0_i = '0;
        ras_restore_valid_i = '0;
        ras_restore_data_i = '0;
        ras_restore_ptr_i = '0;
        ras_restore_count_i = '0;
        ras_restore_pop_i = '0;
        ras_restore_push_i = '0;
        ras_restore_link_i = '0;
        ex_predict_train_valid_i = '0;
        ex_predict_train_tag_i = '0;
        ex_predict_train_pc_i = '0;
        ex_predict_train_taken_i = '0;
        ex_predict_train_target_i = '0;
        ex_predict_train_type_i = '0;
        ex_predict_train_fast_index_i = '0;
        mem_predict_train_valid_i = '0;
        mem_predict_train_tag_i = '0;
        mem_predict_train_pc_i = '0;
        mem_predict_train_taken_i = '0;
        mem_predict_train_target_i = '0;
        mem_predict_train_type_i = '0;
        mem_predict_train_fast_index_i = '0;
        age_head_i = '0;
        cancel_valid_i = '0;
        cancel_tag_i = '0;
        tick(); rst_n_i = 1; tick();
    end endtask
    localparam BTB_ENTRIES = ISSUE_WIDTH == 2 ? 128 : 64;
    localparam RAS_DEPTH = ISSUE_WIDTH == 2 ? 8 : 4;
    reg [1:0] counters [0:4095];
    bit btb_valid [0:127];
    integer btb_pc [0:127];
    integer btb_target [0:127];
    integer btb_type [0:127];
    reg [11:0] history;
    reg [31:0] stack [0:7];
    integer pointer;
    integer count;
    integer seed = 707;
    integer queries;
    integer burst_index [0:3];
    bit picked_index [0:4095];
    integer selected_index;
    function automatic integer random_next;
        seed = seed*1664525+1013904223;
        return (seed >> 1)&'h7fffffff;
    endfunction
    function automatic integer saturate(input integer value,input bit up);
        return up ? (value<3 ? value+1 : 3) : (value>0 ? value-1 : 0);
    endfunction
    task train_reference(input integer address,input integer target,input integer kind,
                         input integer index_value,input bit outcome);
        integer idx;
        begin
            idx = (address >> 2)&(BTB_ENTRIES-1);
            btb_valid[idx] = 1;
            btb_pc[idx] = address;
            btb_target[idx] = target;
            btb_type[idx] = kind;
            if (kind == 0) begin
                counters[index_value] = 2'(saturate(int'(counters[index_value]),outcome));
                history = {history[10:0],outcome};
            end
        end
    endtask
    task train_one(input integer address,input integer kind,input integer index_value,
                   input bit outcome);
        begin
            ex_predict_train_valid_i = 1;
            ex_predict_train_pc_i = 32'(address);
            ex_predict_train_target_i = 32'(address+256);
            ex_predict_train_type_i = 3'(kind);
            ex_predict_train_fast_index_i = 12'(index_value);
            ex_predict_train_taken_i = outcome;
            train_reference(address,address+256,kind,index_value,outcome);
            tick();ex_predict_train_valid_i = 0;
        end
    endtask
    task query(input integer address,input bit accept);
        reg [31:0] temp_stack [0:7];
        integer temp_pointer;
        integer temp_count;
        integer pc_value;
        integer group_address;
        bit held_skip;
        integer idx;
        integer fast_index;
        integer kind;
        integer expected_target;
        integer actual_type;
        integer actual_fast_index;
        reg [31:0] actual_target;
        reg [RAS_BITS-1:0] actual_data;
        integer actual_ptr;
        integer actual_count;
        bit hit;
        bit direction;
        bit first_taken;
        bit actual_hit;
        bit actual_taken;
        bit pop;
        bit push;
        begin
            queries++;
            held_skip=query_skip0_i;
            group_address=ISSUE_WIDTH==1 ? (address & -8) : address;
            if(ISSUE_WIDTH==1) query_skip0_i=held_skip || ((address & 4)!=0);
            predict_req_pc_i = 32'(group_address);
            predict_req_valid_i = accept;
            temp_pointer = pointer;
            temp_count = count;
            for (integer j = 0; j < 8; j++) temp_stack[j] = stack[j];
            first_taken = 0;
            #1;
            for (integer word_number = 0; word_number < 2; word_number++) begin
                pc_value = group_address + 4*word_number;
                idx = (pc_value >> 2)&(BTB_ENTRIES-1);
                fast_index = ((pc_value >> 2)^int'(history))&4095;
                hit = btb_valid[idx] && btb_pc[idx] == pc_value;
                kind = hit ? btb_type[idx] : 0;
                direction = hit && (kind != 0 || counters[fast_index] >= 2);
                if (word_number == 0 && query_skip0_i) direction = 0;
                expected_target = hit ? btb_target[idx] : 0;
                if (hit && (kind == 4 || kind == 5) && temp_count != 0)
                    expected_target = int'(temp_stack[(temp_pointer-1)&(RAS_DEPTH-1)]);
                if(word_number==0 && temp_count!=0 &&
                   fast0_ras_top_o !== temp_stack[(temp_pointer-1)&(RAS_DEPTH-1)])
                    $fatal(1,"F1 RAS top capture");
                actual_hit = word_number == 0 ? fast0_hit_o : fast1_hit_o;
                actual_taken = word_number == 0 ? fast0_taken_o : fast1_taken_o;
                actual_target = word_number == 0 ? fast0_target_o : fast1_target_o;
                actual_fast_index = word_number == 0 ? int'(fast0_fast_index_o) :
                    int'(fast1_fast_index_o);
                if(actual_fast_index!=fast_index) $fatal(1,"GHR snapshot query=%0d index=%0d/%0d",
                    queries,fast_index,actual_fast_index);
                actual_type = word_number == 0 ? int'(fast0_type_o) : int'(fast1_type_o);
                actual_data = word_number == 0 ? fast0_ras_data_o : fast1_ras_data_o;
                actual_ptr = word_number == 0 ? int'(fast0_ras_ptr_o) : int'(fast1_ras_ptr_o);
                actual_count = word_number == 0 ? int'(fast0_ras_count_o) : int'(fast1_ras_count_o);
                if (actual_hit !== hit || actual_taken !== direction ||
                    (hit && (actual_target !== 32'(expected_target) || actual_type != kind)))
                    $fatal(1,"CV07 query=%0d width=%0d PC=%h hit=%b/%b taken=%b/%b target=%h/%h type=%0d/%0d",
                           queries,ISSUE_WIDTH,pc_value,hit,actual_hit,direction,actual_taken,
                           expected_target,actual_target,kind,actual_type);
                if (actual_ptr != temp_pointer || actual_count != temp_count)
                    $fatal(1,"RAS query=%0d pointer=%0d/%0d count=%0d/%0d",queries,
                           temp_pointer,actual_ptr,temp_count,actual_count);
                for (integer j = 0; j < RAS_DEPTH; j++)
                    if (actual_data[32*j +: 32] !== temp_stack[j])
                        $fatal(1,"RAS contents query=%0d entry=%0d expected=%h actual=%h",
                               queries,j,temp_stack[j],actual_data[32*j +: 32]);
                if (direction && !first_taken) begin
                    pop = (kind == 4 || kind == 5) && temp_count != 0;
                    push = kind == 3 || kind == 5;
                    if (pop) begin
                        temp_pointer = (temp_pointer-1)&(RAS_DEPTH-1);
                        temp_count--;
                    end
                    if (push) begin
                        temp_stack[temp_pointer] = 32'(pc_value+4);
                        temp_pointer = (temp_pointer+1)&(RAS_DEPTH-1);
                        if (temp_count < RAS_DEPTH) temp_count++;
                    end
                end
                if (word_number == 0) first_taken = direction;
            end
            tick();predict_req_valid_i = 0;query_skip0_i=held_skip;
            if (accept) begin
                pointer = temp_pointer;count = temp_count;
                for (integer j = 0; j < 8; j++) stack[j] = temp_stack[j];
            end
        end
    endtask
    task restore(input integer ptr_value,input integer count_value,input bit pop,input bit push);
        begin
            ras_restore_valid_i = 1;
            ras_restore_ptr_i = RAS_PTR_BITS'(ptr_value);
            ras_restore_count_i = RAS_COUNT_BITS'(count_value);
            ras_restore_pop_i = pop;
            ras_restore_push_i = push;
            ras_restore_link_i = 32'h3456789c;
            for (integer j = 0; j < RAS_DEPTH; j++) begin
                stack[j] = 32'h1000+32'(j*4);
                ras_restore_data_i[32*j +: 32] = stack[j];
            end
            pointer = ptr_value;count = count_value;
            if (pop && count != 0) begin
                pointer = (pointer-1)&(RAS_DEPTH-1);count--;
            end
            if (push) begin
                stack[pointer] = ras_restore_link_i;
                pointer = (pointer+1)&(RAS_DEPTH-1);
                if (count < RAS_DEPTH) count++;
            end
            tick();ras_restore_valid_i = 0;
            ras_restore_pop_i = 0;ras_restore_push_i = 0;
        end
    endtask
    integer idx;
    integer address;
    reg [11:0] next_history;
    integer kind;
    integer old_address;
    integer old_kind;
    integer old_index;
    bit outcome;
    bit old_outcome;
    initial begin
        initialize();history = 0;queries = 0;
        for (integer j = 0; j < 4096; j++) counters[j] = 1;
        for (integer j = 0; j < 128; j++) btb_valid[j] = 0;
        restore(0,0,0,0);
        query(0,0);
        // Every fast counter sees a taken transition from weak NT, then an NT transition.
        for (integer n = 0; n < 4096; n++) begin
            next_history = {history[10:0],1'b1};
            address = (n^int'(next_history))*4;
            train_one(address,0,n,1);query(address,0);
            next_history = {history[10:0],1'b0};
            address = (n^int'(next_history))*4;
            train_one(address,0,n,0);query(address,0);
        end
        // Mixed PC aliases, MEM/EX collisions, and all call/return classes.
        for (integer n = 0; n < 1200; n++) begin
            address = (random_next()%2048)*4;
            kind = random_next()%6;
            idx = random_next()%4096;
            outcome = 1'(random_next());
            ex_predict_train_valid_i = 1;
            ex_predict_train_pc_i = 32'(address);
            ex_predict_train_target_i = 32'(address+256);
            ex_predict_train_type_i = 3'(kind);
            ex_predict_train_fast_index_i = 12'(idx);
            ex_predict_train_taken_i = outcome;
            if (ISSUE_WIDTH == 2 && n%7 == 0) begin
                old_address = (random_next()%2048)*4;
                old_kind = random_next()%6;
                old_index = n%14 == 0 ? idx : random_next()%4096;
                old_outcome = 1'(random_next());
                mem_predict_train_valid_i = 1;
                mem_predict_train_pc_i = 32'(old_address);
                mem_predict_train_target_i = 32'(old_address+512);
                mem_predict_train_type_i = 3'(old_kind);
                mem_predict_train_fast_index_i = 12'(old_index);
                mem_predict_train_taken_i = old_outcome;
                train_reference(old_address,old_address+512,old_kind,old_index,old_outcome);
            end
            train_reference(address,address+256,kind,idx,outcome);
            tick();ex_predict_train_valid_i = 0;mem_predict_train_valid_i = 0;
            query(address,1);
            query((random_next()%2048)*4,1);
        end
        train_one(0,3,0,1);
        for (integer n = 0; n < 3*RAS_DEPTH; n++) query(0,1);
        train_one(64,4,0,1);
        for (integer n = 0; n < 2*RAS_DEPTH; n++) query(64,1);
        for (integer n = 0; n <= RAS_DEPTH; n++) begin
            restore(n%RAS_DEPTH,n,0,0);query(64,0);
            restore(n%RAS_DEPTH,n,1,1);query(64,0);
        end
        if(ISSUE_WIDTH==1) begin
            // An 8B-aligned request starting at its upper word skips the old
            // lower-word call and applies only the upper-word return.
            restore(1,1,0,0);train_one(0,3,0,1);train_one(4,4,0,1);
            query_skip0_i=1;query(0,1);query_skip0_i=0;
        end
        if(ISSUE_WIDTH==2) begin
            for(integer j=0;j<4096;j++) picked_index[j]=0;
            for(integer which=0;which<4;which++) begin
                selected_index=-1;
                for(integer j=0;j<4096;j++)
                    if(counters[j]==1 && !picked_index[j] && selected_index<0) selected_index=j;
                if(selected_index<0) $fatal(1,"burst fast counter stimulus");
                burst_index[which]=selected_index;picked_index[selected_index]=1;
            end
            mem_predict_train_valid_i=1;ex_predict_train_valid_i=1;
            mem_predict_train_tag_i=0;ex_predict_train_tag_i=1;
            mem_predict_train_pc_i='h4000;ex_predict_train_pc_i='h4004;
            mem_predict_train_target_i='h4100;ex_predict_train_target_i='h4104;
            mem_predict_train_type_i=0;ex_predict_train_type_i=0;
            mem_predict_train_taken_i=1;ex_predict_train_taken_i=1;
            mem_predict_train_fast_index_i=12'(burst_index[0]);
            ex_predict_train_fast_index_i=12'(burst_index[1]);
            train_reference('h4000,'h4100,0,burst_index[0],1);
            train_reference('h4004,'h4104,0,burst_index[1],1);
            tick();
            mem_predict_train_tag_i=2;ex_predict_train_tag_i=3;
            mem_predict_train_pc_i='h4008;ex_predict_train_pc_i='h400c;
            mem_predict_train_target_i='h4108;ex_predict_train_target_i='h410c;
            mem_predict_train_fast_index_i=12'(burst_index[2]);
            ex_predict_train_fast_index_i=12'(burst_index[3]);
            train_reference('h4008,'h4108,0,burst_index[2],1);
            history={history[10:0],1'b1}; // EX table write drops, its GHR bit survives.
            tick();mem_predict_train_valid_i=0;ex_predict_train_valid_i=0;
            query('h4008,0);query('h400c,0);
            // Install conditional BTB entries without changing the two counters under test.
            next_history={history[10:0],1'b0};
            address=(burst_index[3]^int'(next_history))*4;
            train_one(address,0,burst_index[0],0);query(address,0);
            next_history={history[10:0],1'b0};
            address=(burst_index[2]^int'(next_history))*4;
            train_one(address,0,burst_index[0],0);query(address,0);
        end
        if(ISSUE_WIDTH==2) begin
            // BTB-only traffic cannot occupy the independent fast pending entry.
            selected_index=-1;
            for(integer j=0;j<4096;j++)
                if(counters[j]==1 && selected_index<0) selected_index=j;
            if(selected_index<0) $fatal(1,"mixed burst counter stimulus");
            mem_predict_train_valid_i=1;ex_predict_train_valid_i=1;
            mem_predict_train_tag_i=0;ex_predict_train_tag_i=1;
            mem_predict_train_pc_i='h5000;ex_predict_train_pc_i='h5004;
            mem_predict_train_target_i='h5100;ex_predict_train_target_i='h5104;
            mem_predict_train_type_i=1;ex_predict_train_type_i=1;
            train_reference('h5000,'h5100,1,0,1);
            train_reference('h5004,'h5104,1,0,1);
            tick();
            mem_predict_train_tag_i=2;ex_predict_train_tag_i=3;
            mem_predict_train_pc_i='h5008;ex_predict_train_pc_i='h500c;
            mem_predict_train_target_i='h5108;ex_predict_train_target_i='h510c;
            ex_predict_train_type_i=0;ex_predict_train_taken_i=1;
            ex_predict_train_fast_index_i=12'(selected_index);
            train_reference('h5008,'h5108,1,0,1);
            counters[selected_index]=2'(saturate(int'(counters[selected_index]),1));
            history={history[10:0],1'b1};
            tick();mem_predict_train_valid_i=0;ex_predict_train_valid_i=0;
            query('h500c,0);
            next_history={history[10:0],1'b0};address=(selected_index^int'(next_history))*4;
            train_one(address,0,(selected_index+1)%4096,0);query(address,0);
        end
        // Same-cycle age cancellation masks the younger training event.
        cancel_valid_i = 1;cancel_tag_i = 1;age_head_i = 0;
        ex_predict_train_valid_i = 1;ex_predict_train_tag_i = 2;
        ex_predict_train_pc_i = 128;ex_predict_train_type_i = 3;
        tick();ex_predict_train_valid_i = 0;cancel_valid_i = 0;
        query(128,0);
        age_head_i=3;cancel_tag_i=0;cancel_valid_i=1;
        ex_predict_train_valid_i=1;ex_predict_train_tag_i=1;
        ex_predict_train_pc_i='h2000;ex_predict_train_target_i='h2100;
        ex_predict_train_type_i=0;ex_predict_train_fast_index_i=2000;
        ex_predict_train_taken_i=1;
        mem_predict_train_valid_i=(ISSUE_WIDTH==2);mem_predict_train_tag_i=3;
        mem_predict_train_pc_i='h2004;mem_predict_train_target_i='h2200;
        mem_predict_train_type_i=1;
        if(ISSUE_WIDTH==2) train_reference('h2004,'h2200,1,0,1);
        tick();ex_predict_train_valid_i=0;mem_predict_train_valid_i=0;cancel_valid_i=0;
        query('h2000,0);
        rst_n_i=0;tick();rst_n_i=1;tick();
        history=0;pointer=0;count=0;
        for(integer j=0;j<128;j++) btb_valid[j]=0;
        query(0,0);train_one(0,0,1,1);query(0,0);
        $display("PASS CV07 predictor ISSUE_WIDTH=%0d: all4096 counters, BTB aliases, RAS overflow/full restore, MEM/EX, cancel seed707 queries=%0d",ISSUE_WIDTH,queries);
        $finish;
    end
endmodule
