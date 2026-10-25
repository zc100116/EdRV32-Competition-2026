// cpu_frontend/tb.sv
// cpu-testplan C-R2; cpu-spec 3.2, 4.1, 4.4.
// Drive F1/F2/IB with a delayed I-cache model and check the decoded instruction stream.
// Stop with a diagnostic on the first mismatch; print PASS on completion.
// Clock domain: clk_sys.
`timescale 1ns/1ps
module tb #(parameter RVC_EN=1);
    reg clk_i=0;
    always #5 clk_i=~clk_i;
    reg rst_n_i=0;
    reg redirect_valid_i=0;
    reg [31:0] redirect_pc_i=0;
    reg [36:0] redirect_ras_i=0;
    reg redirect_push_i=0;
    reg redirect_pop_i=0;
    reg [31:0] redirect_return_pc_i=0;
    reg d_redirect_valid_i=0;
    reg [31:0] d_redirect_pc_i=0;
    reg [36:0] d_redirect_ras_i=0;
    reg d_redirect_push_i=0;
    reg d_redirect_pop_i=0;
    reg [31:0] d_redirect_return_pc_i=0;
    reg halt_i=0;
    reg update_valid_i=0;
    reg [31:0] update_pc_i=0;
    reg [31:0] update_target_i=0;
    reg [2:0] update_type_i=0;
    reg update_taken_i=0;
    reg update_compressed_i=0;
    reg [8:0] update_index_i=0;
    reg [1:0] decode_pop_count_i=0;
    wire [357:0] decode_data_o;
    wire [1:0] decode_valid_count_o;
    wire [2:0] ib_count_o;
    wire ic_req_valid_o;
    wire [31:0] ic_req_addr_o;
    reg ic_req_ready_i=0;
    reg ic_resp_valid_i=0;
    reg [63:0] ic_resp_data_i=0;
    reg ic_resp_err_i=0;
    wire ic_kill_o;
    reg invalidate_i=0;
    wire invalidate_done_o;
    wire ic_inv_o;
    reg ic_inv_done_i=0;
    wire f1_valid_o;
    wire f2_valid_o;
    wire fetch_wait_o;
    reg [15:0] memory[0:4095];
    reg model_pending=0;
    reg [31:0] model_addr=0;
    integer delay_left=0;
    reg allow_request=1;
    integer cycle_number=0;
    integer expected_pc=0;
    integer accepted=0;
    integer retired=0;
    integer pairs=0;
    integer killed=0;
    integer waits=0;
    integer blocked=0;
    integer predicted=0;
    integer crossed=0;
    integer errors=0;
    integer high_redirects=0;
    integer d_redirects=0;
    integer i;
    integer lane;
    integer length_bytes;
    reg [178:0] record_value;
    reg [31:0] expected_raw;
    reg [31:0] expected_instr;
    reg expected_error;

    edrv32_cpu_frontend #(.RVC_EN(RVC_EN)) dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .redirect_valid_i(redirect_valid_i),
        .redirect_pc_i(redirect_pc_i),
        .redirect_ras_i(redirect_ras_i),
        .redirect_push_i(redirect_push_i),
        .redirect_pop_i(redirect_pop_i),
        .redirect_return_pc_i(redirect_return_pc_i),
        .d_redirect_valid_i(d_redirect_valid_i),
        .d_redirect_pc_i(d_redirect_pc_i),
        .d_redirect_ras_i(d_redirect_ras_i),
        .d_redirect_push_i(d_redirect_push_i),
        .d_redirect_pop_i(d_redirect_pop_i),
        .d_redirect_return_pc_i(d_redirect_return_pc_i),
        .halt_i(halt_i),
        .update_valid_i(update_valid_i),
        .update_pc_i(update_pc_i),
        .update_target_i(update_target_i),
        .update_type_i(update_type_i),
        .update_taken_i(update_taken_i),
        .update_compressed_i(update_compressed_i),
        .update_index_i(update_index_i),
        .decode_pop_count_i(decode_pop_count_i),
        .decode_data_o(decode_data_o),
        .decode_valid_count_o(decode_valid_count_o),
        .ib_count_o(ib_count_o),
        .ic_req_valid_o(ic_req_valid_o),
        .ic_req_addr_o(ic_req_addr_o),
        .ic_req_ready_i(ic_req_ready_i),
        .ic_resp_valid_i(ic_resp_valid_i),
        .ic_resp_data_i(ic_resp_data_i),
        .ic_resp_err_i(ic_resp_err_i),
        .ic_kill_o(ic_kill_o),
        .invalidate_i(invalidate_i),
        .invalidate_done_o(invalidate_done_o),
        .ic_inv_o(ic_inv_o),
        .ic_inv_done_i(ic_inv_done_i),
        .f1_valid_o(f1_valid_o),
        .f2_valid_o(f2_valid_o),
        .fetch_wait_o(fetch_wait_o)
    );
    // Single-outstanding I$ model supports hit response plus a new request in one cycle.
    always @(*)begin
        ic_req_ready_i=allow_request && (!model_pending || delay_left==0);
        ic_resp_valid_i=model_pending && delay_left==0;
        ic_resp_err_i=model_addr==32'h100;
        ic_resp_data_i={memory[(model_addr>>1)+3],memory[(model_addr>>1)+2],
            memory[(model_addr>>1)+1],memory[model_addr>>1]};
        ic_inv_done_i=ic_inv_o;
    end
    always @(posedge clk_i)begin
        if(!rst_n_i)begin model_pending<=0;delay_left<=0;end
        else begin
            if(ic_kill_o)begin
                model_pending<=0;killed=killed+1;
            end else begin
                if(model_pending && delay_left>0)delay_left<=delay_left-1;
                if(ic_resp_valid_i)model_pending<=0;
                if(ic_req_valid_o && ic_req_ready_i)begin
                    if(ic_req_addr_o[2:0]!=0)$fatal(1,"FAIL unaligned I$ request");
                    model_pending<=1;model_addr<=ic_req_addr_o;
                    delay_left<=((ic_req_addr_o>>3)%9==0)?8:0;
                    accepted=accepted+1;
                end
            end
            if(halt_i && ic_req_valid_o)$fatal(1,"FAIL halt issued a request");
            if(fetch_wait_o)waits=waits+1;
            if(ic_req_valid_o && !ic_req_ready_i)blocked=blocked+1;
            if(invalidate_done_o!==ic_inv_done_i)$fatal(1,"FAIL invalidate completion");
            if(redirect_valid_i)begin expected_pc=integer'(redirect_pc_i);end
            else if(d_redirect_valid_i)begin expected_pc=integer'(d_redirect_pc_i);end
            else begin
                if(decode_pop_count_i>decode_valid_count_o)$fatal(1,"FAIL invalid test pop");
                if(decode_pop_count_i==2)pairs=pairs+1;
                for(lane=0;lane<integer'(decode_pop_count_i);lane=lane+1)begin
                    record_value=decode_data_o[lane*179+:179];
                    length_bytes=(RVC_EN && memory[expected_pc/2][1:0]!=3)?2:4;
                    expected_raw=length_bytes==2?{16'b0,memory[expected_pc/2]}:
                        {memory[expected_pc/2+1],memory[expected_pc/2]};
                    expected_instr=expected_raw;
                    if(length_bytes==2)begin
                        case(expected_raw[15:0])
                            16'h0001:expected_instr=32'h00000013;
                            16'h0085:expected_instr=32'h00108093;
                            default:$fatal(1,"FAIL unexpected test encoding %h",expected_raw);
                        endcase
                    end
                    expected_error=((expected_pc&~7)=='h100) ||
                        (length_bytes==4 && ((expected_pc+2)&~7)=='h100);
                    if(record_value[31:0]!==32'(expected_pc) ||
                        record_value[63:32]!==expected_instr ||
                        record_value[95:64]!==expected_raw ||
                        record_value[96] !== (length_bytes==2) || record_value[97] ||
                        record_value[98]!==expected_error)
                        $fatal(1,"FAIL frontend PC expected=%h actual=%h instr=%h/%h raw=%h/%h flags=%b time=%t",
                            expected_pc,record_value[31:0],expected_instr,record_value[63:32],
                            expected_raw,record_value[95:64],record_value[100:96],$time);
                    if(record_value[141:133]!==9'(expected_pc>>1))
                        $fatal(1,"FAIL saved gshare index PC=%h",expected_pc);
                    if(record_value[100])begin
                        if(expected_pc!=(RVC_EN?6:'hc) || record_value[132:101]!='h40)
                            $fatal(1,"FAIL predicted target PC=%h target=%h",
                                expected_pc,record_value[132:101]);
                        predicted=predicted+1;
                    end
                    if(expected_pc==6 && length_bytes==4)crossed=crossed+1;
                    if(expected_error)errors=errors+1;
                    retired=retired+1;
                    expected_pc=(expected_pc==(RVC_EN?6:'hc))?'h40:expected_pc+length_bytes;
                end
            end
        end
    end
    initial begin
        halt_i=1;
        for(i=0;i<4096;i=i+1)memory[i]=RVC_EN?16'h0001:(i[0]?16'h0000:16'h0013);
        if(RVC_EN)begin
            memory[0]=16'h0085;
            memory[1]=16'h0113;memory[2]=16'h0070;
            memory[3]=16'h006f;memory[4]=16'h03a0;
            memory['hfe/2]=16'h0213;memory['h100/2]=16'h0010;
        end
        memory['hc/2]=16'h006f;memory['he/2]=16'h0340;
        repeat(2)@(negedge clk_i);rst_n_i=1;
        update_valid_i=1;update_pc_i=RVC_EN?6:'hc;update_target_i='h40;update_type_i=3;
        update_taken_i=1;
        @(negedge clk_i);update_valid_i=0;halt_i=0;
        for(cycle_number=0;cycle_number<1200;cycle_number=cycle_number+1)begin
            @(negedge clk_i);
            allow_request=($urandom_range(0,3)!=0);
            decode_pop_count_i=2'($urandom_range(0,integer'(decode_valid_count_o)));
            redirect_valid_i=0;d_redirect_valid_i=0;
            halt_i=(cycle_number>=500 && cycle_number<520);
            invalidate_i=(cycle_number==900);
            if(cycle_number>=600 && high_redirects==0 && model_pending && delay_left>1)begin
                redirect_valid_i=1;redirect_pc_i='h180;
                d_redirect_valid_i=1;d_redirect_pc_i='h1a0;
                high_redirects=high_redirects+1;decode_pop_count_i=0;
            end else if(cycle_number>=850 && d_redirects==0 && model_pending)begin
                d_redirect_valid_i=1;d_redirect_pc_i='h200;
                d_redirects=d_redirects+1;decode_pop_count_i=0;
            end
        end
        @(negedge clk_i);halt_i=1;decode_pop_count_i=0;
        if(accepted<50 || retired<100 || pairs==0 || killed==0 || waits==0 ||
            blocked==0 || predicted==0 || (RVC_EN && crossed==0) || errors==0 ||
            high_redirects==0 || d_redirects==0)
            $fatal(1,"FAIL frontend coverage accepted=%d retired=%d kill=%d predicted=%d cross=%d errors=%d",
                accepted,retired,killed,predicted,crossed,errors);
        $display("PASS frontend RVC=%0d requests=%0d instructions=%0d pairs=%0d kill=%0d wait=%0d backpressure=%0d cross=%0d errors=%0d",
            RVC_EN,accepted,retired,pairs,killed,waits,blocked,crossed,errors);$finish;
    end
endmodule
