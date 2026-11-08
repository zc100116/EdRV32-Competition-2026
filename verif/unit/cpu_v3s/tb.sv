// File: cpu_v3s/tb.sv
// Spec: cpu-spec 4.2-4.5; exercise physical lanes and program-order completion.
// Check swapped WAW, pipe-1 branches/JAL, and younger load cancellation.
// Clock domain: clk_sys.
`timescale 1ns/1ps
module tb;
    reg clk_i=0;
    always #5 clk_i=~clk_i;
    reg rst_n_i=0;
    wire ic_req_valid;
    wire [31:0] ic_req_addr;
    reg ic_ready=1;
    integer ic_delay=0;
    reg ic_resp_valid=0;
    reg [63:0] ic_resp_data=0;
    wire ic_kill;
    wire dc_req_valid;
    reg dc_ready=1;
    integer dc_ready_delay=0;
    wire [31:0] dc_req_addr;
    wire dc_req_store;
    wire [1:0] dc_req_size;
    wire dc_commit;
    wire dc_kill;
    wire [31:0] dc_store_data;
    wire dc_fence;
    wire dc_clean;
    wire ic_inv;
    wire [63:0] debug_value;
    reg dc_resp_valid=0;
    reg dc_pending=0;
    reg dc_device=0;
    reg irq_meip=0;
    integer device_commits;
    integer dc_delay=0;
    reg [31:0] memory[0:63];
    integer expected_pc[0:8];
    integer expected_count;
    integer retired;
    integer scenario;
    integer cycles;
    integer lane;
    integer i;
    integer redirects;
    integer swaps;
    integer d_slot1;
    integer stalled_d_slot1;
    integer warm_jalr;
    integer wrong_jalr;
    integer accepted_divisions;
    integer accepted_requests;
    integer ras_ref_ptr;
    integer ras_ref_count;
    integer ras_ref_slot;
    integer ras_ref_lane;
    integer ras_checkpoints;
    reg [31:0] ras_ref_data [0:3];
    reg [31:0] ras_ref_instr;
    reg ras_ref_call;
    reg ras_ref_return;
    integer stalled_jal0;
    integer deferred_jal_swap;
    integer retained_jal_mapping;
    integer traps;
    integer trace_traps;
    reg finished;
    edrv32_cpu_core dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .rst_sys_csr_n_i(rst_n_i),
        .rst_sys_counter_n_i({10{rst_n_i}}),
        .ic_req_valid_o(ic_req_valid),
        .ic_req_addr_o(ic_req_addr),
        .ic_req_ready_i(ic_ready),
        .ic_resp_valid_i(ic_resp_valid),
        .ic_resp_valid_copy_i({8{ic_resp_valid}}),
        .ic_resp_data_i(ic_resp_data),
        .ic_resp_err_i(1'b0),
        .ic_kill_o(ic_kill),
        .ic_inv_o(ic_inv),
        .ic_inv_done_i(1'b1),
        .dc_early_valid_o(),
        .dc_early_addr_o(),
        .dc_early_way_hit_i(2'b00),
        .dc_early_way_data_i(64'b0),
        .dc_req_early_o(),
        .dc_req_valid_o(dc_req_valid),
        .dc_req_addr_o(dc_req_addr),
        .dc_req_store_o(dc_req_store),
        .dc_req_size_o(dc_req_size),
        .dc_req_ready_i(dc_ready),
        .dc_resp_valid_i(dc_resp_valid),
        .dc_resp_way_data_i(64'h55),
        .dc_resp_way_hit_i(2'b01),
        .dc_resp_err_i(1'b0),
        .dc_resp_device_i(dc_device),
        .dc_kill_o(dc_kill),
        .dc_commit_o(dc_commit),
        .dc_store_data_o(dc_store_data),
        .dc_fence_o(dc_fence),
        .dc_clean_all_o(dc_clean),
        .dc_fence_done_i(1'b1),
        .dc_wb_event_i(1'b0),
        .irq_meip_i(irq_meip),
        .irq_msip_i(1'b0),
        .irq_mtip_i(1'b0),
        .mtime_i(64'b0),
        .debug_o(debug_value)
    );
    // cpu-spec 4.4/4.5: an M redirect restores the stack after every older commit.
    always @(posedge clk_i) begin
        if (!rst_n_i) begin
            ras_ref_ptr = 0;
            ras_ref_count = 0;
        end else begin
            for (ras_ref_slot=0;ras_ref_slot<2;ras_ref_slot++) begin
                ras_ref_lane = ras_ref_slot ^ int'(dut.m_swap_r);
                ras_ref_instr = dut.m_record_r[ras_ref_lane][63:32];
                ras_ref_call = (ras_ref_instr[6:0]==7'h6f || ras_ref_instr[6:0]==7'h67) &&
                    (ras_ref_instr[11:7]==1 || ras_ref_instr[11:7]==5);
                ras_ref_return = ras_ref_instr[6:0]==7'h67 && !ras_ref_call &&
                    (ras_ref_instr[19:15]==1 || ras_ref_instr[19:15]==5);
                if (dut.m_commit_w[ras_ref_lane]) begin
                    if (ras_ref_return && ras_ref_count!=0) begin
                        ras_ref_ptr = (ras_ref_ptr+3)%4;
                        ras_ref_count--;
                    end
                    if (ras_ref_call) begin
                        ras_ref_data[ras_ref_ptr] = dut.m_record_r[ras_ref_lane][31:0]+4;
                        ras_ref_ptr = (ras_ref_ptr+1)%4;
                        if (ras_ref_count<4) ras_ref_count++;
                    end
                end
            end
        end
    end
    always @(negedge clk_i) begin
        if (rst_n_i && dut.m_redirect_r) begin
            ras_checkpoints++;
            if (dut.u_frontend.redirect_ras_i[36:34]!=3'(ras_ref_count) ||
                dut.u_frontend.redirect_ras_i[33:32]!=2'(ras_ref_ptr) ||
                (ras_ref_count!=0 && dut.u_frontend.redirect_ras_i[31:0]!=
                ras_ref_data[(ras_ref_ptr+3)%4]))
                $fatal(1,"FAIL committed RAS checkpoint scenario=%0d",scenario);
        end
    end
    // Scenario 18 retains a redirected JAL while an older E load waits for request ready.
    always @(posedge clk_i) begin
        if (!rst_n_i) begin
            dc_ready <= (scenario==18 || scenario==21) ? 0 : 1;
            dc_ready_delay <= 0;
        end else if (scenario==21 && dut.d_capture_w && dut.d_record_w[0][31:0]==8) begin
            // Release the old load exactly as the registered JAL redirect becomes visible.
            dc_ready <= 1;
        end else if (scenario==18 && dut.d_redirect_w && dut.d_record_w[0][31:0]==8) begin
            dc_ready_delay <= 6;
        end else if (dc_ready_delay!=0) begin
            dc_ready_delay <= dc_ready_delay-1;
            if (dc_ready_delay==1)
                dc_ready <= 1;
        end
    end
    // Scenario 15 drains M/W before a faulting branch and a normal younger DIV enter E.
    always @(posedge clk_i) begin
        if (!rst_n_i) begin
            ic_ready <= 1;
            ic_delay <= 0;
        end else if (scenario==15 && ic_req_valid && ic_ready && ic_req_addr==0) begin
            ic_ready <= 0;
            ic_delay <= 8;
        end else if (ic_delay!=0) begin
            ic_delay <= ic_delay-1;
            if (ic_delay==1)
                ic_ready <= 1;
        end
    end
    always @(posedge clk_i) begin
        ic_resp_valid <= 0;
        if (rst_n_i && ic_req_valid && ic_ready && !ic_kill) begin
            ic_resp_valid <= 1;
            ic_resp_data <= {memory[ic_req_addr[7:2]+1],memory[ic_req_addr[7:2]]};
        end
        if (!rst_n_i || ic_kill)
            ic_resp_valid <= 0;
        dc_resp_valid <= 0;
        if (!rst_n_i || dc_kill) begin
            dc_pending <= 0;
            dc_device <= 0;
            dc_delay <= 0;
        end else begin
            if (dc_req_valid && dc_ready) begin
                dc_pending <= 1;
                dc_device <= dc_req_addr == 'h100;
                dc_delay <= dc_req_addr == 'h100 ? 0 : 5;
            end
            if (dc_commit && dc_device) begin
                device_commits++;
                dc_delay <= 5;
            end
            if (dc_resp_valid)
                dc_device <= 0;
            if (dc_pending && dc_delay != 0)
                dc_delay <= dc_delay-1;
            if (dc_pending && dc_delay == 1) begin
                dc_resp_valid <= 1;
                dc_pending <= 0;
            end
        end
        if (rst_n_i && (!finished || (traps!=0 && trace_traps==0))) begin
            // The replicated RAS interface must preserve the original redirect cycle.
            if (dut.frontend_redirect_copy_w !==
                {17{dut.frontend_redirect_w || dut.frontend_d_redirect_w}})
                $fatal(1,"FAIL RAS redirect replicas changed restoration cycle");
            if (dut.d_issue_w == 2 && dut.d_swap_w)
                swaps++;
            if (dut.e_redirect_w) begin
                redirects++;

            end
            if ((scenario==2 || scenario==3) && dut.e_capture_w && !dut.e_redirect1_w)
                $fatal(1,"FAIL branch did not resolve from pipe1");
            if (dut.d_redirect_w && dut.d_redirect_slot_r) begin
                d_slot1++;
                if (!dut.d_available_w)
                    stalled_d_slot1++;
            end
            if (dc_req_valid && (scenario==4 || scenario==11 || scenario==19 || scenario==20))
                $fatal(1,"FAIL canceled/faulted load requested scenario=%0d pc=%h",
                    scenario,dut.e_record_r[0][31:0]);
            if (scenario==10 && dut.m_lane_fault_w != 0 &&
                (dut.u_frontend.update_valid_i || dut.e_redirect_w || dut.d_redirect_w))
                $fatal(1,"FAIL younger prediction resolved past a known M fault");
            if (scenario==12 && dut.e_valid_r[0] &&
                dut.e_record_r[0][38:32]==7'h67 && dut.e_record_r[0][100]) begin
                warm_jalr++;
                if (!dut.e_swap_r || !dut.e_target_match_w || dut.e_redirect_w ||
                    dut.e_record_r[0][132:101]!=32)
                    $fatal(1,"FAIL swapped JALR target comparison");
            end
            if (scenario==13 && dut.e_valid_r[0] &&
                dut.e_record_r[0][38:32]==7'h67 && dut.e_record_r[0][100]) begin
                wrong_jalr++;
                if (!dut.e_swap_r || dut.e_target_match_w || !dut.e_redirect0_w ||
                    dut.e_record_r[0][132:101]!=32 || dut.e_lane_target_w[0]!=48)
                    $fatal(1,"FAIL swapped JALR missed wrong target");
            end
            if (dut.div_start_w)
                accepted_divisions++;
            if (dc_req_valid && dc_ready)
                accepted_requests++;
            if ((scenario==14 || scenario==15) && dut.div_start_w)
                $fatal(1,"FAIL flushed younger DIV started");
            if (scenario==16 && dut.trace_valid_w!=0 &&
                ((dut.trace_valid_w[0] && dut.trace_pc_w[31:0]==12) ||
                (dut.trace_valid_w[1] && dut.trace_pc_w[63:32]==12)))
                $fatal(1,"FAIL flushed younger MUL retired");
            if ((scenario==14 || scenario==16) && dut.e_valid_r[1] && !dut.e_resolved_r &&
                dut.e_record_r[1][31:0]==8 && (!dut.e_redirect1_w || !dut.e_resolve_w))
                $fatal(1,"FAIL older branch waited for younger multiply/divide");
            if (scenario==21 && dut.d_redirect_r && !dut.d_redirect_issued_r &&
                dut.d_record_w[0][31:0]==8 && dut.d_record_w[1][31:0]==12) begin
                retained_jal_mapping++;
                if (dut.d_swap_w)
                    $fatal(1,"FAIL retained slot0 JAL swapped with unissued load");
            end
            if (scenario==18 && dut.d_redirect_w && dut.d_record_w[0][31:0]==8) begin
                if (dut.d_issue_w!=0)
                    $fatal(1,"FAIL JAL0 redirect did not overlap backend request stall");
                stalled_jal0++;
            end
            if (scenario==18 && dut.d_issue_w==2 && dut.d_record_w[0][31:0]==8) begin
                if (!dut.d_swap_w || dut.d_record_w[1][31:0]!=16)
                    $fatal(1,"FAIL retained JAL0 did not swap with its target load");
                deferred_jal_swap++;
            end
            if ((scenario==19 || scenario==20) && dut.d_issue_w!=0 && dut.d_record_w[0][31:0]==0 &&
                dut.d_issue_w!=(scenario==19 ? 1 : 2))
                $fatal(1,"FAIL illegal opcode family pairing");
            if (dut.trace_trap_w) begin
                trace_traps++;
                if ((scenario==4 || scenario==10) &&
                    (dut.trace_valid_w!=1 || dut.trace_pc_w[31:0]!=0 ||
                    dut.trace_cause_w!=(scenario==4 ? 4 : 0)))
                    $fatal(1,"FAIL younger fault traced before older retirement");
            end
            if (dut.m_trap_w && traps == 0) begin
                traps++;
                if (scenario == 4) begin
                    if (dut.m_trap_pc_w != 4 || dut.m_trap_cause_w != 4 ||
                        dut.m_trap_value_w != 2 ||
                        dut.m_commit_w != 2'b10)
                        $fatal(1,"FAIL younger load fault pc=%h cause=%h commit=%b",
                            dut.m_trap_pc_w,dut.m_trap_cause_w,dut.m_commit_w);
                end else if (scenario == 5) begin
                    if (dut.m_trap_pc_w != 0 || dut.m_trap_cause_w != 0 ||
                        dut.m_trap_value_w != 2 ||
                        dut.m_commit_w != 0 || accepted_requests != 1 ||
                        !dc_kill || dc_commit)
                        $fatal(1,"FAIL older branch fault");
                    finished=1;
                end else if (scenario == 23) begin
                    if (dut.m_trap_pc_w!=8 || dut.m_trap_cause_w!=4 ||
                        dut.m_trap_value_w!=2 || dut.m_commit_w!=0)
                        $fatal(1,"FAIL target load trap after call");
                    finished=1;
                end else if (scenario == 10) begin
                    if (dut.m_trap_pc_w != 4 || dut.m_trap_cause_w != 0 ||
                        dut.m_trap_value_w != 6 ||
                        dut.m_commit_w != 2'b01 || !dc_resp_valid || dc_kill || !dc_commit)
                        $fatal(1,"FAIL younger branch fault bypassed older load completion");
                end else if (scenario == 11) begin
                    if (dut.m_trap_pc_w != 0 || dut.m_trap_cause_w != 4 ||
                        dut.m_trap_value_w != 2 ||
                        dut.m_commit_w != 0)
                        $fatal(1,"FAIL oldest simultaneous fault");
                    finished=1;
                end else if (scenario==15) begin
                    if (dut.m_trap_pc_w!=8 || dut.m_trap_cause_w!=0 ||
                        dut.m_trap_value_w!=10 || dut.m_commit_w!=0 || dut.div_busy_w)
                        $fatal(1,"FAIL older branch fault started younger DIV");
                    finished=1;
                end else if ((scenario==19 || scenario==20)) begin
                    if (dut.m_trap_pc_w!=0 || dut.m_trap_cause_w!=2 ||
                        dut.m_trap_value_w!=memory[0] || dut.m_commit_w!=0)
                        $fatal(1,"FAIL illegal opcode family exception");
                    finished=1;
                end else if (scenario == 7 || scenario == 8) begin
                    if (dut.m_trap_cause_w != 32'h8000000b ||
                        dut.m_trap_pc_w != (scenario == 7 ? 16 : 24) ||
                        dut.m_commit_w != 0 || dut.m_trap_value_w != 0 || dc_commit ||
                        (scenario == 7 && !dc_kill))
                        $fatal(1,"FAIL device interrupt scenario=%0d pc=%h cause=%h",
                            scenario,dut.m_trap_pc_w,dut.m_trap_cause_w);
                    finished=1;
                end else
                    $fatal(1,"FAIL unexpected trap scenario=%0d",scenario);
            end
            for (lane=0;lane<2;lane++) begin
                if ((scenario==7 || scenario==8 || scenario==15 || !finished) &&
                    dut.trace_valid_w[lane]) begin
                    if (retired >= expected_count ||
                        dut.trace_pc_w[lane*32+:32] != 32'(expected_pc[retired]))
                        $fatal(1,"FAIL order scenario=%0d retired=%0d expected=%h actual=%h",
                            scenario,retired,expected_pc[retired],dut.trace_pc_w[lane*32+:32]);
                    if (scenario == 1 && dut.trace_rd_w[lane*5+:5] == 6 &&
                        dut.trace_rd_data_w[lane*32+:32] != 'h56)
                        $fatal(1,"FAIL swapped WAW forwarding");
                    if (scenario == 1 && dut.trace_rd_w[lane*5+:5] == 7 &&
                        dut.trace_rd_data_w[lane*32+:32] != 'h57)
                        $fatal(1,"FAIL swapped WAW register-file value");
                    if (scenario == 10 && dut.trace_rd_w[lane*5+:5] == 5 &&
                        dut.trace_rd_data_w[lane*32+:32] != 'h55)
                        $fatal(1,"FAIL older load value at younger branch trap");
                    if ((scenario==12 || scenario==13) && dut.trace_pc_w[lane*32+:32]==12 &&
                        (dut.trace_rd_w[lane*5+:5]!=1 ||
                        dut.trace_rd_data_w[lane*32+:32]!=16))
                        $fatal(1,"FAIL swapped JALR link");
                    if ((scenario==17 || scenario==22) &&
                        dut.trace_pc_w[lane*32+:32]==12 &&
                        (dut.trace_rd_w[lane*5+:5]!=5 || dut.trace_rd_data_w[lane*32+:32]!=33))
                        $fatal(1,"FAIL swapped DIV result");
                    if ((scenario==17 || scenario==22) &&
                        dut.trace_pc_w[lane*32+:32]==16 &&
                        dut.trace_rd_data_w[lane*32+:32]!=34)
                        $fatal(1,"FAIL swapped DIV WAW forwarding");
                    if (scenario==18 && dut.trace_pc_w[lane*32+:32]==20 &&
                        dut.trace_rd_data_w[lane*32+:32]!='h56)
                        $fatal(1,"FAIL retained JAL target load result");
                    if (scenario == 6 && dut.trace_rd_w[lane*5+:5] == 1 &&
                        dut.trace_rd_data_w[lane*32+:32] != 8)
                        $fatal(1,"FAIL pipe1 JAL link");
                    retired++;
                    if (retired == expected_count && scenario!=7 && scenario!=8 &&
                        scenario!=15 && scenario!=23)
                        finished=1;
                end
            end
        end
    end
    initial begin
        finished=1;
        for (scenario=1;scenario<=23;scenario++) begin
            rst_n_i=0;
            repeat(3) @(negedge clk_i);
            for (i=0;i<64;i++) memory[i]=32'h00000013;
            retired=0;redirects=0;swaps=0;d_slot1=0;traps=0;trace_traps=0;
            device_commits=0;irq_meip=0;stalled_d_slot1=0;
            warm_jalr=0;wrong_jalr=0;accepted_divisions=0;
            accepted_requests=0;ras_checkpoints=0;
            stalled_jal0=0;deferred_jal_swap=0;retained_jal_mapping=0;
            expected_count=3;
            expected_pc[0]=0;expected_pc[1]=4;expected_pc[2]=8;
            case (scenario)
                1: begin
                    memory[0]=32'h00700293; // addi x5,x0,7
                    memory[1]=32'h00002283; // lw x5,0(x0)
                    memory[2]=32'h00128313; // addi x6,x5,1
                    memory[4]=32'h00228393; // addi x7,x5,2 after writeback
                    expected_count=5;expected_pc[3]=12;expected_pc[4]=16;
                end
                2: begin
                    memory[0]=32'h00300413;
                    memory[1]=32'h00000663; // beq x0,x0,+12
                    memory[4]=32'h00400493;
                    expected_pc[2]=16;
                end
                3: begin
                    memory[0]=32'h00000663; // beq x0,x0,+12
                    memory[1]=32'h00002283;
                    memory[3]=32'h00400493;
                    expected_count=2;expected_pc[1]=12;
                end
                4: begin
                    memory[0]=32'h00700293;
                    memory[1]=32'h00202303; // lw x6,2(x0)
                    expected_count=1;
                end
                5: begin
                    memory[0]=32'h00000163; // beq x0,x0,+2
                    memory[1]=32'h00002283;
                    expected_count=0;
                end
                6: begin
                    memory[0]=32'h00300413;
                    memory[1]=32'h00c000ef; // jal x1,+12
                    memory[4]=32'h00400493;
                    expected_pc[2]=16;
                end
                7,8: begin
                    memory[0]=32'h00800513; // addi x10,x0,8
                    memory[1]=32'h30052073; // csrrs x0,mstatus,x10
                    memory[2]=32'h80000593; // addi x11,x0,-2048
                    memory[3]=32'h3045a073; // csrrs x0,mie,x11
                    memory[4]=32'h00700293; // older ALU in pipe1
                    memory[5]=32'h10002303; // younger device load in pipe0
                    expected_pc[3]=12;expected_pc[4]=16;expected_pc[5]=20;
                    expected_count=scenario==7?4:6;
                end
                9: begin
                    memory[0]=32'h00002283; // load stalls the group behind it
                    memory[1]=32'h00128313; // dependent older ALU
                    memory[2]=32'h008000ef; // cold slot1 JAL while M waits
                    memory[4]=32'h00700393;
                    expected_count=4;expected_pc[3]=16;
                end
                10: begin
                    memory[0]=32'h00002283; // older delayed load
                    memory[1]=32'h00000163; // younger misaligned taken branch
                    memory[2]=32'h00000863; // younger E branch must not train
                    expected_count=1;
                end
                11: begin
                    memory[0]=32'h00202283; // older misaligned load
                    memory[1]=32'h00000163; // younger misaligned taken branch
                    expected_count=0;
                end
                12,13: begin
                    memory[0]=32'h02000493; // x9 = JALR target
                    memory[1]=32'h00000513;
                    memory[2]=scenario==12 ? 32'h00700593 : 32'hff000593;
                    memory[3]=32'h000480e7; // jalr x1,0(x9), swapped into pipe0
                    memory[8]=scenario==12 ? 32'h00150513 : 32'h03000493;
                    memory[9]=32'hfe5ff06f; // jal x0,-28, revisit warm JALR
                    memory[12]=32'h00900613;
                    expected_count=scenario==12 ? 8 : 9;
                    expected_pc[8]=48;
                    expected_pc[3]=12;expected_pc[4]=32;expected_pc[5]=36;
                    expected_pc[6]=8;expected_pc[7]=12;
                end
                14,15,16: begin
                    memory[0]=32'h06400493; // x9 = 100
                    memory[1]=32'h00300513; // x10 = 3
                    memory[2]=scenario==15 ? 32'h00000163 : 32'h00000663;
                    memory[3]=scenario==16 ? 32'h02a482b3 : 32'h02a4c2b3;
                    memory[5]=32'h00700313;
                    expected_count=scenario==15 ? 2 : 4;
                    expected_pc[3]=20;
                end
                17: begin
                    memory[0]=32'h06400493;
                    memory[1]=32'h00300513;
                    memory[2]=32'h00700293; // older x5 = 7 in pipe1
                    memory[3]=32'h02a4c2b3; // younger x5 = 100/3 in pipe0
                    memory[4]=32'h00128313;
                    expected_count=5;expected_pc[3]=12;expected_pc[4]=16;
                end
                18: begin
                    memory[0]=32'h0040006f; // enter at upper word of next fetch
                    memory[1]=32'h00002283; // standalone older load, request held
                    memory[2]=32'h0080006f; // cold JAL0 redirects while load is in E
                    memory[4]=32'h00002303; // corrected target only executes in pipe0
                    memory[5]=32'h00130393;
                    expected_count=5;expected_pc[3]=16;expected_pc[4]=20;
                end
                19,20: begin
                    memory[0]=scenario==19 ? 32'hffffffff : 32'h04001293;
                    memory[1]=32'h00002303;
                    expected_count=0;
                end
                21: begin
                    memory[0]=32'h00002283; // delayed older load holds the cold JAL in D
                    memory[1]=32'h00700413;
                    memory[2]=32'h008000ef; // retained head JAL x1,+8
                    memory[3]=32'h00002303; // adjacent load can execute only on pipe0
                    memory[4]=32'h00100393;
                    expected_count=4;expected_pc[3]=16;
                end
                22: begin
                    memory[0]=32'h06400493;
                    memory[1]=32'h00300513;
                    memory[2]=32'h00001663; // correct not-taken branch, older in pipe1
                    memory[3]=32'h02a4c2b3; // younger DIV waits for registered resolution
                    memory[4]=32'h00128313;
                    expected_count=5;expected_pc[3]=12;expected_pc[4]=16;
                end
                23: begin
                    memory[0]=32'h008000ef; // call, then trap in its target
                    memory[2]=32'h00202303;
                    expected_count=1;
                end
                default: $fatal(1,"FAIL scenario");
            endcase
            finished=0;rst_n_i=1;cycles=0;
            while (!finished && cycles<150) begin
                @(negedge clk_i);cycles++;
                if (scenario == 7 && dut.m_valid_r[0] && dut.m_record_r[0][31:0] == 20)
                    irq_meip=1;
                if (scenario == 8 && device_commits != 0)
                    irq_meip=1;
            end
            // W2 trace can follow the M trap decision by two clocks.
            if (traps!=0 && trace_traps==0) repeat(3) @(negedge clk_i);
            if (!finished || ((scenario == 1 || scenario == 3 ||
                scenario == 4 || scenario == 5 || (scenario>=14 && scenario<=20 && scenario!=19)) && swaps == 0) ||
                ((scenario == 2 || scenario == 3 || scenario==14 || scenario==16) &&
                redirects != 1) ||
                (scenario == 6 && d_slot1 != 1) ||
                ((scenario == 4 || scenario == 5 || scenario==7 || scenario==8 ||
                scenario==10 || scenario==11 || scenario==15 || (scenario==19 || scenario==20)) && (traps != 1 || trace_traps != 1)) ||
                ((scenario==7 || scenario==8) && (device_commits != (scenario == 8 ? 1 : 0) ||
                retired != expected_count)) ||
                (scenario==9 && (stalled_d_slot1 != 1 || d_slot1 != 1 || redirects != 0)) ||
                (scenario==12 && warm_jalr==0) || (scenario==13 && wrong_jalr==0) ||
                (scenario==15 && retired!=2) ||
                ((scenario==17 || scenario==22) && accepted_divisions!=1) ||
                (scenario==18 && (stalled_jal0!=1 || deferred_jal_swap!=1)) ||
                (scenario==21 && retained_jal_mapping!=1) ||
                (scenario==23 && (traps!=1 || trace_traps!=1 || ras_checkpoints!=1)))
                $fatal(1,"FAIL coverage scenario=%0d retired=%0d swap=%0d E=%0d D1=%0d trap=%0d",
                    scenario,retired,swaps,redirects,d_slot1,traps);
            $display("PASS V3s scenario=%0d cycles=%0d",scenario,cycles);
        end
        $display("PASS cpu_v3s");
        $finish;
    end
endmodule
