// File: edrv32_cpu2_fetch.v
// Spec: cpu-v2-spec 3.3, 5.2, 5.5.
// Description: Parallel cache-way LVT candidates before instruction way selection.
// Private interfaces carry frontend context and explicit credit reservation events.
// Clock domain: clk_sys.
module edrv32_cpu2_fetch #(
    parameter ISSUE_WIDTH = 2
) (
    clk_i,
    rst_n_i,
    ic_resp_valid_i,
    ic_resp_ready_o,
    word0_control_o,
    word1_control_o,
    ic_resp_bank0_way0_instr_i,
    ic_resp_bank0_way1_instr_i,
    ic_resp_bank1_way0_instr_i,
    ic_resp_bank1_way1_instr_i,
    ic_resp_bank0_way_hit_i,
    ic_resp_bank0_error_i,
    ic_resp_bank1_way_hit_i,
    ic_resp_bank1_error_i,
    context_valid_i,
    context_count_i,
    context_skip0_i,
    context_parity_i,
    context0_pc_i,
    context0_predict_taken_i,
    context0_predict_target_i,
    context0_predict_token_i,
    context0_predict_provider_i,
    context0_predict_alternate_i,
    context0_predict_index0_i,
    context0_predict_index1_i,
    context0_predict_index2_i,
    context0_predict_index3_i,
    context0_predict_tag0_i,
    context0_predict_tag1_i,
    context0_predict_tag2_i,
    context0_predict_tag3_i,
    context0_predict_base_index_i,
    context0_predict_fast_index_i,
    context0_ras_data_i,
    context0_ras_ptr_i,
    context0_ras_count_i,
    context1_pc_i,
    context1_predict_taken_i,
    context1_predict_target_i,
    context1_predict_token_i,
    context1_predict_provider_i,
    context1_predict_alternate_i,
    context1_predict_index0_i,
    context1_predict_index1_i,
    context1_predict_index2_i,
    context1_predict_index3_i,
    context1_predict_tag0_i,
    context1_predict_tag1_i,
    context1_predict_tag2_i,
    context1_predict_tag3_i,
    context1_predict_base_index_i,
    context1_predict_fast_index_i,
    context1_ras_data_i,
    context1_ras_ptr_i,
    context1_ras_count_i,
    lvt_i,
    wb0_valid_i,
    wb0_rd_i,
    wb1_valid_i,
    wb1_rd_i,
    wb0_valid_copy_i,
    wb0_rd_copy_i,
    wb1_valid_copy_i,
    wb1_rd_copy_i,
    fetch_push_valid_o,
    fetch_push_ready_i,
    fetch_push_count_o,
    fetch_push0_pc_o,
    fetch_push0_instr_o,
    fetch_push0_error_o,
    fetch_push0_candidates_o,
    fetch_push0_predict_taken_o,
    fetch_push0_predict_target_o,
    fetch_push0_predict_token_o,
    fetch_push0_predict_provider_o,
    fetch_push0_predict_alternate_o,
    fetch_push0_predict_index0_o,
    fetch_push0_predict_index1_o,
    fetch_push0_predict_index2_o,
    fetch_push0_predict_index3_o,
    fetch_push0_predict_tag0_o,
    fetch_push0_predict_tag1_o,
    fetch_push0_predict_tag2_o,
    fetch_push0_predict_tag3_o,
    fetch_push0_predict_base_index_o,
    fetch_push0_predict_fast_index_o,
    fetch_push0_ras_data_o,
    fetch_push0_ras_ptr_o,
    fetch_push0_ras_count_o,
    fetch_push1_pc_o,
    fetch_push1_instr_o,
    fetch_push1_error_o,
    fetch_push1_candidates_o,
    fetch_push1_predict_taken_o,
    fetch_push1_predict_target_o,
    fetch_push1_predict_token_o,
    fetch_push1_predict_provider_o,
    fetch_push1_predict_alternate_o,
    fetch_push1_predict_index0_o,
    fetch_push1_predict_index1_o,
    fetch_push1_predict_index2_o,
    fetch_push1_predict_index3_o,
    fetch_push1_predict_tag0_o,
    fetch_push1_predict_tag1_o,
    fetch_push1_predict_tag2_o,
    fetch_push1_predict_tag3_o,
    fetch_push1_predict_base_index_o,
    fetch_push1_predict_fast_index_o,
    fetch_push1_ras_data_o,
    fetch_push1_ras_ptr_o,
    fetch_push1_ras_count_o
);
    localparam RAS_BITS = (ISSUE_WIDTH == 2) ? 256 : 128;
    localparam RAS_PTR_BITS = (ISSUE_WIDTH == 2) ? 3 : 2;
    localparam RAS_COUNT_BITS = RAS_PTR_BITS+1;
    input wire clk_i;
    input wire rst_n_i;

    // Physical cache-bank results; owner and opcode queries precede both selection muxes.
    input wire ic_resp_valid_i;
    output wire ic_resp_ready_o;
    // Opcode family decode is parallel with LVT/WB candidates in each physical way.
    output wire word0_control_o;
    output wire word1_control_o;
    function control_opcode;
        input [6:0] opcode_i;
        begin
            case (opcode_i)
                7'h63, 7'h6f, 7'h67: control_opcode = 1'b1;
                default: control_opcode = 1'b0;
            endcase
        end
    endfunction
    input wire [32-1:0] ic_resp_bank0_way0_instr_i;
    input wire [32-1:0] ic_resp_bank0_way1_instr_i;
    input wire [32-1:0] ic_resp_bank1_way0_instr_i;
    input wire [32-1:0] ic_resp_bank1_way1_instr_i;
    input wire [2-1:0] ic_resp_bank0_way_hit_i;
    input wire ic_resp_bank0_error_i;
    input wire [2-1:0] ic_resp_bank1_way_hit_i;
    input wire ic_resp_bank1_error_i;

    // Private oldest F2 context: metadata j is logical PC+j*4, parity orders the raw banks.
    // skip0 removes the lower word only in the aligned single-issue configuration.
    input wire context_valid_i;
    input wire [2-1:0] context_count_i;
    input wire context_skip0_i;
    input wire context_parity_i;
    input wire [32-1:0] context0_pc_i;
    input wire context0_predict_taken_i;
    input wire [32-1:0] context0_predict_target_i;
    input wire context0_predict_token_i;
    input wire [3-1:0] context0_predict_provider_i;
    input wire context0_predict_alternate_i;
    input wire [9-1:0] context0_predict_index0_i;
    input wire [9-1:0] context0_predict_index1_i;
    input wire [9-1:0] context0_predict_index2_i;
    input wire [9-1:0] context0_predict_index3_i;
    input wire [10-1:0] context0_predict_tag0_i;
    input wire [10-1:0] context0_predict_tag1_i;
    input wire [10-1:0] context0_predict_tag2_i;
    input wire [10-1:0] context0_predict_tag3_i;
    input wire [12-1:0] context0_predict_base_index_i;
    input wire [12-1:0] context0_predict_fast_index_i;
    input wire [RAS_BITS-1:0] context0_ras_data_i;
    input wire [RAS_PTR_BITS-1:0] context0_ras_ptr_i;
    input wire [RAS_COUNT_BITS-1:0] context0_ras_count_i;
    input wire [32-1:0] context1_pc_i;
    input wire context1_predict_taken_i;
    input wire [32-1:0] context1_predict_target_i;
    input wire context1_predict_token_i;
    input wire [3-1:0] context1_predict_provider_i;
    input wire context1_predict_alternate_i;
    input wire [9-1:0] context1_predict_index0_i;
    input wire [9-1:0] context1_predict_index1_i;
    input wire [9-1:0] context1_predict_index2_i;
    input wire [9-1:0] context1_predict_index3_i;
    input wire [10-1:0] context1_predict_tag0_i;
    input wire [10-1:0] context1_predict_tag1_i;
    input wire [10-1:0] context1_predict_tag2_i;
    input wire [10-1:0] context1_predict_tag3_i;
    input wire [12-1:0] context1_predict_base_index_i;
    input wire [12-1:0] context1_predict_fast_index_i;
    input wire [RAS_BITS-1:0] context1_ras_data_i;
    input wire [RAS_PTR_BITS-1:0] context1_ras_ptr_i;
    input wire [RAS_COUNT_BITS-1:0] context1_ras_count_i;
    input wire [31:1] lvt_i;
    input wire wb0_valid_i;
    input wire [5-1:0] wb0_rd_i;
    input wire wb1_valid_i;
    input wire [5-1:0] wb1_rd_i;
    input wire wb0_valid_copy_i;
    input wire [4:0] wb0_rd_copy_i;
    input wire wb1_valid_copy_i;
    input wire [4:0] wb1_rd_copy_i;
    output wire fetch_push_valid_o;
    input wire fetch_push_ready_i;
    output wire [2-1:0] fetch_push_count_o;
    output wire [32-1:0] fetch_push0_pc_o;
    output wire [32-1:0] fetch_push0_instr_o;
    output wire fetch_push0_error_o;
    output wire [5-1:0] fetch_push0_candidates_o;
    output wire fetch_push0_predict_taken_o;
    output wire [32-1:0] fetch_push0_predict_target_o;
    output wire fetch_push0_predict_token_o;
    output wire [3-1:0] fetch_push0_predict_provider_o;
    output wire fetch_push0_predict_alternate_o;
    output wire [9-1:0] fetch_push0_predict_index0_o;
    output wire [9-1:0] fetch_push0_predict_index1_o;
    output wire [9-1:0] fetch_push0_predict_index2_o;
    output wire [9-1:0] fetch_push0_predict_index3_o;
    output wire [10-1:0] fetch_push0_predict_tag0_o;
    output wire [10-1:0] fetch_push0_predict_tag1_o;
    output wire [10-1:0] fetch_push0_predict_tag2_o;
    output wire [10-1:0] fetch_push0_predict_tag3_o;
    output wire [12-1:0] fetch_push0_predict_base_index_o;
    output wire [12-1:0] fetch_push0_predict_fast_index_o;
    output wire [RAS_BITS-1:0] fetch_push0_ras_data_o;
    output wire [RAS_PTR_BITS-1:0] fetch_push0_ras_ptr_o;
    output wire [RAS_COUNT_BITS-1:0] fetch_push0_ras_count_o;
    output wire [32-1:0] fetch_push1_pc_o;
    output wire [32-1:0] fetch_push1_instr_o;
    output wire fetch_push1_error_o;
    output wire [5-1:0] fetch_push1_candidates_o;
    output wire fetch_push1_predict_taken_o;
    output wire [32-1:0] fetch_push1_predict_target_o;
    output wire fetch_push1_predict_token_o;
    output wire [3-1:0] fetch_push1_predict_provider_o;
    output wire fetch_push1_predict_alternate_o;
    output wire [9-1:0] fetch_push1_predict_index0_o;
    output wire [9-1:0] fetch_push1_predict_index1_o;
    output wire [9-1:0] fetch_push1_predict_index2_o;
    output wire [9-1:0] fetch_push1_predict_index3_o;
    output wire [10-1:0] fetch_push1_predict_tag0_o;
    output wire [10-1:0] fetch_push1_predict_tag1_o;
    output wire [10-1:0] fetch_push1_predict_tag2_o;
    output wire [10-1:0] fetch_push1_predict_tag3_o;
    output wire [12-1:0] fetch_push1_predict_base_index_o;
    output wire [12-1:0] fetch_push1_predict_fast_index_o;
    output wire [RAS_BITS-1:0] fetch_push1_ras_data_o;
    output wire [RAS_PTR_BITS-1:0] fetch_push1_ras_ptr_o;
    output wire [RAS_COUNT_BITS-1:0] fetch_push1_ras_count_o;

    wire [63:0] selected_instr_w;
    wire [9:0] selected_candidates_w;
    wire [63:0] physical_instr_w;
    wire [3:0] physical_owner_w;
    wire [1:0] physical_error_w;
    wire [1:0] physical_control_w;
    wire [1:0] selected_error_w;
    wire [1:0] selected_control_w;
    genvar bank;
    genvar way;
    wire unused_w;





    assign fetch_push_valid_o = ic_resp_valid_i && context_valid_i;
    assign ic_resp_ready_o = fetch_push_ready_i && context_valid_i;
    assign fetch_push_count_o = context_count_i;
    assign word0_control_o = selected_control_w[0];
    assign word1_control_o = selected_control_w[1];
    generate
        for (bank = 0; bank < 2; bank = bank + 1) begin : g_bank
            wire [63:0] instr_w;
            wire [1:0] hit_w;
            (* keep = "true", syn_keep = 1 *) wire [3:0] owners_w;
            wire [1:0] controls_w;
            wire error_w;
            if (bank == 0) begin : g_bank0
                assign instr_w = {ic_resp_bank0_way1_instr_i, ic_resp_bank0_way0_instr_i};
                assign hit_w = ic_resp_bank0_way_hit_i;
                assign error_w = ic_resp_bank0_error_i;
            end else begin : g_bank1
                assign instr_w = {ic_resp_bank1_way1_instr_i, ic_resp_bank1_way0_instr_i};
                assign hit_w = ic_resp_bank1_way_hit_i;
                assign error_w = ic_resp_bank1_error_i;
            end
            for (way = 0; way < 2; way = way + 1) begin : g_way
                wire [31:0] word_w;
                assign word_w = instr_w[32*way +: 32];
                assign controls_w[way] = control_opcode(word_w[6:0]);
                if (ISSUE_WIDTH == 2) begin : g_owners
                    wire [1-1:0] region_wb0_valid_w;
                    wire [5-1:0] region_wb0_rd_w;
                    wire [1-1:0] region_wb1_valid_w;
                    wire [5-1:0] region_wb1_rd_w;
                    if (bank == 0) begin : g_wb_region0
                        assign region_wb0_valid_w = wb0_valid_i;
                        assign region_wb0_rd_w = wb0_rd_i;
                        assign region_wb1_valid_w = wb1_valid_i;
                        assign region_wb1_rd_w = wb1_rd_i;
                    end else begin : g_wb_region1
                        assign region_wb0_valid_w = wb0_valid_copy_i;
                        assign region_wb0_rd_w = wb0_rd_copy_i;
                        assign region_wb1_valid_w = wb1_valid_copy_i;
                        assign region_wb1_rd_w = wb1_rd_copy_i;
                    end
                    wire [4:0] rs1_w;
                    wire [4:0] rs2_w;
                    assign rs1_w = word_w[19:15];
                    assign rs2_w = word_w[24:20];

                    // Parallel per-way LVT and WB compares precede the hit selection.
                    assign owners_w[2*way] = rs1_w == 5'd0 ? 1'b0 :
                        region_wb1_valid_w && region_wb1_rd_w == rs1_w ? 1'b1 :
                        region_wb0_valid_w && region_wb0_rd_w == rs1_w ? 1'b0 : lvt_i[rs1_w];
                    assign owners_w[2*way+1] = rs2_w == 5'd0 ? 1'b0 :
                        region_wb1_valid_w && region_wb1_rd_w == rs2_w ? 1'b1 :
                        region_wb0_valid_w && region_wb0_rd_w == rs2_w ? 1'b0 : lvt_i[rs2_w];
                end else begin : g_no_owners
                    assign owners_w[2*way +: 2] = 2'd0;
                end
                wire unused_word_w;
                assign unused_word_w = ^word_w;
            end
            assign physical_instr_w[32*bank +: 32] = hit_w[1] ? instr_w[63:32] : instr_w[31:0];
            assign physical_owner_w[2*bank +: 2] = hit_w[1] ?
                owners_w[3:2] : owners_w[1:0];
            assign physical_error_w[bank] = error_w;
            assign physical_control_w[bank] = hit_w[1] ? controls_w[1] : controls_w[0];
            wire unused_hit_w;
            assign unused_hit_w = hit_w[0];
        end
    endgenerate
    // Parity only selects already decoded physical-bank results.
    assign selected_instr_w[31:0] = context_parity_i ? physical_instr_w[63:32] :
        physical_instr_w[31:0];
    assign selected_instr_w[63:32] = context_parity_i ? physical_instr_w[31:0] :
        physical_instr_w[63:32];
    assign selected_error_w = context_parity_i ?
        {physical_error_w[0], physical_error_w[1]} : physical_error_w;
    assign selected_control_w = context_parity_i ?
        {physical_control_w[0], physical_control_w[1]} : physical_control_w;
    assign selected_candidates_w[4:0] = ISSUE_WIDTH == 2 ?
        {context_parity_i, physical_owner_w} : 5'd0;
    assign selected_candidates_w[9:5] = ISSUE_WIDTH == 2 ?
        {!context_parity_i, physical_owner_w} : 5'd0;
    assign fetch_push0_pc_o = context_skip0_i ? context1_pc_i : context0_pc_i;
    assign fetch_push0_instr_o = context_skip0_i ? selected_instr_w[32 +: 32] :
        selected_instr_w[0 +: 32];
    assign fetch_push0_error_o = context_skip0_i ? selected_error_w[1] : selected_error_w[0];
    assign fetch_push0_candidates_o = context_skip0_i ? selected_candidates_w[5 +: 5] :
        selected_candidates_w[0 +: 5];
    assign fetch_push0_predict_taken_o = context_skip0_i ? context1_predict_taken_i :
        context0_predict_taken_i;
    assign fetch_push0_predict_target_o = context_skip0_i ? context1_predict_target_i :
        context0_predict_target_i;
    assign fetch_push0_predict_token_o = context_skip0_i ? context1_predict_token_i :
        context0_predict_token_i;
    assign fetch_push0_predict_provider_o = context_skip0_i ? context1_predict_provider_i :
        context0_predict_provider_i;
    assign fetch_push0_predict_alternate_o = context_skip0_i ? context1_predict_alternate_i :
        context0_predict_alternate_i;
    assign fetch_push0_predict_index0_o = context_skip0_i ? context1_predict_index0_i :
        context0_predict_index0_i;
    assign fetch_push0_predict_index1_o = context_skip0_i ? context1_predict_index1_i :
        context0_predict_index1_i;
    assign fetch_push0_predict_index2_o = context_skip0_i ? context1_predict_index2_i :
        context0_predict_index2_i;
    assign fetch_push0_predict_index3_o = context_skip0_i ? context1_predict_index3_i :
        context0_predict_index3_i;
    assign fetch_push0_predict_tag0_o = context_skip0_i ? context1_predict_tag0_i :
        context0_predict_tag0_i;
    assign fetch_push0_predict_tag1_o = context_skip0_i ? context1_predict_tag1_i :
        context0_predict_tag1_i;
    assign fetch_push0_predict_tag2_o = context_skip0_i ? context1_predict_tag2_i :
        context0_predict_tag2_i;
    assign fetch_push0_predict_tag3_o = context_skip0_i ? context1_predict_tag3_i :
        context0_predict_tag3_i;
    assign fetch_push0_predict_base_index_o = context_skip0_i ? context1_predict_base_index_i :
        context0_predict_base_index_i;
    assign fetch_push0_predict_fast_index_o = context_skip0_i ? context1_predict_fast_index_i :
        context0_predict_fast_index_i;
    assign fetch_push0_ras_data_o = context_skip0_i ? context1_ras_data_i : context0_ras_data_i;
    assign fetch_push0_ras_ptr_o = context_skip0_i ? context1_ras_ptr_i : context0_ras_ptr_i;
    assign fetch_push0_ras_count_o = context_skip0_i ? context1_ras_count_i : context0_ras_count_i;
    assign fetch_push1_pc_o = context1_pc_i;
    assign fetch_push1_instr_o = selected_instr_w[32 +: 32];
    assign fetch_push1_error_o = selected_error_w[1];
    assign fetch_push1_candidates_o = selected_candidates_w[5 +: 5];
    assign fetch_push1_predict_taken_o = context1_predict_taken_i;
    assign fetch_push1_predict_target_o = context1_predict_target_i;
    assign fetch_push1_predict_token_o = context1_predict_token_i;
    assign fetch_push1_predict_provider_o = context1_predict_provider_i;
    assign fetch_push1_predict_alternate_o = context1_predict_alternate_i;
    assign fetch_push1_predict_index0_o = context1_predict_index0_i;
    assign fetch_push1_predict_index1_o = context1_predict_index1_i;
    assign fetch_push1_predict_index2_o = context1_predict_index2_i;
    assign fetch_push1_predict_index3_o = context1_predict_index3_i;
    assign fetch_push1_predict_tag0_o = context1_predict_tag0_i;
    assign fetch_push1_predict_tag1_o = context1_predict_tag1_i;
    assign fetch_push1_predict_tag2_o = context1_predict_tag2_i;
    assign fetch_push1_predict_tag3_o = context1_predict_tag3_i;
    assign fetch_push1_predict_base_index_o = context1_predict_base_index_i;
    assign fetch_push1_predict_fast_index_o = context1_predict_fast_index_i;
    assign fetch_push1_ras_data_o = context1_ras_data_i;
    assign fetch_push1_ras_ptr_o = context1_ras_ptr_i;
    assign fetch_push1_ras_count_o = context1_ras_count_i;
    assign unused_w = ^{clk_i, rst_n_i, lvt_i, wb0_valid_i, wb0_rd_i, wb1_valid_i,
        wb1_rd_i, wb0_valid_copy_i, wb0_rd_copy_i, wb1_valid_copy_i, wb1_rd_copy_i};
endmodule
