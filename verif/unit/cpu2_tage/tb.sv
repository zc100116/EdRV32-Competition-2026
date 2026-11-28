// Self-checking public-interface test; independent architectural reference.
module tb #(
    parameter [31:0] FPU_FORMAT = "NONE"
);
    localparam TAG_BITS = FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2;
    reg clk_i;
    reg rst_n_i;
    reg f1_valid_i;
    reg [31:0] f1_pc_i;
    wire f2_valid_o;
    wire [1:0] f2_prediction_o;
    wire [1:0] f2_alternate_o;
    wire [5:0] f2_provider_o;
    wire [71:0] f2_indices_o;
    wire [79:0] f2_tags_o;
    wire [23:0] f2_base_indices_o;
    reg d_valid_i;
    reg [35:0] d_indices_i;
    reg [39:0] d_tags_i;
    reg [11:0] d_base_index_i;
    reg [2:0] d_provider_i;
    reg d_prediction_i;
    reg d_alternate_i;
    reg ex_resolve_i;
    reg ex_taken_i;
    reg mem_resolve_i;
    reg mem_taken_i;
    reg [35:0] ex_indices;
    reg [39:0] ex_tags;
    reg [11:0] ex_base_index;
    reg [2:0] ex_provider;
    reg [0:0] ex_prediction;
    reg [0:0] ex_alternate;
    reg [TAG_BITS-1:0] ex_tag;
    reg [35:0] mem_indices;
    reg [39:0] mem_tags;
    reg [11:0] mem_base_index;
    reg [2:0] mem_provider;
    reg [0:0] mem_prediction;
    reg [0:0] mem_alternate;
    reg [TAG_BITS-1:0] mem_tag;
    reg manual_mode = 0;
    reg cancel_valid = 0;
    reg [TAG_BITS-1:0] cancel_tag = 0;
    reg [TAG_BITS-1:0] age_head = 0;
    reg [TAG_BITS-1:0] next_tag = 0;
    always @(posedge clk_i) begin
        if (!manual_mode) begin
        mem_indices <= ex_indices;
        mem_tags <= ex_tags;
        mem_base_index <= ex_base_index;
        mem_provider <= ex_provider;
        mem_prediction <= ex_prediction;
        mem_alternate <= ex_alternate;
        mem_tag <= ex_tag;
        ex_indices <= d_indices_i;
        ex_tags <= d_tags_i;
        ex_base_index <= d_base_index_i;
        ex_provider <= d_provider_i;
        ex_prediction <= d_prediction_i;
        ex_alternate <= d_alternate_i;
        ex_tag <= next_tag;
        end
        if (d_valid_i) next_tag <= next_tag + 1;
    end
    reg ex_live = 0;
    reg mem_live = 0;
    always @(posedge clk_i) begin
        if (!manual_mode) begin
            ex_live <= d_valid_i;
            mem_live <= ex_live && !ex_resolve_i;
        end
    end
    edrv32_cpu2_tage #(
        .FPU_FORMAT(FPU_FORMAT)
    ) dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .f1_valid_i(f1_valid_i),
        .f1_pc_i(f1_pc_i),
        .f2_valid_o(f2_valid_o),
        .f2_prediction_o(f2_prediction_o),
        .f2_alternate_o(f2_alternate_o),
        .f2_provider_o(f2_provider_o),
        .f2_indices_o(f2_indices_o),
        .f2_tags_o(f2_tags_o),
        .f2_base_indices_o(f2_base_indices_o),
        .predict_read0_valid_i(d_valid_i),
        .predict_read0_tag_i(next_tag),
        .predict_read0_base_index_i(d_base_index_i),
        .predict_read0_index0_i(d_indices_i[0 +: 9]),
        .predict_read0_index1_i(d_indices_i[9 +: 9]),
        .predict_read0_index2_i(d_indices_i[18 +: 9]),
        .predict_read0_index3_i(d_indices_i[27 +: 9]),
        .predict_read0_tag0_i(d_tags_i[0 +: 10]),
        .predict_read0_tag1_i(d_tags_i[10 +: 10]),
        .predict_read0_tag2_i(d_tags_i[20 +: 10]),
        .predict_read0_tag3_i(d_tags_i[30 +: 10]),
        .predict_read1_valid_i(1'b0),
        .predict_read1_tag_i({TAG_BITS{1'b0}}),
        .predict_read1_base_index_i(12'd0),
        .predict_read1_index0_i(9'd0),
        .predict_read1_index1_i(9'd0),
        .predict_read1_index2_i(9'd0),
        .predict_read1_index3_i(9'd0),
        .predict_read1_tag0_i(10'd0),
        .predict_read1_tag1_i(10'd0),
        .predict_read1_tag2_i(10'd0),
        .predict_read1_tag3_i(10'd0),
        .ex_predict_train_valid_i(ex_resolve_i && ex_live),
        .ex_predict_train_tag_i(ex_tag),
        .ex_predict_train_taken_i(ex_taken_i),
        .ex_predict_train_token_i(1'b1),
        .ex_predict_train_provider_i(ex_provider),
        .ex_predict_train_prediction_i(ex_prediction),
        .ex_predict_train_alternate_i(ex_alternate),
        .ex_predict_train_base_index_i(ex_base_index),
        .ex_predict_train_index0_i(ex_indices[0 +: 9]),
        .ex_predict_train_index1_i(ex_indices[9 +: 9]),
        .ex_predict_train_index2_i(ex_indices[18 +: 9]),
        .ex_predict_train_index3_i(ex_indices[27 +: 9]),
        .ex_predict_train_tag0_i(ex_tags[0 +: 10]),
        .ex_predict_train_tag1_i(ex_tags[10 +: 10]),
        .ex_predict_train_tag2_i(ex_tags[20 +: 10]),
        .ex_predict_train_tag3_i(ex_tags[30 +: 10]),
        .mem_predict_train_valid_i(mem_resolve_i && mem_live),
        .mem_predict_train_tag_i(mem_tag),
        .mem_predict_train_taken_i(mem_taken_i),
        .mem_predict_train_token_i(1'b1),
        .mem_predict_train_provider_i(mem_provider),
        .mem_predict_train_prediction_i(mem_prediction),
        .mem_predict_train_alternate_i(mem_alternate),
        .mem_predict_train_base_index_i(mem_base_index),
        .mem_predict_train_index0_i(mem_indices[0 +: 9]),
        .mem_predict_train_index1_i(mem_indices[9 +: 9]),
        .mem_predict_train_index2_i(mem_indices[18 +: 9]),
        .mem_predict_train_index3_i(mem_indices[27 +: 9]),
        .mem_predict_train_tag0_i(mem_tags[0 +: 10]),
        .mem_predict_train_tag1_i(mem_tags[10 +: 10]),
        .mem_predict_train_tag2_i(mem_tags[20 +: 10]),
        .mem_predict_train_tag3_i(mem_tags[30 +: 10]),
        .age_head_i(age_head),
        .cancel_valid_i(cancel_valid),
        .cancel_tag_i(cancel_tag)
    );
    always #5 clk_i = ~clk_i;
    task tick; begin @(posedge clk_i); #1; end endtask
    task init_inputs; begin
        clk_i = '0;
        rst_n_i = '0;
        f1_valid_i = '0;
        f1_pc_i = '0;
        d_valid_i = '0;
        d_indices_i = '0;
        d_tags_i = '0;
        d_base_index_i = '0;
        d_provider_i = '0;
        d_prediction_i = '0;
        d_alternate_i = '0;
        ex_resolve_i = '0;
        ex_taken_i = '0;
        mem_resolve_i = '0;
        mem_taken_i = '0;
        tick(); rst_n_i = 1; tick();
    end endtask
    reg [15:0] tables [0:3][0:511];
    reg [1:0] base [0:4095];
    bit trained_seen [0:3][0:511];
    reg [95:0] history;
    reg [35:0] expected_indices [0:1];
    reg [39:0] expected_tags [0:1];
    reg [11:0] expected_base [0:1];
    reg [2:0] expected_provider [0:1];
    reg expected_prediction [0:1];
    reg expected_alternate [0:1];
    reg [35:0] token_indices [0:3];
    reg [39:0] token_tags [0:3];
    reg [11:0] token_base [0:3];
    reg [2:0] token_provider [0:3];
    reg token_prediction [0:3];
    reg token_alternate [0:3];
    integer n;
    integer m;
    integer t;
    integer pc;
    integer slot;
    reg outcome;
    integer lengths [0:3];
    integer provider_seen [0:4];
    function automatic integer folded(input reg [95:0] value,input integer width);
        integer k;
        begin
            folded=0;
            for(k=0;k<96;k=k+width) folded=folded ^ int'((value>>k)&((96'd1<<width)-1));
        end
    endfunction
    task predict_reference(input integer address);
        reg [95:0] h;
        reg [15:0] row;
        integer word_pc;
        integer idx;
        integer tag_value;
        begin
            for(integer q=0;q<2;q=q+1) begin
                word_pc=(address+4*q)>>2;
                expected_base[q]=12'(word_pc);
                expected_prediction[q]=base[word_pc&4095]>=2;
                expected_alternate[q]=expected_prediction[q];expected_provider[q]=0;
                for(integer j=0;j<4;j=j+1) begin
                    h=history & ((lengths[j]==96)?{96{1'b1}}:((96'd1<<lengths[j])-1));
                    idx=(word_pc ^ folded(h,9))&511;
                    tag_value=((word_pc>>9)^folded(h,10)^folded(h>>1,9))&1023;
                    expected_indices[q][9*j+:9]=9'(idx);
                    expected_tags[q][10*j+:10]=10'(tag_value);
                    row=tables[j][idx];
                    if(row[15] && row[14:5]==10'(tag_value)) begin
                        expected_alternate[q]=expected_prediction[q];
                        expected_prediction[q]=row[4:2]>=4;
                        expected_provider[q]=3'(j+1);
                    end
                end
            end
        end
    endtask
    task compare_query;
        begin
            if(!f2_valid_o) $fatal(1,"missing F2");
            for(integer q=0;q<2;q=q+1) begin
                if(f2_indices_o[36*q+:36]!==expected_indices[q] ||
                    f2_tags_o[40*q+:40]!==expected_tags[q] ||
                    f2_base_indices_o[12*q+:12]!==expected_base[q])
                    $fatal(1,"fold/token mismatch q%0d idx %h/%h tag %h/%h",q,
                        f2_indices_o[36*q+:36],expected_indices[q],
                        f2_tags_o[40*q+:40],expected_tags[q]);
                if(f2_prediction_o[q]!==expected_prediction[q] ||
                    f2_alternate_o[q]!==expected_alternate[q] ||
                    f2_provider_o[3*q+:3]!==expected_provider[q])
                    $fatal(1,"TAGE q%0d expected p%0d/%b alt%b got p%0d/%b alt%b time%0t",q,
                        expected_provider[q],expected_prediction[q],expected_alternate[q],
                        f2_provider_o[3*q+:3],f2_prediction_o[q],f2_alternate_o[q],$time);
                provider_seen[int'(expected_provider[q])]++;
            end
        end
    endtask
    task request(input integer address);
        begin
            f1_valid_i=1;f1_pc_i=32'(address);predict_reference(address);tick();
            compare_query();f1_valid_i=0;
        end
    endtask
    task save_token(input integer which,input integer q);
        begin
            token_indices[which]=expected_indices[q];token_tags[which]=expected_tags[q];
            token_base[which]=expected_base[q];token_provider[which]=expected_provider[q];
            token_prediction[which]=expected_prediction[q];
            token_alternate[which]=expected_alternate[q];
        end
    endtask
    task d_token(input integer which);
        begin
            d_valid_i=1;d_indices_i=token_indices[which];d_tags_i=token_tags[which];
            d_base_index_i=token_base[which];d_provider_i=token_provider[which];
            d_prediction_i=token_prediction[which];d_alternate_i=token_alternate[which];
        end
    endtask
    function automatic integer sat(input integer old_value,input bit up_value,input integer maximum);
        sat=up_value?((old_value==maximum)?old_value:old_value+1):
            ((old_value==0)?0:old_value-1);
    endfunction
    task update_reference(input integer which,input bit taken);
        integer idx;
        integer tag_value;
        integer provider;
        integer counter;
        integer useful;
        reg [15:0] row;
        bit allocated;
        begin
            idx=int'(token_base[which]);base[idx]=2'(sat(int'(base[idx]),taken,3));
            provider=int'(token_provider[which])-1;
            if(provider>=0) begin
                idx=int'(token_indices[which][9*provider+:9]);
                tag_value=int'(token_tags[which][10*provider+:10]);row=tables[provider][idx];
                if(row[15] && row[14:5]==10'(tag_value)) begin
                    counter=sat(int'(row[4:2]),taken,7);useful=int'(row[1:0]);
                    if(token_prediction[which]!=token_alternate[which])
                        useful=sat(useful,token_prediction[which]==taken,3);
                    trained_seen[provider][idx]=1;
                    tables[provider][idx]={1'b1,10'(tag_value),3'(counter),2'(useful)};
                end
            end
            allocated=0;
            if(token_prediction[which]!=taken) begin
                for(integer j=provider+1;j<4;j=j+1) begin
                    idx=int'(token_indices[which][9*j+:9]);row=tables[j][idx];
                    if(!allocated) begin
                        if(!row[15] || row[1:0]==0) begin
                            trained_seen[j][idx]=1;
                            tables[j][idx]={1'b1,token_tags[which][10*j+:10],
                                taken?3'd4:3'd3,2'd0};allocated=1;
                        end else begin
                            trained_seen[j][idx]=1;
                            tables[j][idx]={row[15:2],row[1:0]-2'd1};
                        end
                    end
                end
            end
        end
    endtask
    // The pure update datapath has an independent directed row-level check as well.
    reg [63:0] unit_rows;
    reg [39:0] unit_tags;
    reg [2:0] unit_provider;
    reg unit_pred;
    reg unit_alt;
    reg unit_taken;
    wire [63:0] unit_new_rows;
    wire [3:0] unit_mask;
    wire [1:0] unit_new_base;
    edrv32_cpu2_tage_update update_dut (
        .rows_i(unit_rows), .tags_i(unit_tags), .provider_i(unit_provider),
        .prediction_i(unit_pred), .alternate_i(unit_alt), .taken_i(unit_taken),
        .base_i(2'd2), .base_o(unit_new_base), .rows_o(unit_new_rows), .write_o(unit_mask)
    );
    reg [TAG_BITS-1:0] saved_record_tag [0:3];
    integer fresh_base;
    integer base_pc;
    integer base_only_pc;
    integer burst_pc [0:3];
    bit picked_base [0:4095];
    task base_only_query_pc(input integer address,output integer selected);
        begin
            selected=0;
            for(integer candidate=0;candidate<8;candidate++) begin
                predict_reference(address+candidate*16384);
                if(expected_provider[0]==0 && selected==0) selected=address+candidate*16384;
            end
            if(selected==0) $fatal(1,"base-only query stimulus");
        end
    endtask
    task load_ex(input integer which,input reg [TAG_BITS-1:0] tag_value);
        begin
            ex_tag=tag_value;
            ex_indices=token_indices[which];ex_tags=token_tags[which];
            ex_base_index=token_base[which];ex_provider=token_provider[which];
            ex_prediction=token_prediction[which];ex_alternate=token_alternate[which];
        end
    endtask
    task load_mem(input integer which,input reg [TAG_BITS-1:0] tag_value);
        begin
            mem_tag=tag_value;
            mem_indices=token_indices[which];mem_tags=token_tags[which];
            mem_base_index=token_base[which];mem_provider=token_provider[which];
            mem_prediction=token_prediction[which];mem_alternate=token_alternate[which];
        end
    endtask
    // Drive a real token through D/EX and compare using the public state model.
    task resolve_single(input integer address,input bit direction);
        begin
            request(address);save_token(0,0);d_token(0);tick();d_valid_i=0;
            ex_resolve_i=1;ex_taken_i=direction;
            update_reference(0,direction);history={history[94:0],direction};
            tick();ex_resolve_i=0;tick();
        end
    endtask
    reg [95:0] desired_history;
    reg [35:0] preserved_indices;
    reg [95:0] limited_history;
    integer candidate_pc;
    integer chosen_pc;
    integer target_pc;
    integer chosen_tag;
    bit tag_unused;
    bit all_rows_match;
    bit acceptable;
    task establish_history;
        begin
            if(history!==desired_history)
            for(integer bit_number=95;bit_number>=0;bit_number--) begin
                chosen_pc=0;
                // Eight candidates exceed the four prohibited table indices.
                for(integer candidate=1;candidate<=8;candidate++) begin
                    candidate_pc='h100000+4*candidate;
                    predict_reference(candidate_pc);acceptable=1;
                    for(integer j=0;j<4;j++)
                        if(expected_indices[0][9*j+:9]==preserved_indices[9*j+:9])
                            acceptable=0;
                    if(acceptable && chosen_pc==0) chosen_pc=candidate_pc;
                end
                if(chosen_pc==0) $fatal(1,"history stimulus index selection");
                resolve_single(chosen_pc,desired_history[bit_number]);
            end
            if(history!==desired_history) $fatal(1,"reference history load");
        end
    endtask
    initial begin
        init_inputs();history=0;lengths[0]=4;lengths[1]=12;lengths[2]=32;lengths[3]=96;
        for(n=0;n<4096;n=n+1) base[n]=1;
        for(n=0;n<4;n=n+1) for(m=0;m<512;m=m+1) begin tables[n][m]=0;trained_seen[n][m]=0;end
        for(n=0;n<5;n=n+1) provider_seen[n]=0;
        for(n=0;n<4096;n=n+2) request(n*4);
        // Longest provider arithmetic and pressure stop after the first free candidate.
        unit_rows={{1'b1,10'd7,3'd7,2'd3},{1'b1,10'd7,3'd0,2'd1},
            {1'b1,10'd7,3'd3,2'd2},{1'b1,10'd7,3'd4,2'd3}};
        unit_tags={4{10'd7}};unit_provider=4;unit_pred=1;unit_alt=0;unit_taken=1;#1;
        if(unit_mask!==8 || unit_new_rows[63:48]!==unit_rows[63:48] || unit_new_base!==3)
            $fatal(1,"provider saturation/usefulness");
        unit_provider=1;unit_pred=1;unit_taken=0;#1;
        if(unit_mask!==15 || unit_new_rows[17:16]!==1 || unit_new_rows[33:32]!==0 ||
            unit_new_rows[49:48]!==2) $fatal(1,"allocation pressure");
        unit_rows[33:32]=0;#1;
        if(unit_mask!==7 || unit_new_rows[47:32]!=={1'b1,10'd7,3'd3,2'd0})
            $fatal(1,"first longer allocation");
        request(0);save_token(0,0);
        if(f2_provider_o!==0 || f2_prediction_o!==0) $fatal(1,"cold base weak not taken");
        // No live D token: EX/MEM resolution cannot train the TAGE history.
        ex_resolve_i=1;ex_taken_i=1;mem_resolve_i=1;mem_taken_i=1;tick();
        ex_resolve_i=0;mem_resolve_i=0;request(0);
        // Consecutive D tokens, delayed older MEM + younger EX, plus a third EX.
        // First two branch PCs alias the tagged index but have different tags.
        request(0);save_token(0,0);request(2048);save_token(1,0);save_token(2,0);
        d_token(0);tick();d_token(1);tick();d_token(2);
        mem_resolve_i=1;mem_taken_i=1;ex_resolve_i=1;ex_taken_i=1;
        update_reference(0,1);update_reference(1,1);
        f1_valid_i=1;f1_pc_i=2048;predict_reference(2048);
        history={history[93:0],2'b11};tick();compare_query();

        d_valid_i=0;mem_resolve_i=0;ex_resolve_i=1;ex_taken_i=0;
        update_reference(2,0);f1_pc_i=0;predict_reference(0);
        history={history[94:0],1'b0};tick();compare_query();

        ex_resolve_i=0;f1_valid_i=0;tick();tick();

        for(n=0;n<360;n=n+1) begin
            pc=((n%6==0)?n*4096:((n%11)*4));
            request(pc);save_token(0,n%2);d_token(0);tick();d_valid_i=0;
            outcome=1'((n*17+n/7)%3);
            ex_resolve_i=1;ex_taken_i=outcome;
            update_reference(0,outcome);
            f1_valid_i=1;f1_pc_i=32'(pc);predict_reference(pc);
            history={history[94:0],outcome};tick();compare_query();
            ex_resolve_i=0;f1_valid_i=0;tick();
        end
        if(provider_seen[0]==0 || provider_seen[1]==0) $fatal(1,"provider/no-hit coverage");
        // Reproduce one complete 96-bit history between target branches. The
        // fillers avoid all four target rows, so each misprediction allocates
        // the next longer provider without reading any RTL state.
        desired_history=96'h0123456789abcdefdeadbeef;
        for(integer j=0;j<4;j++) begin
            limited_history=desired_history &
                ((lengths[j]==96)?{96{1'b1}}:((96'd1<<lengths[j])-1));
            preserved_indices[9*j+:9]=9'((('h180000>>2)^folded(limited_history,9))&511);
        end
        for(integer round_number=0;round_number<6;round_number++) begin
            establish_history();request('h180000);save_token(0,0);
            d_token(0);tick();d_valid_i=0;
            outcome=!token_prediction[0];ex_resolve_i=1;ex_taken_i=outcome;
            update_reference(0,outcome);history={history[94:0],outcome};
            tick();ex_resolve_i=0;tick();
        end
        for(integer p=0;p<5;p++)
            if(provider_seen[p]==0) $fatal(1,"provider coverage missing=%0d",p);
        if($test$plusargs("ALL_ROWS")) begin
            desired_history=0;
            for(integer row_number=0;row_number<512;row_number++) begin
                all_rows_match=0;
                for(integer epoch_number=0;epoch_number<5;epoch_number++) begin
                    if(!all_rows_match) begin
                        // Avoid all current tags to restart at base. Busy rows
                        // consume usefulness under pressure before allocation.
                        chosen_tag=-1;
                        for(integer candidate=640;candidate<648;candidate++) begin
                            tag_unused=1;
                            for(integer j=0;j<4;j++)
                                if(tables[j][row_number][15] &&
                                   tables[j][row_number][14:5]==10'(candidate)) tag_unused=0;
                            if(tag_unused && chosen_tag<0) chosen_tag=candidate;
                        end
                        if(chosen_tag<0) $fatal(1,"full-row stimulus tag selection");
                        target_pc=(chosen_tag<<11)|(row_number<<2);
                        for(integer j=0;j<4;j++) preserved_indices[9*j+:9]=9'(row_number);
                        for(integer step_number=0;step_number<8;step_number++) begin
                            establish_history();request(target_pc);save_token(0,0);
                            if(token_provider[0]!=4) begin
                                outcome=!token_prediction[0];d_token(0);tick();d_valid_i=0;
                                ex_resolve_i=1;ex_taken_i=outcome;
                                update_reference(0,outcome);history={history[94:0],outcome};
                                tick();ex_resolve_i=0;tick();
                            end
                        end
                        all_rows_match=1;
                        for(integer j=0;j<4;j++)
                            if(!tables[j][row_number][15] ||
                               tables[j][row_number][14:5]!=10'(chosen_tag)) all_rows_match=0;
                    end
                end
                if(!all_rows_match) $fatal(1,"full-row allocation coverage row=%0d",row_number);
                establish_history();request(target_pc);
                if(expected_provider[0]!==4) $fatal(1,"longest row lookup row=%0d",row_number);
            end
            for(integer j=0;j<4;j++) for(integer row_number=0;row_number<512;row_number++)
                if(!trained_seen[j][row_number]) $fatal(1,"untrained table=%0d row=%0d",j,row_number);
            $display("PASS CV07 all 4x512 tagged rows allocated and queried");
        end
        // The explicitly specified three-way collision drops EX table writes,
        // retains MEM in the single pending slot, and advances both history bits.
        manual_mode=1;ex_live=0;mem_live=0;ex_resolve_i=0;mem_resolve_i=0;
        for(integer candidate=0;candidate<4096;candidate++) picked_base[candidate]=0;
        for(integer which=0;which<4;which++) begin
            fresh_base=-1;
            for(integer candidate=0;candidate<4096;candidate++)
                if(base[candidate]==1 && !picked_base[candidate] && fresh_base<0)
                    fresh_base=candidate;
            if(fresh_base<0) $fatal(1,"burst base stimulus");
            picked_base[fresh_base]=1;
            base_only_query_pc('h1c0000+4*fresh_base,base_only_pc);
            burst_pc[which]=base_only_pc;
            request(base_only_pc);save_token(which,0);d_token(which);
            saved_record_tag[which]=next_tag;tick();d_valid_i=0;
        end
        load_mem(0,saved_record_tag[0]);load_ex(1,saved_record_tag[1]);
        mem_live=1;ex_live=1;mem_resolve_i=1;ex_resolve_i=1;
        mem_taken_i=1;ex_taken_i=1;
        update_reference(0,1);update_reference(1,1);history={history[93:0],2'b11};
        tick();
        load_mem(2,saved_record_tag[2]);load_ex(3,saved_record_tag[3]);
        update_reference(2,1);
        f1_valid_i=1;f1_pc_i=32'(burst_pc[3]);predict_reference(burst_pc[3]);
        history={history[93:0],2'b11};tick();compare_query();
        mem_live=0;ex_live=0;mem_resolve_i=0;ex_resolve_i=0;f1_valid_i=0;tick();
        base_only_query_pc(burst_pc[3],base_only_pc);request(base_only_pc);
        if(expected_prediction[0]) $fatal(1,"dropped EX base stimulus");
        base_only_query_pc(burst_pc[2],base_only_pc);request(base_only_pc);
        if(!expected_prediction[0]) $fatal(1,"retained MEM base stimulus");
        // An operand wait can retain the D record for many cycles; association
        // is by completion tag rather than the old fixed D/EX/MEM schedule.
        manual_mode=1;ex_live=0;mem_live=0;ex_resolve_i=0;mem_resolve_i=0;
        request('h12340);save_token(0,0);d_token(0);
        ex_tag=next_tag;ex_indices=token_indices[0];ex_tags=token_tags[0];
        ex_base_index=token_base[0];ex_provider=token_provider[0];
        ex_prediction=token_prediction[0];ex_alternate=token_alternate[0];
        tick();d_valid_i=0;
        repeat(20) tick();
        ex_live=1;ex_resolve_i=1;ex_taken_i=1;
        update_reference(0,1);history={history[94:0],1'b1};
        tick();ex_resolve_i=0;ex_live=0;tick();request('h12340);
        // A younger pre-read record must observe an older table/base write
        // while it waits. Two increments then one decrement distinguish a stale
        // base row (NT) from the current row (taken), through a no-provider query.
        fresh_base=-1;
        for(integer candidate=0;candidate<4096;candidate++)
            if(base[candidate]==1 && fresh_base<0) fresh_base=candidate;
        if(fresh_base<0) $fatal(1,"fresh base stimulus");
        base_pc='h1c0000+4*fresh_base;
        base_only_query_pc(base_pc,base_only_pc);base_pc=base_only_pc;
        request(base_pc);save_token(0,0);d_token(0);saved_record_tag[0]=next_tag;
        tick();d_valid_i=0;
        request(base_pc);save_token(1,0);d_token(1);saved_record_tag[1]=next_tag;
        tick();d_valid_i=0;repeat(10) tick();
        load_mem(0,saved_record_tag[0]);mem_live=1;mem_resolve_i=1;mem_taken_i=1;
        update_reference(0,1);history={history[94:0],1'b1};
        tick();mem_resolve_i=0;mem_live=0;repeat(20) tick();
        load_ex(1,saved_record_tag[1]);ex_live=1;ex_resolve_i=1;ex_taken_i=1;
        update_reference(1,1);history={history[94:0],1'b1};
        tick();ex_resolve_i=0;ex_live=0;tick();
        base_only_query_pc(base_pc,base_only_pc);
        request(base_only_pc);save_token(2,0);d_token(2);saved_record_tag[2]=next_tag;
        tick();d_valid_i=0;load_ex(2,saved_record_tag[2]);
        ex_live=1;ex_resolve_i=1;ex_taken_i=0;
        update_reference(2,0);history={history[94:0],1'b0};
        tick();ex_resolve_i=0;ex_live=0;tick();
        base_only_query_pc(base_pc,base_only_pc);request(base_only_pc);
        if(!expected_prediction[0]) $fatal(1,"base forwarding stimulus threshold");
        // Cancel at exactly the stored tag, including a simultaneous resolution.
        next_tag=0;
        request('h12344);save_token(0,0);d_token(0);
        ex_tag=next_tag;ex_indices=token_indices[0];ex_tags=token_tags[0];
        ex_base_index=token_base[0];ex_provider=token_provider[0];
        ex_prediction=token_prediction[0];ex_alternate=token_alternate[0];
        tick();d_valid_i=0;repeat(7) tick();
        age_head={TAG_BITS{1'b1}};cancel_tag=ex_tag;cancel_valid=1;
        ex_live=1;ex_resolve_i=1;ex_taken_i=1;
        tick();cancel_valid=0;ex_resolve_i=0;ex_live=0;tick();request('h12344);
        // Soft reset invalidates query/record control and history, retaining the tables.
        f1_valid_i=0;rst_n_i=0;tick();rst_n_i=1;tick();history=0;
        if(f2_valid_o) $fatal(1,"soft reset query valid");
        request('h180000);
        $display("PASS cpu2_tage: all providers, folds, pending collisions, 20-cycle tag wait and same-edge cancel");
        $finish;
    end

endmodule
