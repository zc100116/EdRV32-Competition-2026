// File: edrv32_cpu2_ib.v
// Spec: cpu-v2-spec 3.3, 5.2, 5.5.
// Description: Fixed-head IB with physical in-flight credits and same-edge owner repair.
// Private interfaces carry frontend context and explicit credit reservation events.
// Clock domain: clk_sys.
module edrv32_cpu2_ib #(
    parameter ISSUE_WIDTH = 2
) (
    clk_i,
    rst_n_i,
    fetch_push_valid_i,
    fetch_push_ready_o,
    fetch_push_count_i,
    fetch_push0_pc_i,
    fetch_push0_instr_i,
    fetch_push0_error_i,
    fetch_push0_candidates_i,
    fetch_push0_predict_taken_i,
    fetch_push0_predict_target_i,
    fetch_push0_predict_token_i,
    fetch_push0_predict_provider_i,
    fetch_push0_predict_alternate_i,
    fetch_push0_predict_index0_i,
    fetch_push0_predict_index1_i,
    fetch_push0_predict_index2_i,
    fetch_push0_predict_index3_i,
    fetch_push0_predict_tag0_i,
    fetch_push0_predict_tag1_i,
    fetch_push0_predict_tag2_i,
    fetch_push0_predict_tag3_i,
    fetch_push0_predict_base_index_i,
    fetch_push0_predict_fast_index_i,
    fetch_push0_ras_data_i,
    fetch_push0_ras_ptr_i,
    fetch_push0_ras_count_i,
    fetch_push1_pc_i,
    fetch_push1_instr_i,
    fetch_push1_error_i,
    fetch_push1_candidates_i,
    fetch_push1_predict_taken_i,
    fetch_push1_predict_target_i,
    fetch_push1_predict_token_i,
    fetch_push1_predict_provider_i,
    fetch_push1_predict_alternate_i,
    fetch_push1_predict_index0_i,
    fetch_push1_predict_index1_i,
    fetch_push1_predict_index2_i,
    fetch_push1_predict_index3_i,
    fetch_push1_predict_tag0_i,
    fetch_push1_predict_tag1_i,
    fetch_push1_predict_tag2_i,
    fetch_push1_predict_tag3_i,
    fetch_push1_predict_base_index_i,
    fetch_push1_predict_fast_index_i,
    fetch_push1_ras_data_i,
    fetch_push1_ras_ptr_i,
    fetch_push1_ras_count_i,
    ib_remove_count_i,
    ib_credit_o,
    frontend_flush_i,
    reserve_valid_i,
    reserve_cancel_count_i,
    wb0_valid_i,
    wb0_rd_i,
    wb1_valid_i,
    wb1_rd_i,
    wb0_valid_copy_i,
    wb0_rd_copy_i,
    wb1_valid_copy_i,
    wb1_rd_copy_i,
    ib_head0_valid_o,
    ib_head1_valid_o,
    ib_head0_pc_o,
    ib_head0_instr_o,
    ib_head0_error_o,
    ib_head0_candidates_o,
    ib_head0_predict_taken_o,
    ib_head0_predict_target_o,
    ib_head0_predict_token_o,
    ib_head0_predict_provider_o,
    ib_head0_predict_alternate_o,
    ib_head0_predict_index0_o,
    ib_head0_predict_index1_o,
    ib_head0_predict_index2_o,
    ib_head0_predict_index3_o,
    ib_head0_predict_tag0_o,
    ib_head0_predict_tag1_o,
    ib_head0_predict_tag2_o,
    ib_head0_predict_tag3_o,
    ib_head0_predict_base_index_o,
    ib_head0_predict_fast_index_o,
    ib_head0_ras_data_o,
    ib_head0_ras_ptr_o,
    ib_head0_ras_count_o,
    ib_head1_pc_o,
    ib_head1_instr_o,
    ib_head1_error_o,
    ib_head1_candidates_o,
    ib_head1_predict_taken_o,
    ib_head1_predict_target_o,
    ib_head1_predict_token_o,
    ib_head1_predict_provider_o,
    ib_head1_predict_alternate_o,
    ib_head1_predict_index0_o,
    ib_head1_predict_index1_o,
    ib_head1_predict_index2_o,
    ib_head1_predict_index3_o,
    ib_head1_predict_tag0_o,
    ib_head1_predict_tag1_o,
    ib_head1_predict_tag2_o,
    ib_head1_predict_tag3_o,
    ib_head1_predict_base_index_o,
    ib_head1_predict_fast_index_o,
    ib_head1_ras_data_o,
    ib_head1_ras_ptr_o,
    ib_head1_ras_count_o
);
    localparam RAS_BITS = (ISSUE_WIDTH == 2) ? 256 : 128;
    localparam RAS_PTR_BITS = (ISSUE_WIDTH == 2) ? 3 : 2;
    localparam RAS_COUNT_BITS = RAS_PTR_BITS+1;
    localparam PHYSICAL = (ISSUE_WIDTH == 2) ? 12 : 8;
    localparam [3:0] CAPACITY = (ISSUE_WIDTH == 2) ? 4'd12 : 4'd8;
    input wire clk_i;
    input wire rst_n_i;

    // Each accepted group already owns two reserved physical entries; it cannot be blocked.
    input wire fetch_push_valid_i;
    output wire fetch_push_ready_o;
    input wire [2-1:0] fetch_push_count_i;
    input wire [32-1:0] fetch_push0_pc_i;
    input wire [32-1:0] fetch_push0_instr_i;
    input wire fetch_push0_error_i;
    input wire [5-1:0] fetch_push0_candidates_i;
    input wire fetch_push0_predict_taken_i;
    input wire [32-1:0] fetch_push0_predict_target_i;
    input wire fetch_push0_predict_token_i;
    input wire [3-1:0] fetch_push0_predict_provider_i;
    input wire fetch_push0_predict_alternate_i;
    input wire [9-1:0] fetch_push0_predict_index0_i;
    input wire [9-1:0] fetch_push0_predict_index1_i;
    input wire [9-1:0] fetch_push0_predict_index2_i;
    input wire [9-1:0] fetch_push0_predict_index3_i;
    input wire [10-1:0] fetch_push0_predict_tag0_i;
    input wire [10-1:0] fetch_push0_predict_tag1_i;
    input wire [10-1:0] fetch_push0_predict_tag2_i;
    input wire [10-1:0] fetch_push0_predict_tag3_i;
    input wire [12-1:0] fetch_push0_predict_base_index_i;
    input wire [12-1:0] fetch_push0_predict_fast_index_i;
    input wire [RAS_BITS-1:0] fetch_push0_ras_data_i;
    input wire [RAS_PTR_BITS-1:0] fetch_push0_ras_ptr_i;
    input wire [RAS_COUNT_BITS-1:0] fetch_push0_ras_count_i;
    input wire [32-1:0] fetch_push1_pc_i;
    input wire [32-1:0] fetch_push1_instr_i;
    input wire fetch_push1_error_i;
    input wire [5-1:0] fetch_push1_candidates_i;
    input wire fetch_push1_predict_taken_i;
    input wire [32-1:0] fetch_push1_predict_target_i;
    input wire fetch_push1_predict_token_i;
    input wire [3-1:0] fetch_push1_predict_provider_i;
    input wire fetch_push1_predict_alternate_i;
    input wire [9-1:0] fetch_push1_predict_index0_i;
    input wire [9-1:0] fetch_push1_predict_index1_i;
    input wire [9-1:0] fetch_push1_predict_index2_i;
    input wire [9-1:0] fetch_push1_predict_index3_i;
    input wire [10-1:0] fetch_push1_predict_tag0_i;
    input wire [10-1:0] fetch_push1_predict_tag1_i;
    input wire [10-1:0] fetch_push1_predict_tag2_i;
    input wire [10-1:0] fetch_push1_predict_tag3_i;
    input wire [12-1:0] fetch_push1_predict_base_index_i;
    input wire [12-1:0] fetch_push1_predict_fast_index_i;
    input wire [RAS_BITS-1:0] fetch_push1_ras_data_i;
    input wire [RAS_PTR_BITS-1:0] fetch_push1_ras_ptr_i;
    input wire [RAS_COUNT_BITS-1:0] fetch_push1_ras_count_i;
    input wire [2-1:0] ib_remove_count_i;
    output wire [4-1:0] ib_credit_o;
    input wire frontend_flush_i;

    // Private IF credits: reserve_valid consumes two slots at I$ acceptance.
    // A push returns its unused reservation; reserve_cancel_count returns whole canceled groups.
    input wire reserve_valid_i;
    input wire [2-1:0] reserve_cancel_count_i;

    // WB copies are registered by commit on the same edge, never delayed locally.
    input wire wb0_valid_i;
    input wire [5-1:0] wb0_rd_i;
    input wire wb1_valid_i;
    input wire [5-1:0] wb1_rd_i;
    input wire wb0_valid_copy_i;
    input wire [4:0] wb0_rd_copy_i;
    input wire wb1_valid_copy_i;
    input wire [4:0] wb1_rd_copy_i;
    output wire ib_head0_valid_o;
    output wire ib_head1_valid_o;
    output wire [32-1:0] ib_head0_pc_o;
    output wire [32-1:0] ib_head0_instr_o;
    output wire ib_head0_error_o;
    output wire [5-1:0] ib_head0_candidates_o;
    output wire ib_head0_predict_taken_o;
    output wire [32-1:0] ib_head0_predict_target_o;
    output wire ib_head0_predict_token_o;
    output wire [3-1:0] ib_head0_predict_provider_o;
    output wire ib_head0_predict_alternate_o;
    output wire [9-1:0] ib_head0_predict_index0_o;
    output wire [9-1:0] ib_head0_predict_index1_o;
    output wire [9-1:0] ib_head0_predict_index2_o;
    output wire [9-1:0] ib_head0_predict_index3_o;
    output wire [10-1:0] ib_head0_predict_tag0_o;
    output wire [10-1:0] ib_head0_predict_tag1_o;
    output wire [10-1:0] ib_head0_predict_tag2_o;
    output wire [10-1:0] ib_head0_predict_tag3_o;
    output wire [12-1:0] ib_head0_predict_base_index_o;
    output wire [12-1:0] ib_head0_predict_fast_index_o;
    output wire [RAS_BITS-1:0] ib_head0_ras_data_o;
    output wire [RAS_PTR_BITS-1:0] ib_head0_ras_ptr_o;
    output wire [RAS_COUNT_BITS-1:0] ib_head0_ras_count_o;
    output wire [32-1:0] ib_head1_pc_o;
    output wire [32-1:0] ib_head1_instr_o;
    output wire ib_head1_error_o;
    output wire [5-1:0] ib_head1_candidates_o;
    output wire ib_head1_predict_taken_o;
    output wire [32-1:0] ib_head1_predict_target_o;
    output wire ib_head1_predict_token_o;
    output wire [3-1:0] ib_head1_predict_provider_o;
    output wire ib_head1_predict_alternate_o;
    output wire [9-1:0] ib_head1_predict_index0_o;
    output wire [9-1:0] ib_head1_predict_index1_o;
    output wire [9-1:0] ib_head1_predict_index2_o;
    output wire [9-1:0] ib_head1_predict_index3_o;
    output wire [10-1:0] ib_head1_predict_tag0_o;
    output wire [10-1:0] ib_head1_predict_tag1_o;
    output wire [10-1:0] ib_head1_predict_tag2_o;
    output wire [10-1:0] ib_head1_predict_tag3_o;
    output wire [12-1:0] ib_head1_predict_base_index_o;
    output wire [12-1:0] ib_head1_predict_fast_index_o;
    output wire [RAS_BITS-1:0] ib_head1_ras_data_o;
    output wire [RAS_PTR_BITS-1:0] ib_head1_ras_ptr_o;
    output wire [RAS_COUNT_BITS-1:0] ib_head1_ras_count_o;

    reg [3:0] count_r;
    reg [3:0] credit_r;
    reg [PHYSICAL:0] occupancy_r;
    wire push_w;
    wire [PHYSICAL:0] retained_w;
    wire [1:0] push_count_w;
    wire [PHYSICAL*32-1:0] pc_flat_w;
    wire [PHYSICAL*32-1:0] instr_flat_w;
    wire [PHYSICAL*1-1:0] error_flat_w;
    wire [PHYSICAL*5-1:0] candidates_flat_w;
    wire [PHYSICAL*1-1:0] predict_taken_flat_w;
    wire [PHYSICAL*32-1:0] predict_target_flat_w;
    wire [PHYSICAL*1-1:0] predict_token_flat_w;
    wire [PHYSICAL*3-1:0] predict_provider_flat_w;
    wire [PHYSICAL*1-1:0] predict_alternate_flat_w;
    wire [PHYSICAL*9-1:0] predict_index0_flat_w;
    wire [PHYSICAL*9-1:0] predict_index1_flat_w;
    wire [PHYSICAL*9-1:0] predict_index2_flat_w;
    wire [PHYSICAL*9-1:0] predict_index3_flat_w;
    wire [PHYSICAL*10-1:0] predict_tag0_flat_w;
    wire [PHYSICAL*10-1:0] predict_tag1_flat_w;
    wire [PHYSICAL*10-1:0] predict_tag2_flat_w;
    wire [PHYSICAL*10-1:0] predict_tag3_flat_w;
    wire [PHYSICAL*12-1:0] predict_base_index_flat_w;
    wire [PHYSICAL*12-1:0] predict_fast_index_flat_w;
    wire [PHYSICAL*RAS_BITS-1:0] ras_data_flat_w;
    wire [PHYSICAL*RAS_PTR_BITS-1:0] ras_ptr_flat_w;
    wire [PHYSICAL*RAS_COUNT_BITS-1:0] ras_count_flat_w;
    wire [PHYSICAL*5-1:0] corrected_candidates_w;
    genvar slot;
    wire unused_w;





    assign push_w = fetch_push_valid_i;
    assign push_count_w = push_w ? fetch_push_count_i : 2'd0;
    assign retained_w = occupancy_r >> ib_remove_count_i;
    assign fetch_push_ready_o = 1'b1;
    assign ib_credit_o = credit_r;
    assign ib_head0_valid_o = count_r != 4'd0;
    assign ib_head1_valid_o = (ISSUE_WIDTH == 2) && count_r >= 4'd2;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            count_r <= 4'd0;
            credit_r <= CAPACITY;
            occupancy_r <= {{PHYSICAL{1'b0}}, 1'b1};
        end else if (frontend_flush_i) begin
            count_r <= 4'd0;
            credit_r <= CAPACITY;
            occupancy_r <= {{PHYSICAL{1'b0}}, 1'b1};
        end else begin
            count_r <= count_r - {2'b0, ib_remove_count_i} + {2'b0, push_count_w};
            credit_r <= credit_r + {2'b0, ib_remove_count_i} - {2'b0, reserve_valid_i, 1'b0} +
                {1'b0, reserve_cancel_count_i, 1'b0} + (push_w ? 4'd2 -
                {2'b0, fetch_push_count_i} : 4'd0);
            occupancy_r <= retained_w << push_count_w;
        end
    end
    generate
        for (slot = 0; slot < PHYSICAL; slot = slot + 1) begin : g_slot
            wire insert0_w;
            wire insert1_w;
            assign insert0_w = push_w && retained_w[slot];
            if (slot == 0) begin : g_first
                assign insert1_w = 1'b0;
            end else begin : g_later
                assign insert1_w = push_w && fetch_push_count_i == 2'd2 && retained_w[slot-1];
            end
            reg [32-1:0] pc_r;
            wire [32-1:0] pc_next1_w;
            wire [32-1:0] pc_next2_w;
            wire [32-1:0] pc_selected_w;
            assign pc_flat_w[32*slot +: 32] = pc_r;
            if (slot < PHYSICAL-1) begin : g_pc_next1
                assign pc_next1_w = pc_flat_w[32*(slot+1) +: 32];
            end else begin : g_pc_end1
                assign pc_next1_w = {32{1'b0}};
            end
            if (slot < PHYSICAL-2) begin : g_pc_next2
                assign pc_next2_w = pc_flat_w[32*(slot+2) +: 32];
            end else begin : g_pc_end2
                assign pc_next2_w = {32{1'b0}};
            end
            assign pc_selected_w = insert0_w ? fetch_push0_pc_i :
                insert1_w ? fetch_push1_pc_i :
                ib_remove_count_i == 2'd2 ? pc_next2_w :
                ib_remove_count_i == 2'd1 ? pc_next1_w : pc_r;
            always @(posedge clk_i) begin
                pc_r <= pc_selected_w;
            end
            reg [32-1:0] instr_r;
            wire [32-1:0] instr_next1_w;
            wire [32-1:0] instr_next2_w;
            wire [32-1:0] instr_selected_w;
            assign instr_flat_w[32*slot +: 32] = instr_r;
            if (slot < PHYSICAL-1) begin : g_instr_next1
                assign instr_next1_w = instr_flat_w[32*(slot+1) +: 32];
            end else begin : g_instr_end1
                assign instr_next1_w = {32{1'b0}};
            end
            if (slot < PHYSICAL-2) begin : g_instr_next2
                assign instr_next2_w = instr_flat_w[32*(slot+2) +: 32];
            end else begin : g_instr_end2
                assign instr_next2_w = {32{1'b0}};
            end
            assign instr_selected_w = insert0_w ? fetch_push0_instr_i :
                insert1_w ? fetch_push1_instr_i :
                ib_remove_count_i == 2'd2 ? instr_next2_w :
                ib_remove_count_i == 2'd1 ? instr_next1_w : instr_r;
            always @(posedge clk_i) begin
                instr_r <= instr_selected_w;
            end
            reg [1-1:0] error_r;
            wire [1-1:0] error_next1_w;
            wire [1-1:0] error_next2_w;
            wire [1-1:0] error_selected_w;
            assign error_flat_w[1*slot +: 1] = error_r;
            if (slot < PHYSICAL-1) begin : g_error_next1
                assign error_next1_w = error_flat_w[1*(slot+1) +: 1];
            end else begin : g_error_end1
                assign error_next1_w = {1{1'b0}};
            end
            if (slot < PHYSICAL-2) begin : g_error_next2
                assign error_next2_w = error_flat_w[1*(slot+2) +: 1];
            end else begin : g_error_end2
                assign error_next2_w = {1{1'b0}};
            end
            assign error_selected_w = insert0_w ? fetch_push0_error_i :
                insert1_w ? fetch_push1_error_i :
                ib_remove_count_i == 2'd2 ? error_next2_w :
                ib_remove_count_i == 2'd1 ? error_next1_w : error_r;
            always @(posedge clk_i) begin
                error_r <= error_selected_w;
            end
            reg [5-1:0] candidates_r;
            wire [5-1:0] candidates_next1_w;
            wire [5-1:0] candidates_next2_w;
            wire [5-1:0] candidates_selected_w;
            assign candidates_flat_w[5*slot +: 5] = candidates_r;
            if (slot < PHYSICAL-1) begin : g_candidates_next1
                assign candidates_next1_w = corrected_candidates_w[5*(slot+1) +: 5];
            end else begin : g_candidates_end1
                assign candidates_next1_w = {5{1'b0}};
            end
            if (slot < PHYSICAL-2) begin : g_candidates_next2
                assign candidates_next2_w = corrected_candidates_w[5*(slot+2) +: 5];
            end else begin : g_candidates_end2
                assign candidates_next2_w = {5{1'b0}};
            end
            assign candidates_selected_w = insert0_w ? fetch_push0_candidates_i :
                insert1_w ? fetch_push1_candidates_i :
                ib_remove_count_i == 2'd2 ? candidates_next2_w :
                ib_remove_count_i == 2'd1 ? candidates_next1_w :
                corrected_candidates_w[5*slot +: 5];
            wire [1-1:0] region_wb0_valid_w;
            wire [5-1:0] region_wb0_rd_w;
            wire [1-1:0] region_wb1_valid_w;
            wire [5-1:0] region_wb1_rd_w;
            if (slot < PHYSICAL/2) begin : g_wb_region0
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
            wire [1:0] owner1_w;
            wire [1:0] owner2_w;
            assign rs1_w = instr_r[19:15];
            assign rs2_w = instr_r[24:20];
            assign owner1_w = rs1_w == 5'd0 ? 2'b00 :
                region_wb1_valid_w && region_wb1_rd_w == rs1_w ? 2'b11 :
                region_wb0_valid_w && region_wb0_rd_w == rs1_w ? 2'b00 :
                {candidates_r[2], candidates_r[0]};
            assign owner2_w = rs2_w == 5'd0 ? 2'b00 :
                region_wb1_valid_w && region_wb1_rd_w == rs2_w ? 2'b11 :
                region_wb0_valid_w && region_wb0_rd_w == rs2_w ? 2'b00 :
                {candidates_r[3], candidates_r[1]};
            assign corrected_candidates_w[5*slot +: 5] = {candidates_r[4],
                owner2_w[1], owner1_w[1], owner2_w[0], owner1_w[0]};
            always @(posedge clk_i) begin
                candidates_r <= (ISSUE_WIDTH == 2) ? candidates_selected_w : 5'd0;
            end
            reg [1-1:0] predict_taken_r;
            wire [1-1:0] predict_taken_next1_w;
            wire [1-1:0] predict_taken_next2_w;
            wire [1-1:0] predict_taken_selected_w;
            assign predict_taken_flat_w[1*slot +: 1] = predict_taken_r;
            if (slot < PHYSICAL-1) begin : g_predict_taken_next1
                assign predict_taken_next1_w = predict_taken_flat_w[1*(slot+1) +: 1];
            end else begin : g_predict_taken_end1
                assign predict_taken_next1_w = {1{1'b0}};
            end
            if (slot < PHYSICAL-2) begin : g_predict_taken_next2
                assign predict_taken_next2_w = predict_taken_flat_w[1*(slot+2) +: 1];
            end else begin : g_predict_taken_end2
                assign predict_taken_next2_w = {1{1'b0}};
            end
            assign predict_taken_selected_w = insert0_w ? fetch_push0_predict_taken_i :
                insert1_w ? fetch_push1_predict_taken_i :
                ib_remove_count_i == 2'd2 ? predict_taken_next2_w :
                ib_remove_count_i == 2'd1 ? predict_taken_next1_w : predict_taken_r;
            always @(posedge clk_i) begin
                predict_taken_r <= predict_taken_selected_w;
            end
            reg [32-1:0] predict_target_r;
            wire [32-1:0] predict_target_next1_w;
            wire [32-1:0] predict_target_next2_w;
            wire [32-1:0] predict_target_selected_w;
            assign predict_target_flat_w[32*slot +: 32] = predict_target_r;
            if (slot < PHYSICAL-1) begin : g_predict_target_next1
                assign predict_target_next1_w = predict_target_flat_w[32*(slot+1) +: 32];
            end else begin : g_predict_target_end1
                assign predict_target_next1_w = {32{1'b0}};
            end
            if (slot < PHYSICAL-2) begin : g_predict_target_next2
                assign predict_target_next2_w = predict_target_flat_w[32*(slot+2) +: 32];
            end else begin : g_predict_target_end2
                assign predict_target_next2_w = {32{1'b0}};
            end
            assign predict_target_selected_w = insert0_w ? fetch_push0_predict_target_i :
                insert1_w ? fetch_push1_predict_target_i :
                ib_remove_count_i == 2'd2 ? predict_target_next2_w :
                ib_remove_count_i == 2'd1 ? predict_target_next1_w : predict_target_r;
            always @(posedge clk_i) begin
                predict_target_r <= predict_target_selected_w;
            end
            reg [1-1:0] predict_token_r;
            wire [1-1:0] predict_token_next1_w;
            wire [1-1:0] predict_token_next2_w;
            wire [1-1:0] predict_token_selected_w;
            assign predict_token_flat_w[1*slot +: 1] = predict_token_r;
            if (slot < PHYSICAL-1) begin : g_predict_token_next1
                assign predict_token_next1_w = predict_token_flat_w[1*(slot+1) +: 1];
            end else begin : g_predict_token_end1
                assign predict_token_next1_w = {1{1'b0}};
            end
            if (slot < PHYSICAL-2) begin : g_predict_token_next2
                assign predict_token_next2_w = predict_token_flat_w[1*(slot+2) +: 1];
            end else begin : g_predict_token_end2
                assign predict_token_next2_w = {1{1'b0}};
            end
            assign predict_token_selected_w = insert0_w ? fetch_push0_predict_token_i :
                insert1_w ? fetch_push1_predict_token_i :
                ib_remove_count_i == 2'd2 ? predict_token_next2_w :
                ib_remove_count_i == 2'd1 ? predict_token_next1_w : predict_token_r;
            always @(posedge clk_i) begin
                predict_token_r <= (ISSUE_WIDTH == 2) ? predict_token_selected_w : {1{1'b0}};
            end
            reg [3-1:0] predict_provider_r;
            wire [3-1:0] predict_provider_next1_w;
            wire [3-1:0] predict_provider_next2_w;
            wire [3-1:0] predict_provider_selected_w;
            assign predict_provider_flat_w[3*slot +: 3] = predict_provider_r;
            if (slot < PHYSICAL-1) begin : g_predict_provider_next1
                assign predict_provider_next1_w = predict_provider_flat_w[3*(slot+1) +: 3];
            end else begin : g_predict_provider_end1
                assign predict_provider_next1_w = {3{1'b0}};
            end
            if (slot < PHYSICAL-2) begin : g_predict_provider_next2
                assign predict_provider_next2_w = predict_provider_flat_w[3*(slot+2) +: 3];
            end else begin : g_predict_provider_end2
                assign predict_provider_next2_w = {3{1'b0}};
            end
            assign predict_provider_selected_w = insert0_w ? fetch_push0_predict_provider_i :
                insert1_w ? fetch_push1_predict_provider_i :
                ib_remove_count_i == 2'd2 ? predict_provider_next2_w :
                ib_remove_count_i == 2'd1 ? predict_provider_next1_w : predict_provider_r;
            always @(posedge clk_i) begin
                predict_provider_r <= (ISSUE_WIDTH == 2) ? predict_provider_selected_w : {3{1'b0}};
            end
            reg [1-1:0] predict_alternate_r;
            wire [1-1:0] predict_alternate_next1_w;
            wire [1-1:0] predict_alternate_next2_w;
            wire [1-1:0] predict_alternate_selected_w;
            assign predict_alternate_flat_w[1*slot +: 1] = predict_alternate_r;
            if (slot < PHYSICAL-1) begin : g_predict_alternate_next1
                assign predict_alternate_next1_w = predict_alternate_flat_w[1*(slot+1) +: 1];
            end else begin : g_predict_alternate_end1
                assign predict_alternate_next1_w = {1{1'b0}};
            end
            if (slot < PHYSICAL-2) begin : g_predict_alternate_next2
                assign predict_alternate_next2_w = predict_alternate_flat_w[1*(slot+2) +: 1];
            end else begin : g_predict_alternate_end2
                assign predict_alternate_next2_w = {1{1'b0}};
            end
            assign predict_alternate_selected_w = insert0_w ? fetch_push0_predict_alternate_i :
                insert1_w ? fetch_push1_predict_alternate_i :
                ib_remove_count_i == 2'd2 ? predict_alternate_next2_w :
                ib_remove_count_i == 2'd1 ? predict_alternate_next1_w : predict_alternate_r;
            always @(posedge clk_i) begin
                predict_alternate_r <= (ISSUE_WIDTH == 2) ? predict_alternate_selected_w :
                    {1{1'b0}};
            end
            reg [9-1:0] predict_index0_r;
            wire [9-1:0] predict_index0_next1_w;
            wire [9-1:0] predict_index0_next2_w;
            wire [9-1:0] predict_index0_selected_w;
            assign predict_index0_flat_w[9*slot +: 9] = predict_index0_r;
            if (slot < PHYSICAL-1) begin : g_predict_index0_next1
                assign predict_index0_next1_w = predict_index0_flat_w[9*(slot+1) +: 9];
            end else begin : g_predict_index0_end1
                assign predict_index0_next1_w = {9{1'b0}};
            end
            if (slot < PHYSICAL-2) begin : g_predict_index0_next2
                assign predict_index0_next2_w = predict_index0_flat_w[9*(slot+2) +: 9];
            end else begin : g_predict_index0_end2
                assign predict_index0_next2_w = {9{1'b0}};
            end
            assign predict_index0_selected_w = insert0_w ? fetch_push0_predict_index0_i :
                insert1_w ? fetch_push1_predict_index0_i :
                ib_remove_count_i == 2'd2 ? predict_index0_next2_w :
                ib_remove_count_i == 2'd1 ? predict_index0_next1_w : predict_index0_r;
            always @(posedge clk_i) begin
                predict_index0_r <= (ISSUE_WIDTH == 2) ? predict_index0_selected_w : {9{1'b0}};
            end
            reg [9-1:0] predict_index1_r;
            wire [9-1:0] predict_index1_next1_w;
            wire [9-1:0] predict_index1_next2_w;
            wire [9-1:0] predict_index1_selected_w;
            assign predict_index1_flat_w[9*slot +: 9] = predict_index1_r;
            if (slot < PHYSICAL-1) begin : g_predict_index1_next1
                assign predict_index1_next1_w = predict_index1_flat_w[9*(slot+1) +: 9];
            end else begin : g_predict_index1_end1
                assign predict_index1_next1_w = {9{1'b0}};
            end
            if (slot < PHYSICAL-2) begin : g_predict_index1_next2
                assign predict_index1_next2_w = predict_index1_flat_w[9*(slot+2) +: 9];
            end else begin : g_predict_index1_end2
                assign predict_index1_next2_w = {9{1'b0}};
            end
            assign predict_index1_selected_w = insert0_w ? fetch_push0_predict_index1_i :
                insert1_w ? fetch_push1_predict_index1_i :
                ib_remove_count_i == 2'd2 ? predict_index1_next2_w :
                ib_remove_count_i == 2'd1 ? predict_index1_next1_w : predict_index1_r;
            always @(posedge clk_i) begin
                predict_index1_r <= (ISSUE_WIDTH == 2) ? predict_index1_selected_w : {9{1'b0}};
            end
            reg [9-1:0] predict_index2_r;
            wire [9-1:0] predict_index2_next1_w;
            wire [9-1:0] predict_index2_next2_w;
            wire [9-1:0] predict_index2_selected_w;
            assign predict_index2_flat_w[9*slot +: 9] = predict_index2_r;
            if (slot < PHYSICAL-1) begin : g_predict_index2_next1
                assign predict_index2_next1_w = predict_index2_flat_w[9*(slot+1) +: 9];
            end else begin : g_predict_index2_end1
                assign predict_index2_next1_w = {9{1'b0}};
            end
            if (slot < PHYSICAL-2) begin : g_predict_index2_next2
                assign predict_index2_next2_w = predict_index2_flat_w[9*(slot+2) +: 9];
            end else begin : g_predict_index2_end2
                assign predict_index2_next2_w = {9{1'b0}};
            end
            assign predict_index2_selected_w = insert0_w ? fetch_push0_predict_index2_i :
                insert1_w ? fetch_push1_predict_index2_i :
                ib_remove_count_i == 2'd2 ? predict_index2_next2_w :
                ib_remove_count_i == 2'd1 ? predict_index2_next1_w : predict_index2_r;
            always @(posedge clk_i) begin
                predict_index2_r <= (ISSUE_WIDTH == 2) ? predict_index2_selected_w : {9{1'b0}};
            end
            reg [9-1:0] predict_index3_r;
            wire [9-1:0] predict_index3_next1_w;
            wire [9-1:0] predict_index3_next2_w;
            wire [9-1:0] predict_index3_selected_w;
            assign predict_index3_flat_w[9*slot +: 9] = predict_index3_r;
            if (slot < PHYSICAL-1) begin : g_predict_index3_next1
                assign predict_index3_next1_w = predict_index3_flat_w[9*(slot+1) +: 9];
            end else begin : g_predict_index3_end1
                assign predict_index3_next1_w = {9{1'b0}};
            end
            if (slot < PHYSICAL-2) begin : g_predict_index3_next2
                assign predict_index3_next2_w = predict_index3_flat_w[9*(slot+2) +: 9];
            end else begin : g_predict_index3_end2
                assign predict_index3_next2_w = {9{1'b0}};
            end
            assign predict_index3_selected_w = insert0_w ? fetch_push0_predict_index3_i :
                insert1_w ? fetch_push1_predict_index3_i :
                ib_remove_count_i == 2'd2 ? predict_index3_next2_w :
                ib_remove_count_i == 2'd1 ? predict_index3_next1_w : predict_index3_r;
            always @(posedge clk_i) begin
                predict_index3_r <= (ISSUE_WIDTH == 2) ? predict_index3_selected_w : {9{1'b0}};
            end
            reg [10-1:0] predict_tag0_r;
            wire [10-1:0] predict_tag0_next1_w;
            wire [10-1:0] predict_tag0_next2_w;
            wire [10-1:0] predict_tag0_selected_w;
            assign predict_tag0_flat_w[10*slot +: 10] = predict_tag0_r;
            if (slot < PHYSICAL-1) begin : g_predict_tag0_next1
                assign predict_tag0_next1_w = predict_tag0_flat_w[10*(slot+1) +: 10];
            end else begin : g_predict_tag0_end1
                assign predict_tag0_next1_w = {10{1'b0}};
            end
            if (slot < PHYSICAL-2) begin : g_predict_tag0_next2
                assign predict_tag0_next2_w = predict_tag0_flat_w[10*(slot+2) +: 10];
            end else begin : g_predict_tag0_end2
                assign predict_tag0_next2_w = {10{1'b0}};
            end
            assign predict_tag0_selected_w = insert0_w ? fetch_push0_predict_tag0_i :
                insert1_w ? fetch_push1_predict_tag0_i :
                ib_remove_count_i == 2'd2 ? predict_tag0_next2_w :
                ib_remove_count_i == 2'd1 ? predict_tag0_next1_w : predict_tag0_r;
            always @(posedge clk_i) begin
                predict_tag0_r <= (ISSUE_WIDTH == 2) ? predict_tag0_selected_w : {10{1'b0}};
            end
            reg [10-1:0] predict_tag1_r;
            wire [10-1:0] predict_tag1_next1_w;
            wire [10-1:0] predict_tag1_next2_w;
            wire [10-1:0] predict_tag1_selected_w;
            assign predict_tag1_flat_w[10*slot +: 10] = predict_tag1_r;
            if (slot < PHYSICAL-1) begin : g_predict_tag1_next1
                assign predict_tag1_next1_w = predict_tag1_flat_w[10*(slot+1) +: 10];
            end else begin : g_predict_tag1_end1
                assign predict_tag1_next1_w = {10{1'b0}};
            end
            if (slot < PHYSICAL-2) begin : g_predict_tag1_next2
                assign predict_tag1_next2_w = predict_tag1_flat_w[10*(slot+2) +: 10];
            end else begin : g_predict_tag1_end2
                assign predict_tag1_next2_w = {10{1'b0}};
            end
            assign predict_tag1_selected_w = insert0_w ? fetch_push0_predict_tag1_i :
                insert1_w ? fetch_push1_predict_tag1_i :
                ib_remove_count_i == 2'd2 ? predict_tag1_next2_w :
                ib_remove_count_i == 2'd1 ? predict_tag1_next1_w : predict_tag1_r;
            always @(posedge clk_i) begin
                predict_tag1_r <= (ISSUE_WIDTH == 2) ? predict_tag1_selected_w : {10{1'b0}};
            end
            reg [10-1:0] predict_tag2_r;
            wire [10-1:0] predict_tag2_next1_w;
            wire [10-1:0] predict_tag2_next2_w;
            wire [10-1:0] predict_tag2_selected_w;
            assign predict_tag2_flat_w[10*slot +: 10] = predict_tag2_r;
            if (slot < PHYSICAL-1) begin : g_predict_tag2_next1
                assign predict_tag2_next1_w = predict_tag2_flat_w[10*(slot+1) +: 10];
            end else begin : g_predict_tag2_end1
                assign predict_tag2_next1_w = {10{1'b0}};
            end
            if (slot < PHYSICAL-2) begin : g_predict_tag2_next2
                assign predict_tag2_next2_w = predict_tag2_flat_w[10*(slot+2) +: 10];
            end else begin : g_predict_tag2_end2
                assign predict_tag2_next2_w = {10{1'b0}};
            end
            assign predict_tag2_selected_w = insert0_w ? fetch_push0_predict_tag2_i :
                insert1_w ? fetch_push1_predict_tag2_i :
                ib_remove_count_i == 2'd2 ? predict_tag2_next2_w :
                ib_remove_count_i == 2'd1 ? predict_tag2_next1_w : predict_tag2_r;
            always @(posedge clk_i) begin
                predict_tag2_r <= (ISSUE_WIDTH == 2) ? predict_tag2_selected_w : {10{1'b0}};
            end
            reg [10-1:0] predict_tag3_r;
            wire [10-1:0] predict_tag3_next1_w;
            wire [10-1:0] predict_tag3_next2_w;
            wire [10-1:0] predict_tag3_selected_w;
            assign predict_tag3_flat_w[10*slot +: 10] = predict_tag3_r;
            if (slot < PHYSICAL-1) begin : g_predict_tag3_next1
                assign predict_tag3_next1_w = predict_tag3_flat_w[10*(slot+1) +: 10];
            end else begin : g_predict_tag3_end1
                assign predict_tag3_next1_w = {10{1'b0}};
            end
            if (slot < PHYSICAL-2) begin : g_predict_tag3_next2
                assign predict_tag3_next2_w = predict_tag3_flat_w[10*(slot+2) +: 10];
            end else begin : g_predict_tag3_end2
                assign predict_tag3_next2_w = {10{1'b0}};
            end
            assign predict_tag3_selected_w = insert0_w ? fetch_push0_predict_tag3_i :
                insert1_w ? fetch_push1_predict_tag3_i :
                ib_remove_count_i == 2'd2 ? predict_tag3_next2_w :
                ib_remove_count_i == 2'd1 ? predict_tag3_next1_w : predict_tag3_r;
            always @(posedge clk_i) begin
                predict_tag3_r <= (ISSUE_WIDTH == 2) ? predict_tag3_selected_w : {10{1'b0}};
            end
            reg [12-1:0] predict_base_index_r;
            wire [12-1:0] predict_base_index_next1_w;
            wire [12-1:0] predict_base_index_next2_w;
            wire [12-1:0] predict_base_index_selected_w;
            assign predict_base_index_flat_w[12*slot +: 12] = predict_base_index_r;
            if (slot < PHYSICAL-1) begin : g_predict_base_index_next1
                assign predict_base_index_next1_w = predict_base_index_flat_w[12*(slot+1) +: 12];
            end else begin : g_predict_base_index_end1
                assign predict_base_index_next1_w = {12{1'b0}};
            end
            if (slot < PHYSICAL-2) begin : g_predict_base_index_next2
                assign predict_base_index_next2_w = predict_base_index_flat_w[12*(slot+2) +: 12];
            end else begin : g_predict_base_index_end2
                assign predict_base_index_next2_w = {12{1'b0}};
            end
            assign predict_base_index_selected_w = insert0_w ? fetch_push0_predict_base_index_i :
                insert1_w ? fetch_push1_predict_base_index_i :
                ib_remove_count_i == 2'd2 ? predict_base_index_next2_w :
                ib_remove_count_i == 2'd1 ? predict_base_index_next1_w : predict_base_index_r;
            always @(posedge clk_i) begin
                predict_base_index_r <= (ISSUE_WIDTH == 2) ? predict_base_index_selected_w :
                    {12{1'b0}};
            end
            reg [12-1:0] predict_fast_index_r;
            wire [12-1:0] predict_fast_index_next1_w;
            wire [12-1:0] predict_fast_index_next2_w;
            wire [12-1:0] predict_fast_index_selected_w;
            assign predict_fast_index_flat_w[12*slot +: 12] = predict_fast_index_r;
            if (slot < PHYSICAL-1) begin : g_predict_fast_index_next1
                assign predict_fast_index_next1_w = predict_fast_index_flat_w[12*(slot+1) +: 12];
            end else begin : g_predict_fast_index_end1
                assign predict_fast_index_next1_w = {12{1'b0}};
            end
            if (slot < PHYSICAL-2) begin : g_predict_fast_index_next2
                assign predict_fast_index_next2_w = predict_fast_index_flat_w[12*(slot+2) +: 12];
            end else begin : g_predict_fast_index_end2
                assign predict_fast_index_next2_w = {12{1'b0}};
            end
            assign predict_fast_index_selected_w = insert0_w ? fetch_push0_predict_fast_index_i :
                insert1_w ? fetch_push1_predict_fast_index_i :
                ib_remove_count_i == 2'd2 ? predict_fast_index_next2_w :
                ib_remove_count_i == 2'd1 ? predict_fast_index_next1_w : predict_fast_index_r;
            always @(posedge clk_i) begin
                predict_fast_index_r <= predict_fast_index_selected_w;
            end
            reg [RAS_BITS-1:0] ras_data_r;
            wire [RAS_BITS-1:0] ras_data_next1_w;
            wire [RAS_BITS-1:0] ras_data_next2_w;
            wire [RAS_BITS-1:0] ras_data_selected_w;
            assign ras_data_flat_w[RAS_BITS*slot +: RAS_BITS] = ras_data_r;
            if (slot < PHYSICAL-1) begin : g_ras_data_next1
                assign ras_data_next1_w = ras_data_flat_w[RAS_BITS*(slot+1) +: RAS_BITS];
            end else begin : g_ras_data_end1
                assign ras_data_next1_w = {RAS_BITS{1'b0}};
            end
            if (slot < PHYSICAL-2) begin : g_ras_data_next2
                assign ras_data_next2_w = ras_data_flat_w[RAS_BITS*(slot+2) +: RAS_BITS];
            end else begin : g_ras_data_end2
                assign ras_data_next2_w = {RAS_BITS{1'b0}};
            end
            assign ras_data_selected_w = insert0_w ? fetch_push0_ras_data_i :
                insert1_w ? fetch_push1_ras_data_i :
                ib_remove_count_i == 2'd2 ? ras_data_next2_w :
                ib_remove_count_i == 2'd1 ? ras_data_next1_w : ras_data_r;
            always @(posedge clk_i) begin
                ras_data_r <= ras_data_selected_w;
            end
            reg [RAS_PTR_BITS-1:0] ras_ptr_r;
            wire [RAS_PTR_BITS-1:0] ras_ptr_next1_w;
            wire [RAS_PTR_BITS-1:0] ras_ptr_next2_w;
            wire [RAS_PTR_BITS-1:0] ras_ptr_selected_w;
            assign ras_ptr_flat_w[RAS_PTR_BITS*slot +: RAS_PTR_BITS] = ras_ptr_r;
            if (slot < PHYSICAL-1) begin : g_ras_ptr_next1
                assign ras_ptr_next1_w = ras_ptr_flat_w[RAS_PTR_BITS*(slot+1) +: RAS_PTR_BITS];
            end else begin : g_ras_ptr_end1
                assign ras_ptr_next1_w = {RAS_PTR_BITS{1'b0}};
            end
            if (slot < PHYSICAL-2) begin : g_ras_ptr_next2
                assign ras_ptr_next2_w = ras_ptr_flat_w[RAS_PTR_BITS*(slot+2) +: RAS_PTR_BITS];
            end else begin : g_ras_ptr_end2
                assign ras_ptr_next2_w = {RAS_PTR_BITS{1'b0}};
            end
            assign ras_ptr_selected_w = insert0_w ? fetch_push0_ras_ptr_i :
                insert1_w ? fetch_push1_ras_ptr_i :
                ib_remove_count_i == 2'd2 ? ras_ptr_next2_w :
                ib_remove_count_i == 2'd1 ? ras_ptr_next1_w : ras_ptr_r;
            always @(posedge clk_i) begin
                ras_ptr_r <= ras_ptr_selected_w;
            end
            reg [RAS_COUNT_BITS-1:0] ras_count_r;
            wire [RAS_COUNT_BITS-1:0] ras_count_next1_w;
            wire [RAS_COUNT_BITS-1:0] ras_count_next2_w;
            wire [RAS_COUNT_BITS-1:0] ras_count_selected_w;
            assign ras_count_flat_w[RAS_COUNT_BITS*slot +: RAS_COUNT_BITS] = ras_count_r;
            if (slot < PHYSICAL-1) begin : g_ras_count_next1
                assign ras_count_next1_w = ras_count_flat_w[RAS_COUNT_BITS*(slot+1) +:
                    RAS_COUNT_BITS];
            end else begin : g_ras_count_end1
                assign ras_count_next1_w = {RAS_COUNT_BITS{1'b0}};
            end
            if (slot < PHYSICAL-2) begin : g_ras_count_next2
                assign ras_count_next2_w = ras_count_flat_w[RAS_COUNT_BITS*(slot+2) +:
                    RAS_COUNT_BITS];
            end else begin : g_ras_count_end2
                assign ras_count_next2_w = {RAS_COUNT_BITS{1'b0}};
            end
            assign ras_count_selected_w = insert0_w ? fetch_push0_ras_count_i :
                insert1_w ? fetch_push1_ras_count_i :
                ib_remove_count_i == 2'd2 ? ras_count_next2_w :
                ib_remove_count_i == 2'd1 ? ras_count_next1_w : ras_count_r;
            always @(posedge clk_i) begin
                ras_count_r <= ras_count_selected_w;
            end
        end
    endgenerate
    assign ib_head0_pc_o = pc_flat_w[0 +: 32];
    assign ib_head0_instr_o = instr_flat_w[0 +: 32];
    assign ib_head0_error_o = error_flat_w[0 +: 1];
    assign ib_head0_candidates_o = candidates_flat_w[0 +: 5];
    assign ib_head0_predict_taken_o = predict_taken_flat_w[0 +: 1];
    assign ib_head0_predict_target_o = predict_target_flat_w[0 +: 32];
    assign ib_head0_predict_token_o = predict_token_flat_w[0 +: 1];
    assign ib_head0_predict_provider_o = predict_provider_flat_w[0 +: 3];
    assign ib_head0_predict_alternate_o = predict_alternate_flat_w[0 +: 1];
    assign ib_head0_predict_index0_o = predict_index0_flat_w[0 +: 9];
    assign ib_head0_predict_index1_o = predict_index1_flat_w[0 +: 9];
    assign ib_head0_predict_index2_o = predict_index2_flat_w[0 +: 9];
    assign ib_head0_predict_index3_o = predict_index3_flat_w[0 +: 9];
    assign ib_head0_predict_tag0_o = predict_tag0_flat_w[0 +: 10];
    assign ib_head0_predict_tag1_o = predict_tag1_flat_w[0 +: 10];
    assign ib_head0_predict_tag2_o = predict_tag2_flat_w[0 +: 10];
    assign ib_head0_predict_tag3_o = predict_tag3_flat_w[0 +: 10];
    assign ib_head0_predict_base_index_o = predict_base_index_flat_w[0 +: 12];
    assign ib_head0_predict_fast_index_o = predict_fast_index_flat_w[0 +: 12];
    assign ib_head0_ras_data_o = ras_data_flat_w[0 +: RAS_BITS];
    assign ib_head0_ras_ptr_o = ras_ptr_flat_w[0 +: RAS_PTR_BITS];
    assign ib_head0_ras_count_o = ras_count_flat_w[0 +: RAS_COUNT_BITS];
    assign ib_head1_pc_o = (ISSUE_WIDTH == 2) ? pc_flat_w[32*1 +: 32] : {32{1'b0}};
    assign ib_head1_instr_o = (ISSUE_WIDTH == 2) ? instr_flat_w[32*1 +: 32] : {32{1'b0}};
    assign ib_head1_error_o = (ISSUE_WIDTH == 2) ? error_flat_w[1*1 +: 1] : {1{1'b0}};
    assign ib_head1_candidates_o = (ISSUE_WIDTH == 2) ? candidates_flat_w[5*1 +: 5] : {5{1'b0}};
    assign ib_head1_predict_taken_o = (ISSUE_WIDTH == 2) ? predict_taken_flat_w[1*1 +: 1] :
        {1{1'b0}};
    assign ib_head1_predict_target_o = (ISSUE_WIDTH == 2) ? predict_target_flat_w[32*1 +: 32] :
        {32{1'b0}};
    assign ib_head1_predict_token_o = (ISSUE_WIDTH == 2) ? predict_token_flat_w[1*1 +: 1] :
        {1{1'b0}};
    assign ib_head1_predict_provider_o = (ISSUE_WIDTH == 2) ? predict_provider_flat_w[3*1 +: 3]
        : {3{1'b0}};
    assign ib_head1_predict_alternate_o = (ISSUE_WIDTH == 2) ? predict_alternate_flat_w[1*1 +:
        1] : {1{1'b0}};
    assign ib_head1_predict_index0_o = (ISSUE_WIDTH == 2) ? predict_index0_flat_w[9*1 +: 9] :
        {9{1'b0}};
    assign ib_head1_predict_index1_o = (ISSUE_WIDTH == 2) ? predict_index1_flat_w[9*1 +: 9] :
        {9{1'b0}};
    assign ib_head1_predict_index2_o = (ISSUE_WIDTH == 2) ? predict_index2_flat_w[9*1 +: 9] :
        {9{1'b0}};
    assign ib_head1_predict_index3_o = (ISSUE_WIDTH == 2) ? predict_index3_flat_w[9*1 +: 9] :
        {9{1'b0}};
    assign ib_head1_predict_tag0_o = (ISSUE_WIDTH == 2) ? predict_tag0_flat_w[10*1 +: 10] :
        {10{1'b0}};
    assign ib_head1_predict_tag1_o = (ISSUE_WIDTH == 2) ? predict_tag1_flat_w[10*1 +: 10] :
        {10{1'b0}};
    assign ib_head1_predict_tag2_o = (ISSUE_WIDTH == 2) ? predict_tag2_flat_w[10*1 +: 10] :
        {10{1'b0}};
    assign ib_head1_predict_tag3_o = (ISSUE_WIDTH == 2) ? predict_tag3_flat_w[10*1 +: 10] :
        {10{1'b0}};
    assign ib_head1_predict_base_index_o = (ISSUE_WIDTH == 2) ? predict_base_index_flat_w[12*1
        +: 12] : {12{1'b0}};
    assign ib_head1_predict_fast_index_o = (ISSUE_WIDTH == 2) ? predict_fast_index_flat_w[12*1
        +: 12] : {12{1'b0}};
    assign ib_head1_ras_data_o = (ISSUE_WIDTH == 2) ? ras_data_flat_w[RAS_BITS*1 +: RAS_BITS] :
        {RAS_BITS{1'b0}};
    assign ib_head1_ras_ptr_o = (ISSUE_WIDTH == 2) ? ras_ptr_flat_w[RAS_PTR_BITS*1 +:
        RAS_PTR_BITS] : {RAS_PTR_BITS{1'b0}};
    assign ib_head1_ras_count_o = (ISSUE_WIDTH == 2) ? ras_count_flat_w[RAS_COUNT_BITS*1 +:
        RAS_COUNT_BITS] : {RAS_COUNT_BITS{1'b0}};
    assign unused_w = ^candidates_flat_w;
endmodule
