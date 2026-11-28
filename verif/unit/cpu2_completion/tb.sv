// File: tb.sv
// Spec: cpu-v2-testplan CV09/CV10; cpu-v2-spec 3-6.
// Description: Self-check all six fixed configurations. Clock: clk_sys.
// Public-interface CV09/CV10 checks for all six fixed configurations.
module check_completion #(parameter ISSUE_WIDTH=2, parameter [31:0] FPU_FORMAT="NONE")
    (output reg finished);
    localparam N = FPU_FORMAT == "FD" ? 16 : FPU_FORMAT == "F" ? 8 : 4;
    localparam T = FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2;
    localparam B = FPU_FORMAT == "FD" ? 64 : 32;
    reg clk_i;
    reg rst_n_i;
    reg allocate_valid_i;
    reg [1:0] allocate_count_i;
    wire allocate_ready_o;
    wire [(FPU_FORMAT == "FD" ? 5 : FPU_FORMAT == "F" ? 4 : 3)-1:0] allocate_credit_o;
    reg [1:0] retire_count_i;
    reg commit_cancel_valid_i;
    reg [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] commit_cancel_tag_i;
    reg branch_redirect_valid_i;
    reg [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] branch_redirect_tag_i;
    reg [31:0] branch_redirect_pc_i;
    wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] age_head_o;
    wire cancel_valid_o;
    wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] cancel_tag_o;
    reg [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] allocate0_tag_i;
    reg [31:0] allocate0_pc_i;
    reg [31:0] allocate0_instr_i;
    reg [4:0] allocate0_rd_i;
    reg [1:0] allocate0_dest_i;
    reg [31:0] allocate0_csr_src_i;
    reg allocate0_store_i;
    reg allocate0_divide_i;
    reg allocate0_double_beat_i;
    wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] head0_tag_o;
    wire [31:0] head0_pc_o;
    wire [31:0] head0_next_pc_o;
    wire [31:0] head0_instr_o;
    wire [4:0] head0_rd_o;
    wire [1:0] head0_dest_o;
    wire [31:0] head0_csr_src_o;
    wire head0_store_o;
    wire head0_divide_o;
    wire head0_double_beat_o;
    wire head0_valid_o;
    wire head0_done_o;
    wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] head0_data_o;
    wire [4:0] head0_flags_o;
    wire head0_exception_o;
    wire [3:0] head0_cause_o;
    wire [31:0] head0_tval_o;
    wire head0_device_o;
    wire [31:0] head0_mem_addr_o;
    wire [63:0] head0_mem_data_o;
    wire [7:0] head0_mem_mask_o;
    reg [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] allocate1_tag_i;
    reg [31:0] allocate1_pc_i;
    reg [31:0] allocate1_instr_i;
    reg [4:0] allocate1_rd_i;
    reg [1:0] allocate1_dest_i;
    reg [31:0] allocate1_csr_src_i;
    reg allocate1_store_i;
    reg allocate1_divide_i;
    reg allocate1_double_beat_i;
    wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] head1_tag_o;
    wire [31:0] head1_pc_o;
    wire [31:0] head1_next_pc_o;
    wire [31:0] head1_instr_o;
    wire [4:0] head1_rd_o;
    wire [1:0] head1_dest_o;
    wire [31:0] head1_csr_src_o;
    wire head1_store_o;
    wire head1_divide_o;
    wire head1_double_beat_o;
    wire head1_valid_o;
    wire head1_done_o;
    wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] head1_data_o;
    wire [4:0] head1_flags_o;
    wire head1_exception_o;
    wire [3:0] head1_cause_o;
    wire [31:0] head1_tval_o;
    wire head1_device_o;
    wire [31:0] head1_mem_addr_o;
    wire [63:0] head1_mem_data_o;
    wire [7:0] head1_mem_mask_o;
    reg [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] source0_tag_i;
    reg source0_valid_i;
    reg source0_domain_i;
    wire source0_ready_o;
    wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] source0_data_o;
    reg [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] source1_tag_i;
    reg source1_valid_i;
    reg source1_domain_i;
    wire source1_ready_o;
    wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] source1_data_o;
    reg [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] source2_tag_i;
    reg source2_valid_i;
    reg source2_domain_i;
    wire source2_ready_o;
    wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] source2_data_o;
    reg [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] source3_tag_i;
    reg source3_valid_i;
    reg source3_domain_i;
    wire source3_ready_o;
    wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] source3_data_o;
    reg [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] source4_tag_i;
    reg source4_valid_i;
    reg source4_domain_i;
    wire source4_ready_o;
    wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] source4_data_o;
    reg alu0_complete_valid_i;
    reg [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] alu0_complete_tag_i;
    reg [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] alu0_complete_data_i;
    reg [4:0] alu0_complete_flags_i;
    reg alu0_complete_exception_i;
    reg [3:0] alu0_complete_cause_i;
    reg [31:0] alu0_complete_tval_i;
    wire alu0_complete_ready_o;
    reg alu1_complete_valid_i;
    reg [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] alu1_complete_tag_i;
    reg [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] alu1_complete_data_i;
    reg [4:0] alu1_complete_flags_i;
    reg alu1_complete_exception_i;
    reg [3:0] alu1_complete_cause_i;
    reg [31:0] alu1_complete_tval_i;
    wire alu1_complete_ready_o;
    reg [31:0] branch_complete_next_pc_i;
    reg branch_complete_valid_i;
    reg [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] branch_complete_tag_i;
    reg [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] branch_complete_data_i;
    reg [4:0] branch_complete_flags_i;
    reg branch_complete_exception_i;
    reg [3:0] branch_complete_cause_i;
    reg [31:0] branch_complete_tval_i;
    wire branch_complete_ready_o;
    reg mul_complete_valid_i;
    reg [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] mul_complete_tag_i;
    reg [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] mul_complete_data_i;
    reg [4:0] mul_complete_flags_i;
    reg mul_complete_exception_i;
    reg [3:0] mul_complete_cause_i;
    reg [31:0] mul_complete_tval_i;
    wire mul_complete_ready_o;
    reg div_complete_valid_i;
    reg [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] div_complete_tag_i;
    reg [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] div_complete_data_i;
    reg [4:0] div_complete_flags_i;
    reg div_complete_exception_i;
    reg [3:0] div_complete_cause_i;
    reg [31:0] div_complete_tval_i;
    wire div_complete_ready_o;
    reg lsu_complete_valid_i;
    reg [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] lsu_complete_tag_i;
    reg [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] lsu_complete_data_i;
    reg [4:0] lsu_complete_flags_i;
    reg lsu_complete_exception_i;
    reg [3:0] lsu_complete_cause_i;
    reg [31:0] lsu_complete_tval_i;
    wire lsu_complete_ready_o;
    reg csr_complete_valid_i;
    reg [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] csr_complete_tag_i;
    reg [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] csr_complete_data_i;
    reg [4:0] csr_complete_flags_i;
    reg csr_complete_exception_i;
    reg [3:0] csr_complete_cause_i;
    reg [31:0] csr_complete_tval_i;
    wire csr_complete_ready_o;
    reg fp_resp_valid_i;
    reg [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] fp_resp_tag_i;
    reg [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] fp_resp_data_i;
    reg [4:0] fp_resp_flags_i;
    wire fp_resp_ready_o;
    reg decode_complete_valid_i;
    reg [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] decode_complete_tag_i;
    reg decode_complete_exception_i;
    reg [3:0] decode_complete_cause_i;
    reg [31:0] decode_complete_tval_i;
    wire decode_complete_ready_o;
    reg fp_resp_int_dest_i;
    reg lsu_complete_device_i;
    reg [31:0] lsu_complete_mem_addr_i;
    reg [63:0] lsu_complete_mem_data_i;
    reg [7:0] lsu_complete_mem_mask_i;
    edrv32_cpu2_completion #(.ISSUE_WIDTH(ISSUE_WIDTH), .FPU_FORMAT(FPU_FORMAT)) dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .allocate_valid_i(allocate_valid_i),
        .allocate_count_i(allocate_count_i),
        .allocate_ready_o(allocate_ready_o),
        .allocate_credit_o(allocate_credit_o),
        .retire_count_i(retire_count_i),
        .commit_cancel_valid_i(commit_cancel_valid_i),
        .commit_cancel_tag_i(commit_cancel_tag_i),
        .branch_redirect_valid_i(branch_redirect_valid_i),
        .branch_redirect_tag_i(branch_redirect_tag_i),
        .branch_redirect_pc_i(branch_redirect_pc_i),
        .age_head_o(age_head_o),
        .cancel_valid_o(cancel_valid_o),
        .cancel_tag_o(cancel_tag_o),
        .allocate0_tag_i(allocate0_tag_i),
        .allocate0_pc_i(allocate0_pc_i),
        .allocate0_instr_i(allocate0_instr_i),
        .allocate0_rd_i(allocate0_rd_i),
        .allocate0_dest_i(allocate0_dest_i),
        .allocate0_csr_src_i(allocate0_csr_src_i),
        .allocate0_store_i(allocate0_store_i),
        .allocate0_divide_i(allocate0_divide_i),
        .allocate0_double_beat_i(allocate0_double_beat_i),
        .head0_tag_o(head0_tag_o),
        .head0_pc_o(head0_pc_o),
        .head0_next_pc_o(head0_next_pc_o),
        .head0_instr_o(head0_instr_o),
        .head0_rd_o(head0_rd_o),
        .head0_dest_o(head0_dest_o),
        .head0_csr_src_o(head0_csr_src_o),
        .head0_store_o(head0_store_o),
        .head0_divide_o(head0_divide_o),
        .head0_double_beat_o(head0_double_beat_o),
        .head0_valid_o(head0_valid_o),
        .head0_done_o(head0_done_o),
        .head0_data_o(head0_data_o),
        .head0_flags_o(head0_flags_o),
        .head0_exception_o(head0_exception_o),
        .head0_cause_o(head0_cause_o),
        .head0_tval_o(head0_tval_o),
        .head0_device_o(head0_device_o),
        .head0_mem_addr_o(head0_mem_addr_o),
        .head0_mem_data_o(head0_mem_data_o),
        .head0_mem_mask_o(head0_mem_mask_o),
        .allocate1_tag_i(allocate1_tag_i),
        .allocate1_pc_i(allocate1_pc_i),
        .allocate1_instr_i(allocate1_instr_i),
        .allocate1_rd_i(allocate1_rd_i),
        .allocate1_dest_i(allocate1_dest_i),
        .allocate1_csr_src_i(allocate1_csr_src_i),
        .allocate1_store_i(allocate1_store_i),
        .allocate1_divide_i(allocate1_divide_i),
        .allocate1_double_beat_i(allocate1_double_beat_i),
        .head1_tag_o(head1_tag_o),
        .head1_pc_o(head1_pc_o),
        .head1_next_pc_o(head1_next_pc_o),
        .head1_instr_o(head1_instr_o),
        .head1_rd_o(head1_rd_o),
        .head1_dest_o(head1_dest_o),
        .head1_csr_src_o(head1_csr_src_o),
        .head1_store_o(head1_store_o),
        .head1_divide_o(head1_divide_o),
        .head1_double_beat_o(head1_double_beat_o),
        .head1_valid_o(head1_valid_o),
        .head1_done_o(head1_done_o),
        .head1_data_o(head1_data_o),
        .head1_flags_o(head1_flags_o),
        .head1_exception_o(head1_exception_o),
        .head1_cause_o(head1_cause_o),
        .head1_tval_o(head1_tval_o),
        .head1_device_o(head1_device_o),
        .head1_mem_addr_o(head1_mem_addr_o),
        .head1_mem_data_o(head1_mem_data_o),
        .head1_mem_mask_o(head1_mem_mask_o),
        .source0_tag_i(source0_tag_i),
        .source0_valid_i(source0_valid_i),
        .source0_domain_i(source0_domain_i),
        .source0_ready_o(source0_ready_o),
        .source0_data_o(source0_data_o),
        .source1_tag_i(source1_tag_i),
        .source1_valid_i(source1_valid_i),
        .source1_domain_i(source1_domain_i),
        .source1_ready_o(source1_ready_o),
        .source1_data_o(source1_data_o),
        .source2_tag_i(source2_tag_i),
        .source2_valid_i(source2_valid_i),
        .source2_domain_i(source2_domain_i),
        .source2_ready_o(source2_ready_o),
        .source2_data_o(source2_data_o),
        .source3_tag_i(source3_tag_i),
        .source3_valid_i(source3_valid_i),
        .source3_domain_i(source3_domain_i),
        .source3_ready_o(source3_ready_o),
        .source3_data_o(source3_data_o),
        .source4_tag_i(source4_tag_i),
        .source4_valid_i(source4_valid_i),
        .source4_domain_i(source4_domain_i),
        .source4_ready_o(source4_ready_o),
        .source4_data_o(source4_data_o),
        .alu0_complete_valid_i(alu0_complete_valid_i),
        .alu0_complete_tag_i(alu0_complete_tag_i),
        .alu0_complete_data_i(alu0_complete_data_i),
        .alu0_complete_flags_i(alu0_complete_flags_i),
        .alu0_complete_exception_i(alu0_complete_exception_i),
        .alu0_complete_cause_i(alu0_complete_cause_i),
        .alu0_complete_tval_i(alu0_complete_tval_i),
        .alu0_complete_ready_o(alu0_complete_ready_o),
        .alu1_complete_valid_i(alu1_complete_valid_i),
        .alu1_complete_tag_i(alu1_complete_tag_i),
        .alu1_complete_data_i(alu1_complete_data_i),
        .alu1_complete_flags_i(alu1_complete_flags_i),
        .alu1_complete_exception_i(alu1_complete_exception_i),
        .alu1_complete_cause_i(alu1_complete_cause_i),
        .alu1_complete_tval_i(alu1_complete_tval_i),
        .alu1_complete_ready_o(alu1_complete_ready_o),
        .branch_complete_next_pc_i(branch_complete_next_pc_i),
        .branch_complete_valid_i(branch_complete_valid_i),
        .branch_complete_tag_i(branch_complete_tag_i),
        .branch_complete_data_i(branch_complete_data_i),
        .branch_complete_flags_i(branch_complete_flags_i),
        .branch_complete_exception_i(branch_complete_exception_i),
        .branch_complete_cause_i(branch_complete_cause_i),
        .branch_complete_tval_i(branch_complete_tval_i),
        .branch_complete_ready_o(branch_complete_ready_o),
        .mul_complete_valid_i(mul_complete_valid_i),
        .mul_complete_tag_i(mul_complete_tag_i),
        .mul_complete_data_i(mul_complete_data_i),
        .mul_complete_flags_i(mul_complete_flags_i),
        .mul_complete_exception_i(mul_complete_exception_i),
        .mul_complete_cause_i(mul_complete_cause_i),
        .mul_complete_tval_i(mul_complete_tval_i),
        .mul_complete_ready_o(mul_complete_ready_o),
        .div_complete_valid_i(div_complete_valid_i),
        .div_complete_tag_i(div_complete_tag_i),
        .div_complete_data_i(div_complete_data_i),
        .div_complete_flags_i(div_complete_flags_i),
        .div_complete_exception_i(div_complete_exception_i),
        .div_complete_cause_i(div_complete_cause_i),
        .div_complete_tval_i(div_complete_tval_i),
        .div_complete_ready_o(div_complete_ready_o),
        .lsu_complete_valid_i(lsu_complete_valid_i),
        .lsu_complete_tag_i(lsu_complete_tag_i),
        .lsu_complete_data_i(lsu_complete_data_i),
        .lsu_complete_flags_i(lsu_complete_flags_i),
        .lsu_complete_exception_i(lsu_complete_exception_i),
        .lsu_complete_cause_i(lsu_complete_cause_i),
        .lsu_complete_tval_i(lsu_complete_tval_i),
        .lsu_complete_ready_o(lsu_complete_ready_o),
        .csr_complete_valid_i(csr_complete_valid_i),
        .csr_complete_tag_i(csr_complete_tag_i),
        .csr_complete_data_i(csr_complete_data_i),
        .csr_complete_flags_i(csr_complete_flags_i),
        .csr_complete_exception_i(csr_complete_exception_i),
        .csr_complete_cause_i(csr_complete_cause_i),
        .csr_complete_tval_i(csr_complete_tval_i),
        .csr_complete_ready_o(csr_complete_ready_o),
        .fp_resp_valid_i(fp_resp_valid_i),
        .fp_resp_tag_i(fp_resp_tag_i),
        .fp_resp_data_i(fp_resp_data_i),
        .fp_resp_flags_i(fp_resp_flags_i),
        .fp_resp_ready_o(fp_resp_ready_o),
        .decode_complete_valid_i(decode_complete_valid_i),
        .decode_complete_tag_i(decode_complete_tag_i),
        .decode_complete_exception_i(decode_complete_exception_i),
        .decode_complete_cause_i(decode_complete_cause_i),
        .decode_complete_tval_i(decode_complete_tval_i),
        .decode_complete_ready_o(decode_complete_ready_o),
        .fp_resp_int_dest_i(fp_resp_int_dest_i),
        .lsu_complete_device_i(lsu_complete_device_i),
        .lsu_complete_mem_addr_i(lsu_complete_mem_addr_i),
        .lsu_complete_mem_data_i(lsu_complete_mem_data_i),
        .lsu_complete_mem_mask_i(lsu_complete_mem_mask_i)
    );
    always #5 clk_i = ~clk_i;
    task tick; begin @(posedge clk_i); #1; end endtask
    task check(input condition, input [511:0] label);
        if (condition !== 1'b1) $fatal(1,"%s expected=1 actual=%b I=%0d F=%s time=%0t",
            label,condition,ISSUE_WIDTH,FPU_FORMAT,$time);
    endtask
    integer q;
    integer old_head;
    task allocate_one(input integer tagnum, input [1:0] dest);
        begin
            allocate_valid_i=1; allocate_count_i=1;
            allocate0_tag_i=T'(tagnum); allocate0_pc_i=32'h1000+32'(tagnum)*4;
            allocate0_instr_i=32'h13; allocate0_rd_i=5'(tagnum); allocate0_dest_i=dest;
            #1; check(allocate_ready_o,"allocate ready"); tick(); allocate_valid_i=0;
        end
    endtask
    task reset_queue;
        begin
            rst_n_i=0; allocate_valid_i=0; retire_count_i=0;
            alu0_complete_valid_i=0; mul_complete_valid_i=0; branch_complete_valid_i=0;
            fp_resp_valid_i=0; lsu_complete_valid_i=0;
            commit_cancel_valid_i=0; branch_redirect_valid_i=0;
            tick(); rst_n_i=1; tick();
        end
    endtask
    reg [N-1:0] model_valid;
    reg [N-1:0] model_done;
    reg [31:0] model_pc [0:N-1];
    reg [B-1:0] model_data [0:N-1];
    reg [1:0] model_dest [0:N-1];
    reg [31:0] random_state;
    integer model_head;
    integer model_tail;
    integer model_count;
    integer pending0;
    integer pending1;
    integer cycle_index;
    integer candidate;
    integer scan;
    integer added;
    integer removed;
    integer serial;
    integer completed_total;
    integer dual_total;
    integer held_total;
    reg expected0;
    reg expected1;
    task next_random;
        begin
            random_state=random_state ^ (random_state << 13);
            random_state=random_state ^ (random_state >> 17);
            random_state=random_state ^ (random_state << 5);
        end
    endtask
    task random_queue;
        begin
            reset_queue();
            model_valid=0; model_done=0; model_head=0; model_tail=0; model_count=0;
            pending0=-1; pending1=-1; serial=0;
            completed_total=0; dual_total=0; held_total=0;
            random_state=32'h93a71e5b;
            for(cycle_index=0;cycle_index<1000;cycle_index=cycle_index+1) begin
                next_random();
                added=0;
                if(random_state[0] && model_count<N) begin
                    added=(ISSUE_WIDTH==2 && random_state[1] && model_count<N-1) ? 2:1;
                    allocate_valid_i=1; allocate_count_i=2'(added);
                    allocate0_tag_i=T'(model_tail); allocate1_tag_i=T'((model_tail+1)%N);
                    allocate0_pc_i=32'h8000+32'(serial)*4;
                    allocate1_pc_i=32'h8004+32'(serial)*4;
                    allocate0_dest_i=1;
                    allocate1_dest_i=1;
                end else begin allocate_valid_i=0; allocate_count_i=1; end
                if(pending0<0) begin
                    next_random();
                    for(scan=0;scan<N;scan=scan+1) begin
                        candidate=(int'(random_state[T-1:0])+scan)%N;
                        if(pending0<0 && random_state[0] && model_valid[candidate] && !model_done[candidate] &&
                            candidate!=pending1) pending0=candidate;
                    end
                end
                if(pending1<0) begin
                    next_random();
                    for(scan=0;scan<N;scan=scan+1) begin
                        candidate=(int'(random_state[T-1:0])+scan)%N;
                        if(pending1<0 && random_state[1] && model_valid[candidate] && !model_done[candidate] &&
                            candidate!=pending0) pending1=candidate;
                    end
                end
                alu0_complete_valid_i=pending0>=0;
                mul_complete_valid_i=pending1>=0;
                if(pending0>=0) begin
                    alu0_complete_tag_i=T'(pending0); alu0_complete_data_i=model_data[pending0];
                end
                if(pending1>=0) begin
                    mul_complete_tag_i=T'(pending1); mul_complete_data_i=model_data[pending1];
                end
                expected0=1; expected1=1;
                if(FPU_FORMAT!="NONE" && pending0>=0 && pending1>=0 &&
                    ((pending0%2)==(pending1%2) ||
                    (model_dest[pending0]==2 && model_dest[pending1]==2))) begin
                    expected0=((pending0-model_head+N)%N)<((pending1-model_head+N)%N);
                    expected1=!expected0;
                end
                removed=0;
                next_random();
                if(model_count>0 && model_done[model_head] && random_state[0]) begin
                    removed=1;
                    if(ISSUE_WIDTH==2 && model_count>1 && model_done[(model_head+1)%N] &&
                        !(model_dest[model_head]==2 && model_dest[(model_head+1)%N]==2) &&
                        random_state[1]) removed=2;
                end
                retire_count_i=2'(removed);
                next_random(); source0_valid_i=1; source0_tag_i=random_state[T-1:0];
                #1;
                check(32'(allocate_credit_o)==N-model_count,"random occupancy credit");
                if(pending0>=0) check(alu0_complete_ready_o==expected0,"random oldest grant 0");
                if(pending1>=0) check(mul_complete_ready_o==expected1,"random oldest grant 1");
                check(source0_ready_o==(model_valid[source0_tag_i] && model_done[source0_tag_i]),
                    "random arbitrary forwarding readiness");
                if(source0_ready_o) check(source0_data_o==model_data[source0_tag_i],
                    "random arbitrary forwarding value");
                check(head0_valid_o==(model_count>0),"random head valid");
                if(model_count>0) begin
                    check(head0_tag_o==T'(model_head) && head0_pc_o==model_pc[model_head],
                        "random ordered head");
                    check(head0_done_o==model_done[model_head],"random head done");
                    if(model_done[model_head]) check(head0_data_o==model_data[model_head],
                        "random captured head data");
                end
                tick();
                if(removed==2) dual_total=dual_total+1;
                for(scan=0;scan<removed;scan=scan+1)
                    model_valid[(model_head+scan)%N]=0;
                model_head=(model_head+removed)%N;
                if(pending0>=0 && expected0) begin
                    model_done[pending0]=1; pending0=-1; completed_total=completed_total+1;
                end else if(pending0>=0) held_total=held_total+1;
                if(pending1>=0 && expected1) begin
                    model_done[pending1]=1; pending1=-1; completed_total=completed_total+1;
                end else if(pending1>=0) held_total=held_total+1;
                for(scan=0;scan<added;scan=scan+1) begin
                    candidate=(model_tail+scan)%N;
                    model_valid[candidate]=1; model_done[candidate]=0;
                    model_pc[candidate]=32'h8000+32'(serial+scan)*4;
                    model_data[candidate]=B'(32'h20000+32'(serial+scan));
                    model_dest[candidate]=(scan==0) ? allocate0_dest_i:allocate1_dest_i;
                end
                serial=serial+added; model_tail=(model_tail+added)%N;
                model_count=model_count+added-removed;
            end
            check(completed_total>100,"random queue keeps progressing");
            if(ISSUE_WIDTH==2) check(dual_total>0,"random dual retirement covered");
            if(FPU_FORMAT!="NONE") check(held_total>0,"random completion backpressure covered");
            reset_queue();
        end
    endtask
    initial begin
        finished=0;
        clk_i='0;
        rst_n_i='0;
        allocate_valid_i='0;
        allocate_count_i='0;
        retire_count_i='0;
        commit_cancel_valid_i='0;
        commit_cancel_tag_i='0;
        branch_redirect_valid_i='0;
        branch_redirect_tag_i='0;
        branch_redirect_pc_i='0;
        allocate0_tag_i='0;
        allocate0_pc_i='0;
        allocate0_instr_i='0;
        allocate0_rd_i='0;
        allocate0_dest_i='0;
        allocate0_csr_src_i='0;
        allocate0_store_i='0;
        allocate0_divide_i='0;
        allocate0_double_beat_i='0;
        allocate1_tag_i='0;
        allocate1_pc_i='0;
        allocate1_instr_i='0;
        allocate1_rd_i='0;
        allocate1_dest_i='0;
        allocate1_csr_src_i='0;
        allocate1_store_i='0;
        allocate1_divide_i='0;
        allocate1_double_beat_i='0;
        source0_tag_i='0;
        source0_valid_i='0;
        source0_domain_i='0;
        source1_tag_i='0;
        source1_valid_i='0;
        source1_domain_i='0;
        source2_tag_i='0;
        source2_valid_i='0;
        source2_domain_i='0;
        source3_tag_i='0;
        source3_valid_i='0;
        source3_domain_i='0;
        source4_tag_i='0;
        source4_valid_i='0;
        source4_domain_i='0;
        alu0_complete_valid_i='0;
        alu0_complete_tag_i='0;
        alu0_complete_data_i='0;
        alu0_complete_flags_i='0;
        alu0_complete_exception_i='0;
        alu0_complete_cause_i='0;
        alu0_complete_tval_i='0;
        alu1_complete_valid_i='0;
        alu1_complete_tag_i='0;
        alu1_complete_data_i='0;
        alu1_complete_flags_i='0;
        alu1_complete_exception_i='0;
        alu1_complete_cause_i='0;
        alu1_complete_tval_i='0;
        branch_complete_next_pc_i='0;
        branch_complete_valid_i='0;
        branch_complete_tag_i='0;
        branch_complete_data_i='0;
        branch_complete_flags_i='0;
        branch_complete_exception_i='0;
        branch_complete_cause_i='0;
        branch_complete_tval_i='0;
        mul_complete_valid_i='0;
        mul_complete_tag_i='0;
        mul_complete_data_i='0;
        mul_complete_flags_i='0;
        mul_complete_exception_i='0;
        mul_complete_cause_i='0;
        mul_complete_tval_i='0;
        div_complete_valid_i='0;
        div_complete_tag_i='0;
        div_complete_data_i='0;
        div_complete_flags_i='0;
        div_complete_exception_i='0;
        div_complete_cause_i='0;
        div_complete_tval_i='0;
        lsu_complete_valid_i='0;
        lsu_complete_tag_i='0;
        lsu_complete_data_i='0;
        lsu_complete_flags_i='0;
        lsu_complete_exception_i='0;
        lsu_complete_cause_i='0;
        lsu_complete_tval_i='0;
        csr_complete_valid_i='0;
        csr_complete_tag_i='0;
        csr_complete_data_i='0;
        csr_complete_flags_i='0;
        csr_complete_exception_i='0;
        csr_complete_cause_i='0;
        csr_complete_tval_i='0;
        fp_resp_valid_i='0;
        fp_resp_tag_i='0;
        fp_resp_data_i='0;
        fp_resp_flags_i='0;
        decode_complete_valid_i='0;
        decode_complete_tag_i='0;
        decode_complete_exception_i='0;
        decode_complete_cause_i='0;
        decode_complete_tval_i='0;
        fp_resp_int_dest_i='0;
        lsu_complete_device_i='0;
        lsu_complete_mem_addr_i='0;
        lsu_complete_mem_data_i='0;
        lsu_complete_mem_mask_i='0;
        tick(); rst_n_i=1; tick();
        check(32'(allocate_credit_o)==N,"initial credit");
        for(q=0;q<N;q=q+1) allocate_one(q,
            (q==2 && FPU_FORMAT!="NONE") ? 2:0);
        check(allocate_credit_o==0,"queue full");
        allocate_count_i=1; #1; check(!allocate_ready_o,"full backpressure");
        // No-rd branch and store-like results still contend for the same bank.
        branch_complete_valid_i=1; branch_complete_tag_i=0;
        if(FPU_FORMAT=="NONE") begin
            mul_complete_valid_i=1; mul_complete_tag_i=2;
            mul_complete_data_i=B'(32'h12345678);
        end else begin
            lsu_complete_valid_i=1; lsu_complete_tag_i=2;
            lsu_complete_data_i=B'(64'h8765432112345678);
        end
        #1; check(branch_complete_ready_o,"older bank winner");
        check((FPU_FORMAT=="NONE" ? mul_complete_ready_o:lsu_complete_ready_o)==
            (FPU_FORMAT=="NONE"),"bank contention");
        tick(); branch_complete_valid_i=0;
        check(head0_done_o && head0_pc_o==32'h1000,"old head completion PC");
        // Independent younger completion proceeds while the oldest is held.
        tick(); mul_complete_valid_i=0; lsu_complete_valid_i=0;
        source0_valid_i=1; source0_tag_i=2; source0_domain_i=FPU_FORMAT!="NONE";
        #1; check(source0_ready_o && source0_data_o==(FPU_FORMAT=="NONE" ? B'(32'h12345678):
            B'(64'h8765432112345678)),
            "arbitrary completed tag forwarding");
        // Cancel and completion at the same edge cannot resurrect a tag.
        branch_redirect_valid_i=1; branch_redirect_tag_i=0;
        alu0_complete_valid_i=1; alu0_complete_tag_i=1;
        #1; check(cancel_valid_o && cancel_tag_o==1,"branch cancel includes next tag");
        tick(); branch_redirect_valid_i=0; alu0_complete_valid_i=0;
        check(32'(allocate_credit_o)==N-1,"cancel credit restores tail");
        source0_tag_i=1; #1; check(!source0_ready_o,"same edge cancellation wins");
        retire_count_i=1; tick(); retire_count_i=0;
        check(32'(allocate_credit_o)==N,"retired survivor");
        // Full tag wrap uses occupancy rather than a half-ring comparison.
        for(q=0;q<3*N;q=q+1) begin
            old_head=(q+1)%N;
            allocate_one(old_head,1);
            alu0_complete_valid_i=1; alu0_complete_tag_i=T'(old_head);
            alu0_complete_data_i=B'(q+100); tick(); alu0_complete_valid_i=0;
            check(head0_valid_o && head0_done_o && head0_tag_o==T'(old_head),"wrapped head");
            retire_count_i=1; tick(); retire_count_i=0;
        end
        reset_queue();
        allocate_one(0,1); allocate_one(1,1);
        alu0_complete_valid_i=1; alu0_complete_tag_i=0; alu0_complete_data_i=11;
        mul_complete_valid_i=1; mul_complete_tag_i=1; mul_complete_data_i=22;
        #1; check(alu0_complete_ready_o && mul_complete_ready_o,"different banks accept");
        tick(); alu0_complete_valid_i=0; mul_complete_valid_i=0;
        check(head0_done_o && head0_data_o==11,"old result");
        source0_valid_i=1; source0_tag_i=0; source0_domain_i=0;
        source1_valid_i=1; source1_tag_i=1; source1_domain_i=0;
        source2_valid_i=1; source2_tag_i=0; source2_domain_i=0;
        source3_valid_i=1; source3_tag_i=1; source3_domain_i=0;
        source4_valid_i=1; source4_tag_i=0; source4_domain_i=0;
        #1; check(source0_ready_o && source0_data_o==11,"source copy 0");
        check(source1_ready_o && source1_data_o==22,"source copy 1");
        if(ISSUE_WIDTH==2 || FPU_FORMAT=="F")
            check(source2_ready_o && source2_data_o==11,"source copy 2");
        else check(!source2_ready_o,"absent source copy 2");
        if(ISSUE_WIDTH==2) check(source3_ready_o && source3_data_o==22,"source copy 3");
        else check(!source3_ready_o,"absent source copy 3");
        if(ISSUE_WIDTH==2 && FPU_FORMAT=="F")
            check(source4_ready_o && source4_data_o==11,"source copy 4");
        else check(!source4_ready_o,"absent source copy 4");

        if(ISSUE_WIDTH==2) begin
            check(head1_done_o && head1_data_o==22,"young result");
            retire_count_i=2; tick(); retire_count_i=0;
            check(32'(allocate_credit_o)==N,"dual retirement");
        end
        reset_queue();
        if(FPU_FORMAT!="NONE") begin
            allocate_one(0,2); allocate_one(1,2);
            lsu_complete_valid_i=1; lsu_complete_tag_i=0;
            fp_resp_valid_i=1; fp_resp_tag_i=1;
            #1; check(lsu_complete_ready_o && !fp_resp_ready_o,"single FP destination");
            tick(); lsu_complete_valid_i=0; tick(); fp_resp_valid_i=0;
            check(head0_done_o,"FP completed head");
            reset_queue();
        end
        // Prepared device loads cannot forward provisional data.
        allocate_one(0,1);
        lsu_complete_valid_i=1; lsu_complete_tag_i=0; lsu_complete_device_i=1;
        tick(); lsu_complete_valid_i=0; source0_valid_i=1; source0_tag_i=0;
        #1; check(head0_done_o && head0_device_o && !source0_ready_o,"device preparation");
        reset_queue();
        if(ISSUE_WIDTH==2) begin
            allocate_valid_i=1; allocate_count_i=2; allocate0_tag_i=0; allocate1_tag_i=1;
            allocate0_pc_i=32'h2000; allocate1_pc_i=32'h2004;
            tick(); allocate_valid_i=0;
            check(32'(allocate_credit_o)==N-2,"atomic dual allocation");
            check(head0_pc_o==32'h2000 && head1_pc_o==32'h2004,"two PC banks");
        end
        reset_queue();
        for(q=0;q<4*N;q=q+1) begin
            allocate_one(q%N,1);
            case(q%9)
                0: begin alu0_complete_valid_i=1; alu0_complete_tag_i=T'(q%N);
                    alu0_complete_data_i=B'(q+1); end
                1: begin mul_complete_valid_i=1; mul_complete_tag_i=T'(q%N);
                    mul_complete_data_i=B'(q+1); end
                2: begin branch_complete_valid_i=1; branch_complete_tag_i=T'(q%N);
                    branch_complete_data_i=B'(q+1); branch_complete_next_pc_i=32'h8888; end
                3: begin div_complete_valid_i=1; div_complete_tag_i=T'(q%N);
                    div_complete_data_i=B'(q+1); end
                4: begin csr_complete_valid_i=1; csr_complete_tag_i=T'(q%N);
                    csr_complete_data_i=B'(q+1); end
                5: begin lsu_complete_valid_i=1; lsu_complete_tag_i=T'(q%N);
                    lsu_complete_device_i=0; lsu_complete_data_i=B'(q+1); end
                6: begin decode_complete_valid_i=1; decode_complete_tag_i=T'(q%N);
                    decode_complete_exception_i=1; decode_complete_cause_i=2;
                    decode_complete_tval_i=32'hbad; end
                7: begin
                    if(FPU_FORMAT!="NONE") begin fp_resp_valid_i=1; fp_resp_tag_i=T'(q%N);
                        fp_resp_data_i=B'(q+1); fp_resp_int_dest_i=1; fp_resp_flags_i=1; end
                    else begin alu0_complete_valid_i=1; alu0_complete_tag_i=T'(q%N);
                        alu0_complete_data_i=B'(q+1); end
                end
                8: begin
                    if(ISSUE_WIDTH==2) begin alu1_complete_valid_i=1; alu1_complete_tag_i=T'(q%N);
                        alu1_complete_data_i=B'(q+1); end
                    else begin alu0_complete_valid_i=1; alu0_complete_tag_i=T'(q%N);
                        alu0_complete_data_i=B'(q+1); end
                end
            endcase
            tick();
            alu0_complete_valid_i=0; alu1_complete_valid_i=0; mul_complete_valid_i=0;
            branch_complete_valid_i=0; div_complete_valid_i=0; csr_complete_valid_i=0;
            lsu_complete_valid_i=0; fp_resp_valid_i=0; decode_complete_valid_i=0;
            check(head0_done_o && head0_tag_o==T'(q%N),"all completion sources");
            if(q%9==6) check(head0_exception_o && head0_cause_o==2 && head0_tval_o==32'hbad,
                "decode exception completion payload");
            else check(head0_data_o==B'(q+1),"completion source payload");
            if(q%9==2) check(head0_next_pc_o==32'h8888,"actual next PC storage");
            retire_count_i=1; tick(); retire_count_i=0;
        end
        // Keep a nearly full queue straddling zero; cancellation uses head distance.
        allocate_one(0,1); alu0_complete_valid_i=1; alu0_complete_tag_i=0;
        tick(); alu0_complete_valid_i=0; retire_count_i=1; tick(); retire_count_i=0;
        for(q=1;q<=N;q=q+1) allocate_one(q%N,0);
        branch_redirect_valid_i=1; branch_redirect_tag_i=T'(N-1);
        #1; check(cancel_valid_o && cancel_tag_o==0,"wrapped branch boundary");
        tick(); branch_redirect_valid_i=0;
        check(allocate_credit_o==1 && age_head_o==1,"wrapped cancellation preserves older prefix");
        random_queue();
        finished=1;
    end
endmodule
module tb;
    wire [5:0] finished;
    check_completion #(.ISSUE_WIDTH(1),.FPU_FORMAT("NONE")) u_0(finished[0]);
    check_completion #(.ISSUE_WIDTH(1),.FPU_FORMAT("F")) u_1(finished[1]);
    check_completion #(.ISSUE_WIDTH(1),.FPU_FORMAT("FD")) u_2(finished[2]);
    check_completion #(.ISSUE_WIDTH(2),.FPU_FORMAT("NONE")) u_3(finished[3]);
    check_completion #(.ISSUE_WIDTH(2),.FPU_FORMAT("F")) u_4(finished[4]);
    check_completion #(.ISSUE_WIDTH(2),.FPU_FORMAT("FD")) u_5(finished[5]);
    initial begin wait (&finished); $display("PASS completion six configurations"); $finish; end
endmodule
