// File: tb.sv
// Spec: cpu-v2-testplan CV01/CV06/CV15; cpu-v2-spec 3.9, 3.11.
// Description: Real core with shared AXI64 memory, fixed latency and architectural tohost.
// Clock domain: clk_sys.
// The observer updates ordered software state at each accepted edge.
/* verilator lint_off BLKSEQ */
/* verilator lint_off SYNCASYNCNET */
module tb;
    parameter ISSUE_WIDTH = 2;
    import edrv32_axi64_memory_pkg::*;
    bit clk;
    initial clk = 0;
    bit rst_n = 0;
    always #5 clk = !clk;
    edrv32_axi64_if ic();
    edrv32_axi64_if dc();
    edrv32_axi64_memory u_ic (.clk_i(clk), .rst_n_i(rst_n), .bus(ic));
    edrv32_axi64_memory u_dc (.clk_i(clk), .rst_n_i(rst_n), .bus(dc));
    wire [63:0] debug;
    wire cache_irq;
    wire apb_ready;
    wire [31:0] apb_data;
    wire apb_error;
    edrv32_cpu2_top #(.ISSUE_WIDTH(ISSUE_WIDTH), .FPU_FORMAT("NONE")) dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .ic_axi_arid_o(ic.arid),
        .ic_axi_araddr_o(ic.araddr),
        .ic_axi_arlen_o(ic.arlen),
        .ic_axi_arsize_o(ic.arsize),
        .ic_axi_arburst_o(ic.arburst),
        .ic_axi_arvalid_o(ic.arvalid),
        .ic_axi_arready_i(ic.arready),
        .ic_axi_rid_i(ic.rid),
        .ic_axi_rdata_i(ic.rdata),
        .ic_axi_rresp_i(ic.rresp),
        .ic_axi_rlast_i(ic.rlast),
        .ic_axi_rvalid_i(ic.rvalid),
        .ic_axi_rready_o(ic.rready),
        .dc_axi_arid_o(dc.arid),
        .dc_axi_araddr_o(dc.araddr),
        .dc_axi_arlen_o(dc.arlen),
        .dc_axi_arsize_o(dc.arsize),
        .dc_axi_arburst_o(dc.arburst),
        .dc_axi_arvalid_o(dc.arvalid),
        .dc_axi_arready_i(dc.arready),
        .dc_axi_rid_i(dc.rid),
        .dc_axi_rdata_i(dc.rdata),
        .dc_axi_rresp_i(dc.rresp),
        .dc_axi_rlast_i(dc.rlast),
        .dc_axi_rvalid_i(dc.rvalid),
        .dc_axi_rready_o(dc.rready),
        .dc_axi_awid_o(dc.awid),
        .dc_axi_awaddr_o(dc.awaddr),
        .dc_axi_awlen_o(dc.awlen),
        .dc_axi_awsize_o(dc.awsize),
        .dc_axi_awburst_o(dc.awburst),
        .dc_axi_awvalid_o(dc.awvalid),
        .dc_axi_awready_i(dc.awready),
        .dc_axi_wdata_o(dc.wdata),
        .dc_axi_wstrb_o(dc.wstrb),
        .dc_axi_wlast_o(dc.wlast),
        .dc_axi_wvalid_o(dc.wvalid),
        .dc_axi_wready_i(dc.wready),
        .dc_axi_bid_i(dc.bid),
        .dc_axi_bresp_i(dc.bresp),
        .dc_axi_bvalid_i(dc.bvalid),
        .dc_axi_bready_o(dc.bready),
        .apb_paddr_i('0),
        .apb_psel_i('0),
        .apb_penable_i('0),
        .apb_pwrite_i('0),
        .apb_pwdata_i('0),
        .apb_pstrb_i('0),
        .apb_pready_o(apb_ready),
        .apb_prdata_o(apb_data),
        .apb_pslverr_o(apb_error),
        .cache_irq_o(cache_irq),
        .irq_meip_i('0),
        .irq_msip_i('0),
        .irq_mtip_i('0),
        .mtime_i('0),
        .debug_o(debug)
    );
    string mem_hex;
    bit [31:0] tohost_addr;
    longint unsigned cycles;
    longint unsigned retired;
    longint unsigned cycle_limit;
    bit perf_enabled;
    bit [31:0] perf_begin;
    bit [31:0] perf_end;
    longint unsigned perf_start;
    bit perf_started;
    longint unsigned perf_instructions;
    longint unsigned perf_hpm [0:15];
    longint unsigned perf_full;
    longint unsigned perf_ib_empty;
    longint unsigned perf_lsu_busy;
    longint unsigned perf_store_head;
    longint unsigned perf_early;
    longint unsigned perf_early_hit;
    longint unsigned perf_f2;
    longint unsigned perf_bank_wait [0:5];
    longint unsigned perf_late_alu_capture_block;
    longint unsigned perf_late_load_capture_block;
    longint unsigned perf_early_port_block;
    longint unsigned perf_early_word_block;
    longint unsigned perf_early_expired;
    longint unsigned perf_pair_load_wait;
    longint unsigned perf_pair_alu_wait;
    longint unsigned perf_pair_mul_wait;
    longint unsigned perf_pair_expired_load;
    longint unsigned perf_pair_types [0:35];
    bit branch_pending [0:1];
    bit [(ISSUE_WIDTH==2?4:3)-1:0] branch_tag [0:1];
    bit [(ISSUE_WIDTH==2?4:3)-1:0] branch_source1 [0:1];
    bit [(ISSUE_WIDTH==2?4:3)-1:0] branch_source2 [0:1];
    bit [31:0] branch_pc [0:1];
    bit branch_wait1 [0:1];
    bit branch_wait2 [0:1];
    longint unsigned perf_branch_early_available;
    longint unsigned perf_branch_early_delayed;
    longint unsigned perf_branch_early_port;
    longint unsigned perf_miss_store_waits;
    longint unsigned perf_miss_store_cycles;
    bit perf_miss_store_active;
    bit [(ISSUE_WIDTH==2?4:3)-1:0] perf_miss_store_tag;
    longint unsigned perf_ic_miss_cycles;
    longint unsigned perf_dc_miss_cycles;
    bit store_head_active;
    bit [(ISSUE_WIDTH==2?4:3)-1:0] store_head_tag;
    longint unsigned store_head_run;
    longint unsigned store_head_min;
    longint unsigned perf_full_retiring;
    longint unsigned perf_full_store;
    longint unsigned perf_full_load;
    longint unsigned perf_pair_credit;
    longint unsigned perf_pair_operand;
    longint unsigned perf_pair_channel;
    longint unsigned recovery_count [0:2];
    longint unsigned recovery_cycles [0:2];
    bit recovery_valid [0:2];
    bit [31:0] recovery_target [0:2];
    longint unsigned recovery_start [0:2];
    longint unsigned perf_issue [0:2];
    longint unsigned perf_retire [0:2];
    longint unsigned allocated_at [0:(ISSUE_WIDTH==2?16:8)-1];
    integer record_kind [0:(ISSUE_WIDTH==2?16:8)-1];
    longint unsigned kind_count [0:5];
    longint unsigned kind_lifetime [0:5];
    longint unsigned dispatch_count [0:5];
    longint unsigned dispatch_delay [0:5];
    integer trace_fd;
    string trace_path;
    function automatic bit alu_blocked(input bit [(ISSUE_WIDTH==2?4:3)-1:0] tag);
        return (dut.alu0_complete_valid_w && !dut.alu0_complete_ready_w &&
                dut.alu0_complete_tag_w==tag) ||
            (dut.alu1_complete_valid_w && !dut.alu1_complete_ready_w && dut.alu1_complete_tag_w==tag);
    endfunction
    function automatic bit load_blocked(input bit [(ISSUE_WIDTH==2?4:3)-1:0] tag);
        return dut.lsu_complete_valid_w && !dut.lsu_complete_ready_w &&
            !dut.lsu_complete_device_w && dut.lsu_complete_tag_w==tag;
    endfunction
    function automatic bit source_captured(input bit [(ISSUE_WIDTH==2?4:3)-1:0] tag);
        source_captured =
            (dut.early_resp_valid_w && dut.early_resp_hit_w && dut.early_resp_tag_w==tag) ||
            (dut.alu0_complete_valid_w && dut.alu0_complete_ready_w && dut.alu0_complete_tag_w==tag) ||
            (dut.alu1_complete_valid_w && dut.alu1_complete_ready_w && dut.alu1_complete_tag_w==tag) ||
            (dut.branch_complete_valid_w && dut.branch_complete_ready_w && dut.branch_complete_tag_w==tag) ||
            (dut.mul_complete_valid_w && dut.mul_complete_ready_w && dut.mul_complete_tag_w==tag) ||
            (dut.div_complete_valid_w && dut.div_complete_ready_w && dut.div_complete_tag_w==tag) ||
            (dut.lsu_complete_valid_w && dut.lsu_complete_ready_w &&
                !dut.lsu_complete_device_w && dut.lsu_complete_tag_w==tag) ||
            (dut.csr_complete_valid_w && dut.csr_complete_ready_w && dut.csr_complete_tag_w==tag) ||
            (dut.wb0_valid_w && dut.wb0_tag_w==tag) ||
            (dut.wb1_valid_w && dut.wb1_tag_w==tag);
    endfunction
    initial begin
        if (!$value$plusargs("MEM_HEX=%s", mem_hex)) $fatal(1, "FAIL missing MEM_HEX");
        if (!$value$plusargs("TOHOST_ADDR=%h", tohost_addr) && !$test$plusargs("PERF_ONLY"))
            $fatal(1, "FAIL missing TOHOST_ADDR");
        if (!$value$plusargs("MAX_CYCLES=%d", cycle_limit)) cycle_limit = 1000000;
        if ($value$plusargs("TRACE=%s", trace_path)) trace_fd = $fopen(trace_path, "w");
        perf_enabled = $value$plusargs("PERF_BEGIN=%h", perf_begin);
        if (perf_enabled && !$value$plusargs("PERF_END=%h", perf_end))
            $fatal(1, "FAIL missing PERF_END");
        random_stalls = 0;
        delay_max = 0;
        $readmemh(mem_hex, memory);
        repeat (5) @(negedge clk);
        rst_n = 1;
    end
    wire perf_begin_event_w = perf_enabled &&
        ((dut.trace_valid_w[0] && dut.trace_pc_w[31:0]==perf_begin) ||
        (dut.trace_valid_w[1] && dut.trace_pc_w[63:32]==perf_begin));
    wire perf_end_event_w = perf_enabled &&
        ((dut.trace_valid_w[0] && dut.trace_pc_w[31:0]==perf_end) ||
        (dut.trace_valid_w[1] && dut.trace_pc_w[63:32]==perf_end));
    always @(posedge clk) begin
        if (!rst_n) begin
            cycles <= 0;
            retired = 0;
            perf_started = 0;
            perf_start = 0;
            perf_instructions = 0;
            perf_full = 0;
            perf_ib_empty = 0;
            perf_lsu_busy = 0;
            perf_store_head = 0;
            perf_early = 0;
            perf_early_hit = 0;
            perf_f2 = 0;
            perf_ic_miss_cycles=0;perf_dc_miss_cycles=0;
            store_head_active=0;store_head_run=0;store_head_min='1;
            for(int k=0;k<6;k++)perf_bank_wait[k]=0;
            perf_late_alu_capture_block=0;perf_late_load_capture_block=0;
            perf_early_port_block=0;perf_early_word_block=0;perf_early_expired=0;
            perf_pair_load_wait=0;perf_pair_alu_wait=0;perf_pair_mul_wait=0;
            perf_pair_expired_load=0;
            perf_branch_early_available=0;perf_branch_early_delayed=0;perf_branch_early_port=0;
            for(int k=0;k<36;k++)perf_pair_types[k]=0;
            for(int k=0;k<2;k++)branch_pending[k]=0;
            perf_miss_store_waits=0;perf_miss_store_cycles=0;perf_miss_store_active=0;
            perf_full_retiring=0;perf_full_store=0;perf_full_load=0;
            perf_pair_credit=0;perf_pair_operand=0;perf_pair_channel=0;
            for(int k=0;k<3;k++) begin
                recovery_count[k]=0;recovery_cycles[k]=0;recovery_valid[k]=0;
            end
            for (int k=0;k<16;k++) perf_hpm[k]=0;
            for (int k=0;k<3;k++) begin perf_issue[k]=0;perf_retire[k]=0;end
            for (int k=0;k<6;k++) begin
                kind_count[k]=0;kind_lifetime[k]=0;
                dispatch_count[k]=0;dispatch_delay[k]=0;
            end
        end else begin
            cycles <= cycles + 1;
            if ((dut.commit_redirect_valid_w || dut.branch_redirect_valid_w) &&
                (dut.allocate_valid_w || dut.ib_remove_count_w != 0))
                $fatal(1, "FAIL recovery allocated stale IB head cycle=%0d", cycles);
            if ($test$plusargs("CONTROL_LOG") && (dut.allocate_valid_w ||
                dut.cancel_valid_w || dut.commit_redirect_valid_w ||
                dut.execute0_valid_w || dut.execute1_valid_w ||
                dut.wb0_valid_w || dut.wb1_valid_w || cycles+4 >= cycle_limit)) begin
                $display("CTRL cycle=%0d alloc=%b pc=%08x cnt=%0d cancel=%b/%0d redirect=%b",
                    cycles, dut.allocate_valid_w, dut.allocate0_pc_w, dut.allocate_count_w,
                    dut.cancel_valid_w, dut.cancel_tag_w, dut.commit_redirect_valid_w);
                $display("EX0 v/r=%b%b tag=%0d pc=%08x late=%b wait=%b%b tags=%0d/%0d",
                    dut.execute0_valid_w, dut.execute0_ready_w, dut.execute0_tag_w,
                    dut.execute0_pc_w, dut.execute0_late_w, dut.execute0_source1_wait_w,
                    dut.execute0_source2_wait_w, dut.execute0_source1_tag_w,
                    dut.execute0_source2_tag_w);
                $display("EX1 v/r=%b%b tag=%0d pc=%08x late=%b wait=%b%b tags=%0d/%0d",
                    dut.execute1_valid_w, dut.execute1_ready_w, dut.execute1_tag_w,
                    dut.execute1_pc_w, dut.execute1_late_w, dut.execute1_source1_wait_w,
                    dut.execute1_source2_wait_w, dut.execute1_source1_tag_w,
                    dut.execute1_source2_tag_w);
                $display("HEAD pc=%08x tag=%0d done=%b mem=%b WB=%b/%0d %b/%0d",
                    dut.head0_pc_w, dut.head0_tag_w, dut.head0_done_w,
                    dut.branch_debug_mem_valid_w, dut.wb0_valid_w, dut.wb0_tag_w,
                    dut.wb1_valid_w, dut.wb1_tag_w);
                $display("ALU0 %b%b/%0d ALU1 %b%b/%0d BR %b%b/%0d",
                    dut.alu0_complete_valid_w, dut.alu0_complete_ready_w,
                    dut.alu0_complete_tag_w, dut.alu1_complete_valid_w,
                    dut.alu1_complete_ready_w, dut.alu1_complete_tag_w,
                    dut.branch_complete_valid_w, dut.branch_complete_ready_w,
                    dut.branch_complete_tag_w);
            end
            if ($test$plusargs("CONTROL_LOG") && cycles+4>=cycle_limit) begin
                $display("LSU state%0d tag%h req%b/%b complete%b/%b SQ valid%b committed%b count%0d/%0d head%0d tail%0d drain%b/%b tag%h",
                    dut.u_lsu.state_r,dut.u_lsu.tag_r,dut.lsu_req_valid_w,dut.lsu_req_ready_w,
                    dut.lsu_complete_valid_w,dut.lsu_complete_ready_w,dut.u_lsu.sq_valid_r,
                    dut.u_lsu.sq_committed_r,dut.u_lsu.sq_count_r,dut.u_lsu.sq_reserved_r,
                    dut.u_lsu.sq_head_r,dut.u_lsu.sq_tail_r,dut.dc_commit_valid_w,
                    dut.dc_commit_ready_w,dut.dc_commit_tag_w);
                $display("DC state%0d count%0d head%0d valid%b resolved%b pipe%b/%b tag%h addr%h pending%b wait%b refresh%b stale%b",
                    dut.u_dcache.state_r,dut.u_dcache.count_r,dut.u_dcache.head_r,
                    dut.u_dcache.valid_r,dut.u_dcache.resolved_r,dut.u_dcache.pipe_valid_r,
                    dut.u_dcache.pipe_miss_w,dut.u_dcache.pipe_tag_r,dut.u_dcache.pipe_addr_r,
                    dut.u_dcache.pending_valid_r,dut.u_dcache.store_drain_wait_w,
                    dut.u_dcache.refresh_busy_r,dut.u_dcache.pending_stale_r);
            end
            // Track each accepted late branch using only its public execute/return channels.
            for(int p=0;p<2;p++)begin
                if(branch_pending[p])begin
                    bit early1,early2;
                    early1=dut.early_resp_valid_w && dut.early_resp_hit_w &&
                        dut.early_resp_tag_w==branch_source1[p];
                    early2=dut.early_resp_valid_w && dut.early_resp_hit_w &&
                        dut.early_resp_tag_w==branch_source2[p];
                    if(perf_started && (branch_wait1[p] || branch_wait2[p]) &&
                        (!branch_wait1[p] || early1) && (!branch_wait2[p] || early2))begin
                        perf_branch_early_available++;
                        if(!dut.branch_complete_valid_w || dut.branch_complete_tag_w!=branch_tag[p])begin
                            perf_branch_early_delayed++;
                            perf_branch_early_port+=64'(dut.branch_complete_valid_w);
                            if(perf_branch_early_delayed<=4)
                                $display("BR_EARLY_WAIT cycle=%0d pc=%h tag=%h early=%h other_valid=%b",
                                    cycles,branch_pc[p],branch_tag[p],dut.early_resp_tag_w,
                                    dut.branch_complete_valid_w);
                        end
                    end
                    if(source_captured(branch_source1[p]))branch_wait1[p]=0;
                    if(source_captured(branch_source2[p]))branch_wait2[p]=0;
                    if(dut.branch_complete_valid_w && dut.branch_complete_ready_w &&
                        dut.branch_complete_tag_w==branch_tag[p])branch_pending[p]=0;
                    if(dut.cancel_valid_w && ((branch_tag[p]-dut.age_head_w)>=
                        (dut.cancel_tag_w-dut.age_head_w)))branch_pending[p]=0;
                end
            end
            if(dut.branch_execute0_valid_w && dut.branch_execute0_ready_w && dut.execute0_late_w)begin
                branch_pending[0]=1;branch_tag[0]=dut.execute0_tag_w;branch_pc[0]=dut.execute0_pc_w;
                branch_source1[0]=dut.execute0_source1_tag_w;branch_source2[0]=dut.execute0_source2_tag_w;
                branch_wait1[0]=dut.execute0_source1_wait_w;branch_wait2[0]=dut.execute0_source2_wait_w;
            end
            if(dut.branch_execute1_valid_w && dut.branch_execute1_ready_w && dut.execute1_late_w)begin
                branch_pending[1]=1;branch_tag[1]=dut.execute1_tag_w;branch_pc[1]=dut.execute1_pc_w;
                branch_source1[1]=dut.execute1_source1_tag_w;branch_source2[1]=dut.execute1_source2_tag_w;
                branch_wait1[1]=dut.execute1_source1_wait_w;branch_wait2[1]=dut.execute1_source2_wait_w;
            end
            if (dut.trace_trap_w)
                $display("TRAP pc=%08x cause=%08x tval=%08x cycle=%0d",
                    dut.trace_trap_pc_w, dut.trace_cause_w, dut.trace_tval_w, cycles);
            if (cycles >= cycle_limit)
                $fatal(1, "FAIL timeout width=%0d cycles=%0d retired=%0d pc=%08x",
                    ISSUE_WIDTH, cycles, retired, debug[63:32]);
            if (dut.allocate_valid_w && dut.allocate_ready_w) begin
                allocated_at[dut.allocate0_tag_w]=cycles;
                record_kind[dut.allocate0_tag_w]=instruction_kind(dut.allocate0_instr_w);
                if(dut.allocate_count_w==2) begin
                    allocated_at[dut.allocate1_tag_w]=cycles;
                    record_kind[dut.allocate1_tag_w]=instruction_kind(dut.allocate1_instr_w);
                end
            end
            if(perf_begin_event_w) begin
                perf_started=1;
                perf_start=cycles;
                perf_instructions=0;
            end
            if(perf_started && !perf_end_event_w) begin
                perf_full += 64'((dut.allocate_credit_w==0));
                perf_ib_empty += 64'(!dut.ib_head0_valid_w);
                perf_lsu_busy += 64'(!dut.lsu_req_ready_w);
                if(dut.head0_valid_w && dut.head0_store_w && !dut.head0_device_w) begin
                    store_head_run = store_head_active && store_head_tag==dut.head0_tag_w ?
                        store_head_run+1 : 1;
                    store_head_active=1;
                    store_head_tag=dut.head0_tag_w;
                    if(dut.trace_valid_w[0]) begin
                        if(store_head_run<store_head_min) store_head_min=store_head_run;
                        store_head_active=0;
                    end
                end else store_head_active=0;
                perf_store_head += 64'(dut.head0_valid_w && dut.head0_store_w);
                perf_early += 64'(dut.early_req_valid_w);
                perf_early_hit += 64'(dut.early_resp_valid_w && dut.early_resp_hit_w);
                if(dut.allocate_credit_w==0) begin
                    perf_full_retiring+=64'(dut.retire_count_w!=0);
                    perf_full_store+=64'(dut.head0_valid_w && dut.head0_store_w);
                    perf_full_load+=64'(dut.head0_valid_w && dut.head0_trace_instr_w[6:0]==7'h03);
                end
                perf_bank_wait[0]+=64'(dut.alu0_complete_valid_w && !dut.alu0_complete_ready_w);
                perf_bank_wait[1]+=64'(dut.alu1_complete_valid_w && !dut.alu1_complete_ready_w);
                perf_bank_wait[2]+=64'(dut.lsu_complete_valid_w && !dut.lsu_complete_ready_w);
                perf_bank_wait[3]+=64'(dut.mul_complete_valid_w && !dut.mul_complete_ready_w);
                perf_bank_wait[4]+=64'(dut.div_complete_valid_w && !dut.div_complete_ready_w);
                perf_bank_wait[5]+=64'(dut.branch_complete_valid_w && !dut.branch_complete_ready_w);
                if(dut.execute0_valid_w && dut.execute0_ready_w && dut.execute0_late_w)begin
                    if((dut.execute0_source1_wait_w && alu_blocked(dut.execute0_source1_tag_w)) ||
                        (dut.execute0_source2_wait_w && alu_blocked(dut.execute0_source2_tag_w)))begin
                        perf_late_alu_capture_block++;
                        if(perf_late_alu_capture_block<=4)
                            $display("LATE_BANK_WAIT cycle=%0d pc=%h tags=%h/%h branch=%b",
                                cycles,dut.execute0_pc_w,dut.execute0_source1_tag_w,
                                dut.execute0_source2_tag_w,dut.execute0_branch_w);
                    end
                    if((dut.execute0_source1_wait_w && load_blocked(dut.execute0_source1_tag_w)) ||
                        (dut.execute0_source2_wait_w && load_blocked(dut.execute0_source2_tag_w)))
                        perf_late_load_capture_block++;
                end
                if(dut.execute1_valid_w && dut.execute1_ready_w && dut.execute1_late_w)begin
                    if((dut.execute1_source1_wait_w && alu_blocked(dut.execute1_source1_tag_w)) ||
                        (dut.execute1_source2_wait_w && alu_blocked(dut.execute1_source2_tag_w)))begin
                        perf_late_alu_capture_block++;
                        if(perf_late_alu_capture_block<=4)
                            $display("LATE_BANK_WAIT cycle=%0d pc=%h tags=%h/%h branch=%b",
                                cycles,dut.execute1_pc_w,dut.execute1_source1_tag_w,
                                dut.execute1_source2_tag_w,dut.execute1_branch_w);
                    end
                    if((dut.execute1_source1_wait_w && load_blocked(dut.execute1_source1_tag_w)) ||
                        (dut.execute1_source2_wait_w && load_blocked(dut.execute1_source2_tag_w)))
                        perf_late_load_capture_block++;
                end
                if(dut.early_req_valid_w && dut.u_lsu.early_block_w) begin
                    if(dut.u_lsu.early_conflict_w)perf_early_word_block++;
                    else perf_early_port_block++;
                end
                if(dut.dc_req_valid_w && dut.dc_req_ready_w && dut.dc_req_early_w &&
                    !dut.u_lsu.early_reuse_w)perf_early_expired++;
                if(dut.issue_hpm_w[1]) begin
                    perf_pair_types[6*instruction_kind(dut.ib_head0_instr_w)+
                        instruction_kind(dut.ib_head1_instr_w)]++;
                    if(!dut.u_issue.d1_sources_w)begin
                        bit load_wait,alu_wait,mul_wait,expired_load;
                        load_wait=0;alu_wait=0;mul_wait=0;expired_load=0;
                        if(dut.u_issue.d1_wait1_w)begin
                            load_wait|=dut.u_issue.entry_class_w[dut.u_issue.q11_tag_w]==3;
                            alu_wait|=dut.u_issue.entry_class_w[dut.u_issue.q11_tag_w]==0;
                            mul_wait|=dut.u_issue.entry_class_w[dut.u_issue.q11_tag_w]==4;
                            expired_load|=dut.u_issue.entry_class_w[dut.u_issue.q11_tag_w]==3 &&
                                dut.u_issue.entry_countdown_w[dut.u_issue.q11_tag_w]==0;
                        end
                        if(dut.u_issue.d1_wait2_w)begin
                            load_wait|=dut.u_issue.entry_class_w[dut.u_issue.q12_tag_w]==3;
                            alu_wait|=dut.u_issue.entry_class_w[dut.u_issue.q12_tag_w]==0;
                            mul_wait|=dut.u_issue.entry_class_w[dut.u_issue.q12_tag_w]==4;
                            expired_load|=dut.u_issue.entry_class_w[dut.u_issue.q12_tag_w]==3 &&
                                dut.u_issue.entry_countdown_w[dut.u_issue.q12_tag_w]==0;
                        end
                        perf_pair_load_wait+=64'(load_wait);perf_pair_alu_wait+=64'(alu_wait);
                        perf_pair_mul_wait+=64'(mul_wait);perf_pair_expired_load+=64'(expired_load);
                    end
                    if(dut.allocate_credit_w<2) perf_pair_credit++;
                    else if(!dut.u_issue.d1_sources_w) perf_pair_operand++;
                    else perf_pair_channel++;
                end
                if(dut.trace_redirect_valid_w) begin
                    recovery_valid[int'(dut.trace_redirect_stage_w)-1]=1;
                    recovery_target[int'(dut.trace_redirect_stage_w)-1]=dut.trace_redirect_target_w;
                    recovery_start[int'(dut.trace_redirect_stage_w)-1]=cycles;
                end
                for(int k=0;k<3;k++) begin
                    if(recovery_valid[k] && dut.allocate_valid_w && dut.allocate_ready_w &&
                        (dut.allocate0_pc_w==recovery_target[k] ||
                        (dut.allocate_count_w==2 && dut.allocate1_pc_w==recovery_target[k]))) begin
                        recovery_count[k]++;
                        recovery_cycles[k]+=cycles-recovery_start[k];
                        recovery_valid[k]=0;
                    end
                end
                if(dut.u_dcache.miss_store_wait_w && !perf_miss_store_active) begin
                    perf_miss_store_waits++;
                    perf_miss_store_active=1;
                    perf_miss_store_tag=dut.u_dcache.pipe_tag_r;
                end
                if(perf_miss_store_active) begin
                    if((dut.u_dcache.state_r!=0 && !dut.u_dcache.miss_refresh_r &&
                        !dut.u_dcache.wb_maint_r) || (dut.dc_resp_valid_w &&
                        dut.dc_resp_tag_w==perf_miss_store_tag) || (dut.dc_cancel_valid_w &&
                        ((perf_miss_store_tag-dut.age_head_w)>=
                        (dut.dc_cancel_tag_w-dut.age_head_w)))) perf_miss_store_active=0;
                    else perf_miss_store_cycles++;
                end
                perf_ic_miss_cycles+=64'(dut.icache_debug_miss_w);
                perf_dc_miss_cycles+=64'(dut.dcache_debug_miss_w);
                perf_f2 += 64'(dut.f2_redirect_valid_w);
                for(int k=0;k<16;k++) perf_hpm[k]+=dut.hpm_event_w[k];
                perf_issue[dut.ib_remove_count_w]++;
                perf_retire[dut.retire_count_w]++;
                if(dut.execute0_valid_w && dut.execute0_ready_w)
                    dispatch(dut.execute0_tag_w);
                if(dut.execute1_valid_w && dut.execute1_ready_w)
                    dispatch(dut.execute1_tag_w);
                if(dut.lsu_req_valid_w && dut.lsu_req_ready_w) dispatch(dut.lsu_req_tag_w);
                if(dut.mul_req_valid_w && dut.mul_req_ready_w) dispatch(dut.mul_req_tag_w);
                if(dut.div_req_valid_w && dut.div_req_ready_w) dispatch(dut.div_req_tag_w);
                if(dut.csr_req_valid_w && dut.csr_req_ready_w) dispatch(dut.csr_req_tag_w);
            end
            for (int j = 0; j < 2; j++) begin
                if (dut.trace_valid_w[j]) begin
                    retired = retired + 1;
                    if (perf_enabled && dut.trace_pc_w[j*32 +: 32] == perf_begin) begin
                        perf_instructions = 0;
                        perf_start = cycles;
                        perf_started = 1;
                    end
                    if (perf_enabled && perf_started &&
                        dut.trace_pc_w[j*32 +: 32] == perf_end) begin
                        $display("PERF width=%0d cycles=%0d", ISSUE_WIDTH, cycles-perf_start);
                        $write("STATS instructions=%0d full=%0d ib_empty=%0d lsu_busy=%0d ",
                            perf_instructions,perf_full,perf_ib_empty,perf_lsu_busy);
                        $display("store_head=%0d early=%0d early_hit=%0d f2=%0d",
                            perf_store_head,perf_early,perf_early_hit,perf_f2);
                        $display("BANK_WAIT alu0=%0d alu1=%0d lsu=%0d mul=%0d div=%0d branch=%0d",
                            perf_bank_wait[0],perf_bank_wait[1],perf_bank_wait[2],perf_bank_wait[3],
                            perf_bank_wait[4],perf_bank_wait[5]);
                        $display("LATE_CAPTURE_BLOCK alu=%0d load=%0d",
                            perf_late_alu_capture_block,perf_late_load_capture_block);
                        $display("EARLY_DETAIL port_block=%0d word_block=%0d expired=%0d",
                            perf_early_port_block,perf_early_word_block,perf_early_expired);
                        $display("PAIR_OPERAND load=%0d alu=%0d mul=%0d expired_load=%0d",
                            perf_pair_load_wait,perf_pair_alu_wait,perf_pair_mul_wait,perf_pair_expired_load);
                        $display("BR_EARLY available=%0d delayed=%0d other_result=%0d",
                            perf_branch_early_available,perf_branch_early_delayed,perf_branch_early_port);
                        for(int k=0;k<36;k++)if(perf_pair_types[k]!=0)
                            $display("PAIR_STRUCT older=%0d younger=%0d count=%0d",k/6,k%6,perf_pair_types[k]);
                        $display("MISS_STORE_WAIT events=%0d cycles=%0d",
                            perf_miss_store_waits,perf_miss_store_cycles);
                        $display("MISS_CYCLES ic=%0d dc=%0d",
                            perf_ic_miss_cycles,perf_dc_miss_cycles);
                        $display("STORE_HEAD_MIN cycles=%0d",store_head_min);
                        $display("DETAIL full_retiring=%0d full_store=%0d full_load=%0d",
                            perf_full_retiring,perf_full_store,perf_full_load);
                        $display("PAIR6 credit=%0d operand=%0d channel=%0d",
                            perf_pair_credit,perf_pair_operand,perf_pair_channel);
                        for(int k=0;k<3;k++) $display("RECOVERY stage=%0d count=%0d cycles=%0d",
                            k+1,recovery_count[k],recovery_cycles[k]);
                        for(int k=0;k<16;k++) $display("HPM event=%0d count=%0d",k+1,perf_hpm[k]);
                        for(int k=0;k<3;k++) $display("COUNTS n=%0d issue=%0d retire=%0d",
                            k,perf_issue[k],perf_retire[k]);
                        for(int k=0;k<6;k++)
                            $display("KIND k=%0d count=%0d lifetime=%0d dispatch=%0d delay=%0d",
                                k,kind_count[k],kind_lifetime[k],dispatch_count[k],dispatch_delay[k]);
                        perf_started = 0;
                        if($test$plusargs("PERF_ONLY")) begin
                            $display("PASS performance window width=%0d", ISSUE_WIDTH);
                            $finish;
                        end
                    end
                    if(perf_started) begin
                        perf_instructions++;
                        kind_count[instruction_kind(dut.trace_instr_w[j*32 +:32])]++;
                        kind_lifetime[record_kind[j==0?dut.head0_tag_w:dut.head1_tag_w]] +=
                            cycles-allocated_at[j==0?dut.head0_tag_w:dut.head1_tag_w];
                    end
                    if (dut.trace_mem_valid_w[j] && dut.trace_mem_store_w[j] &&
                        dut.trace_mem_addr_w[j*32 +: 32] == 32'h40007000)
                        $write("%c", dut.trace_mem_data_w[j*64 +: 8]);
                    if (trace_fd != 0)
                        $fdisplay(trace_fd, "%0d %08x %08x %0d %08x", cycles,
                            dut.trace_pc_w[j*32 +: 32], dut.trace_instr_w[j*32 +: 32],
                            dut.trace_rd_w[j*5 +: 5], dut.trace_rd_data_w[j*64 +: 32]);
                    if (!$test$plusargs("PERF_ONLY") && dut.trace_mem_valid_w[j] &&
                        dut.trace_mem_store_w[j] && dut.trace_mem_addr_w[j*32 +: 32] == tohost_addr &&
                        dut.trace_mem_data_w[j*64 +: 32] != 0) begin
                        if (dut.trace_mem_data_w[j*64 +: 32] != 1)
                            $fatal(1, "FAIL tohost=%08x pc=%08x cycle=%0d",
                                dut.trace_mem_data_w[j*64 +: 32],
                                dut.trace_pc_w[j*32 +: 32], cycles);
                        $display("PASS width=%0d cycles=%0d retired=%0d",
                            ISSUE_WIDTH, cycles, retired);
                        $finish;
                    end
                end
            end
        end
    end
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic integer instruction_kind(input bit [31:0] code);
        case(code[6:0])
            7'h03: return 1;
            7'h23: return 2;
            7'h63,7'h67,7'h6f: return 3;
            7'h73,7'h0f: return 5;
            7'h33: return code[25]?4:0;
            default:return 0;
        endcase
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */
    task automatic dispatch(input bit [(ISSUE_WIDTH==2?4:3)-1:0] tag);
        dispatch_count[record_kind[tag]]++;
        dispatch_delay[record_kind[tag]]+=cycles-allocated_at[tag];
    endtask
    /* verilator lint_off UNUSEDSIGNAL */
    wire unused_w = ^{debug, cache_irq, apb_ready, apb_data, apb_error,
        ic.arid, ic.arburst, ic.awid, ic.awburst, ic.wlast,
        dc.arid, dc.arburst, dc.awid, dc.awburst, dc.wlast};
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
