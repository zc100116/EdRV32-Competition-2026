// File: cpu_redirect_wait/tb.sv
// Spec: cpu-spec v0.15 4.4, 4.5; C-R6 P3/P4.
// Description: Hold an older load in M while E branches or D JALs redirect once.
// Check retention, predictor/RAS updates, and simultaneous or subsequent M faults.
// Clock domain: clk_sys.
`timescale 1ns/1ps
module tb;
    reg clk_i=0;
    always #5 clk_i=~clk_i;
    reg rst_n_i=0;
    wire ic_req_valid;
    wire [31:0] ic_req_addr;
    reg ic_resp_valid=0;
    reg [63:0] ic_resp_data=0;
    wire ic_kill;
    wire dc_req_valid;
    wire dc_kill;
    wire dc_resp_valid;
    wire dc_resp_err;
    reg pending=0;
    integer delay_left=0;
    integer scenario=0;
    integer cycles=0;
    integer e_redirects=0;
    integer d_redirects=0;
    integer updates=0;
    integer early=0;
    integer scenario_done=0;
    integer i;
    reg [31:0] program_words[0:63];
    reg held_e=0;
    reg held_d=0;
    reg [178:0] saved_e;
    reg [178:0] saved_d;
    reg [178:0] saved_d1;
    wire d_case=scenario==1 || scenario==4;
    wire error_case=scenario>=2;
    assign dc_resp_valid=pending && delay_left==0;
    assign dc_resp_err=dc_resp_valid && error_case;
    wire [43:0] t4_predecode_w;
    edrv32_cpu_predecode u_t4_predecode0 (
        .instr_i(ic_resp_data[0 +: 32]),
        .predecode_o(t4_predecode_w[0 +: 22])
    );
    edrv32_cpu_predecode u_t4_predecode1 (
        .instr_i(ic_resp_data[32 +: 32]),
        .predecode_o(t4_predecode_w[22 +: 22])
    );
    edrv32_cpu_core dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .rst_sys_csr_n_i(rst_n_i),
        .rst_sys_counter_n_i({10{rst_n_i}}),
        .ic_req_valid_o(ic_req_valid),
        .ic_req_addr_o(ic_req_addr),
        .ic_req_ready_i(1'b1),
        .ic_resp_valid_i(ic_resp_valid),
        .ic_resp_valid_copy_i({8{ic_resp_valid}}),
        .ic_resp_data_i(ic_resp_data),
        .ic_resp_predecode_i(t4_predecode_w),
        .ic_resp_err_i(1'b0),
        .ic_kill_o(ic_kill),
        .ic_inv_o(),
        .ic_inv_done_i(1'b0),
        .dc_early_valid_o(),
        .dc_early_addr_o(),
        .dc_early_way_hit_i(2'b00),
        .dc_early_way_data_i(64'b0),
        .dc_req_early_o(),
        .dc_req_valid_o(dc_req_valid),
        .dc_req_addr_o(),
        .dc_req_store_o(),
        .dc_req_size_o(),
        .dc_req_ready_i(!pending || dc_resp_valid),
        .dc_resp_valid_i(dc_resp_valid),
        .dc_resp_way_data_i(64'd0),
        .dc_resp_way_hit_i(2'b01),
        .dc_resp_err_i(dc_resp_err),
        .dc_resp_device_i(1'b0),
        .dc_kill_o(dc_kill),
        .dc_commit_o(),
        .dc_store_data_o(),
        .dc_fence_o(),
        .dc_clean_all_o(),
        .dc_fence_done_i(1'b0),
        .dc_wb_event_i(1'b0),
        .irq_meip_i(1'b0),
        .irq_msip_i(1'b0),
        .irq_mtip_i(1'b0),
        .mtime_i(64'd0),
        .debug_o()
    );
    always @(posedge clk_i) begin
        if (!rst_n_i) begin
            ic_resp_valid<=0;
            pending<=0;
            delay_left<=0;
        end else begin
            ic_resp_valid<=ic_req_valid && !ic_kill;
            if (ic_req_valid)
                ic_resp_data<={program_words[ic_req_addr[7:2]+1],
                    program_words[ic_req_addr[7:2]]};
            if (dc_resp_valid || dc_kill)
                pending<=0;
            if (pending && delay_left>0)
                delay_left<=delay_left-1;
            if (dc_req_valid && (!pending || dc_resp_valid)) begin
                pending<=1;
                delay_left<=scenario==3 ? 0 : 12;
            end
            cycles=cycles+1;
            if (dut.m_redirect_w && (dut.e_capture_w || dut.d_capture_w))
                $fatal(1,"FAIL M priority scenario=%0d time=%t",scenario,$time);
            if (dut.e_redirect_w && dut.frontend_d_redirect_w)
                $fatal(1,"FAIL E priority time=%t",$time);
            if (held_e && !dut.m_redirect_w) begin
                if (!dut.e_valid_r[0] || dut.e_record_r[0]!==saved_e)
                    $fatal(1,"FAIL E lost stalled instruction time=%t",$time);
                if (dut.e_valid_r[1])
                    $fatal(1,"FAIL E slot 1 survived redirect time=%t",$time);
            end
            if (held_d && !dut.backend_redirect_w &&
                (dut.d_count_w!=2 || dut.d_record_w[0]!==saved_d ||
                 dut.d_record_w[1]!==saved_d1))
                $fatal(1,"FAIL D lost stalled JAL time=%t",$time);
            if (dut.e_redirect_w) begin
                e_redirects=e_redirects+1;
                if (d_case || dut.e_record_r[0][31:0]!=12 || !dut.m_wait_w)
                    $fatal(1,"FAIL unexpected E redirect scenario=%0d time=%t",scenario,$time);
                saved_e=dut.e_record_r[0];
                held_e=1;
                early=early+1;
            end
            if (dut.d_redirect_w) begin
                d_redirects=d_redirects+1;
                if (!d_case || dut.d_record_w[0][31:0]!=12 ||
                    dut.d_record_w[1][31:0]!=16 || !dut.d_redirect_slot_r || dut.d_issue_w!=0)
                    $fatal(1,"FAIL unexpected D redirect scenario=%0d PC=%h issue=%0d time=%t",
                        scenario,dut.d_record_w[0][31:0],dut.d_issue_w,$time);
                saved_d=dut.d_record_w[0];
                saved_d1=dut.d_record_w[1];
                held_d=1;
                early=early+1;
            end
            if (dut.u_frontend.update_valid_i)
                updates=updates+1;
            if (dut.e_advance_w || dut.m_redirect_w)
                held_e=0;
            if (dut.d_issue_w!=0 || dut.backend_redirect_w)
                held_d=0;
            if (dut.trace_valid_w!=0) begin
                for (integer lane=0;lane<2;lane=lane+1) begin
                    if (dut.trace_valid_w[lane] &&
                        dut.trace_instr_w[lane*32+:32]==32'h06300193)
                        $fatal(1,"FAIL retired wrong path time=%t",$time);
                    if (dut.trace_valid_w[lane] && dut.trace_pc_w[lane*32+:32]==28) begin
                        if (error_case || dut.trace_rd_data_w[lane*32+:32]!=7)
                            $fatal(1,"FAIL target retirement scenario=%0d",scenario);
                        scenario_done=1;
                    end
                end
            end
            if (dut.m_trap_w) begin
                if (!error_case || dut.m_trap_pc_w!=4 || dut.m_trap_cause_w!=5 ||
                    dut.m_redirect_pc_w!=0)
                    $fatal(1,"FAIL M fault scenario=%0d time=%t",scenario,$time);
                scenario_done=1;
            end
            if (cycles>150)
                $fatal(1,"FAIL timeout scenario=%0d",scenario);
        end
    end
    initial begin
        for (scenario=0;scenario<5;scenario=scenario+1) begin
            rst_n_i=0;
            repeat(3) @(negedge clk_i);
            for (i=0;i<64;i=i+1) program_words[i]=32'h00000013;
            // E-produced base excludes early addressing, retaining the intended
            // ordinary-load wait window under cpu-spec 4.10.
            program_words[0]=32'h00000093; // addi x1,x0,0
            program_words[1]=32'h0000a103; // lw x2,0(x1)
            program_words[2]=32'h00000013;
            program_words[3]=d_case ? 32'h02010033 : 32'h00000863;
            program_words[4]=d_case ? 32'h00c000ef : 32'h06300193;
            program_words[5]=32'h06300193;
            program_words[6]=32'h06300193;
            program_words[7]=32'h00700213; // addi x4,x0,7
            cycles=0;e_redirects=0;d_redirects=0;updates=0;early=0;
            held_e=0;held_d=0;scenario_done=0;
            rst_n_i=1;
            wait(scenario_done!=0);
            @(negedge clk_i);
            if (scenario==3) begin
                if (e_redirects!=0 || d_redirects!=0 || updates!=0)
                    $fatal(1,"FAIL simultaneous M fault updated younger instruction");
            end else begin
                if (early!=1 || e_redirects!=(d_case?0:1) || d_redirects!=(d_case?1:0))
                    $fatal(1,"FAIL redirect count scenario=%0d E=%0d D=%0d early=%0d",
                        scenario,e_redirects,d_redirects,early);
                if (!error_case && updates!=1)
                    $fatal(1,"FAIL training count scenario=%0d count=%0d",scenario,updates);
                if (d_case && !error_case &&
                    (dut.u_frontend.u_predictor.ras_count_r!=1 ||
                    dut.u_frontend.u_predictor.ras_data_r[31:0]!=20))
                    $fatal(1,"FAIL D RAS restored more than once");
            end
            $display("PASS redirect_wait scenario=%0d E=%0d D=%0d updates=%0d",
                scenario,e_redirects,d_redirects,updates);
        end
        $display("PASS cpu_redirect_wait");
        $finish;
    end
endmodule
