// cpu_f2_recover/tb.sv
// cpu-testplan U-11; cpu-spec v0.3 4.4.
// Preseed stale or correct BTB entries and compare instruction bytes with memory.
// Verify request cancellation, BTB invalidation, RAS restoration and redirect priority.
// Clock domain: clk_sys.
`timescale 1ns/1ps
module tb;
    localparam RVC_EN=1;
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
    reg [15:0] memory[0:511];
    reg model_pending=0;
    reg [31:0] model_addr=0;
    integer model_delay=0;
    integer scenario;
    integer cycle_number;
    integer expected_pc;
    integer checked;
    integer recoveries;
    integer kills;
    integer priority_seen;
    integer lane;
    integer i;
    integer length_bytes;
    integer trained_pc;
    integer retry_pc;
    reg [31:0] expected_raw;
    reg [31:0] expected_instr;
    reg [178:0] entry;
    reg [36:0] expected_ras;
    reg [36:0] recovery_snapshot;
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
    always @(*) begin
        ic_req_ready_i=!model_pending || model_delay==0;
        ic_resp_valid_i=model_pending && model_delay==0;
        ic_resp_data_i={memory[(model_addr>>1)+3],memory[(model_addr>>1)+2],
            memory[(model_addr>>1)+1],memory[model_addr>>1]};
        ic_resp_err_i=0;
    end
    always @(posedge clk_i) begin
        if(!rst_n_i)begin model_pending<=0;model_delay<=0;end
        else if(ic_kill_o)begin
            if((scenario==0 || scenario==1) && (!model_pending || model_addr!=32'h40))
                $fatal(1,"FAIL U-11 target request not canceled case=%0d addr=%h",
                    scenario,model_addr);
            model_pending<=0;kills=kills+1;
        end
        else begin
            if(model_pending && model_delay>0)model_delay<=model_delay-1;
            if(ic_resp_valid_i)model_pending<=0;
            if(ic_req_valid_o && ic_req_ready_i)begin
                model_pending<=1;model_addr<=ic_req_addr_o;
                model_delay<=ic_req_addr_o == 32'h40 ? 6 : 0;
            end
        end
    end
    // Model checks the visible instruction stream, without inspecting assembled RTL data.
    always @(posedge clk_i) begin
        if(rst_n_i)begin
            if(redirect_valid_i)expected_pc=integer'(redirect_pc_i);
            else if(d_redirect_valid_i)expected_pc=integer'(d_redirect_pc_i);
            else begin
                for(lane=0;lane<integer'(decode_pop_count_i);lane=lane+1)begin
                    entry=decode_data_o[lane*179+:179];
                    length_bytes=memory[expected_pc/2][1:0]==3?4:2;
                    expected_raw=length_bytes==4?
                        {memory[expected_pc/2+1],memory[expected_pc/2]}:
                        {16'b0,memory[expected_pc/2]};
                    expected_instr=expected_raw;
                    if(length_bytes==2)begin
                        case(expected_raw[15:0])
                            16'h0001:expected_instr=32'h00000013;
                            16'h282d:expected_instr=32'h03a000ef;
                            default:$fatal(1,"FAIL U-11 test encoding %h",expected_raw);
                        endcase
                    end
                    if(entry[31:0]!==32'(expected_pc) || entry[95:64]!==expected_raw ||
                        entry[63:32]!==expected_instr || entry[96] !== (length_bytes==2) ||
                        entry[98:97]!==0)
                        $fatal(1,"FAIL U-11 case=%0d PC=%h/%h raw=%h/%h instruction=%h/%h time=%t",
                            scenario,expected_pc,entry[31:0],expected_raw,entry[95:64],
                            expected_instr,entry[63:32],$time);
                    if(entry[178:142]!==expected_ras)
                        $fatal(1,"FAIL U-11 record RAS case=%0d PC=%h expected=%h actual=%h",
                            scenario,expected_pc,expected_ras,entry[178:142]);
                    if(scenario==4 || scenario==5)begin
                        if(expected_pc==6)begin
                            if(!entry[100])$fatal(1,"FAIL U-11 lost correct prediction");
                            expected_pc='h40;
                            expected_ras={3'd2,2'd2,32'(6+length_bytes)};
                        end else expected_pc=expected_pc+length_bytes;
                    end else expected_pc=expected_pc+length_bytes;
                    checked=checked+1;
                end
            end
            if(dut.recover_w)begin
                recoveries=recoveries+1;
                recovery_snapshot=dut.recover_ras_w;
                if(dut.recover_pc_w!==32'(retry_pc) ||
                    dut.recover_btb_index_w!==5'(trained_pc>>3))
                    $fatal(1,"FAIL U-11 recovery address case=%0d PC=%h BTB=%d",
                        scenario,dut.recover_pc_w,dut.recover_btb_index_w);
                if(ic_req_valid_o)$fatal(1,"FAIL U-11 issued request during recovery");
                #1;
                if(dut.u_predictor.btb_valid_r[trained_pc>>3] ||
                    dut.f1_pc_r!==32'(retry_pc) || dut.u_predictor.predict_ras_o!==recovery_snapshot)
                    $fatal(1,"FAIL U-11 recovery state case=%0d PC=%h RAS=%h/%h",
                        scenario,dut.f1_pc_r,dut.u_predictor.predict_ras_o,recovery_snapshot);
            end
        end
    end
    initial begin
        for(scenario=0;scenario<8;scenario=scenario+1)begin
            @(negedge clk_i);rst_n_i=0;halt_i=1;decode_pop_count_i=0;
            redirect_valid_i=0;d_redirect_valid_i=0;update_valid_i=0;
            expected_pc=0;checked=0;recoveries=0;kills=0;priority_seen=0;
            expected_ras={3'd1,2'd1,32'habcdef00};
            for(i=0;i<512;i=i+1)memory[i]=16'h0001;
            trained_pc=6;retry_pc=6;
            update_compressed_i=1;
            case(scenario)
                0:begin // Predicted position is upper half of the instruction at PC 4.
                    memory[2]=16'h0193;memory[3]=16'h0090;retry_pc=4;
                end
                1,6,7:begin // BTB says 16 bits; actual instruction crosses the group boundary.
                    memory[3]=16'h0193;memory[4]=16'h0090;
                end
                2:begin // BTB says 32 bits; actual instruction is compressed.
                    update_compressed_i=0;
                end
                3:begin // Predicted position is upper half in the following fetch group.
                    trained_pc=8;retry_pc=6;
                    memory[3]=16'h0193;memory[4]=16'h0090;
                end
                4:begin // Correct 32-bit position and length, crossing the group boundary.
                    update_compressed_i=0;memory[3]=16'h00ef;memory[4]=16'h03a0;
                end
                5:begin // Correct compressed call position and length.
                    memory[3]=16'h282d;
                end
                default:begin end
            endcase
            repeat(2)@(negedge clk_i);rst_n_i=1;
            redirect_valid_i=1;redirect_pc_i=0;redirect_ras_i=expected_ras;
            @(negedge clk_i);redirect_valid_i=0;
            update_valid_i=1;update_pc_i=32'(trained_pc);update_target_i='h40;
            update_type_i=3;update_taken_i=1;
            @(negedge clk_i);update_valid_i=0;halt_i=0;
            for(cycle_number=0;cycle_number<100;cycle_number=cycle_number+1)begin
                @(negedge clk_i);
                decode_pop_count_i=cycle_number<8?0:decode_valid_count_o;
                redirect_valid_i=0;d_redirect_valid_i=0;
                if(scenario>=6 && !priority_seen && dut.recover_w)begin
                    // Resolve an older redirect on the same edge as an F2 mismatch.
                    d_redirect_valid_i=1;d_redirect_pc_i='h100;
                    d_redirect_ras_i={3'd1,2'd3,32'hbbbb0000};
                    expected_ras=d_redirect_ras_i;
                    if(scenario==7)begin
                        redirect_valid_i=1;redirect_pc_i='h180;
                        redirect_ras_i={3'd1,2'd2,32'hcccc0000};
                        expected_ras=redirect_ras_i;
                    end
                    decode_pop_count_i=0;priority_seen=1;
                    #1;if(dut.recover_w)$fatal(1,"FAIL U-11 redirect priority");
                end
                if(checked>=12)cycle_number=100;
            end
            @(negedge clk_i);halt_i=1;decode_pop_count_i=0;
            if(checked<12)$fatal(1,"FAIL U-11 no progress case=%0d",scenario);
            if(scenario<4)begin
                if(recoveries!=1 || kills==0 || dut.u_predictor.btb_valid_r[trained_pc>>3])
                    $fatal(1,"FAIL U-11 missing recovery case=%0d recovery=%0d kill=%0d",
                        scenario,recoveries,kills);
            end else begin
                if(recoveries!=0 || !dut.u_predictor.btb_valid_r[trained_pc>>3] ||
                    (scenario>=6 && !priority_seen))
                    $fatal(1,"FAIL U-11 unexpected recovery case=%0d",scenario);
            end
            $display("PASS U-11 case=%0d checked=%0d recovery=%0d kill=%0d",
                scenario,checked,recoveries,kills);
        end
        $display("PASS U-11 all stale-boundary, length, correct-prediction and priority cases");
        $finish;
    end
endmodule
