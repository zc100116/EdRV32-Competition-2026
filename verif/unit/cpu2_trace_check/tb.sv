// File: tb.sv
// Spec: cpu-v2-testplan 2/4, V01 synthetic checker self-test.
// Description: Replay independent trace and BFM stimulus; runner verifies negative diagnostics.
// Clock: clk_i, 10 time units.
module tb #(
    parameter ISSUE_WIDTH = 2,
    parameter string FPU_FORMAT = "FD",
    localparam T = FPU_FORMAT == "NONE" ? 2 : (FPU_FORMAT == "F" ? 3 : 4)
);
    reg clk_i;
    reg rst_n_i = 0;
    reg finish_i = 0;
    integer fd;
    integer count;
    string path;
    reg [ISSUE_WIDTH-1:0] trace_valid = 0;
    reg [32*ISSUE_WIDTH-1:0] trace_pc = 0;
    reg [32*ISSUE_WIDTH-1:0] trace_instr = 0;
    reg [5*ISSUE_WIDTH-1:0] trace_rd = 0;
    reg [2*ISSUE_WIDTH-1:0] trace_rd_domain = 0;
    reg [64*ISSUE_WIDTH-1:0] trace_rd_data = 0;
    reg [5*ISSUE_WIDTH-1:0] trace_flags = 0;
    reg [1*ISSUE_WIDTH-1:0] trace_csr_valid = 0;
    reg [12*ISSUE_WIDTH-1:0] trace_csr_addr = 0;
    reg [32*ISSUE_WIDTH-1:0] trace_csr_data = 0;
    reg [1*ISSUE_WIDTH-1:0] trace_mem_valid = 0;
    reg [1*ISSUE_WIDTH-1:0] trace_mem_store = 0;
    reg [32*ISSUE_WIDTH-1:0] trace_mem_addr = 0;
    reg [64*ISSUE_WIDTH-1:0] trace_mem_data = 0;
    reg [8*ISSUE_WIDTH-1:0] trace_mem_mask = 0;
    reg [5-1:0] trace_fflags = 0;
    reg [3-1:0] trace_frm = 0;
    reg [2-1:0] trace_fs = 0;
    reg trace_trap = 0;
    reg [32-1:0] trace_cause = 0;
    reg [32-1:0] trace_trap_pc = 0;
    reg [32-1:0] trace_tval = 0;
    reg trace_mem_effect_valid = 0;
    reg [T-1:0] trace_mem_effect_tag = 0;
    reg [32-1:0] trace_mem_effect_addr = 0;
    reg [32-1:0] trace_mem_effect_data = 0;
    reg [4-1:0] trace_mem_effect_mask = 0;
    reg trace_redirect_valid = 0;
    reg [T-1:0] trace_redirect_tag = 0;
    reg [32-1:0] trace_redirect_pc = 0;
    reg [32-1:0] trace_redirect_target = 0;
    reg [2-1:0] trace_redirect_stage = 0;
    reg [2-1:0] trace_redirect_cause = 0;
    reg trace_source0_valid = 0;
    reg [T-1:0] trace_source0_tag = 0;
    reg trace_source0_domain = 0;
    reg trace_source1_valid = 0;
    reg [T-1:0] trace_source1_tag = 0;
    reg trace_source1_domain = 0;
    reg trace_source2_valid = 0;
    reg [T-1:0] trace_source2_tag = 0;
    reg trace_source2_domain = 0;
    reg trace_source3_valid = 0;
    reg [T-1:0] trace_source3_tag = 0;
    reg trace_source3_domain = 0;
    reg trace_source4_valid = 0;
    reg [T-1:0] trace_source4_tag = 0;
    reg trace_source4_domain = 0;
    reg bfm_valid = 0;
    reg [32-1:0] bfm_addr = 0;
    reg [32-1:0] bfm_data = 0;
    reg [4-1:0] bfm_mask = 0;
    initial begin
        clk_i = 0;
        forever #5 clk_i = ~clk_i;
    end
    edrv32_cpu2_trace_check #(
        .ISSUE_WIDTH(ISSUE_WIDTH),
        .FPU_FORMAT(FPU_FORMAT)
    ) u_check (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .finish_i(finish_i),
        .trace_valid_i(trace_valid),
        .trace_pc_i(trace_pc),
        .trace_instr_i(trace_instr),
        .trace_rd_i(trace_rd),
        .trace_rd_domain_i(trace_rd_domain),
        .trace_rd_data_i(trace_rd_data),
        .trace_flags_i(trace_flags),
        .trace_csr_valid_i(trace_csr_valid),
        .trace_csr_addr_i(trace_csr_addr),
        .trace_csr_data_i(trace_csr_data),
        .trace_mem_valid_i(trace_mem_valid),
        .trace_mem_store_i(trace_mem_store),
        .trace_mem_addr_i(trace_mem_addr),
        .trace_mem_data_i(trace_mem_data),
        .trace_mem_mask_i(trace_mem_mask),
        .trace_fflags_i(trace_fflags),
        .trace_frm_i(trace_frm),
        .trace_fs_i(trace_fs),
        .trace_trap_i(trace_trap),
        .trace_cause_i(trace_cause),
        .trace_trap_pc_i(trace_trap_pc),
        .trace_tval_i(trace_tval),
        .trace_mem_effect_valid_i(trace_mem_effect_valid),
        .trace_mem_effect_tag_i(trace_mem_effect_tag),
        .trace_mem_effect_addr_i(trace_mem_effect_addr),
        .trace_mem_effect_data_i(trace_mem_effect_data),
        .trace_mem_effect_mask_i(trace_mem_effect_mask),
        .trace_redirect_valid_i(trace_redirect_valid),
        .trace_redirect_tag_i(trace_redirect_tag),
        .trace_redirect_pc_i(trace_redirect_pc),
        .trace_redirect_target_i(trace_redirect_target),
        .trace_redirect_stage_i(trace_redirect_stage),
        .trace_redirect_cause_i(trace_redirect_cause),
        .trace_source0_valid_i(trace_source0_valid),
        .trace_source0_tag_i(trace_source0_tag),
        .trace_source0_domain_i(trace_source0_domain),
        .trace_source1_valid_i(trace_source1_valid),
        .trace_source1_tag_i(trace_source1_tag),
        .trace_source1_domain_i(trace_source1_domain),
        .trace_source2_valid_i(trace_source2_valid),
        .trace_source2_tag_i(trace_source2_tag),
        .trace_source2_domain_i(trace_source2_domain),
        .trace_source3_valid_i(trace_source3_valid),
        .trace_source3_tag_i(trace_source3_tag),
        .trace_source3_domain_i(trace_source3_domain),
        .trace_source4_valid_i(trace_source4_valid),
        .trace_source4_tag_i(trace_source4_tag),
        .trace_source4_domain_i(trace_source4_domain),
        .bfm_valid_i(bfm_valid),
        .bfm_addr_i(bfm_addr),
        .bfm_data_i(bfm_data),
        .bfm_mask_i(bfm_mask)
    );
    initial begin
        if (!$value$plusargs("STIMULUS=%s", path)) $fatal(1, "FAIL missing STIMULUS");
        fd = $fopen(path, "r");
        if (fd == 0) $fatal(1, "FAIL open stimulus");
        @(negedge clk_i);
        rst_n_i = 1;
        while (!$feof(fd)) begin
            count = $fscanf(fd, "%h", finish_i);
            count = count + $fscanf(fd, "%h", trace_valid);
            count = count + $fscanf(fd, "%h", trace_pc);
            count = count + $fscanf(fd, "%h", trace_instr);
            count = count + $fscanf(fd, "%h", trace_rd);
            count = count + $fscanf(fd, "%h", trace_rd_domain);
            count = count + $fscanf(fd, "%h", trace_rd_data);
            count = count + $fscanf(fd, "%h", trace_flags);
            count = count + $fscanf(fd, "%h", trace_csr_valid);
            count = count + $fscanf(fd, "%h", trace_csr_addr);
            count = count + $fscanf(fd, "%h", trace_csr_data);
            count = count + $fscanf(fd, "%h", trace_mem_valid);
            count = count + $fscanf(fd, "%h", trace_mem_store);
            count = count + $fscanf(fd, "%h", trace_mem_addr);
            count = count + $fscanf(fd, "%h", trace_mem_data);
            count = count + $fscanf(fd, "%h", trace_mem_mask);
            count = count + $fscanf(fd, "%h", trace_fflags);
            count = count + $fscanf(fd, "%h", trace_frm);
            count = count + $fscanf(fd, "%h", trace_fs);
            count = count + $fscanf(fd, "%h", trace_trap);
            count = count + $fscanf(fd, "%h", trace_cause);
            count = count + $fscanf(fd, "%h", trace_trap_pc);
            count = count + $fscanf(fd, "%h", trace_tval);
            count = count + $fscanf(fd, "%h", trace_mem_effect_valid);
            count = count + $fscanf(fd, "%h", trace_mem_effect_tag);
            count = count + $fscanf(fd, "%h", trace_mem_effect_addr);
            count = count + $fscanf(fd, "%h", trace_mem_effect_data);
            count = count + $fscanf(fd, "%h", trace_mem_effect_mask);
            count = count + $fscanf(fd, "%h", trace_redirect_valid);
            count = count + $fscanf(fd, "%h", trace_redirect_tag);
            count = count + $fscanf(fd, "%h", trace_redirect_pc);
            count = count + $fscanf(fd, "%h", trace_redirect_target);
            count = count + $fscanf(fd, "%h", trace_redirect_stage);
            count = count + $fscanf(fd, "%h", trace_redirect_cause);
            count = count + $fscanf(fd, "%h", trace_source0_valid);
            count = count + $fscanf(fd, "%h", trace_source0_tag);
            count = count + $fscanf(fd, "%h", trace_source0_domain);
            count = count + $fscanf(fd, "%h", trace_source1_valid);
            count = count + $fscanf(fd, "%h", trace_source1_tag);
            count = count + $fscanf(fd, "%h", trace_source1_domain);
            count = count + $fscanf(fd, "%h", trace_source2_valid);
            count = count + $fscanf(fd, "%h", trace_source2_tag);
            count = count + $fscanf(fd, "%h", trace_source2_domain);
            count = count + $fscanf(fd, "%h", trace_source3_valid);
            count = count + $fscanf(fd, "%h", trace_source3_tag);
            count = count + $fscanf(fd, "%h", trace_source3_domain);
            count = count + $fscanf(fd, "%h", trace_source4_valid);
            count = count + $fscanf(fd, "%h", trace_source4_tag);
            count = count + $fscanf(fd, "%h", trace_source4_domain);
            count = count + $fscanf(fd, "%h", bfm_valid);
            count = count + $fscanf(fd, "%h", bfm_addr);
            count = count + $fscanf(fd, "%h", bfm_data);
            count = count + $fscanf(fd, "%h", bfm_mask);
            if (count == 53) begin
                @(negedge clk_i);
                if (finish_i) $finish;
            end else if (count != -1) $fatal(1, "FAIL malformed stimulus");
        end
        $fatal(1, "FAIL stimulus missing finish");
    end
endmodule
