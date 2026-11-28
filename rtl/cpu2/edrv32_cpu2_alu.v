// File: edrv32_cpu2_alu.v
// Spec: cpu-v2-spec 3.2, 3.4, 5.2-5.3.
// Description: Registered issue ID/EX drives the early ALU; local skid and MEM retain blocked results.
// Registered capacity isolates ID; accepted completions capture waiting operands before reuse.
// Clock domain: clk_sys.
module edrv32_cpu2_alu #(
    parameter ISSUE_WIDTH = 2,
    parameter [31:0] FPU_FORMAT = "NONE"
) (
    // Execute inputs, completion snoops and per-pipeline result interfaces.
    input wire lsu_complete_device_i,
    // Frozen early return: data was captured locally by LSU before operand capture.
    input wire early_resp_valid_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] early_resp_tag_i,
    input wire early_resp_hit_i,
    input wire [31:0] early_resp_data_i,
    input wire wb0_valid_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] wb0_tag_i,
    input wire [31:0] wb0_data_i,
    input wire wb1_valid_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] wb1_tag_i,
    input wire [31:0] wb1_data_i,
    input wire clk_i,
    input wire rst_n_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] age_head_i,
    input wire cancel_valid_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] cancel_tag_i,
    input wire execute0_valid_i,
    output wire execute0_ready_o,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] execute0_tag_i,
    input wire [32-1:0] execute0_pc_i,
    input wire [32-1:0] execute0_instr_i,
    input wire [32-1:0] execute0_src1_i,
    input wire [32-1:0] execute0_src2_i,
    input wire [32-1:0] execute0_imm_i,
    input wire execute0_late_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] execute0_source1_tag_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] execute0_source2_tag_i,
    input wire execute0_source1_wait_i,
    input wire execute0_source2_wait_i,
    input wire execute1_valid_i,
    output wire execute1_ready_o,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] execute1_tag_i,
    input wire [32-1:0] execute1_pc_i,
    input wire [32-1:0] execute1_instr_i,
    input wire [32-1:0] execute1_src1_i,
    input wire [32-1:0] execute1_src2_i,
    input wire [32-1:0] execute1_imm_i,
    input wire execute1_late_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] execute1_source1_tag_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] execute1_source2_tag_i,
    input wire execute1_source1_wait_i,
    input wire execute1_source2_wait_i,
    input wire alu0_complete_valid_i,
    input wire alu0_complete_ready_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] alu0_complete_tag_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] alu0_complete_data_i,
    input wire alu1_complete_valid_i,
    input wire alu1_complete_ready_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] alu1_complete_tag_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] alu1_complete_data_i,
    input wire branch_complete_valid_i,
    input wire branch_complete_ready_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] branch_complete_tag_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] branch_complete_data_i,
    input wire mul_complete_valid_i,
    input wire mul_complete_ready_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] mul_complete_tag_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] mul_complete_data_i,
    input wire div_complete_valid_i,
    input wire div_complete_ready_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] div_complete_tag_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] div_complete_data_i,
    input wire lsu_complete_valid_i,
    input wire lsu_complete_ready_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] lsu_complete_tag_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] lsu_complete_data_i,
    input wire csr_complete_valid_i,
    input wire csr_complete_ready_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] csr_complete_tag_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] csr_complete_data_i,
    input wire fp_resp_valid_i,
    input wire fp_resp_ready_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] fp_resp_tag_i,
    input wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] fp_resp_data_i,
    output wire alu0_complete_valid_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] alu0_complete_tag_o,
    output wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] alu0_complete_data_o,
    output wire [5-1:0] alu0_complete_flags_o,
    output wire alu0_complete_exception_o,
    output wire [4-1:0] alu0_complete_cause_o,
    output wire [32-1:0] alu0_complete_tval_o,
    output wire alu1_complete_valid_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] alu1_complete_tag_o,
    output wire [((|(FPU_FORMAT ^ "FD")) ? 32 : 64)-1:0] alu1_complete_data_o,
    output wire [5-1:0] alu1_complete_flags_o,
    output wire alu1_complete_exception_o,
    output wire [4-1:0] alu1_complete_cause_o,
    output wire [32-1:0] alu1_complete_tval_o,
    output wire [1:0] debug_mem_valid_o
);
    localparam T = ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3;
    localparam B = (FPU_FORMAT == "FD") ? 64 : 32;
    generate
        if (ISSUE_WIDTH > 0) begin : g_pipe0
            reg skid_valid_r;
            reg [T-1:0] skid_tag_r;
            reg [31:0] skid_data_r;
            reg mem_valid_r;
            assign debug_mem_valid_o[0] = mem_valid_r;
            reg [T-1:0] mem_tag_r;
            reg [31:0] mem_instr_r;
            reg [31:0] mem_src1_r;
            reg [31:0] mem_src2_r;
            reg [31:0] mem_imm_r;
            reg [T-1:0] mem_source1_tag_r;
            reg [T-1:0] mem_source2_tag_r;
            reg mem_wait1_r;
            reg mem_wait2_r;
            wire ex_valid_r = execute0_valid_i && execute0_ready_o && !input_cancel_w;
            wire ex_late_r = (ISSUE_WIDTH == 2) && execute0_late_i;
            wire [T-1:0] ex_tag_r = execute0_tag_i;
            wire [32-1:0] ex_pc_r = execute0_pc_i;
            wire [32-1:0] ex_instr_r = execute0_instr_i;
            wire [32-1:0] ex_src1_r = execute0_src1_i;
            wire [32-1:0] ex_src2_r = execute0_src2_i;
            wire [32-1:0] ex_imm_r = execute0_imm_i;
            wire [T-1:0] ex_source1_tag_r = execute0_source1_tag_i;
            wire [T-1:0] ex_source2_tag_r = execute0_source2_tag_i;
            wire ex_wait1_r = (ISSUE_WIDTH == 2) && execute0_source1_wait_i;
            wire ex_wait2_r = (ISSUE_WIDTH == 2) && execute0_source2_wait_i;
            wire [T-1:0] ex_age_w = ex_tag_r - age_head_i;
            wire [T-1:0] cancel_age_w = cancel_tag_i - age_head_i;
            wire ex_cancel_w = cancel_valid_i && (ex_age_w >= cancel_age_w);
            wire [T-1:0] skid_age_w = skid_tag_r - age_head_i;
            wire skid_cancel_w = skid_valid_r && cancel_valid_i && (skid_age_w >= cancel_age_w);
            wire [T-1:0] mem_age_w = mem_tag_r - age_head_i;
            wire mem_cancel_w = mem_valid_r && cancel_valid_i && (mem_age_w >= cancel_age_w);
            wire [T-1:0] input_age_w = execute0_tag_i - age_head_i;
            wire input_cancel_w = execute0_valid_i && cancel_valid_i &&
                (input_age_w >= cancel_age_w);
            wire ex_early_w = ex_valid_r && !ex_late_r;
            // Both operand choices below come from local/LSU registers, never D$ RAM.
            wire mem_ready_w = mem_valid_r && (!mem_wait1_r || mem_source1_early_w) &&
                (!mem_wait2_r || mem_source2_early_w);
            assign execute0_ready_o = ex_late_r ?
                (!mem_valid_r || (mem_ready_w && !skid_valid_r)) : !skid_valid_r;
            wire transfer_w = ex_valid_r && ex_late_r;
            reg lock_valid_r;
            reg [T-1:0] lock_tag_r;
            wire candidate_skid_w = skid_valid_r &&
                (!mem_ready_w || (skid_age_w < mem_age_w));
            wire candidate_mem_w = mem_ready_w && !candidate_skid_w &&
                (!ex_early_w || (mem_age_w < ex_age_w));
            wire candidate_ex_w = ex_early_w && !candidate_skid_w && !candidate_mem_w;
            wire select_skid_w = lock_valid_r ?
                (skid_valid_r && (skid_tag_r == lock_tag_r)) : candidate_skid_w;
            wire select_mem_w = lock_valid_r ?
                (mem_ready_w && (mem_tag_r == lock_tag_r)) : candidate_mem_w;
            wire select_ex_w = lock_valid_r ?
                (ex_early_w && (ex_tag_r == lock_tag_r)) : candidate_ex_w;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    lock_valid_r <= 1'b0;
                else if (alu0_complete_valid_o && alu0_complete_ready_i)
                    lock_valid_r <= 1'b0;
                else if (lock_valid_r && cancel_valid_i &&
                    ((lock_tag_r-age_head_i) >= cancel_age_w))
                    lock_valid_r <= 1'b0;
                else if (alu0_complete_valid_o &&
                    !(cancel_valid_i && (alu0_complete_tag_o-age_head_i) >= cancel_age_w))
                    lock_valid_r <= 1'b1;
            end
            always @(posedge clk_i) begin
                if (alu0_complete_valid_o && !alu0_complete_ready_i)
                    lock_tag_r <= alu0_complete_tag_o;
            end
            wire ex_done_w = select_ex_w && alu0_complete_ready_i;
            wire skid_done_w = select_skid_w && alu0_complete_ready_i;
            wire mem_done_w = select_mem_w && alu0_complete_ready_i;
            // Reuse the EX result skid when a ready MEM slot is replaced under backpressure.
            wire stash_mem_w = transfer_w && mem_valid_r && !mem_done_w && !mem_cancel_w;
            wire stash_w = (ex_early_w && !skid_valid_r && !ex_done_w) || stash_mem_w;
            wire ex_hit1_w;
            wire [31:0] ex_capture1_w;
            wire ex_source1_early_w = early_resp_valid_i && early_resp_hit_i &&
                (early_resp_tag_i == ex_source1_tag_r);
            wire ex_source1_0_w = alu0_complete_valid_i && alu0_complete_ready_i &&
                (alu0_complete_tag_i == ex_source1_tag_r);
            wire ex_source1_1_w = alu1_complete_valid_i && alu1_complete_ready_i &&
                (alu1_complete_tag_i == ex_source1_tag_r);
            wire ex_source1_2_w = branch_complete_valid_i && branch_complete_ready_i &&
                (branch_complete_tag_i == ex_source1_tag_r);
            wire ex_source1_3_w = mul_complete_valid_i && mul_complete_ready_i &&
                (mul_complete_tag_i == ex_source1_tag_r);
            wire ex_source1_4_w = div_complete_valid_i && div_complete_ready_i &&
                (div_complete_tag_i == ex_source1_tag_r);
            wire ex_source1_5_w = lsu_complete_valid_i && lsu_complete_ready_i &&
                !lsu_complete_device_i &&
                (lsu_complete_tag_i == ex_source1_tag_r);
            wire ex_source1_6_w = csr_complete_valid_i && csr_complete_ready_i &&
                (csr_complete_tag_i == ex_source1_tag_r);
            wire ex_source1_7_w = fp_resp_valid_i && fp_resp_ready_i &&
                (fp_resp_tag_i == ex_source1_tag_r);
            wire ex_source1_wb0_w = wb0_valid_i && (wb0_tag_i == ex_source1_tag_r);
            wire ex_source1_wb1_w = (ISSUE_WIDTH == 2) && wb1_valid_i &&
                (wb1_tag_i == ex_source1_tag_r);
            assign ex_hit1_w = ex_source1_early_w || ex_source1_0_w ||
                ex_source1_1_w ||
                ex_source1_2_w ||
                ex_source1_3_w ||
                ex_source1_4_w ||
                ex_source1_5_w ||
                ex_source1_6_w ||
                ex_source1_7_w || ex_source1_wb0_w || ex_source1_wb1_w;
            assign ex_capture1_w = ({32{ex_source1_early_w}} & early_resp_data_i) |
                ({32{ex_source1_0_w}} & alu0_complete_data_i[31:0]) |
                ({32{ex_source1_1_w}} & alu1_complete_data_i[31:0]) |
                ({32{ex_source1_2_w}} & branch_complete_data_i[31:0]) |
                ({32{ex_source1_3_w}} & mul_complete_data_i[31:0]) |
                ({32{ex_source1_4_w}} & div_complete_data_i[31:0]) |
                ({32{ex_source1_5_w}} & lsu_complete_data_i[31:0]) |
                ({32{ex_source1_6_w}} & csr_complete_data_i[31:0]) |
                ({32{ex_source1_7_w}} & fp_resp_data_i[31:0]) |
                ({32{ex_source1_wb0_w}} & wb0_data_i) |
                ({32{ex_source1_wb1_w}} & wb1_data_i);
            wire ex_hit2_w;
            wire [31:0] ex_capture2_w;
            wire ex_source2_early_w = early_resp_valid_i && early_resp_hit_i &&
                (early_resp_tag_i == ex_source2_tag_r);
            wire ex_source2_0_w = alu0_complete_valid_i && alu0_complete_ready_i &&
                (alu0_complete_tag_i == ex_source2_tag_r);
            wire ex_source2_1_w = alu1_complete_valid_i && alu1_complete_ready_i &&
                (alu1_complete_tag_i == ex_source2_tag_r);
            wire ex_source2_2_w = branch_complete_valid_i && branch_complete_ready_i &&
                (branch_complete_tag_i == ex_source2_tag_r);
            wire ex_source2_3_w = mul_complete_valid_i && mul_complete_ready_i &&
                (mul_complete_tag_i == ex_source2_tag_r);
            wire ex_source2_4_w = div_complete_valid_i && div_complete_ready_i &&
                (div_complete_tag_i == ex_source2_tag_r);
            wire ex_source2_5_w = lsu_complete_valid_i && lsu_complete_ready_i &&
                !lsu_complete_device_i &&
                (lsu_complete_tag_i == ex_source2_tag_r);
            wire ex_source2_6_w = csr_complete_valid_i && csr_complete_ready_i &&
                (csr_complete_tag_i == ex_source2_tag_r);
            wire ex_source2_7_w = fp_resp_valid_i && fp_resp_ready_i &&
                (fp_resp_tag_i == ex_source2_tag_r);
            wire ex_source2_wb0_w = wb0_valid_i && (wb0_tag_i == ex_source2_tag_r);
            wire ex_source2_wb1_w = (ISSUE_WIDTH == 2) && wb1_valid_i &&
                (wb1_tag_i == ex_source2_tag_r);
            assign ex_hit2_w = ex_source2_early_w || ex_source2_0_w ||
                ex_source2_1_w ||
                ex_source2_2_w ||
                ex_source2_3_w ||
                ex_source2_4_w ||
                ex_source2_5_w ||
                ex_source2_6_w ||
                ex_source2_7_w || ex_source2_wb0_w || ex_source2_wb1_w;
            assign ex_capture2_w = ({32{ex_source2_early_w}} & early_resp_data_i) |
                ({32{ex_source2_0_w}} & alu0_complete_data_i[31:0]) |
                ({32{ex_source2_1_w}} & alu1_complete_data_i[31:0]) |
                ({32{ex_source2_2_w}} & branch_complete_data_i[31:0]) |
                ({32{ex_source2_3_w}} & mul_complete_data_i[31:0]) |
                ({32{ex_source2_4_w}} & div_complete_data_i[31:0]) |
                ({32{ex_source2_5_w}} & lsu_complete_data_i[31:0]) |
                ({32{ex_source2_6_w}} & csr_complete_data_i[31:0]) |
                ({32{ex_source2_7_w}} & fp_resp_data_i[31:0]) |
                ({32{ex_source2_wb0_w}} & wb0_data_i) |
                ({32{ex_source2_wb1_w}} & wb1_data_i);
            wire mem_hit1_w;
            wire [31:0] mem_capture1_w;
            wire mem_source1_early_w = early_resp_valid_i && early_resp_hit_i &&
                (early_resp_tag_i == mem_source1_tag_r);
            wire mem_source1_0_w = alu0_complete_valid_i && alu0_complete_ready_i &&
                (alu0_complete_tag_i == mem_source1_tag_r);
            wire mem_source1_1_w = alu1_complete_valid_i && alu1_complete_ready_i &&
                (alu1_complete_tag_i == mem_source1_tag_r);
            wire mem_source1_2_w = branch_complete_valid_i && branch_complete_ready_i &&
                (branch_complete_tag_i == mem_source1_tag_r);
            wire mem_source1_3_w = mul_complete_valid_i && mul_complete_ready_i &&
                (mul_complete_tag_i == mem_source1_tag_r);
            wire mem_source1_4_w = div_complete_valid_i && div_complete_ready_i &&
                (div_complete_tag_i == mem_source1_tag_r);
            wire mem_source1_5_w = lsu_complete_valid_i && lsu_complete_ready_i &&
                !lsu_complete_device_i &&
                (lsu_complete_tag_i == mem_source1_tag_r);
            wire mem_source1_6_w = csr_complete_valid_i && csr_complete_ready_i &&
                (csr_complete_tag_i == mem_source1_tag_r);
            wire mem_source1_7_w = fp_resp_valid_i && fp_resp_ready_i &&
                (fp_resp_tag_i == mem_source1_tag_r);
            wire mem_source1_wb0_w = wb0_valid_i && (wb0_tag_i == mem_source1_tag_r);
            wire mem_source1_wb1_w = (ISSUE_WIDTH == 2) && wb1_valid_i &&
                (wb1_tag_i == mem_source1_tag_r);
            assign mem_hit1_w = mem_source1_early_w || mem_source1_0_w ||
                mem_source1_1_w ||
                mem_source1_2_w ||
                mem_source1_3_w ||
                mem_source1_4_w ||
                mem_source1_5_w ||
                mem_source1_6_w ||
                mem_source1_7_w || mem_source1_wb0_w || mem_source1_wb1_w;
            assign mem_capture1_w = ({32{mem_source1_early_w}} & early_resp_data_i) |
                ({32{mem_source1_0_w}} & alu0_complete_data_i[31:0]) |
                ({32{mem_source1_1_w}} & alu1_complete_data_i[31:0]) |
                ({32{mem_source1_2_w}} & branch_complete_data_i[31:0]) |
                ({32{mem_source1_3_w}} & mul_complete_data_i[31:0]) |
                ({32{mem_source1_4_w}} & div_complete_data_i[31:0]) |
                ({32{mem_source1_5_w}} & lsu_complete_data_i[31:0]) |
                ({32{mem_source1_6_w}} & csr_complete_data_i[31:0]) |
                ({32{mem_source1_7_w}} & fp_resp_data_i[31:0]) |
                ({32{mem_source1_wb0_w}} & wb0_data_i) |
                ({32{mem_source1_wb1_w}} & wb1_data_i);
            wire mem_hit2_w;
            wire [31:0] mem_capture2_w;
            wire mem_source2_early_w = early_resp_valid_i && early_resp_hit_i &&
                (early_resp_tag_i == mem_source2_tag_r);
            wire mem_source2_0_w = alu0_complete_valid_i && alu0_complete_ready_i &&
                (alu0_complete_tag_i == mem_source2_tag_r);
            wire mem_source2_1_w = alu1_complete_valid_i && alu1_complete_ready_i &&
                (alu1_complete_tag_i == mem_source2_tag_r);
            wire mem_source2_2_w = branch_complete_valid_i && branch_complete_ready_i &&
                (branch_complete_tag_i == mem_source2_tag_r);
            wire mem_source2_3_w = mul_complete_valid_i && mul_complete_ready_i &&
                (mul_complete_tag_i == mem_source2_tag_r);
            wire mem_source2_4_w = div_complete_valid_i && div_complete_ready_i &&
                (div_complete_tag_i == mem_source2_tag_r);
            wire mem_source2_5_w = lsu_complete_valid_i && lsu_complete_ready_i &&
                !lsu_complete_device_i &&
                (lsu_complete_tag_i == mem_source2_tag_r);
            wire mem_source2_6_w = csr_complete_valid_i && csr_complete_ready_i &&
                (csr_complete_tag_i == mem_source2_tag_r);
            wire mem_source2_7_w = fp_resp_valid_i && fp_resp_ready_i &&
                (fp_resp_tag_i == mem_source2_tag_r);
            wire mem_source2_wb0_w = wb0_valid_i && (wb0_tag_i == mem_source2_tag_r);
            wire mem_source2_wb1_w = (ISSUE_WIDTH == 2) && wb1_valid_i &&
                (wb1_tag_i == mem_source2_tag_r);
            assign mem_hit2_w = mem_source2_early_w || mem_source2_0_w ||
                mem_source2_1_w ||
                mem_source2_2_w ||
                mem_source2_3_w ||
                mem_source2_4_w ||
                mem_source2_5_w ||
                mem_source2_6_w ||
                mem_source2_7_w || mem_source2_wb0_w || mem_source2_wb1_w;
            assign mem_capture2_w = ({32{mem_source2_early_w}} & early_resp_data_i) |
                ({32{mem_source2_0_w}} & alu0_complete_data_i[31:0]) |
                ({32{mem_source2_1_w}} & alu1_complete_data_i[31:0]) |
                ({32{mem_source2_2_w}} & branch_complete_data_i[31:0]) |
                ({32{mem_source2_3_w}} & mul_complete_data_i[31:0]) |
                ({32{mem_source2_4_w}} & div_complete_data_i[31:0]) |
                ({32{mem_source2_5_w}} & lsu_complete_data_i[31:0]) |
                ({32{mem_source2_6_w}} & csr_complete_data_i[31:0]) |
                ({32{mem_source2_7_w}} & fp_resp_data_i[31:0]) |
                ({32{mem_source2_wb0_w}} & wb0_data_i) |
                ({32{mem_source2_wb1_w}} & wb1_data_i);
            wire [31:0] ex_b_w = (ex_instr_r[6:0] == 7'h13) ?
                ex_imm_r : ex_src2_r;
            wire [31:0] ex_arithmetic_right_w = $signed(ex_src1_r) >>> ex_b_w[4:0];
            reg [31:0] ex_a_w;
            reg [31:0] ex_result_w;
            always @(*) begin
                ex_a_w = ex_src1_r;
                ex_result_w = 32'd0;
                if (ex_instr_r[6:0] == 7'h17)
                    ex_a_w = ex_pc_r;
                if ((ex_instr_r[6:0] == 7'h33) &&
                    (ex_instr_r[31:25] == 7'h10)) begin
                    case (ex_instr_r[14:12])
                        3'd2: ex_a_w = ex_src1_r << 1;
                        3'd4: ex_a_w = ex_src1_r << 2;
                        3'd6: ex_a_w = ex_src1_r << 3;
                        default: ex_a_w = ex_src1_r;
                    endcase
                end
                case (ex_instr_r[14:12])
                    3'd0: ex_result_w = ex_a_w + ex_b_w;
                    3'd1: ex_result_w = ex_a_w << ex_b_w[4:0];
                    3'd2: ex_result_w = {31'd0, $signed(ex_a_w) < $signed(ex_b_w)};
                    3'd3: ex_result_w = {31'd0, ex_a_w < ex_b_w};
                    3'd4: ex_result_w = ex_a_w ^ ex_b_w;
                    3'd5: ex_result_w = ex_instr_r[30] ?
                        ex_arithmetic_right_w :
                        (ex_a_w >> ex_b_w[4:0]);
                    3'd6: ex_result_w = ex_a_w | ex_b_w;
                    3'd7: ex_result_w = ex_a_w & ex_b_w;
                    default: ex_result_w = 32'd0;
                endcase
                begin
                if ((ex_instr_r[6:0] == 7'h33) &&
                    (ex_instr_r[31:25] == 7'h20) && (ex_instr_r[14:12] == 3'd0))
                    ex_result_w = ex_a_w - ex_b_w;
                if ((ex_instr_r[6:0] == 7'h33) &&
                    (ex_instr_r[31:25] == 7'h10))
                    ex_result_w = ex_a_w + ex_b_w;
                if (ex_instr_r[6:0] == 7'h37)
                    ex_result_w = ex_imm_r;
                if (ex_instr_r[6:0] == 7'h17)
                    ex_result_w = ex_a_w + ex_imm_r;
                end
            end
            wire [31:0] mem_operand1_w = mem_wait1_r && mem_source1_early_w ?
                early_resp_data_i : mem_src1_r;
            wire [31:0] mem_operand2_w = mem_wait2_r && mem_source2_early_w ?
                early_resp_data_i : mem_src2_r;
            wire [31:0] mem_b_w = (mem_instr_r[6:0] == 7'h13) ?
                mem_imm_r : mem_operand2_w;
            reg [31:0] mem_a_w;
            reg [31:0] mem_result_w;
            always @(*) begin
                mem_a_w = mem_operand1_w;
                mem_result_w = 32'd0;
                if ((mem_instr_r[6:0] == 7'h33) &&
                    (mem_instr_r[31:25] == 7'h10)) begin
                    case (mem_instr_r[14:12])
                        3'd2: mem_a_w = mem_operand1_w << 1;
                        3'd4: mem_a_w = mem_operand1_w << 2;
                        3'd6: mem_a_w = mem_operand1_w << 3;
                        default: mem_a_w = mem_operand1_w;
                    endcase
                end
                case (mem_instr_r[14:12])
                    3'd0: mem_result_w = mem_a_w + mem_b_w;
                    3'd2: mem_result_w = {31'd0, $signed(mem_a_w) < $signed(mem_b_w)};
                    3'd3: mem_result_w = {31'd0, mem_a_w < mem_b_w};
                    3'd4: mem_result_w = mem_a_w ^ mem_b_w;
                    3'd6: mem_result_w = mem_a_w | mem_b_w;
                    3'd7: mem_result_w = mem_a_w & mem_b_w;
                    default: mem_result_w = 32'd0;
                endcase
                begin
                if ((mem_instr_r[6:0] == 7'h33) &&
                    (mem_instr_r[31:25] == 7'h20) && (mem_instr_r[14:12] == 3'd0))
                    mem_result_w = mem_a_w - mem_b_w;
                if ((mem_instr_r[6:0] == 7'h33) &&
                    (mem_instr_r[31:25] == 7'h10))
                    mem_result_w = mem_a_w + mem_b_w;
                end
            end
            /* verilator lint_off UNUSEDSIGNAL */
            wire unused_instr_w = ^mem_instr_r;
            /* verilator lint_on UNUSEDSIGNAL */
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    skid_valid_r <= 1'b0;
                    mem_valid_r <= 1'b0;
                    mem_wait1_r <= 1'b0;
                    mem_wait2_r <= 1'b0;
                end else begin
                    if (skid_done_w || skid_cancel_w)
                        skid_valid_r <= 1'b0;
                    if (stash_w && !ex_cancel_w)
                        skid_valid_r <= 1'b1;
                    if (mem_done_w || mem_cancel_w)
                        mem_valid_r <= 1'b0;
                    if (mem_hit1_w)
                        mem_wait1_r <= 1'b0;
                    if (mem_hit2_w)
                        mem_wait2_r <= 1'b0;
                    if (transfer_w && !ex_cancel_w) begin
                        mem_valid_r <= 1'b1;
                        mem_wait1_r <= ex_wait1_r && !ex_hit1_w;
                        mem_wait2_r <= ex_wait2_r && !ex_hit2_w;
                    end
                end
            end
            always @(posedge clk_i) begin
                if (stash_w) begin
                    skid_tag_r <= stash_mem_w ? mem_tag_r : ex_tag_r;
                    skid_data_r <= stash_mem_w ? mem_result_w : ex_result_w;
                end
                if (transfer_w) begin
                    mem_tag_r <= ex_tag_r;
                    mem_instr_r <= ex_instr_r;
                    mem_imm_r <= ex_imm_r;
                    mem_source1_tag_r <= ex_source1_tag_r;
                    mem_source2_tag_r <= ex_source2_tag_r;
                    mem_src1_r <= (ex_wait1_r && ex_hit1_w) ?
                        ex_capture1_w : ex_src1_r;
                    mem_src2_r <= (ex_wait2_r && ex_hit2_w) ?
                        ex_capture2_w : ex_src2_r;
                end else begin
                    if (mem_wait1_r && mem_hit1_w)
                        mem_src1_r <= mem_capture1_w;
                    if (mem_wait2_r && mem_hit2_w)
                        mem_src2_r <= mem_capture2_w;
                end
            end
            assign alu0_complete_valid_o = select_skid_w || select_mem_w || select_ex_w;
            assign alu0_complete_tag_o = select_skid_w ? skid_tag_r :
                select_mem_w ? mem_tag_r : ex_tag_r;
            assign alu0_complete_data_o = {{(B-32){1'b0}},
                select_skid_w ? skid_data_r : select_mem_w ? mem_result_w : ex_result_w};
            assign alu0_complete_flags_o = 5'd0;
            assign alu0_complete_exception_o = 1'd0;
            assign alu0_complete_cause_o = 4'd0;
            assign alu0_complete_tval_o = 32'd0;
        end else begin : g_inactive0
            assign alu0_complete_valid_o = 1'd0;
            assign alu0_complete_tag_o = {T{1'b0}};
            assign alu0_complete_data_o = {B{1'b0}};
            assign alu0_complete_flags_o = 5'd0;
            assign alu0_complete_exception_o = 1'd0;
            assign alu0_complete_cause_o = 4'd0;
            assign alu0_complete_tval_o = 32'd0;
            assign execute0_ready_o = 1'b0;
            assign debug_mem_valid_o[0] = 1'b0;
        end
    endgenerate
    generate
        if (ISSUE_WIDTH > 1) begin : g_pipe1
            reg skid_valid_r;
            reg [T-1:0] skid_tag_r;
            reg [31:0] skid_data_r;
            reg mem_valid_r;
            assign debug_mem_valid_o[1] = mem_valid_r;
            reg [T-1:0] mem_tag_r;
            reg [31:0] mem_instr_r;
            reg [31:0] mem_src1_r;
            reg [31:0] mem_src2_r;
            reg [31:0] mem_imm_r;
            reg [T-1:0] mem_source1_tag_r;
            reg [T-1:0] mem_source2_tag_r;
            reg mem_wait1_r;
            reg mem_wait2_r;
            wire ex_valid_r = execute1_valid_i && execute1_ready_o && !input_cancel_w;
            wire ex_late_r = (ISSUE_WIDTH == 2) && execute1_late_i;
            wire [T-1:0] ex_tag_r = execute1_tag_i;
            wire [32-1:0] ex_pc_r = execute1_pc_i;
            wire [32-1:0] ex_instr_r = execute1_instr_i;
            wire [32-1:0] ex_src1_r = execute1_src1_i;
            wire [32-1:0] ex_src2_r = execute1_src2_i;
            wire [32-1:0] ex_imm_r = execute1_imm_i;
            wire [T-1:0] ex_source1_tag_r = execute1_source1_tag_i;
            wire [T-1:0] ex_source2_tag_r = execute1_source2_tag_i;
            wire ex_wait1_r = (ISSUE_WIDTH == 2) && execute1_source1_wait_i;
            wire ex_wait2_r = (ISSUE_WIDTH == 2) && execute1_source2_wait_i;
            wire [T-1:0] ex_age_w = ex_tag_r - age_head_i;
            wire [T-1:0] cancel_age_w = cancel_tag_i - age_head_i;
            wire ex_cancel_w = cancel_valid_i && (ex_age_w >= cancel_age_w);
            wire [T-1:0] skid_age_w = skid_tag_r - age_head_i;
            wire skid_cancel_w = skid_valid_r && cancel_valid_i && (skid_age_w >= cancel_age_w);
            wire [T-1:0] mem_age_w = mem_tag_r - age_head_i;
            wire mem_cancel_w = mem_valid_r && cancel_valid_i && (mem_age_w >= cancel_age_w);
            wire [T-1:0] input_age_w = execute1_tag_i - age_head_i;
            wire input_cancel_w = execute1_valid_i && cancel_valid_i &&
                (input_age_w >= cancel_age_w);
            wire ex_early_w = ex_valid_r && !ex_late_r;
            // Both operand choices below come from local/LSU registers, never D$ RAM.
            wire mem_ready_w = mem_valid_r && (!mem_wait1_r || mem_source1_early_w) &&
                (!mem_wait2_r || mem_source2_early_w);
            assign execute1_ready_o = ex_late_r ?
                (!mem_valid_r || (mem_ready_w && !skid_valid_r)) : !skid_valid_r;
            wire transfer_w = ex_valid_r && ex_late_r;
            reg lock_valid_r;
            reg [T-1:0] lock_tag_r;
            wire candidate_skid_w = skid_valid_r &&
                (!mem_ready_w || (skid_age_w < mem_age_w));
            wire candidate_mem_w = mem_ready_w && !candidate_skid_w &&
                (!ex_early_w || (mem_age_w < ex_age_w));
            wire candidate_ex_w = ex_early_w && !candidate_skid_w && !candidate_mem_w;
            wire select_skid_w = lock_valid_r ?
                (skid_valid_r && (skid_tag_r == lock_tag_r)) : candidate_skid_w;
            wire select_mem_w = lock_valid_r ?
                (mem_ready_w && (mem_tag_r == lock_tag_r)) : candidate_mem_w;
            wire select_ex_w = lock_valid_r ?
                (ex_early_w && (ex_tag_r == lock_tag_r)) : candidate_ex_w;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    lock_valid_r <= 1'b0;
                else if (alu1_complete_valid_o && alu1_complete_ready_i)
                    lock_valid_r <= 1'b0;
                else if (lock_valid_r && cancel_valid_i &&
                    ((lock_tag_r-age_head_i) >= cancel_age_w))
                    lock_valid_r <= 1'b0;
                else if (alu1_complete_valid_o &&
                    !(cancel_valid_i && (alu1_complete_tag_o-age_head_i) >= cancel_age_w))
                    lock_valid_r <= 1'b1;
            end
            always @(posedge clk_i) begin
                if (alu1_complete_valid_o && !alu1_complete_ready_i)
                    lock_tag_r <= alu1_complete_tag_o;
            end
            wire ex_done_w = select_ex_w && alu1_complete_ready_i;
            wire skid_done_w = select_skid_w && alu1_complete_ready_i;
            wire mem_done_w = select_mem_w && alu1_complete_ready_i;
            // Reuse the EX result skid when a ready MEM slot is replaced under backpressure.
            wire stash_mem_w = transfer_w && mem_valid_r && !mem_done_w && !mem_cancel_w;
            wire stash_w = (ex_early_w && !skid_valid_r && !ex_done_w) || stash_mem_w;
            wire ex_hit1_w;
            wire [31:0] ex_capture1_w;
            wire ex_source1_early_w = early_resp_valid_i && early_resp_hit_i &&
                (early_resp_tag_i == ex_source1_tag_r);
            wire ex_source1_0_w = alu0_complete_valid_i && alu0_complete_ready_i &&
                (alu0_complete_tag_i == ex_source1_tag_r);
            wire ex_source1_1_w = alu1_complete_valid_i && alu1_complete_ready_i &&
                (alu1_complete_tag_i == ex_source1_tag_r);
            wire ex_source1_2_w = branch_complete_valid_i && branch_complete_ready_i &&
                (branch_complete_tag_i == ex_source1_tag_r);
            wire ex_source1_3_w = mul_complete_valid_i && mul_complete_ready_i &&
                (mul_complete_tag_i == ex_source1_tag_r);
            wire ex_source1_4_w = div_complete_valid_i && div_complete_ready_i &&
                (div_complete_tag_i == ex_source1_tag_r);
            wire ex_source1_5_w = lsu_complete_valid_i && lsu_complete_ready_i &&
                !lsu_complete_device_i &&
                (lsu_complete_tag_i == ex_source1_tag_r);
            wire ex_source1_6_w = csr_complete_valid_i && csr_complete_ready_i &&
                (csr_complete_tag_i == ex_source1_tag_r);
            wire ex_source1_7_w = fp_resp_valid_i && fp_resp_ready_i &&
                (fp_resp_tag_i == ex_source1_tag_r);
            wire ex_source1_wb0_w = wb0_valid_i && (wb0_tag_i == ex_source1_tag_r);
            wire ex_source1_wb1_w = (ISSUE_WIDTH == 2) && wb1_valid_i &&
                (wb1_tag_i == ex_source1_tag_r);
            assign ex_hit1_w = ex_source1_early_w || ex_source1_0_w ||
                ex_source1_1_w ||
                ex_source1_2_w ||
                ex_source1_3_w ||
                ex_source1_4_w ||
                ex_source1_5_w ||
                ex_source1_6_w ||
                ex_source1_7_w || ex_source1_wb0_w || ex_source1_wb1_w;
            assign ex_capture1_w = ({32{ex_source1_early_w}} & early_resp_data_i) |
                ({32{ex_source1_0_w}} & alu0_complete_data_i[31:0]) |
                ({32{ex_source1_1_w}} & alu1_complete_data_i[31:0]) |
                ({32{ex_source1_2_w}} & branch_complete_data_i[31:0]) |
                ({32{ex_source1_3_w}} & mul_complete_data_i[31:0]) |
                ({32{ex_source1_4_w}} & div_complete_data_i[31:0]) |
                ({32{ex_source1_5_w}} & lsu_complete_data_i[31:0]) |
                ({32{ex_source1_6_w}} & csr_complete_data_i[31:0]) |
                ({32{ex_source1_7_w}} & fp_resp_data_i[31:0]) |
                ({32{ex_source1_wb0_w}} & wb0_data_i) |
                ({32{ex_source1_wb1_w}} & wb1_data_i);
            wire ex_hit2_w;
            wire [31:0] ex_capture2_w;
            wire ex_source2_early_w = early_resp_valid_i && early_resp_hit_i &&
                (early_resp_tag_i == ex_source2_tag_r);
            wire ex_source2_0_w = alu0_complete_valid_i && alu0_complete_ready_i &&
                (alu0_complete_tag_i == ex_source2_tag_r);
            wire ex_source2_1_w = alu1_complete_valid_i && alu1_complete_ready_i &&
                (alu1_complete_tag_i == ex_source2_tag_r);
            wire ex_source2_2_w = branch_complete_valid_i && branch_complete_ready_i &&
                (branch_complete_tag_i == ex_source2_tag_r);
            wire ex_source2_3_w = mul_complete_valid_i && mul_complete_ready_i &&
                (mul_complete_tag_i == ex_source2_tag_r);
            wire ex_source2_4_w = div_complete_valid_i && div_complete_ready_i &&
                (div_complete_tag_i == ex_source2_tag_r);
            wire ex_source2_5_w = lsu_complete_valid_i && lsu_complete_ready_i &&
                !lsu_complete_device_i &&
                (lsu_complete_tag_i == ex_source2_tag_r);
            wire ex_source2_6_w = csr_complete_valid_i && csr_complete_ready_i &&
                (csr_complete_tag_i == ex_source2_tag_r);
            wire ex_source2_7_w = fp_resp_valid_i && fp_resp_ready_i &&
                (fp_resp_tag_i == ex_source2_tag_r);
            wire ex_source2_wb0_w = wb0_valid_i && (wb0_tag_i == ex_source2_tag_r);
            wire ex_source2_wb1_w = (ISSUE_WIDTH == 2) && wb1_valid_i &&
                (wb1_tag_i == ex_source2_tag_r);
            assign ex_hit2_w = ex_source2_early_w || ex_source2_0_w ||
                ex_source2_1_w ||
                ex_source2_2_w ||
                ex_source2_3_w ||
                ex_source2_4_w ||
                ex_source2_5_w ||
                ex_source2_6_w ||
                ex_source2_7_w || ex_source2_wb0_w || ex_source2_wb1_w;
            assign ex_capture2_w = ({32{ex_source2_early_w}} & early_resp_data_i) |
                ({32{ex_source2_0_w}} & alu0_complete_data_i[31:0]) |
                ({32{ex_source2_1_w}} & alu1_complete_data_i[31:0]) |
                ({32{ex_source2_2_w}} & branch_complete_data_i[31:0]) |
                ({32{ex_source2_3_w}} & mul_complete_data_i[31:0]) |
                ({32{ex_source2_4_w}} & div_complete_data_i[31:0]) |
                ({32{ex_source2_5_w}} & lsu_complete_data_i[31:0]) |
                ({32{ex_source2_6_w}} & csr_complete_data_i[31:0]) |
                ({32{ex_source2_7_w}} & fp_resp_data_i[31:0]) |
                ({32{ex_source2_wb0_w}} & wb0_data_i) |
                ({32{ex_source2_wb1_w}} & wb1_data_i);
            wire mem_hit1_w;
            wire [31:0] mem_capture1_w;
            wire mem_source1_early_w = early_resp_valid_i && early_resp_hit_i &&
                (early_resp_tag_i == mem_source1_tag_r);
            wire mem_source1_0_w = alu0_complete_valid_i && alu0_complete_ready_i &&
                (alu0_complete_tag_i == mem_source1_tag_r);
            wire mem_source1_1_w = alu1_complete_valid_i && alu1_complete_ready_i &&
                (alu1_complete_tag_i == mem_source1_tag_r);
            wire mem_source1_2_w = branch_complete_valid_i && branch_complete_ready_i &&
                (branch_complete_tag_i == mem_source1_tag_r);
            wire mem_source1_3_w = mul_complete_valid_i && mul_complete_ready_i &&
                (mul_complete_tag_i == mem_source1_tag_r);
            wire mem_source1_4_w = div_complete_valid_i && div_complete_ready_i &&
                (div_complete_tag_i == mem_source1_tag_r);
            wire mem_source1_5_w = lsu_complete_valid_i && lsu_complete_ready_i &&
                !lsu_complete_device_i &&
                (lsu_complete_tag_i == mem_source1_tag_r);
            wire mem_source1_6_w = csr_complete_valid_i && csr_complete_ready_i &&
                (csr_complete_tag_i == mem_source1_tag_r);
            wire mem_source1_7_w = fp_resp_valid_i && fp_resp_ready_i &&
                (fp_resp_tag_i == mem_source1_tag_r);
            wire mem_source1_wb0_w = wb0_valid_i && (wb0_tag_i == mem_source1_tag_r);
            wire mem_source1_wb1_w = (ISSUE_WIDTH == 2) && wb1_valid_i &&
                (wb1_tag_i == mem_source1_tag_r);
            assign mem_hit1_w = mem_source1_early_w || mem_source1_0_w ||
                mem_source1_1_w ||
                mem_source1_2_w ||
                mem_source1_3_w ||
                mem_source1_4_w ||
                mem_source1_5_w ||
                mem_source1_6_w ||
                mem_source1_7_w || mem_source1_wb0_w || mem_source1_wb1_w;
            assign mem_capture1_w = ({32{mem_source1_early_w}} & early_resp_data_i) |
                ({32{mem_source1_0_w}} & alu0_complete_data_i[31:0]) |
                ({32{mem_source1_1_w}} & alu1_complete_data_i[31:0]) |
                ({32{mem_source1_2_w}} & branch_complete_data_i[31:0]) |
                ({32{mem_source1_3_w}} & mul_complete_data_i[31:0]) |
                ({32{mem_source1_4_w}} & div_complete_data_i[31:0]) |
                ({32{mem_source1_5_w}} & lsu_complete_data_i[31:0]) |
                ({32{mem_source1_6_w}} & csr_complete_data_i[31:0]) |
                ({32{mem_source1_7_w}} & fp_resp_data_i[31:0]) |
                ({32{mem_source1_wb0_w}} & wb0_data_i) |
                ({32{mem_source1_wb1_w}} & wb1_data_i);
            wire mem_hit2_w;
            wire [31:0] mem_capture2_w;
            wire mem_source2_early_w = early_resp_valid_i && early_resp_hit_i &&
                (early_resp_tag_i == mem_source2_tag_r);
            wire mem_source2_0_w = alu0_complete_valid_i && alu0_complete_ready_i &&
                (alu0_complete_tag_i == mem_source2_tag_r);
            wire mem_source2_1_w = alu1_complete_valid_i && alu1_complete_ready_i &&
                (alu1_complete_tag_i == mem_source2_tag_r);
            wire mem_source2_2_w = branch_complete_valid_i && branch_complete_ready_i &&
                (branch_complete_tag_i == mem_source2_tag_r);
            wire mem_source2_3_w = mul_complete_valid_i && mul_complete_ready_i &&
                (mul_complete_tag_i == mem_source2_tag_r);
            wire mem_source2_4_w = div_complete_valid_i && div_complete_ready_i &&
                (div_complete_tag_i == mem_source2_tag_r);
            wire mem_source2_5_w = lsu_complete_valid_i && lsu_complete_ready_i &&
                !lsu_complete_device_i &&
                (lsu_complete_tag_i == mem_source2_tag_r);
            wire mem_source2_6_w = csr_complete_valid_i && csr_complete_ready_i &&
                (csr_complete_tag_i == mem_source2_tag_r);
            wire mem_source2_7_w = fp_resp_valid_i && fp_resp_ready_i &&
                (fp_resp_tag_i == mem_source2_tag_r);
            wire mem_source2_wb0_w = wb0_valid_i && (wb0_tag_i == mem_source2_tag_r);
            wire mem_source2_wb1_w = (ISSUE_WIDTH == 2) && wb1_valid_i &&
                (wb1_tag_i == mem_source2_tag_r);
            assign mem_hit2_w = mem_source2_early_w || mem_source2_0_w ||
                mem_source2_1_w ||
                mem_source2_2_w ||
                mem_source2_3_w ||
                mem_source2_4_w ||
                mem_source2_5_w ||
                mem_source2_6_w ||
                mem_source2_7_w || mem_source2_wb0_w || mem_source2_wb1_w;
            assign mem_capture2_w = ({32{mem_source2_early_w}} & early_resp_data_i) |
                ({32{mem_source2_0_w}} & alu0_complete_data_i[31:0]) |
                ({32{mem_source2_1_w}} & alu1_complete_data_i[31:0]) |
                ({32{mem_source2_2_w}} & branch_complete_data_i[31:0]) |
                ({32{mem_source2_3_w}} & mul_complete_data_i[31:0]) |
                ({32{mem_source2_4_w}} & div_complete_data_i[31:0]) |
                ({32{mem_source2_5_w}} & lsu_complete_data_i[31:0]) |
                ({32{mem_source2_6_w}} & csr_complete_data_i[31:0]) |
                ({32{mem_source2_7_w}} & fp_resp_data_i[31:0]) |
                ({32{mem_source2_wb0_w}} & wb0_data_i) |
                ({32{mem_source2_wb1_w}} & wb1_data_i);
            wire [31:0] ex_b_w = (ex_instr_r[6:0] == 7'h13) ?
                ex_imm_r : ex_src2_r;
            wire [31:0] ex_arithmetic_right_w = $signed(ex_src1_r) >>> ex_b_w[4:0];
            reg [31:0] ex_a_w;
            reg [31:0] ex_result_w;
            always @(*) begin
                ex_a_w = ex_src1_r;
                ex_result_w = 32'd0;
                if (ex_instr_r[6:0] == 7'h17)
                    ex_a_w = ex_pc_r;
                if ((ex_instr_r[6:0] == 7'h33) &&
                    (ex_instr_r[31:25] == 7'h10)) begin
                    case (ex_instr_r[14:12])
                        3'd2: ex_a_w = ex_src1_r << 1;
                        3'd4: ex_a_w = ex_src1_r << 2;
                        3'd6: ex_a_w = ex_src1_r << 3;
                        default: ex_a_w = ex_src1_r;
                    endcase
                end
                case (ex_instr_r[14:12])
                    3'd0: ex_result_w = ex_a_w + ex_b_w;
                    3'd1: ex_result_w = ex_a_w << ex_b_w[4:0];
                    3'd2: ex_result_w = {31'd0, $signed(ex_a_w) < $signed(ex_b_w)};
                    3'd3: ex_result_w = {31'd0, ex_a_w < ex_b_w};
                    3'd4: ex_result_w = ex_a_w ^ ex_b_w;
                    3'd5: ex_result_w = ex_instr_r[30] ?
                        ex_arithmetic_right_w :
                        (ex_a_w >> ex_b_w[4:0]);
                    3'd6: ex_result_w = ex_a_w | ex_b_w;
                    3'd7: ex_result_w = ex_a_w & ex_b_w;
                    default: ex_result_w = 32'd0;
                endcase
                begin
                if ((ex_instr_r[6:0] == 7'h33) &&
                    (ex_instr_r[31:25] == 7'h20) && (ex_instr_r[14:12] == 3'd0))
                    ex_result_w = ex_a_w - ex_b_w;
                if ((ex_instr_r[6:0] == 7'h33) &&
                    (ex_instr_r[31:25] == 7'h10))
                    ex_result_w = ex_a_w + ex_b_w;
                if (ex_instr_r[6:0] == 7'h37)
                    ex_result_w = ex_imm_r;
                if (ex_instr_r[6:0] == 7'h17)
                    ex_result_w = ex_a_w + ex_imm_r;
                end
            end
            wire [31:0] mem_operand1_w = mem_wait1_r && mem_source1_early_w ?
                early_resp_data_i : mem_src1_r;
            wire [31:0] mem_operand2_w = mem_wait2_r && mem_source2_early_w ?
                early_resp_data_i : mem_src2_r;
            wire [31:0] mem_b_w = (mem_instr_r[6:0] == 7'h13) ?
                mem_imm_r : mem_operand2_w;
            reg [31:0] mem_a_w;
            reg [31:0] mem_result_w;
            always @(*) begin
                mem_a_w = mem_operand1_w;
                mem_result_w = 32'd0;
                if ((mem_instr_r[6:0] == 7'h33) &&
                    (mem_instr_r[31:25] == 7'h10)) begin
                    case (mem_instr_r[14:12])
                        3'd2: mem_a_w = mem_operand1_w << 1;
                        3'd4: mem_a_w = mem_operand1_w << 2;
                        3'd6: mem_a_w = mem_operand1_w << 3;
                        default: mem_a_w = mem_operand1_w;
                    endcase
                end
                case (mem_instr_r[14:12])
                    3'd0: mem_result_w = mem_a_w + mem_b_w;
                    3'd2: mem_result_w = {31'd0, $signed(mem_a_w) < $signed(mem_b_w)};
                    3'd3: mem_result_w = {31'd0, mem_a_w < mem_b_w};
                    3'd4: mem_result_w = mem_a_w ^ mem_b_w;
                    3'd6: mem_result_w = mem_a_w | mem_b_w;
                    3'd7: mem_result_w = mem_a_w & mem_b_w;
                    default: mem_result_w = 32'd0;
                endcase
                begin
                if ((mem_instr_r[6:0] == 7'h33) &&
                    (mem_instr_r[31:25] == 7'h20) && (mem_instr_r[14:12] == 3'd0))
                    mem_result_w = mem_a_w - mem_b_w;
                if ((mem_instr_r[6:0] == 7'h33) &&
                    (mem_instr_r[31:25] == 7'h10))
                    mem_result_w = mem_a_w + mem_b_w;
                end
            end
            /* verilator lint_off UNUSEDSIGNAL */
            wire unused_instr_w = ^mem_instr_r;
            /* verilator lint_on UNUSEDSIGNAL */
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    skid_valid_r <= 1'b0;
                    mem_valid_r <= 1'b0;
                    mem_wait1_r <= 1'b0;
                    mem_wait2_r <= 1'b0;
                end else begin
                    if (skid_done_w || skid_cancel_w)
                        skid_valid_r <= 1'b0;
                    if (stash_w && !ex_cancel_w)
                        skid_valid_r <= 1'b1;
                    if (mem_done_w || mem_cancel_w)
                        mem_valid_r <= 1'b0;
                    if (mem_hit1_w)
                        mem_wait1_r <= 1'b0;
                    if (mem_hit2_w)
                        mem_wait2_r <= 1'b0;
                    if (transfer_w && !ex_cancel_w) begin
                        mem_valid_r <= 1'b1;
                        mem_wait1_r <= ex_wait1_r && !ex_hit1_w;
                        mem_wait2_r <= ex_wait2_r && !ex_hit2_w;
                    end
                end
            end
            always @(posedge clk_i) begin
                if (stash_w) begin
                    skid_tag_r <= stash_mem_w ? mem_tag_r : ex_tag_r;
                    skid_data_r <= stash_mem_w ? mem_result_w : ex_result_w;
                end
                if (transfer_w) begin
                    mem_tag_r <= ex_tag_r;
                    mem_instr_r <= ex_instr_r;
                    mem_imm_r <= ex_imm_r;
                    mem_source1_tag_r <= ex_source1_tag_r;
                    mem_source2_tag_r <= ex_source2_tag_r;
                    mem_src1_r <= (ex_wait1_r && ex_hit1_w) ?
                        ex_capture1_w : ex_src1_r;
                    mem_src2_r <= (ex_wait2_r && ex_hit2_w) ?
                        ex_capture2_w : ex_src2_r;
                end else begin
                    if (mem_wait1_r && mem_hit1_w)
                        mem_src1_r <= mem_capture1_w;
                    if (mem_wait2_r && mem_hit2_w)
                        mem_src2_r <= mem_capture2_w;
                end
            end
            assign alu1_complete_valid_o = select_skid_w || select_mem_w || select_ex_w;
            assign alu1_complete_tag_o = select_skid_w ? skid_tag_r :
                select_mem_w ? mem_tag_r : ex_tag_r;
            assign alu1_complete_data_o = {{(B-32){1'b0}},
                select_skid_w ? skid_data_r : select_mem_w ? mem_result_w : ex_result_w};
            assign alu1_complete_flags_o = 5'd0;
            assign alu1_complete_exception_o = 1'd0;
            assign alu1_complete_cause_o = 4'd0;
            assign alu1_complete_tval_o = 32'd0;
        end else begin : g_inactive1
            assign alu1_complete_valid_o = 1'd0;
            assign alu1_complete_tag_o = {T{1'b0}};
            assign alu1_complete_data_o = {B{1'b0}};
            assign alu1_complete_flags_o = 5'd0;
            assign alu1_complete_exception_o = 1'd0;
            assign alu1_complete_cause_o = 4'd0;
            assign alu1_complete_tval_o = 32'd0;
            assign execute1_ready_o = 1'b0;
            assign debug_mem_valid_o[1] = 1'b0;
        end
    endgenerate
    /* verilator lint_off UNUSEDSIGNAL */
    wire unused_w = ^{early_resp_valid_i, early_resp_tag_i, early_resp_hit_i,
        early_resp_data_i, lsu_complete_device_i,
        wb0_valid_i,
        wb0_tag_i,
        wb0_data_i,
        wb1_valid_i,
        wb1_tag_i,
        wb1_data_i,
        clk_i,
        rst_n_i,
        age_head_i,
        cancel_valid_i,
        cancel_tag_i,
        execute0_valid_i,
        execute0_tag_i,
        execute0_pc_i,
        execute0_instr_i,
        execute0_src1_i,
        execute0_src2_i,
        execute0_imm_i,
        execute0_late_i,
        execute0_source1_tag_i,
        execute0_source2_tag_i,
        execute0_source1_wait_i,
        execute0_source2_wait_i,
        execute1_valid_i,
        execute1_tag_i,
        execute1_pc_i,
        execute1_instr_i,
        execute1_src1_i,
        execute1_src2_i,
        execute1_imm_i,
        execute1_late_i,
        execute1_source1_tag_i,
        execute1_source2_tag_i,
        execute1_source1_wait_i,
        execute1_source2_wait_i,
        alu0_complete_valid_i,
        alu0_complete_ready_i,
        alu0_complete_tag_i,
        alu0_complete_data_i,
        alu1_complete_valid_i,
        alu1_complete_ready_i,
        alu1_complete_tag_i,
        alu1_complete_data_i,
        branch_complete_valid_i,
        branch_complete_ready_i,
        branch_complete_tag_i,
        branch_complete_data_i,
        mul_complete_valid_i,
        mul_complete_ready_i,
        mul_complete_tag_i,
        mul_complete_data_i,
        div_complete_valid_i,
        div_complete_ready_i,
        div_complete_tag_i,
        div_complete_data_i,
        lsu_complete_valid_i,
        lsu_complete_ready_i,
        lsu_complete_tag_i,
        lsu_complete_data_i,
        csr_complete_valid_i,
        csr_complete_ready_i,
        csr_complete_tag_i,
        csr_complete_data_i,
        fp_resp_valid_i,
        fp_resp_ready_i,
        fp_resp_tag_i,
        fp_resp_data_i};
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
