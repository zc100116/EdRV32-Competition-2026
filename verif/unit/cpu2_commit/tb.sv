// File: tb.sv
// Spec: cpu-v2-testplan CV09/CV10; cpu-v2-spec 3-6.
// Description: Self-check all six fixed configurations. Clock: clk_sys.
// Public-interface CV09/CV10 checks for all six fixed configurations.
module check_commit #(parameter ISSUE_WIDTH=2, parameter [31:0] FPU_FORMAT="NONE")
    (output reg finished);
    localparam N = FPU_FORMAT == "FD" ? 16 : FPU_FORMAT == "F" ? 8 : 4;
    localparam T = FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2;
    localparam B = FPU_FORMAT == "FD" ? 64 : 32;
    reg [31:0] trace_noise;
    reg clk_i;
    reg rst_n_i;
    reg [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] head0_tag_i;
    reg [31:0] head0_pc_i;
    reg [31:0] head0_next_pc_i;
    reg [31:0] head0_instr_i;
    wire [3:0] head0_kind_i;
    reg [4:0] head0_rd_i;
    reg [1:0] head0_dest_i;
    reg head0_store_i;
    reg head0_divide_i;
    reg head0_double_beat_i;
    reg head0_valid_i;
    reg head0_done_i;
    reg [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] head0_data_i;
    reg [4:0] head0_flags_i;
    reg head0_exception_i;
    reg [3:0] head0_cause_i;
    reg [31:0] head0_tval_i;
    reg head0_device_i;
    reg [31:0] head0_mem_addr_i;
    reg [63:0] head0_mem_data_i;
    reg [7:0] head0_mem_mask_i;
    wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] wb0_tag_o;
    wire wb0_valid_copy_o;
    wire [4:0] wb0_rd_copy_o;
    wire wb0_valid_o;
    wire [4:0] wb0_rd_o;
    wire [31:0] wb0_data_o;
    reg [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] head1_tag_i;
    reg [31:0] head1_pc_i;
    reg [31:0] head1_next_pc_i;
    reg [31:0] head1_instr_i;
    wire [3:0] head1_kind_i;
    reg [4:0] head1_rd_i;
    reg [1:0] head1_dest_i;
    reg head1_store_i;
    reg head1_divide_i;
    reg head1_double_beat_i;
    reg head1_valid_i;
    reg head1_done_i;
    reg [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] head1_data_i;
    reg [4:0] head1_flags_i;
    reg head1_exception_i;
    reg [3:0] head1_cause_i;
    reg [31:0] head1_tval_i;
    reg head1_device_i;
    reg [31:0] head1_mem_addr_i;
    reg [63:0] head1_mem_data_i;
    reg [7:0] head1_mem_mask_i;
    wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] wb1_tag_o;
    wire wb1_valid_copy_o;
    wire [4:0] wb1_rd_copy_o;
    wire wb1_valid_o;
    wire [4:0] wb1_rd_o;
    wire [31:0] wb1_data_o;
    reg [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] age_head_i;
    reg cancel_valid_i;
    reg [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] cancel_tag_i;
    reg branch_redirect_valid_i;
    reg [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] branch_redirect_tag_i;
    reg [31:0] branch_redirect_pc_i;
    wire [1:0] retire_count_o;
    wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] fp_wb_tag_o;
    wire fp_wb_valid_o;
    wire [4:0] fp_wb_rd_o;
    wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] fp_wb_data_o;
    wire commit_lsu_valid_o;
    reg commit_lsu_ready_i;
    wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] commit_lsu_tag_o;
    reg commit_lsu_done_valid_i;
    wire commit_lsu_done_ready_o;
    reg [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] commit_lsu_done_tag_i;
    reg commit_lsu_done_error_i;
    reg [31:0] commit_lsu_done_fault_addr_i;
    reg [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] commit_lsu_done_data_i;
    wire csr_commit_valid_o;
    wire fp_commit_flags_valid_o;
    wire [4:0] fp_commit_flags_o;
    wire fp_commit_write_o;
    reg irq_pending_i;
    reg [31:0] irq_cause_i;
    reg irq_wake_i;
    reg [31:0] trap_target_i;
    reg [31:0] csr_mepc_i;
    wire mret_valid_o;
    wire trap_valid_o;
    wire [31:0] trap_pc_o;
    wire [31:0] trap_cause_o;
    wire [31:0] trap_tval_o;
    wire commit_cancel_valid_o;
    wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] commit_cancel_tag_o;
    wire commit_redirect_valid_o;
    wire [31:0] commit_redirect_pc_o;
    wire fetch_stop_o;
    wire dc_fence_valid_o;
    reg dc_fence_ready_i;
    wire dc_fence_clean_all_o;
    reg dc_fence_done_i;
    wire ic_inv_valid_o;
    reg ic_inv_ready_i;
    reg ic_inv_done_i;
    wire [1:0] counter_retire_count_o;
    wire [1:0] hpm_branch_count_o;
    edrv32_cpu2_commit #(.ISSUE_WIDTH(ISSUE_WIDTH), .FPU_FORMAT(FPU_FORMAT)) dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .head0_tag_i(head0_tag_i),
        .head0_pc_i(head0_pc_i),
        .head0_next_pc_i(head0_next_pc_i),
        .head0_kind_i(head0_kind_i),
        .head0_trace_instr_i(head0_instr_i ^ trace_noise),
        .head0_rd_i(head0_rd_i),
        .head0_dest_i(head0_dest_i),
        .head0_store_i(head0_store_i),
        .head0_divide_i(head0_divide_i),
        .head0_double_beat_i(head0_double_beat_i),
        .head0_valid_i(head0_valid_i),
        .head0_done_i(head0_done_i),
        .head0_data_i(head0_data_i),
        .head0_flags_i(head0_flags_i),
        .head0_exception_i(head0_exception_i),
        .head0_cause_i(head0_cause_i),
        .head0_tval_i(head0_tval_i),
        .head0_device_i(head0_device_i),
        .head0_mem_addr_i(head0_mem_addr_i),
        .head0_mem_data_i(head0_mem_data_i),
        .head0_mem_mask_i(head0_mem_mask_i),
        .wb0_tag_o(wb0_tag_o),
        .wb0_valid_copy_o(wb0_valid_copy_o),
        .wb0_rd_copy_o(wb0_rd_copy_o),
        .wb0_valid_o(wb0_valid_o),
        .wb0_rd_o(wb0_rd_o),
        .wb0_data_o(wb0_data_o),
        .head1_tag_i(head1_tag_i),
        .head1_pc_i(head1_pc_i),
        .head1_next_pc_i(head1_next_pc_i),
        .head1_kind_i(head1_kind_i),
        .head1_trace_instr_i(head1_instr_i ^ trace_noise),
        .head1_rd_i(head1_rd_i),
        .head1_dest_i(head1_dest_i),
        .head1_store_i(head1_store_i),
        .head1_divide_i(head1_divide_i),
        .head1_double_beat_i(head1_double_beat_i),
        .head1_valid_i(head1_valid_i),
        .head1_done_i(head1_done_i),
        .head1_data_i(head1_data_i),
        .head1_flags_i(head1_flags_i),
        .head1_exception_i(head1_exception_i),
        .head1_cause_i(head1_cause_i),
        .head1_tval_i(head1_tval_i),
        .head1_device_i(head1_device_i),
        .head1_mem_addr_i(head1_mem_addr_i),
        .head1_mem_data_i(head1_mem_data_i),
        .head1_mem_mask_i(head1_mem_mask_i),
        .wb1_tag_o(wb1_tag_o),
        .wb1_valid_copy_o(wb1_valid_copy_o),
        .wb1_rd_copy_o(wb1_rd_copy_o),
        .wb1_valid_o(wb1_valid_o),
        .wb1_rd_o(wb1_rd_o),
        .wb1_data_o(wb1_data_o),
        .age_head_i(age_head_i),
        .cancel_valid_i(cancel_valid_i),
        .cancel_tag_i(cancel_tag_i),
        .branch_redirect_valid_i(branch_redirect_valid_i),
        .branch_redirect_tag_i(branch_redirect_tag_i),
        .branch_redirect_pc_i(branch_redirect_pc_i),
        .retire_count_o(retire_count_o),
        .fp_wb_tag_o(fp_wb_tag_o),
        .fp_wb_valid_o(fp_wb_valid_o),
        .fp_wb_rd_o(fp_wb_rd_o),
        .fp_wb_data_o(fp_wb_data_o),
        .commit_lsu_valid_o(commit_lsu_valid_o),
        .commit_lsu_ready_i(commit_lsu_ready_i),
        .commit_lsu_tag_o(commit_lsu_tag_o),
        .commit_lsu_done_valid_i(commit_lsu_done_valid_i),
        .commit_lsu_done_ready_o(commit_lsu_done_ready_o),
        .commit_lsu_done_tag_i(commit_lsu_done_tag_i),
        .commit_lsu_done_error_i(commit_lsu_done_error_i),
        .commit_lsu_done_fault_addr_i(commit_lsu_done_fault_addr_i),
        .commit_lsu_done_data_i(commit_lsu_done_data_i),
        .csr_commit_valid_o(csr_commit_valid_o),
        .fp_commit_flags_valid_o(fp_commit_flags_valid_o),
        .fp_commit_flags_o(fp_commit_flags_o),
        .fp_commit_write_o(fp_commit_write_o),
        .irq_pending_i(irq_pending_i),
        .irq_cause_i(irq_cause_i),
        .irq_wake_i(irq_wake_i),
        .trap_target_i(trap_target_i),
        .csr_mepc_i(csr_mepc_i),
        .mret_valid_o(mret_valid_o),
        .trap_valid_o(trap_valid_o),
        .trap_pc_o(trap_pc_o),
        .trap_cause_o(trap_cause_o),
        .trap_tval_o(trap_tval_o),
        .commit_cancel_valid_o(commit_cancel_valid_o),
        .commit_cancel_tag_o(commit_cancel_tag_o),
        .commit_redirect_valid_o(commit_redirect_valid_o),
        .commit_redirect_pc_o(commit_redirect_pc_o),
        .fetch_stop_o(fetch_stop_o),
        .dc_fence_valid_o(dc_fence_valid_o),
        .dc_fence_ready_i(dc_fence_ready_i),
        .dc_fence_clean_all_o(dc_fence_clean_all_o),
        .dc_fence_done_i(dc_fence_done_i),
        .ic_inv_valid_o(ic_inv_valid_o),
        .ic_inv_ready_i(ic_inv_ready_i),
        .ic_inv_done_i(ic_inv_done_i),
        .counter_retire_count_o(counter_retire_count_o),
        .hpm_branch_count_o(hpm_branch_count_o)
    );
    // Interface classification model; original words remain trace-only stimuli.
    function [3:0] commit_kind(input [31:0] instr);
        begin
            if(instr==32'h30200073) commit_kind=4;
            else if(instr==32'h10500073) commit_kind=5;
            else if(instr[6:0]==7'h0f) commit_kind=instr[14:12]==1 ? 2:1;
            else if(instr[6:0]==7'h73) commit_kind=instr[14:12]!=0 ? 6:3;
            else if(instr[6:0]==7'h63 || instr[6:0]==7'h67 || instr[6:0]==7'h6f)
                commit_kind=7;
            else if(instr[6:0]==7'h53) commit_kind=8;
            else commit_kind=0;
        end
    endfunction
    assign head0_kind_i=commit_kind(head0_instr_i);
    assign head1_kind_i=commit_kind(head1_instr_i);
    always #5 clk_i = ~clk_i;
    task tick; begin @(posedge clk_i); #1; end endtask
    task check(input condition, input [511:0] label);
        if (condition !== 1'b1) $fatal(1,"%s expected=1 actual=%b I=%0d F=%s time=%0t",
            label,condition,ISSUE_WIDTH,FPU_FORMAT,$time);
    endtask
    always @(negedge clk_i) begin
        if(rst_n_i && ISSUE_WIDTH==2) begin
            check(wb0_valid_copy_o===wb0_valid_o && wb1_valid_copy_o===wb1_valid_o,
                "WB copies have the same registered edge");
            if(wb0_valid_o) check(wb0_rd_copy_o===wb0_rd_o,"old WB region copy");
            if(wb1_valid_o) check(wb1_rd_copy_o===wb1_rd_o,"young WB region copy");
        end
        if(rst_n_i && ISSUE_WIDTH==1)
            check(!wb0_valid_copy_o && !wb1_valid_copy_o,"single issue has no WB copies");
    end
    initial begin
        finished=0; trace_noise=0;
        clk_i='0;
        rst_n_i='0;
        head0_tag_i='0;
        head0_pc_i='0;
        head0_next_pc_i='0;
        head0_instr_i='0;
        head0_rd_i='0;
        head0_dest_i='0;
        head0_store_i='0;
        head0_divide_i='0;
        head0_double_beat_i='0;
        head0_valid_i='0;
        head0_done_i='0;
        head0_data_i='0;
        head0_flags_i='0;
        head0_exception_i='0;
        head0_cause_i='0;
        head0_tval_i='0;
        head0_device_i='0;
        head0_mem_addr_i='0;
        head0_mem_data_i='0;
        head0_mem_mask_i='0;
        head1_tag_i='0;
        head1_pc_i='0;
        head1_next_pc_i='0;
        head1_instr_i='0;
        head1_rd_i='0;
        head1_dest_i='0;
        head1_store_i='0;
        head1_divide_i='0;
        head1_double_beat_i='0;
        head1_valid_i='0;
        head1_done_i='0;
        head1_data_i='0;
        head1_flags_i='0;
        head1_exception_i='0;
        head1_cause_i='0;
        head1_tval_i='0;
        head1_device_i='0;
        head1_mem_addr_i='0;
        head1_mem_data_i='0;
        head1_mem_mask_i='0;
        age_head_i='0;
        cancel_valid_i='0;
        cancel_tag_i='0;
        branch_redirect_valid_i='0;
        branch_redirect_tag_i='0;
        branch_redirect_pc_i='0;
        commit_lsu_ready_i='0;
        commit_lsu_done_valid_i='0;
        commit_lsu_done_tag_i='0;
        commit_lsu_done_error_i='0;
        commit_lsu_done_fault_addr_i='0;
        commit_lsu_done_data_i='0;
        irq_pending_i='0;
        irq_cause_i='0;
        irq_wake_i='0;
        trap_target_i='0;
        csr_mepc_i='0;
        dc_fence_ready_i='0;
        dc_fence_done_i='0;
        ic_inv_ready_i='0;
        ic_inv_done_i='0;
        tick(); rst_n_i=1; tick();
        head0_valid_i=1; head0_done_i=1; head0_pc_i=32'h1000;
        head0_instr_i=32'h13; head0_rd_i=1; head0_dest_i=1; head0_data_i=11;
        head1_valid_i=1; head1_done_i=1; head1_pc_i=32'h1004; head1_tag_i=1;
        head1_instr_i=32'h13; head1_rd_i=1; head1_dest_i=1; head1_data_i=22;
        #1; check(32'(retire_count_o)==ISSUE_WIDTH,"retire ordered prefix");
        trace_noise=head0_instr_i ^ 32'h30200073;
        #1; check(32'(retire_count_o)==ISSUE_WIDTH && !mret_valid_o,
            "trace instruction cannot change retirement behavior");
        check(dut.trace_instr_w[31:0]==32'h30200073,"trace word remains observable");
        trace_noise=0;
        check(!wb0_valid_o,"WB has no combinational retirement path");
        tick();
        check(wb0_valid_o && wb0_tag_o==0 && wb0_data_o==11,"older RF write");
        check(wb1_valid_o==(ISSUE_WIDTH==2),"younger RF write");
        head0_done_i=0; #1; check(retire_count_o==0,"unfinished oldest blocks");
        check(wb0_valid_o && wb0_data_o==11,"WB remains captured through cycle");
        tick(); check(!wb0_valid_o,"WB valid clears on next edge");
        head0_done_i=1; head1_exception_i=1; head1_cause_i=2; head1_tval_i=32'hbad;
        #1;
        if(ISSUE_WIDTH==2) begin
            check(retire_count_o==1 && trap_valid_o && trap_pc_o==32'h1004,
                "younger trap preserves old retirement");
            check(commit_cancel_tag_o==1 && trap_tval_o==32'hbad,"precise young fault");
        end
        head0_exception_i=1; head0_cause_i=5; head0_tval_i=32'hffff;
        irq_pending_i=1; irq_cause_i=32'h8000000b;
        #1; check(trap_cause_o==5 && retire_count_o==0,"old sync fault beats IRQ");
        head0_exception_i=0; head1_exception_i=0;
        #1; check(trap_valid_o && trap_cause_o==32'h8000000b && retire_count_o==0,
            "IRQ before architectural writes");
        head0_done_i=0; head0_divide_i=1;
        #1; check(!trap_valid_o,"head DIV cannot interrupt");
        head0_divide_i=0; #1; check(trap_valid_o,"ordinary long FP can interrupt");
        irq_pending_i=0; head0_done_i=1; head1_valid_i=0;
        // Store authorization is separate from completion and held until accepted.
        head0_store_i=1; head0_instr_i=32'h23; head0_dest_i=0;
        #1; check(commit_lsu_valid_o && retire_count_o==0,"store awaits authorization");
        tick(); check(commit_lsu_valid_o,"authorization backpressure");
        commit_lsu_ready_i=1; tick(); commit_lsu_ready_i=0;
        irq_pending_i=1; #1; check(!trap_valid_o && !commit_lsu_valid_o,"authorized boundary");
        commit_lsu_done_valid_i=1; #1;
        check(retire_count_o==1 && commit_lsu_done_ready_o,"store retires only on done");
        tick(); commit_lsu_done_valid_i=0; irq_pending_i=0;
        // Access fault after authorization carries the failing beat address.
        commit_lsu_ready_i=1; tick(); commit_lsu_ready_i=0;
        commit_lsu_done_valid_i=1; commit_lsu_done_error_i=1;
        commit_lsu_done_fault_addr_i=32'h2004; #1;
        check(trap_valid_o && trap_cause_o==7 && trap_tval_o==32'h2004 && retire_count_o==0,
            "high beat store fault");
        tick(); commit_lsu_done_valid_i=0; commit_lsu_done_error_i=0;
        head0_store_i=0; head0_device_i=1; head0_instr_i=32'h03; head0_dest_i=1;
        commit_lsu_ready_i=1; tick(); commit_lsu_ready_i=0;
        commit_lsu_done_valid_i=1; commit_lsu_done_data_i=B'(32'hffffff80);
        head0_mem_mask_i=1; #1;
        check(dut.trace_mem_valid_w[0] && dut.trace_mem_data_w[63:0]==64'h80,
            "device trace removes sign extension");
        check(retire_count_o==1,"device ready to retire");
        tick(); check(wb0_valid_o && wb0_data_o==32'hffffff80,"device load final data");
        commit_lsu_done_valid_i=0; head0_device_i=0;
        if(FPU_FORMAT!="NONE") begin
            head0_device_i=1; head0_dest_i=2; head0_rd_i=0;
            head0_instr_i=32'h2007; head0_mem_mask_i=8'h0f;
            commit_lsu_ready_i=1; tick(); commit_lsu_ready_i=0;
            commit_lsu_done_valid_i=1; commit_lsu_done_data_i=B'(64'hffffffff7fc01234);
            #1; check(dut.trace_mem_data_w[63:0]==64'h7fc01234,
                "device FLW trace removes NaN boxing");
            tick(); commit_lsu_done_valid_i=0;
            check(fp_wb_valid_o && fp_wb_rd_o==0 &&
                fp_wb_data_o==B'(64'hffffffff7fc01234),"device FP write and f0");
            if(FPU_FORMAT=="FD") begin
                head0_instr_i=32'h3007; head0_double_beat_i=1; head0_mem_mask_i=8'hff;
                irq_pending_i=1; #1; check(!trap_valid_o,"D transaction interrupt boundary");
                commit_lsu_ready_i=1; tick(); commit_lsu_ready_i=0;
                commit_lsu_done_valid_i=1; commit_lsu_done_data_i=B'(64'h89abcdef01234567);
                #1; check(dut.trace_mem_data_w[63:0]==64'h89abcdef01234567,"device FLD raw trace");
                tick(); commit_lsu_done_valid_i=0;
                check(fp_wb_valid_o && fp_wb_data_o==B'(64'h89abcdef01234567),"device FLD WB");
                irq_pending_i=0; head0_double_beat_i=0;
            end
            head0_device_i=0; head0_dest_i=0; head0_rd_i=1;
        end
        // MRET publishes a registered target and updates CSR on its retirement edge.
        head0_instr_i=32'h30200073; head0_dest_i=0; csr_mepc_i=32'h9000;
        head1_valid_i=1; head1_exception_i=1;
        #1; check(mret_valid_o && retire_count_o==1 && !trap_valid_o,"MRET serial boundary");
        head1_valid_i=0; head1_exception_i=0;
        tick(); head0_valid_i=0;
        check(commit_redirect_valid_o && commit_redirect_pc_o==32'h9000,"MRET redirect");
        tick();
        // WFI stops fetch after retirement and wakes with MIE-independent pending.
        head0_valid_i=1; head0_instr_i=32'h10500073; tick(); head0_valid_i=0;
        check(fetch_stop_o,"WFI fetch stop");
        irq_wake_i=1; tick(); irq_wake_i=0; check(!fetch_stop_o,"WFI wake");
        // FENCE.I cannot be split by an interrupt once its D clean is accepted.
        head0_valid_i=1; head0_instr_i=32'h100f; dc_fence_ready_i=1;
        #1; check(dc_fence_valid_o && dc_fence_clean_all_o,"fence clean starts");
        tick(); dc_fence_ready_i=0; irq_pending_i=1; #1;
        check(!trap_valid_o && retire_count_o==0,"fence is indivisible");
        dc_fence_done_i=1; tick(); dc_fence_done_i=0;
        check(ic_inv_valid_o,"invalidate follows D clean");
        ic_inv_ready_i=1; tick(); ic_inv_ready_i=0;
        ic_inv_done_i=1; tick(); ic_inv_done_i=0;
        #1; check(retire_count_o==1,"fence retires after I done");
        tick(); head0_valid_i=0; irq_pending_i=0;
        // Single FP write and FP-to-integer port-zero contention keep a prefix.
        if(FPU_FORMAT!="NONE") begin
            head0_valid_i=1; head1_valid_i=1;
            head0_instr_i=32'h53; head1_instr_i=32'h53;
            head0_dest_i=2; head1_dest_i=2;
            #1; check(retire_count_o==1,"single FP retirement write");
            tick(); check(fp_wb_valid_o && fp_wb_tag_o==0,"registered FP WB");
            head0_instr_i=32'h13; head0_dest_i=1; head1_dest_i=1;
            #1; check(retire_count_o==1,"FP integer write waits for port zero");
            head0_dest_i=0;
            #1; check(32'(retire_count_o)==ISSUE_WIDTH,"FP integer with no old RF write");
            tick();
            if(ISSUE_WIDTH==2) check(wb0_data_o==22 && !wb1_valid_o,"FP integer uses port zero");
        end
        // Old branch redirect suppresses younger retirement immediately.
        head0_instr_i=32'h13; head1_instr_i=32'h13; head0_dest_i=1; head1_dest_i=1;
        head0_valid_i=1;
        branch_redirect_valid_i=1; branch_redirect_tag_i=0;
        #1; check(retire_count_o==1,"branch cancels younger head");
        branch_redirect_valid_i=0;
        head1_valid_i=0; head0_instr_i=32'h6f; head0_next_pc_i=32'hb000;
        tick(); head0_valid_i=0; irq_pending_i=1;
        #1; check(trap_valid_o && trap_pc_o==32'hb000,"empty queue IRQ uses actual branch target");
        // Plain FENCE may be interrupted while draining; FENCE.I above may not.
        irq_pending_i=0; head0_valid_i=1; head0_instr_i=32'h0000000f;
        head0_dest_i=0; dc_fence_ready_i=1; tick(); dc_fence_ready_i=0;
        irq_pending_i=1; #1; check(trap_valid_o && retire_count_o==0,"plain FENCE interrupt");
        finished=1;
    end
endmodule
module tb;
    wire [5:0] finished;
    check_commit #(.ISSUE_WIDTH(1),.FPU_FORMAT("NONE")) u_0(finished[0]);
    check_commit #(.ISSUE_WIDTH(1),.FPU_FORMAT("F")) u_1(finished[1]);
    check_commit #(.ISSUE_WIDTH(1),.FPU_FORMAT("FD")) u_2(finished[2]);
    check_commit #(.ISSUE_WIDTH(2),.FPU_FORMAT("NONE")) u_3(finished[3]);
    check_commit #(.ISSUE_WIDTH(2),.FPU_FORMAT("F")) u_4(finished[4]);
    check_commit #(.ISSUE_WIDTH(2),.FPU_FORMAT("FD")) u_5(finished[5]);
    initial begin wait (&finished); $display("PASS commit six configurations"); $finish; end
endmodule
