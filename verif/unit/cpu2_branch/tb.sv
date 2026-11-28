// CV05 branch direction, target, training, RAS snapshot and cancellation checks.
module tb #(parameter ISSUE_WIDTH=2,parameter [31:0] FPU_FORMAT="NONE");
    localparam T=(ISSUE_WIDTH == 2 || FPU_FORMAT == "FD") ? 4 : 3;
    localparam B=FPU_FORMAT=="FD"?64:32;
    reg clk_i=0;
    reg rst_n_i=0;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] age_head_i=0;
    reg cancel_valid_i=0;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] cancel_tag_i=0;
    reg execute0_valid_i=0;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] execute0_tag_i=0;
    reg [32-1:0] execute0_pc_i=0;
    reg [32-1:0] execute0_instr_i=0;
    reg [32-1:0] execute0_src1_i=0;
    reg [32-1:0] execute0_src2_i=0;
    reg [32-1:0] execute0_imm_i=0;
    reg execute0_late_i=0;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] execute0_source1_tag_i=0;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] execute0_source2_tag_i=0;
    reg execute0_source1_wait_i=0;
    reg execute0_source2_wait_i=0;
    reg execute0_predict_taken_i=0;
    reg [32-1:0] execute0_predict_target_i=0;
    reg execute0_predict_token_i=0;
    reg [3-1:0] execute0_predict_provider_i=0;
    reg execute0_predict_alternate_i=0;
    reg [9-1:0] execute0_predict_index0_i=0;
    reg [9-1:0] execute0_predict_index1_i=0;
    reg [9-1:0] execute0_predict_index2_i=0;
    reg [9-1:0] execute0_predict_index3_i=0;
    reg [10-1:0] execute0_predict_tag0_i=0;
    reg [10-1:0] execute0_predict_tag1_i=0;
    reg [10-1:0] execute0_predict_tag2_i=0;
    reg [10-1:0] execute0_predict_tag3_i=0;
    reg [12-1:0] execute0_predict_base_index_i=0;
    reg [12-1:0] execute0_predict_fast_index_i=0;
    reg [(128*ISSUE_WIDTH)-1:0] execute0_ras_data_i=0;
    reg [(ISSUE_WIDTH+1)-1:0] execute0_ras_ptr_i=0;
    reg [(ISSUE_WIDTH+2)-1:0] execute0_ras_count_i=0;
    wire execute0_ready_o;
    reg execute1_valid_i=0;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] execute1_tag_i=0;
    reg [32-1:0] execute1_pc_i=0;
    reg [32-1:0] execute1_instr_i=0;
    reg [32-1:0] execute1_src1_i=0;
    reg [32-1:0] execute1_src2_i=0;
    reg [32-1:0] execute1_imm_i=0;
    reg execute1_late_i=0;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] execute1_source1_tag_i=0;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] execute1_source2_tag_i=0;
    reg execute1_source1_wait_i=0;
    reg execute1_source2_wait_i=0;
    reg execute1_predict_taken_i=0;
    reg [32-1:0] execute1_predict_target_i=0;
    reg execute1_predict_token_i=0;
    reg [3-1:0] execute1_predict_provider_i=0;
    reg execute1_predict_alternate_i=0;
    reg [9-1:0] execute1_predict_index0_i=0;
    reg [9-1:0] execute1_predict_index1_i=0;
    reg [9-1:0] execute1_predict_index2_i=0;
    reg [9-1:0] execute1_predict_index3_i=0;
    reg [10-1:0] execute1_predict_tag0_i=0;
    reg [10-1:0] execute1_predict_tag1_i=0;
    reg [10-1:0] execute1_predict_tag2_i=0;
    reg [10-1:0] execute1_predict_tag3_i=0;
    reg [12-1:0] execute1_predict_base_index_i=0;
    reg [12-1:0] execute1_predict_fast_index_i=0;
    reg [(128*ISSUE_WIDTH)-1:0] execute1_ras_data_i=0;
    reg [(ISSUE_WIDTH+1)-1:0] execute1_ras_ptr_i=0;
    reg [(ISSUE_WIDTH+2)-1:0] execute1_ras_count_i=0;
    wire execute1_ready_o;
    reg alu0_complete_valid_i=0;
    reg alu0_complete_ready_i=0;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] alu0_complete_tag_i=0;
    reg [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] alu0_complete_data_i=0;
    reg alu1_complete_valid_i=0;
    reg alu1_complete_ready_i=0;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] alu1_complete_tag_i=0;
    reg [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] alu1_complete_data_i=0;
    reg branch_complete_valid_i=0;
    reg branch_complete_ready_i=0;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] branch_complete_tag_i=0;
    reg [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] branch_complete_data_i=0;
    reg mul_complete_valid_i=0;
    reg mul_complete_ready_i=0;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] mul_complete_tag_i=0;
    reg [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] mul_complete_data_i=0;
    reg div_complete_valid_i=0;
    reg div_complete_ready_i=0;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] div_complete_tag_i=0;
    reg [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] div_complete_data_i=0;
    reg lsu_complete_valid_i=0;
    reg lsu_complete_ready_i=0;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] lsu_complete_tag_i=0;
    reg [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] lsu_complete_data_i=0;
    reg csr_complete_valid_i=0;
    reg csr_complete_ready_i=0;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] csr_complete_tag_i=0;
    reg [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] csr_complete_data_i=0;
    reg fp_resp_valid_i=0;
    reg fp_resp_ready_i=0;
    reg [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] fp_resp_tag_i=0;
    reg [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] fp_resp_data_i=0;
    wire branch_complete_valid_o;
    wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] branch_complete_tag_o;
    wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] branch_complete_data_o;
    wire [5-1:0] branch_complete_flags_o;
    wire branch_complete_exception_o;
    wire [4-1:0] branch_complete_cause_o;
    wire [32-1:0] branch_complete_tval_o;
    wire [32-1:0] branch_complete_next_pc_o;
    wire ex_predict_train_valid_o;
    wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] ex_predict_train_tag_o;
    wire [32-1:0] ex_predict_train_pc_o;
    wire ex_predict_train_taken_o;
    wire [32-1:0] ex_predict_train_target_o;
    wire [3-1:0] ex_predict_train_type_o;
    wire ex_predict_train_token_o;
    wire [3-1:0] ex_predict_train_provider_o;
    wire ex_predict_train_alternate_o;
    wire ex_predict_train_prediction_o;
    wire [9-1:0] ex_predict_train_index0_o;
    wire [9-1:0] ex_predict_train_index1_o;
    wire [9-1:0] ex_predict_train_index2_o;
    wire [9-1:0] ex_predict_train_index3_o;
    wire [10-1:0] ex_predict_train_tag0_o;
    wire [10-1:0] ex_predict_train_tag1_o;
    wire [10-1:0] ex_predict_train_tag2_o;
    wire [10-1:0] ex_predict_train_tag3_o;
    wire [12-1:0] ex_predict_train_base_index_o;
    wire [12-1:0] ex_predict_train_fast_index_o;
    wire mem_predict_train_valid_o;
    wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] mem_predict_train_tag_o;
    wire [32-1:0] mem_predict_train_pc_o;
    wire mem_predict_train_taken_o;
    wire [32-1:0] mem_predict_train_target_o;
    wire [3-1:0] mem_predict_train_type_o;
    wire mem_predict_train_token_o;
    wire [3-1:0] mem_predict_train_provider_o;
    wire mem_predict_train_alternate_o;
    wire mem_predict_train_prediction_o;
    wire [9-1:0] mem_predict_train_index0_o;
    wire [9-1:0] mem_predict_train_index1_o;
    wire [9-1:0] mem_predict_train_index2_o;
    wire [9-1:0] mem_predict_train_index3_o;
    wire [10-1:0] mem_predict_train_tag0_o;
    wire [10-1:0] mem_predict_train_tag1_o;
    wire [10-1:0] mem_predict_train_tag2_o;
    wire [10-1:0] mem_predict_train_tag3_o;
    wire [12-1:0] mem_predict_train_base_index_o;
    wire [12-1:0] mem_predict_train_fast_index_o;
    wire branch_redirect_valid_o;
    wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] branch_redirect_tag_o;
    wire [32-1:0] branch_redirect_pc_o;
    wire [(128*ISSUE_WIDTH)-1:0] branch_redirect_ras_data_o;
    wire [(ISSUE_WIDTH+1)-1:0] branch_redirect_ras_ptr_o;
    wire [(ISSUE_WIDTH+2)-1:0] branch_redirect_ras_count_o;
    wire branch_redirect_ras_pop_o;
    wire branch_redirect_ras_push_o;
    wire [32-1:0] branch_redirect_link_o;
    always #5 clk_i=~clk_i;
    reg lsu_complete_device_i=0;
    reg wb0_valid_i=0;
    reg [T-1:0] wb0_tag_i=0;
    reg [31:0] wb0_data_i=0;
    reg wb1_valid_i=0;
    reg [T-1:0] wb1_tag_i=0;
    reg [31:0] wb1_data_i=0;
    reg early_resp_valid_i=0;
    reg [T-1:0] early_resp_tag_i=0;
    reg early_resp_hit_i=0;
    reg [31:0] early_resp_data_i=0;
    edrv32_cpu2_branch #(
        .ISSUE_WIDTH(ISSUE_WIDTH),
        .FPU_FORMAT(FPU_FORMAT)
    ) dut (
        .lsu_complete_device_i(lsu_complete_device_i),
        .early_resp_valid_i(early_resp_valid_i),
        .early_resp_tag_i(early_resp_tag_i),
        .early_resp_hit_i(early_resp_hit_i),
        .early_resp_data_i(early_resp_data_i),
        .wb0_valid_i(wb0_valid_i),
        .wb0_tag_i(wb0_tag_i),
        .wb0_data_i(wb0_data_i),
        .wb1_valid_i(wb1_valid_i),
        .wb1_tag_i(wb1_tag_i),
        .wb1_data_i(wb1_data_i),
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .age_head_i(age_head_i),
        .cancel_valid_i(cancel_valid_i),
        .cancel_tag_i(cancel_tag_i),
        .execute0_valid_i(execute0_valid_i),
        .execute0_tag_i(execute0_tag_i),
        .execute0_pc_i(execute0_pc_i),
        .execute0_instr_i(execute0_instr_i),
        .execute0_src1_i(execute0_src1_i),
        .execute0_src2_i(execute0_src2_i),
        .execute0_imm_i(execute0_imm_i),
        .execute0_late_i(execute0_late_i),
        .execute0_source1_tag_i(execute0_source1_tag_i),
        .execute0_source2_tag_i(execute0_source2_tag_i),
        .execute0_source1_wait_i(execute0_source1_wait_i),
        .execute0_source2_wait_i(execute0_source2_wait_i),
        .execute0_predict_taken_i(execute0_predict_taken_i),
        .execute0_predict_target_i(execute0_predict_target_i),
        .execute0_predict_token_i(execute0_predict_token_i),
        .execute0_predict_provider_i(execute0_predict_provider_i),
        .execute0_predict_alternate_i(execute0_predict_alternate_i),
        .execute0_predict_index0_i(execute0_predict_index0_i),
        .execute0_predict_index1_i(execute0_predict_index1_i),
        .execute0_predict_index2_i(execute0_predict_index2_i),
        .execute0_predict_index3_i(execute0_predict_index3_i),
        .execute0_predict_tag0_i(execute0_predict_tag0_i),
        .execute0_predict_tag1_i(execute0_predict_tag1_i),
        .execute0_predict_tag2_i(execute0_predict_tag2_i),
        .execute0_predict_tag3_i(execute0_predict_tag3_i),
        .execute0_predict_base_index_i(execute0_predict_base_index_i),
        .execute0_predict_fast_index_i(execute0_predict_fast_index_i),
        .execute0_ras_data_i(execute0_ras_data_i),
        .execute0_ras_ptr_i(execute0_ras_ptr_i),
        .execute0_ras_count_i(execute0_ras_count_i),
        .execute0_ready_o(execute0_ready_o),
        .execute1_valid_i(execute1_valid_i),
        .execute1_tag_i(execute1_tag_i),
        .execute1_pc_i(execute1_pc_i),
        .execute1_instr_i(execute1_instr_i),
        .execute1_src1_i(execute1_src1_i),
        .execute1_src2_i(execute1_src2_i),
        .execute1_imm_i(execute1_imm_i),
        .execute1_late_i(execute1_late_i),
        .execute1_source1_tag_i(execute1_source1_tag_i),
        .execute1_source2_tag_i(execute1_source2_tag_i),
        .execute1_source1_wait_i(execute1_source1_wait_i),
        .execute1_source2_wait_i(execute1_source2_wait_i),
        .execute1_predict_taken_i(execute1_predict_taken_i),
        .execute1_predict_target_i(execute1_predict_target_i),
        .execute1_predict_token_i(execute1_predict_token_i),
        .execute1_predict_provider_i(execute1_predict_provider_i),
        .execute1_predict_alternate_i(execute1_predict_alternate_i),
        .execute1_predict_index0_i(execute1_predict_index0_i),
        .execute1_predict_index1_i(execute1_predict_index1_i),
        .execute1_predict_index2_i(execute1_predict_index2_i),
        .execute1_predict_index3_i(execute1_predict_index3_i),
        .execute1_predict_tag0_i(execute1_predict_tag0_i),
        .execute1_predict_tag1_i(execute1_predict_tag1_i),
        .execute1_predict_tag2_i(execute1_predict_tag2_i),
        .execute1_predict_tag3_i(execute1_predict_tag3_i),
        .execute1_predict_base_index_i(execute1_predict_base_index_i),
        .execute1_predict_fast_index_i(execute1_predict_fast_index_i),
        .execute1_ras_data_i(execute1_ras_data_i),
        .execute1_ras_ptr_i(execute1_ras_ptr_i),
        .execute1_ras_count_i(execute1_ras_count_i),
        .execute1_ready_o(execute1_ready_o),
        .alu0_complete_valid_i(alu0_complete_valid_i),
        .alu0_complete_ready_i(alu0_complete_ready_i),
        .alu0_complete_tag_i(alu0_complete_tag_i),
        .alu0_complete_data_i(alu0_complete_data_i),
        .alu1_complete_valid_i(alu1_complete_valid_i),
        .alu1_complete_ready_i(alu1_complete_ready_i),
        .alu1_complete_tag_i(alu1_complete_tag_i),
        .alu1_complete_data_i(alu1_complete_data_i),
        .branch_complete_valid_i(branch_complete_valid_i),
        .branch_complete_ready_i(branch_complete_ready_i),
        .branch_complete_tag_i(branch_complete_tag_i),
        .branch_complete_data_i(branch_complete_data_i),
        .mul_complete_valid_i(mul_complete_valid_i),
        .mul_complete_ready_i(mul_complete_ready_i),
        .mul_complete_tag_i(mul_complete_tag_i),
        .mul_complete_data_i(mul_complete_data_i),
        .div_complete_valid_i(div_complete_valid_i),
        .div_complete_ready_i(div_complete_ready_i),
        .div_complete_tag_i(div_complete_tag_i),
        .div_complete_data_i(div_complete_data_i),
        .lsu_complete_valid_i(lsu_complete_valid_i),
        .lsu_complete_ready_i(lsu_complete_ready_i),
        .lsu_complete_tag_i(lsu_complete_tag_i),
        .lsu_complete_data_i(lsu_complete_data_i),
        .csr_complete_valid_i(csr_complete_valid_i),
        .csr_complete_ready_i(csr_complete_ready_i),
        .csr_complete_tag_i(csr_complete_tag_i),
        .csr_complete_data_i(csr_complete_data_i),
        .fp_resp_valid_i(fp_resp_valid_i),
        .fp_resp_ready_i(fp_resp_ready_i),
        .fp_resp_tag_i(fp_resp_tag_i),
        .fp_resp_data_i(fp_resp_data_i),
        .branch_complete_valid_o(branch_complete_valid_o),
        .branch_complete_tag_o(branch_complete_tag_o),
        .branch_complete_data_o(branch_complete_data_o),
        .branch_complete_flags_o(branch_complete_flags_o),
        .branch_complete_exception_o(branch_complete_exception_o),
        .branch_complete_cause_o(branch_complete_cause_o),
        .branch_complete_tval_o(branch_complete_tval_o),
        .branch_complete_next_pc_o(branch_complete_next_pc_o),
        .ex_predict_train_valid_o(ex_predict_train_valid_o),
        .ex_predict_train_tag_o(ex_predict_train_tag_o),
        .ex_predict_train_pc_o(ex_predict_train_pc_o),
        .ex_predict_train_taken_o(ex_predict_train_taken_o),
        .ex_predict_train_target_o(ex_predict_train_target_o),
        .ex_predict_train_type_o(ex_predict_train_type_o),
        .ex_predict_train_token_o(ex_predict_train_token_o),
        .ex_predict_train_provider_o(ex_predict_train_provider_o),
        .ex_predict_train_alternate_o(ex_predict_train_alternate_o),
        .ex_predict_train_prediction_o(ex_predict_train_prediction_o),
        .ex_predict_train_index0_o(ex_predict_train_index0_o),
        .ex_predict_train_index1_o(ex_predict_train_index1_o),
        .ex_predict_train_index2_o(ex_predict_train_index2_o),
        .ex_predict_train_index3_o(ex_predict_train_index3_o),
        .ex_predict_train_tag0_o(ex_predict_train_tag0_o),
        .ex_predict_train_tag1_o(ex_predict_train_tag1_o),
        .ex_predict_train_tag2_o(ex_predict_train_tag2_o),
        .ex_predict_train_tag3_o(ex_predict_train_tag3_o),
        .ex_predict_train_base_index_o(ex_predict_train_base_index_o),
        .ex_predict_train_fast_index_o(ex_predict_train_fast_index_o),
        .mem_predict_train_valid_o(mem_predict_train_valid_o),
        .mem_predict_train_tag_o(mem_predict_train_tag_o),
        .mem_predict_train_pc_o(mem_predict_train_pc_o),
        .mem_predict_train_taken_o(mem_predict_train_taken_o),
        .mem_predict_train_target_o(mem_predict_train_target_o),
        .mem_predict_train_type_o(mem_predict_train_type_o),
        .mem_predict_train_token_o(mem_predict_train_token_o),
        .mem_predict_train_provider_o(mem_predict_train_provider_o),
        .mem_predict_train_alternate_o(mem_predict_train_alternate_o),
        .mem_predict_train_prediction_o(mem_predict_train_prediction_o),
        .mem_predict_train_index0_o(mem_predict_train_index0_o),
        .mem_predict_train_index1_o(mem_predict_train_index1_o),
        .mem_predict_train_index2_o(mem_predict_train_index2_o),
        .mem_predict_train_index3_o(mem_predict_train_index3_o),
        .mem_predict_train_tag0_o(mem_predict_train_tag0_o),
        .mem_predict_train_tag1_o(mem_predict_train_tag1_o),
        .mem_predict_train_tag2_o(mem_predict_train_tag2_o),
        .mem_predict_train_tag3_o(mem_predict_train_tag3_o),
        .mem_predict_train_base_index_o(mem_predict_train_base_index_o),
        .mem_predict_train_fast_index_o(mem_predict_train_fast_index_o),
        .branch_redirect_valid_o(branch_redirect_valid_o),
        .branch_redirect_tag_o(branch_redirect_tag_o),
        .branch_redirect_pc_o(branch_redirect_pc_o),
        .branch_redirect_ras_data_o(branch_redirect_ras_data_o),
        .branch_redirect_ras_ptr_o(branch_redirect_ras_ptr_o),
        .branch_redirect_ras_count_o(branch_redirect_ras_count_o),
        .branch_redirect_ras_pop_o(branch_redirect_ras_pop_o),
        .branch_redirect_ras_push_o(branch_redirect_ras_push_o),
        .branch_redirect_link_o(branch_redirect_link_o),
        // I06 observation-only outputs.
        .trace_branch_pc_o(),
        .trace_branch_stage_o(),
        .trace_branch_cause_o(),
        .debug_mem_valid_o()
    );
    task tick; @(posedge clk_i); #1; endtask
    task branch(input integer pipeline,input [31:0] code,input [31:0] x,input [31:0] y,
                input [31:0] displacement,input bit taken,input [31:0] target,
                input bit fault,input integer type_value);
        @(negedge clk_i);
        if(pipeline==0) begin
            if(!execute0_ready_o)$fatal(1,"branch input full");
            execute0_valid_i=1;execute0_instr_i=code;execute0_src1_i=x;execute0_src2_i=y;
            execute0_pc_i=32'h100;execute0_imm_i=displacement;execute0_tag_i=0;
            execute0_predict_taken_i=0;execute0_ras_data_i=(128*ISSUE_WIDTH)'(32'hdeadbeef);
        end else begin
            if(!execute1_ready_o)$fatal(1,"branch input1 full");
            execute1_valid_i=1;execute1_instr_i=code;execute1_src1_i=x;execute1_src2_i=y;
            execute1_pc_i=32'h100;execute1_imm_i=displacement;execute1_tag_i=0;
            execute1_predict_taken_i=0;execute1_ras_data_i=(128*ISSUE_WIDTH)'(32'hdeadbeef);
        end
        #1;
        if(!branch_complete_valid_o || branch_complete_tag_o!==0 ||
            branch_complete_data_o!==B'(32'h104) || branch_complete_exception_o!==fault ||
            branch_complete_next_pc_o!==(taken?target:32'h104) ||
            (fault && (branch_complete_cause_o!==0 || branch_complete_tval_o!==target)))
            $fatal(1,"branch complete expected next%h fault%b got valid%b next%h fault%b at%0t",
                taken?target:32'h104,fault,branch_complete_valid_o,
                branch_complete_next_pc_o,branch_complete_exception_o,$time);
        tick();execute0_valid_i=0;execute1_valid_i=0; #1;
        if(ex_predict_train_valid_o!==!fault || (!fault &&
            (ex_predict_train_taken_o!==taken || ex_predict_train_target_o!==target ||
            ex_predict_train_type_o!==3'(type_value))))
            $fatal(1,"branch training type%0d got%0d target%h at%0t",
                type_value,ex_predict_train_type_o,ex_predict_train_target_o,$time);
        if(branch_redirect_valid_o!==(taken&&!fault) ||
            ((taken&&!fault) && (branch_redirect_pc_o!==target ||
                branch_redirect_ras_data_o!==(128*ISSUE_WIDTH)'(32'hdeadbeef))))
            $fatal(1,"branch redirect/RAS at%0t",$time);
        tick();if(ex_predict_train_valid_o || branch_redirect_valid_o)
            $fatal(1,"duplicate training/redirect");
    endtask
    task late_branch(input integer p,input integer condition_code,input [31:0] x,
        input [31:0] y,input bit taken,input integer mask,input [31:0] displacement,
        input bit fault);
        @(negedge clk_i);
        if(p==0)begin
            execute0_valid_i=1;execute0_late_i=1;execute0_tag_i=2;
            execute0_instr_i=(32'(condition_code)<<12)|32'h63;
            execute0_pc_i=32'h100;execute0_imm_i=displacement;
            execute0_src1_i=(mask&1)!=0?0:x;execute0_src2_i=(mask&2)!=0?0:y;
            execute0_source1_wait_i=(mask&1)!=0;execute0_source2_wait_i=(mask&2)!=0;
            execute0_source1_tag_i=0;execute0_source2_tag_i=1;
        end else begin
            execute1_valid_i=1;execute1_late_i=1;execute1_tag_i=2;
            execute1_instr_i=(32'(condition_code)<<12)|32'h63;
            execute1_pc_i=32'h100;execute1_imm_i=displacement;
            execute1_src1_i=(mask&1)!=0?0:x;execute1_src2_i=(mask&2)!=0?0:y;
            execute1_source1_wait_i=(mask&1)!=0;execute1_source2_wait_i=(mask&2)!=0;
            execute1_source1_tag_i=0;execute1_source2_tag_i=1;
        end
        tick();execute0_valid_i=0;execute1_valid_i=0;
        if(branch_complete_valid_o)$fatal(1,"unavailable late branch operand used");
        wb0_valid_i=(mask&1)!=0;wb0_tag_i=0;wb0_data_i=x;
        wb1_valid_i=(mask&2)!=0;wb1_tag_i=1;wb1_data_i=y;
        tick();wb0_valid_i=0;wb1_valid_i=0;#1;
        if(!branch_complete_valid_o || branch_complete_tag_o!==2 ||
            branch_complete_exception_o!==fault ||
            branch_complete_next_pc_o!==(taken?(32'h100+displacement):32'h104))
            $fatal(1,"late condition %0d pipe%0d mask%0d next%h",condition_code,p,mask,
                branch_complete_next_pc_o);
        tick();
        if(mem_predict_train_valid_o!==!fault ||
            (!fault && mem_predict_train_taken_o!==taken) || ex_predict_train_valid_o ||
            branch_redirect_valid_o!==(taken&&!fault))
            $fatal(1,"late branch training stage/direction");
        execute0_late_i=0;execute1_late_i=0;
        execute0_source1_wait_i=0;execute0_source2_wait_i=0;
        execute1_source1_wait_i=0;execute1_source2_wait_i=0;
        tick();if(mem_predict_train_valid_o)$fatal(1,"duplicate late train");
    endtask
    reg [31:0] x,y;
    bit expected;
    initial begin
        tick();rst_n_i=1;branch_complete_ready_i=1;tick();
        // I06: a held pipe0 result must not select an invalid pipe1 with the same tag.
        @(negedge clk_i);
        branch_complete_ready_i=0;
        execute0_valid_i=1; execute0_tag_i=0; execute1_tag_i=0;
        execute0_instr_i=32'h1063; execute0_pc_i=32'h100;
        execute0_imm_i=32'h20; execute0_src1_i=0; execute0_src2_i=0;
        tick(); execute0_valid_i=0; #1;
        if(!branch_complete_valid_o || branch_complete_tag_o!==0)
            $fatal(1,"held pipe0 branch lost to invalid pipe1 tag alias");
        tick();
        if(!branch_complete_valid_o)$fatal(1,"held branch did not remain valid");
        branch_complete_ready_i=1; tick();
        if(ISSUE_WIDTH==2) begin
            // Cancel a newly ready MEM result before it has acquired a completion lock.
            @(negedge clk_i);
            execute0_valid_i=1; execute0_tag_i=2; execute0_late_i=1;
            execute0_source1_wait_i=1; execute0_source1_tag_i=0;
            tick(); execute0_valid_i=0;
            wb0_valid_i=1; wb0_tag_i=0; wb0_data_i=0;
            tick(); wb0_valid_i=0;
            branch_complete_ready_i=0; cancel_valid_i=1; cancel_tag_i=2;
            tick(); cancel_valid_i=0;
            execute0_late_i=0; execute0_source1_wait_i=0;
            execute0_valid_i=1; execute0_tag_i=3; branch_complete_ready_i=1; #1;
            if(!branch_complete_valid_o || branch_complete_tag_o!==3)
                $fatal(1,"canceled newly ready MEM result left a branch lock");
            tick(); execute0_valid_i=0; tick();
        end
        for(integer p=0;p<ISSUE_WIDTH;p++) begin
            for(integer f=0;f<8;f++) begin
                if(f!=2 && f!=3) begin
                    for(integer n=0;n<20;n++) begin
                        x=$random;y=(n%2!=0)?x:$random;
                        case(f)
                            0: expected=x==y;
                            1: expected=x!=y;
                            4: expected=$signed(x)<$signed(y);
                            5: expected=$signed(x)>=$signed(y);
                            6: expected=x<y;
                            7: expected=x>=y;
                            default: expected=0;
                        endcase
                        branch(p,(32'(f)<<12)|32'h63,x,y,32'h20,expected,32'h120,0,0);
                    end
                end
            end
            branch(p,32'h0000006f,0,0,32'h20,1,32'h120,0,1);
            branch(p,32'h000000ef,0,0,32'h20,1,32'h120,0,3);
            branch(p,32'h00008067,32'h201,0,4,1,32'h204,0,4);
            branch(p,32'h000082e7,32'h201,0,4,1,32'h204,0,5);
            branch(p,32'h0000006f,0,0,2,1,32'h102,1,1);
        end
        if(ISSUE_WIDTH==2) begin
            // An early miss must wait; the captured early hit supplies this branch source.
            @(negedge clk_i);execute0_valid_i=1;execute0_late_i=1;execute0_tag_i=2;
            execute0_instr_i=32'h1063;execute0_pc_i=32'h100;execute0_imm_i=32'h20;
            execute0_source1_wait_i=1;execute0_source1_tag_i=0;
            execute0_src1_i=0;execute0_src2_i=33;
            tick();execute0_valid_i=0;
            early_resp_valid_i=1;early_resp_tag_i=0;early_resp_data_i=33;
            early_resp_hit_i=0;tick();
            if(branch_complete_valid_o)$fatal(1,"failed early query released branch source");
            early_resp_hit_i=1;tick();early_resp_valid_i=0;early_resp_hit_i=0;
            if(!branch_complete_valid_o || branch_complete_next_pc_o!=32'h104)
                $fatal(1,"captured early hit did not supply branch source");
            tick();execute0_late_i=0;execute0_source1_wait_i=0;tick();
            for(integer pipeline=0;pipeline<2;pipeline++)begin
                for(integer condition_code=0;condition_code<8;condition_code++)begin
                    if(condition_code!=2 && condition_code!=3)begin
                        for(integer operands=0;operands<3;operands++)begin
                            x=operands==0?32'h80000001:operands==1?3:1;y=3;
                            case(condition_code)
                                0:expected=x==y;
                                1:expected=x!=y;
                                4:expected=$signed(x)<$signed(y);
                                5:expected=$signed(x)>=$signed(y);
                                6:expected=x<y;
                                7:expected=x>=y;
                                default:expected=0;
                            endcase
                            for(integer mask=1;mask<4;mask++)
                                late_branch(pipeline,condition_code,x,y,expected,mask,32'h20,0);
                        end
                    end
                end
            end

            late_branch(0,0,3,3,1,1,2,1);
            late_branch(1,1,3,3,0,2,2,0);
            @(negedge clk_i);
            execute1_valid_i=1;execute1_late_i=1;execute1_source1_wait_i=1;
            execute1_source1_tag_i=0;execute1_tag_i=1;
            execute1_instr_i=32'h00001063;execute1_src1_i=0;execute1_src2_i=0;
            execute1_pc_i=32'h100;execute1_imm_i=32'h20;
            tick();execute1_valid_i=0;tick();
            repeat(3)begin if(branch_complete_valid_o)$fatal(1,"early wait branch");tick();end
            lsu_complete_device_i=1;
            lsu_complete_valid_i=1;lsu_complete_ready_i=1;lsu_complete_tag_i=0;
            lsu_complete_data_i=B'(32'hbad);tick();lsu_complete_valid_i=0;
            lsu_complete_device_i=0;
            if(branch_complete_valid_o)$fatal(1,"branch used device preparation");
            wb0_valid_i=1;wb0_tag_i=0;wb0_data_i=5;

            tick();wb0_valid_i=0;
            if(!branch_complete_valid_o || branch_complete_next_pc_o!==32'h120)
                $fatal(1,"late branch wrong direction");
            tick();if(!mem_predict_train_valid_o || !branch_redirect_valid_o)
                $fatal(1,"late branch stage");
            tick();execute1_late_i=0;execute1_source1_wait_i=0;
        end
        @(negedge clk_i);
        execute0_valid_i=1;execute0_pc_i=32'h100;execute0_imm_i=32'h20;
        execute0_instr_i=32'h6f;execute0_tag_i=1;branch_complete_ready_i=0;
        tick();execute0_valid_i=0;cancel_valid_i=1;cancel_tag_i=1;
        tick();cancel_valid_i=0;
        if(branch_complete_valid_o || branch_redirect_valid_o || ex_predict_train_valid_o)
            $fatal(1,"canceled branch trained/redirected");
        $display("PASS branch ISSUE_WIDTH=%0d FPU_FORMAT=%s",ISSUE_WIDTH,FPU_FORMAT);
        $finish;
    end
endmodule
