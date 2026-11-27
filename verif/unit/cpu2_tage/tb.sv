// Self-checking public-interface test; independent architectural reference.
module tb;
    reg clk_i;
    reg rst_n_i;
    reg f1_valid_i;
    reg [31:0] f1_pc_i;
    wire [1:0] f1_fast_o;
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
    reg fast_update_i;
    reg [11:0] fast_index_i;
    reg fast_taken_i;
    wire pending_o;
    edrv32_cpu2_tage dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .f1_valid_i(f1_valid_i),
        .f1_pc_i(f1_pc_i),
        .f1_fast_o(f1_fast_o),
        .f2_valid_o(f2_valid_o),
        .f2_prediction_o(f2_prediction_o),
        .f2_alternate_o(f2_alternate_o),
        .f2_provider_o(f2_provider_o),
        .f2_indices_o(f2_indices_o),
        .f2_tags_o(f2_tags_o),
        .f2_base_indices_o(f2_base_indices_o),
        .d_valid_i(d_valid_i),
        .d_indices_i(d_indices_i),
        .d_tags_i(d_tags_i),
        .d_base_index_i(d_base_index_i),
        .d_provider_i(d_provider_i),
        .d_prediction_i(d_prediction_i),
        .d_alternate_i(d_alternate_i),
        .ex_resolve_i(ex_resolve_i),
        .ex_taken_i(ex_taken_i),
        .mem_resolve_i(mem_resolve_i),
        .mem_taken_i(mem_taken_i),
        .fast_update_i(fast_update_i),
        .fast_index_i(fast_index_i),
        .fast_taken_i(fast_taken_i),
        .pending_o(pending_o)
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
        fast_update_i = '0;
        fast_index_i = '0;
        fast_taken_i = '0;
        tick(); rst_n_i = 1; tick();
    end endtask
    reg [15:0] tables [0:3][0:511];
    reg [1:0] base [0:4095];
    reg [95:0] history;
    reg [35:0] expected_indices [0:1];
    reg [39:0] expected_tags [0:1];
    reg [11:0] expected_base [0:1];
    reg [2:0] expected_provider [0:1];
    reg expected_prediction [0:1];
    reg expected_alternate [0:1];
    reg [35:0] token_indices [0:2];
    reg [39:0] token_tags [0:2];
    reg [11:0] token_base [0:2];
    reg [2:0] token_provider [0:2];
    reg token_prediction [0:2];
    reg token_alternate [0:2];
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
                    tables[provider][idx]={1'b1,10'(tag_value),3'(counter),2'(useful)};
                end
            end
            allocated=0;
            if(token_prediction[which]!=taken) begin
                for(integer j=provider+1;j<4;j=j+1) begin
                    idx=int'(token_indices[which][9*j+:9]);row=tables[j][idx];
                    if(!allocated) begin
                        if(!row[15] || row[1:0]==0) begin
                            tables[j][idx]={1'b1,token_tags[which][10*j+:10],
                                taken?3'd4:3'd3,2'd0};allocated=1;
                        end else tables[j][idx]={row[15:2],row[1:0]-2'd1};
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
    initial begin
        init_inputs();history=0;lengths[0]=4;lengths[1]=12;lengths[2]=32;lengths[3]=96;
        for(n=0;n<4096;n=n+1) base[n]=1;
        for(n=0;n<4;n=n+1) for(m=0;m<512;m=m+1) tables[n][m]=0;
        for(n=0;n<5;n=n+1) provider_seen[n]=0;
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
        if(!pending_o) $fatal(1,"collision must retain younger pending update");
        d_valid_i=0;mem_resolve_i=0;ex_resolve_i=1;ex_taken_i=0;
        update_reference(2,0);f1_pc_i=0;predict_reference(0);
        history={history[94:0],1'b0};tick();compare_query();
        if(!pending_o) $fatal(1,"pending drain and new EX write");
        ex_resolve_i=0;f1_valid_i=0;tick();tick();
        if(pending_o) $fatal(1,"pending drain");
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
        // Fast gshare updates even without a live TAGE token.
        fast_update_i=1;fast_index_i=0;fast_taken_i=1;tick();fast_update_i=0;
        f1_pc_i=4;#1;if(f1_fast_o[0]!==1) $fatal(1,"fast gshare training");
        $display("PASS cpu2_tage: reference queries, folds, provider/alternate, pending, collisions");
        $finish;
    end

endmodule
