// File: tb.sv
// Spec: cpu-v2-testplan CV09/CV10; cpu-v2-spec 3-6.
// Description: Self-check all six fixed configurations. Clock: clk_sys.
// Public-interface CV09/CV10 checks for all six fixed configurations.
module check_csr #(parameter ISSUE_WIDTH=2, parameter [31:0] FPU_FORMAT="NONE")
    (output reg finished);
    localparam N = ISSUE_WIDTH == 2 || FPU_FORMAT == "FD" ? 16 : 8;
    localparam T = ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3;
    localparam B = FPU_FORMAT == "FD" ? 64 : 32;
    reg clk_i;
    reg rst_n_i;
    reg csr_req_valid_i;
    wire csr_req_ready_o;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] csr_req_tag_i;
    reg [31:0] csr_req_instr_i;
    reg [31:0] csr_req_src_i;
    reg csr_commit_valid_i;
    wire csr_complete_valid_o;
    reg csr_complete_ready_i;
    wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] csr_complete_tag_o;
    wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] csr_complete_data_o;
    wire [4:0] csr_complete_flags_o;
    wire csr_complete_exception_o;
    wire [3:0] csr_complete_cause_o;
    wire [31:0] csr_complete_tval_o;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] age_head_i;
    reg cancel_valid_i;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] cancel_tag_i;
    reg fp_commit_flags_valid_i;
    reg [4:0] fp_commit_flags_i;
    reg fp_commit_write_i;
    wire [2:0] csr_frm_o;
    wire [1:0] csr_fs_o;
    reg irq_meip_i;
    reg irq_msip_i;
    reg irq_mtip_i;
    reg [63:0] mtime_i;
    wire irq_pending_o;
    wire [31:0] irq_cause_o;
    wire [31:0] trap_target_o;
    reg mret_valid_i;
    wire [31:0] csr_mepc_o;
    wire irq_wake_o;
    reg trap_valid_i;
    reg [31:0] trap_pc_i;
    reg [31:0] trap_cause_i;
    reg [31:0] trap_tval_i;
    reg [1:0] counter_retire_count_i;
    reg [15:0] hpm_event_i;
    reg [1:0] hpm_branch_count_i;
    edrv32_cpu2_csr #(.ISSUE_WIDTH(ISSUE_WIDTH), .FPU_FORMAT(FPU_FORMAT)) dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .csr_req_valid_i(csr_req_valid_i),
        .csr_req_ready_o(csr_req_ready_o),
        .csr_req_tag_i(csr_req_tag_i),
        .csr_req_instr_i(csr_req_instr_i),
        .csr_req_src_i(csr_req_src_i),
        .csr_commit_valid_i(csr_commit_valid_i),
        .csr_complete_valid_o(csr_complete_valid_o),
        .csr_complete_ready_i(csr_complete_ready_i),
        .csr_complete_tag_o(csr_complete_tag_o),
        .csr_complete_data_o(csr_complete_data_o),
        .csr_complete_flags_o(csr_complete_flags_o),
        .csr_complete_exception_o(csr_complete_exception_o),
        .csr_complete_cause_o(csr_complete_cause_o),
        .csr_complete_tval_o(csr_complete_tval_o),
        .age_head_i(age_head_i),
        .cancel_valid_i(cancel_valid_i),
        .cancel_tag_i(cancel_tag_i),
        .fp_commit_flags_valid_i(fp_commit_flags_valid_i),
        .fp_commit_flags_i(fp_commit_flags_i),
        .fp_commit_write_i(fp_commit_write_i),
        .csr_frm_o(csr_frm_o),
        .csr_fs_o(csr_fs_o),
        .irq_meip_i(irq_meip_i),
        .irq_msip_i(irq_msip_i),
        .irq_mtip_i(irq_mtip_i),
        .mtime_i(mtime_i),
        .irq_pending_o(irq_pending_o),
        .irq_cause_o(irq_cause_o),
        .trap_target_o(trap_target_o),
        .mret_valid_i(mret_valid_i),
        .csr_mepc_o(csr_mepc_o),
        .irq_wake_o(irq_wake_o),
        .trap_valid_i(trap_valid_i),
        .trap_pc_i(trap_pc_i),
        .trap_cause_i(trap_cause_i),
        .trap_tval_i(trap_tval_i),
        .counter_retire_count_i(counter_retire_count_i),
        .hpm_event_i(hpm_event_i),
        .hpm_branch_count_i(hpm_branch_count_i),
        // I06 observation-only outputs.
        .trace_csr_valid_o(),
        .trace_csr_addr_o(),
        .trace_csr_data_o(),
        .trace_fflags_o(),
        .trace_frm_o(),
        .trace_fs_o()
    );
    always #5 clk_i = ~clk_i;
    task tick; begin @(posedge clk_i); #1; end endtask
    task check(input condition, input [511:0] label);
        if (condition !== 1'b1) $fatal(1,"%s expected=1 actual=%b I=%0d F=%s time=%0t",
            label,condition,ISSUE_WIDTH,FPU_FORMAT,$time);
    endtask
    integer k;
    reg [31:0] observed;
    task access_csr(input [31:0] instr, input [31:0] src);
        begin
            csr_req_valid_i=1; csr_req_instr_i=instr; csr_req_src_i=src;
            tick(); csr_req_valid_i=0;
            check(csr_complete_valid_o && !csr_complete_exception_o,"write response");
            csr_complete_ready_i=1; tick(); csr_complete_ready_i=0;
            // The request bus changes while the saved command and source await retirement.
            csr_req_instr_i=0; csr_req_src_i=32'hfeed1234;
            csr_commit_valid_i=1; tick(); csr_commit_valid_i=0;
        end
    endtask
    task write_csr(input [11:0] addr, input [31:0] value);
        access_csr({addr,5'd1,3'b001,5'd0,7'h73},value);
    endtask
    task read_csr(input [11:0] addr, input illegal, input [31:0] expected);
        begin
            csr_req_valid_i=1; csr_req_instr_i={addr,5'd0,3'b010,5'd1,7'h73};
            #1; check(csr_req_ready_o,"CSR request ready"); tick(); csr_req_valid_i=0;
            check(csr_complete_valid_o,"CSR response capture latency");
            check(csr_complete_exception_o==illegal,"CSR permission");
            if(!illegal && csr_complete_data_o !== B'(expected))
                $fatal(1,"CSR %h expected=%h actual=%h I=%0d F=%h time=%0t",
                    addr,expected,csr_complete_data_o,ISSUE_WIDTH,FPU_FORMAT,$time);
            csr_complete_ready_i=1; tick(); csr_complete_ready_i=0;
        end
    endtask
    // CSR read-modify-write must use the same old value returned to rd.
    task modify_counter;
        begin
            write_csr(12'h320,32'hffffffff);
            write_csr(12'hb00,100);
            write_csr(12'h320,0);
            csr_req_valid_i=1;
            csr_req_instr_i={12'hb00,5'd1,3'b010,5'd1,7'h73};
            csr_req_src_i=128;
            tick(); csr_req_valid_i=0; tick();
            check(csr_complete_valid_o && csr_complete_data_o==100,"counter old value");
            csr_complete_ready_i=1; tick(); csr_complete_ready_i=0;
            repeat(3) tick();
            csr_commit_valid_i=1;
            csr_req_instr_i=0; csr_req_src_i=0;
            tick(); csr_commit_valid_i=0;
            read_csr(12'hc00,0,228);
            write_csr(12'h320,32'hffffffff);
        end
    endtask
    initial begin
        finished=0;
        clk_i='0;
        rst_n_i='0;
        csr_req_valid_i='0;
        csr_req_tag_i='0;
        csr_req_instr_i='0;
        csr_req_src_i='0;
        csr_commit_valid_i='0;
        csr_complete_ready_i='0;
        age_head_i='0;
        cancel_valid_i='0;
        cancel_tag_i='0;
        fp_commit_flags_valid_i='0;
        fp_commit_flags_i='0;
        fp_commit_write_i='0;
        irq_meip_i='0;
        irq_msip_i='0;
        irq_mtip_i='0;
        mtime_i='0;
        mret_valid_i='0;
        trap_valid_i='0;
        trap_pc_i='0;
        trap_cause_i='0;
        trap_tval_i='0;
        counter_retire_count_i='0;
        hpm_event_i='0;
        hpm_branch_count_i='0;
        tick(); rst_n_i=1; tick();
        // I06: FENCE.I shares the ordered system request channel, not CSR permission.
        access_csr(32'h0000100f, 32'b0);
        read_csr(12'h300,0,32'h1800);
        read_csr(12'h001,1,0);
        read_csr(12'h301,0,32'h40001100 | (FPU_FORMAT=="NONE" ? 0:32'h20) |
            (FPU_FORMAT=="FD" ? 32'h8:0));
        read_csr(12'h999,1,0);
        write_csr(12'h305,32'h1234567b); read_csr(12'h305,0,32'h12345678);
        write_csr(12'h341,32'h123); read_csr(12'h341,0,32'h120);
        write_csr(12'h340,32'h2468); read_csr(12'h340,0,32'h2468);
        write_csr(12'h301,0); read_csr(12'h301,0,32'h40001100 |
            (FPU_FORMAT=="NONE" ? 0:32'h20) | (FPU_FORMAT=="FD" ? 32'h8:0));
        write_csr(12'h320,32'hffffffff);
        read_csr(12'h320,0,ISSUE_WIDTH==1 ? 32'h1d:32'h7fd);
        write_csr(12'hb00,32'hffffffff); write_csr(12'hb80,7);
        read_csr(12'hc00,0,32'hffffffff); read_csr(12'hc80,0,7);
        write_csr(12'hb02,55); read_csr(12'hc02,0,55);
        for(k=0;k<(ISSUE_WIDTH==1 ? 2:8);k=k+1) begin
            write_csr(12'(32'h323+k),5); read_csr(12'(32'h323+k),0,5);
            write_csr(12'(32'hb03+k),32'(100+k));
            write_csr(12'(32'hb83+k),32'(200+k));
            read_csr(12'(32'hc03+k),0,32'(100+k));
            read_csr(12'(32'hc83+k),0,32'(200+k));
        end
        if(ISSUE_WIDTH==1) begin
            read_csr(12'h325,1,0); read_csr(12'hb05,1,0); read_csr(12'hc85,1,0);
        end
        mtime_i=64'h123456789abcdef0;
        read_csr(12'hc01,0,32'h9abcdef0); read_csr(12'hc81,0,32'h12345678);
        // HPM pair reasons are delayed and use 5>6>7>8 priority.
        write_csr(12'hb03,0); write_csr(12'h323,5); write_csr(12'h320,0);
        hpm_event_i=16'h00f0; tick(); hpm_event_i=0; tick();
        write_csr(12'h320,32'hffffffff); read_csr(12'hc03,0,1);
        write_csr(12'h323,4); write_csr(12'hb03,0); write_csr(12'h320,0);
        hpm_branch_count_i=2'(ISSUE_WIDTH); tick(); hpm_branch_count_i=0; tick();
        write_csr(12'h320,32'hffffffff); read_csr(12'hc03,0,32'(ISSUE_WIDTH));
        for(k=1;k<=16;k=k+1) begin
            write_csr(12'h323,32'(k)); write_csr(12'hb03,0); write_csr(12'h320,0);
            hpm_event_i=16'(1 << (k-1)); hpm_branch_count_i=2'(k==4 ? 1:0);
            tick(); hpm_event_i=0; hpm_branch_count_i=0; tick();
            write_csr(12'h320,32'hffffffff); read_csr(12'hc03,0,1);
        end
        read_csr(12'hf11,0,0); read_csr(12'hf12,0,0);
        read_csr(12'hf13,0,0); read_csr(12'hf14,0,0); read_csr(12'h344,0,0);
        write_csr(12'h304,32'hffffffff); read_csr(12'h304,0,32'h888);
        // Set/clear and immediate operations use the captured source and uimm.
        write_csr(12'h340,32'h10); read_csr(12'h340,0,32'h10);
        access_csr({12'h340,5'd1,3'b010,5'd0,7'h73},3); read_csr(12'h340,0,32'h13);
        access_csr({12'h340,5'd1,3'b011,5'd0,7'h73},1); read_csr(12'h340,0,32'h12);
        access_csr({12'h340,5'd7,3'b101,5'd0,7'h73},32'hffff); read_csr(12'h340,0,7);
        // Software writes win over simultaneous counter increments.
        write_csr(12'h320,0); write_csr(12'hb00,99); read_csr(12'hc00,0,99);
        counter_retire_count_i=2'(ISSUE_WIDTH);
        write_csr(12'hb02,99); read_csr(12'hc02,0,99); counter_retire_count_i=0;
        write_csr(12'h320,32'hffffffff);
        modify_counter();
        // FP aliases and precise Dirty transitions, including unchanged actual writes.
        write_csr(12'h300,32'h2000);
        if(FPU_FORMAT!="NONE") begin
            read_csr(12'h003,0,0); write_csr(12'h002,7);
            read_csr(12'h003,0,32'he0); read_csr(12'h300,0,32'h80007800);
            write_csr(12'h300,32'h4000); read_csr(12'h002,0,7);
            read_csr(12'h300,0,32'h5800);
            fp_commit_flags_valid_i=1; fp_commit_flags_i=1; tick();
            fp_commit_flags_valid_i=0;
            read_csr(12'h001,0,1); read_csr(12'h300,0,32'h80007800);
            write_csr(12'h003,32'h43); read_csr(12'h001,0,3); read_csr(12'h002,0,2);
            write_csr(12'h300,32'h4000); fp_commit_write_i=1; tick(); fp_commit_write_i=0;
            read_csr(12'h300,0,32'h80007800);
        end else begin read_csr(12'h300,0,32'h1800); read_csr(12'h003,1,0); end
        // MIE-independent wake, external/software/timer priority, vectored target.
        write_csr(12'h300,0); write_csr(12'h304,32'h888);
        irq_meip_i=1; irq_msip_i=1; irq_mtip_i=1;
        #1; check(irq_wake_o && !irq_pending_o,"WFI wake ignores MIE");
        write_csr(12'h300,8); #1;
        check(irq_pending_o && irq_cause_o==32'h8000000b,"external interrupt priority");
        irq_meip_i=0; #1; check(irq_cause_o==32'h80000003,"software priority");
        irq_msip_i=0; #1; check(irq_cause_o==32'h80000007,"timer priority");
        write_csr(12'h305,32'h101); trap_cause_i=32'h80000007;
        #1; check(trap_target_o==32'h11c,"vectored interrupt target");
        trap_valid_i=1; trap_pc_i=32'habc; trap_tval_i=32'hdef; tick(); trap_valid_i=0;
        read_csr(12'h341,0,32'habc); read_csr(12'h342,0,32'h80000007);
        read_csr(12'h343,0,32'hdef); check(!irq_pending_o,"trap clears MIE");
        mret_valid_i=1; tick(); mret_valid_i=0; #1; check(irq_pending_o,"MRET restores MIE");
        trap_valid_i=1; mret_valid_i=1; tick(); trap_valid_i=0; mret_valid_i=0;
        #1; check(!irq_pending_o,"trap wins MRET");
        // RO writes become illegal result records; cancellation removes held records.
        csr_req_valid_i=1; csr_req_instr_i={12'hc00,5'd1,3'b001,5'd0,7'h73};
        tick(); csr_req_valid_i=0; tick(); check(csr_complete_exception_o,"read-only write illegal");
        cancel_valid_i=1; cancel_tag_i=0; tick(); cancel_valid_i=0;
        check(!csr_complete_valid_o,"held CSR cancellation");
        finished=1;
    end
endmodule
module tb;
    wire [5:0] finished;
    check_csr #(.ISSUE_WIDTH(1),.FPU_FORMAT("NONE")) u_0(finished[0]);
    check_csr #(.ISSUE_WIDTH(1),.FPU_FORMAT("F")) u_1(finished[1]);
    check_csr #(.ISSUE_WIDTH(1),.FPU_FORMAT("FD")) u_2(finished[2]);
    check_csr #(.ISSUE_WIDTH(2),.FPU_FORMAT("NONE")) u_3(finished[3]);
    check_csr #(.ISSUE_WIDTH(2),.FPU_FORMAT("F")) u_4(finished[4]);
    check_csr #(.ISSUE_WIDTH(2),.FPU_FORMAT("FD")) u_5(finished[5]);
    initial begin wait (&finished); $display("PASS csr six configurations"); $finish; end
endmodule
