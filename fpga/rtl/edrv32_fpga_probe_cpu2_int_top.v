// File: edrv32_fpga_probe_cpu2_int_top.v
// Spec: cpu-v2-spec 7.
// Description: Registered independent stimuli and observations preserve the four integer probe paths.
// Clock domain: clk_sys.
module edrv32_fpga_probe_cpu2_int_top (
    input wire clk_i,
    input wire rst_n_i,
    input wire stim_i,
    output wire obs_o
);
    reg [255:0] stimulus_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            stimulus_r <= 256'h1;
        else
            stimulus_r <= {stimulus_r[254:0], stimulus_r[255] ^ stimulus_r[253] ^
                stimulus_r[250] ^ stimulus_r[245] ^ stim_i};
    end
    // Preserve each consumer's capture region; shared stimulus bits must not merge regions.
    (* keep = "true", syn_preserve = 1 *) reg [19:0] rf_id_rs_r;
    always @(posedge clk_i) begin
        rf_id_rs_r <= stimulus_r[0 +: 20];
    end
    (* keep = "true", syn_preserve = 1 *) reg [3:0] rf_id_owner_r;
    always @(posedge clk_i) begin
        rf_id_owner_r <= stimulus_r[19 +: 4];
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] rf_wb_valid_r;
    always @(posedge clk_i) begin
        rf_wb_valid_r <= stimulus_r[38 +: 2];
    end
    (* keep = "true", syn_preserve = 1 *) reg [9:0] rf_wb_rd_r;
    always @(posedge clk_i) begin
        rf_wb_rd_r <= stimulus_r[57 +: 10];
    end
    (* keep = "true", syn_preserve = 1 *) reg [63:0] rf_wb_data_r;
    always @(posedge clk_i) begin
        rf_wb_data_r <= stimulus_r[76 +: 64];
    end
    wire [31:1] rf_lvt_w;
    reg [31:1] rf_lvt_r;
    always @(posedge clk_i) begin
        rf_lvt_r <= rf_lvt_w;
    end
    wire [127:0] rf_id_data_w;
    reg [127:0] rf_id_data_r;
    always @(posedge clk_i) begin
        rf_id_data_r <= rf_id_data_w;
    end
    edrv32_cpu2_rf u_rf (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .id_rs_i(rf_id_rs_r),
        .id_owner_i(rf_id_owner_r),
        .wb_valid_i(rf_wb_valid_r),
        .wb_rd_i(rf_wb_rd_r),
        .wb_data_i(rf_wb_data_r),
        .lvt_o(rf_lvt_w),
        .id_data_o(rf_id_data_w)
    );
    (* keep = "true", syn_preserve = 1 *) reg fetch_f1_valid_r;
    always @(posedge clk_i) begin
        fetch_f1_valid_r <= stimulus_r[95 +: 1];
    end
    (* keep = "true", syn_preserve = 1 *) reg [31:0] fetch_f1_pc_r;
    always @(posedge clk_i) begin
        fetch_f1_pc_r <= stimulus_r[114 +: 32];
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] fetch_f1_direction_r;
    always @(posedge clk_i) begin
        fetch_f1_direction_r <= stimulus_r[133 +: 2];
    end
    (* keep = "true", syn_preserve = 1 *) reg fetch_fill_valid_r;
    always @(posedge clk_i) begin
        fetch_fill_valid_r <= stimulus_r[152 +: 1];
    end
    (* keep = "true", syn_preserve = 1 *) reg fetch_fill_way_r;
    always @(posedge clk_i) begin
        fetch_fill_way_r <= stimulus_r[171 +: 1];
    end
    (* keep = "true", syn_preserve = 1 *) reg [31:0] fetch_fill_addr_r;
    always @(posedge clk_i) begin
        fetch_fill_addr_r <= stimulus_r[190 +: 32];
    end
    (* keep = "true", syn_preserve = 1 *) reg [31:0] fetch_fill_instr_r;
    always @(posedge clk_i) begin
        fetch_fill_instr_r <= stimulus_r[209 +: 32];
    end
    (* keep = "true", syn_preserve = 1 *) reg fetch_fill_line_valid_r;
    always @(posedge clk_i) begin
        fetch_fill_line_valid_r <= stimulus_r[228 +: 1];
    end
    (* keep = "true", syn_preserve = 1 *) reg fetch_btb_write_r;
    always @(posedge clk_i) begin
        fetch_btb_write_r <= stimulus_r[247 +: 1];
    end
    (* keep = "true", syn_preserve = 1 *) reg [31:0] fetch_btb_pc_r;
    always @(posedge clk_i) begin
        fetch_btb_pc_r <= stimulus_r[41 +: 32];
    end
    (* keep = "true", syn_preserve = 1 *) reg [31:0] fetch_btb_target_r;
    always @(posedge clk_i) begin
        fetch_btb_target_r <= stimulus_r[60 +: 32];
    end
    (* keep = "true", syn_preserve = 1 *) reg [2:0] fetch_btb_type_r;
    always @(posedge clk_i) begin
        fetch_btb_type_r <= stimulus_r[50 +: 3];
    end
    (* keep = "true", syn_preserve = 1 *) reg [31:1] fetch_lvt_r;
    always @(posedge clk_i) begin
        fetch_lvt_r <= stimulus_r[97 +: 31];
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] fetch_wb_valid_r;
    always @(posedge clk_i) begin
        fetch_wb_valid_r <= stimulus_r[87 +: 2];
    end
    (* keep = "true", syn_preserve = 1 *) reg [9:0] fetch_wb_rd_r;
    always @(posedge clk_i) begin
        fetch_wb_rd_r <= stimulus_r[114 +: 10];
    end
    (* keep = "true", syn_preserve = 1 *) reg fetch_ib_accept_r;
    always @(posedge clk_i) begin
        fetch_ib_accept_r <= stimulus_r[124 +: 1];
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] fetch_ib_remove_r;
    always @(posedge clk_i) begin
        fetch_ib_remove_r <= stimulus_r[144 +: 2];
    end
    wire fetch_ib_ready_w;
    reg fetch_ib_ready_r;
    always @(posedge clk_i) begin
        fetch_ib_ready_r <= fetch_ib_ready_w;
    end
    wire [3:0] fetch_ib_count_w;
    reg [3:0] fetch_ib_count_r;
    always @(posedge clk_i) begin
        fetch_ib_count_r <= fetch_ib_count_w;
    end
    wire [1:0] fetch_id_valid_w;
    reg [1:0] fetch_id_valid_r;
    always @(posedge clk_i) begin
        fetch_id_valid_r <= fetch_id_valid_w;
    end
    wire [63:0] fetch_id_instr_w;
    reg [63:0] fetch_id_instr_r;
    always @(posedge clk_i) begin
        fetch_id_instr_r <= fetch_id_instr_w;
    end
    wire [9:0] fetch_id_candidates_w;
    reg [9:0] fetch_id_candidates_r;
    always @(posedge clk_i) begin
        fetch_id_candidates_r <= fetch_id_candidates_w;
    end
    wire fetch_f2_valid_w;
    reg fetch_f2_valid_r;
    always @(posedge clk_i) begin
        fetch_f2_valid_r <= fetch_f2_valid_w;
    end
    wire [1:0] fetch_f2_hit_w;
    reg [1:0] fetch_f2_hit_r;
    always @(posedge clk_i) begin
        fetch_f2_hit_r <= fetch_f2_hit_w;
    end
    wire [63:0] fetch_f2_instr_w;
    reg [63:0] fetch_f2_instr_r;
    always @(posedge clk_i) begin
        fetch_f2_instr_r <= fetch_f2_instr_w;
    end
    wire [1:0] fetch_f2_taken_w;
    reg [1:0] fetch_f2_taken_r;
    always @(posedge clk_i) begin
        fetch_f2_taken_r <= fetch_f2_taken_w;
    end
    wire [31:0] fetch_f2_target_w;
    reg [31:0] fetch_f2_target_r;
    always @(posedge clk_i) begin
        fetch_f2_target_r <= fetch_f2_target_w;
    end
    wire [5:0] fetch_f2_type_w;
    reg [5:0] fetch_f2_type_r;
    always @(posedge clk_i) begin
        fetch_f2_type_r <= fetch_f2_type_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] fetch_wb_valid_copy_r;
    always @(posedge clk_i) begin
        fetch_wb_valid_copy_r <= stimulus_r[87 +: 2];
    end
    (* keep = "true", syn_preserve = 1 *) reg [9:0] fetch_wb_rd_copy_r;
    always @(posedge clk_i) begin
        fetch_wb_rd_copy_r <= stimulus_r[114 +: 10];
    end
    edrv32_cpu2_fetch u_fetch (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .f1_valid_i(fetch_f1_valid_r),
        .f1_pc_i(fetch_f1_pc_r),
        .f1_direction_i(fetch_f1_direction_r),
        .fill_valid_i(fetch_fill_valid_r),
        .fill_way_i(fetch_fill_way_r),
        .fill_addr_i(fetch_fill_addr_r),
        .fill_instr_i(fetch_fill_instr_r),
        .fill_line_valid_i(fetch_fill_line_valid_r),
        .btb_write_i(fetch_btb_write_r),
        .btb_pc_i(fetch_btb_pc_r),
        .btb_target_i(fetch_btb_target_r),
        .btb_type_i(fetch_btb_type_r),
        .lvt_i(fetch_lvt_r),
        .wb_valid_i(fetch_wb_valid_r),
        .wb_rd_i(fetch_wb_rd_r),
        .wb_valid_copy_i(fetch_wb_valid_copy_r),
        .wb_rd_copy_i(fetch_wb_rd_copy_r),
        .ib_accept_i(fetch_ib_accept_r),
        .ib_remove_i(fetch_ib_remove_r),
        .ib_ready_o(fetch_ib_ready_w),
        .ib_count_o(fetch_ib_count_w),
        .id_valid_o(fetch_id_valid_w),
        .id_instr_o(fetch_id_instr_w),
        .id_candidates_o(fetch_id_candidates_w),
        .f2_valid_o(fetch_f2_valid_w),
        .f2_hit_o(fetch_f2_hit_w),
        .f2_instr_o(fetch_f2_instr_w),
        .f2_taken_o(fetch_f2_taken_w),
        .f2_target_o(fetch_f2_target_w),
        .f2_type_o(fetch_f2_type_w)
    );
    (* keep = "true", syn_preserve = 1 *) reg tage_f1_valid_r;
    always @(posedge clk_i) begin
        tage_f1_valid_r <= stimulus_r[162 +: 1];
    end
    (* keep = "true", syn_preserve = 1 *) reg [31:0] tage_f1_pc_r;
    always @(posedge clk_i) begin
        tage_f1_pc_r <= stimulus_r[212 +: 32];
    end
    wire [1:0] tage_f1_fast_w;
    reg [1:0] tage_f1_fast_r;
    always @(posedge clk_i) begin
        tage_f1_fast_r <= tage_f1_fast_w;
    end
    wire tage_f2_valid_w;
    reg tage_f2_valid_r;
    always @(posedge clk_i) begin
        tage_f2_valid_r <= tage_f2_valid_w;
    end
    wire [1:0] tage_f2_prediction_w;
    reg [1:0] tage_f2_prediction_r;
    always @(posedge clk_i) begin
        tage_f2_prediction_r <= tage_f2_prediction_w;
    end
    wire [1:0] tage_f2_alternate_w;
    reg [1:0] tage_f2_alternate_r;
    always @(posedge clk_i) begin
        tage_f2_alternate_r <= tage_f2_alternate_w;
    end
    wire [5:0] tage_f2_provider_w;
    reg [5:0] tage_f2_provider_r;
    always @(posedge clk_i) begin
        tage_f2_provider_r <= tage_f2_provider_w;
    end
    wire [71:0] tage_f2_indices_w;
    reg [71:0] tage_f2_indices_r;
    always @(posedge clk_i) begin
        tage_f2_indices_r <= tage_f2_indices_w;
    end
    wire [79:0] tage_f2_tags_w;
    reg [79:0] tage_f2_tags_r;
    always @(posedge clk_i) begin
        tage_f2_tags_r <= tage_f2_tags_w;
    end
    wire [23:0] tage_f2_base_indices_w;
    reg [23:0] tage_f2_base_indices_r;
    always @(posedge clk_i) begin
        tage_f2_base_indices_r <= tage_f2_base_indices_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg tage_d_valid_r;
    always @(posedge clk_i) begin
        tage_d_valid_r <= stimulus_r[200 +: 1];
    end
    (* keep = "true", syn_preserve = 1 *) reg [35:0] tage_d_indices_r;
    always @(posedge clk_i) begin
        tage_d_indices_r <= stimulus_r[33 +: 36];
    end
    (* keep = "true", syn_preserve = 1 *) reg [39:0] tage_d_tags_r;
    always @(posedge clk_i) begin
        tage_d_tags_r <= stimulus_r[60 +: 40];
    end
    (* keep = "true", syn_preserve = 1 *) reg [11:0] tage_d_base_index_r;
    always @(posedge clk_i) begin
        tage_d_base_index_r <= stimulus_r[23 +: 12];
    end
    (* keep = "true", syn_preserve = 1 *) reg [2:0] tage_d_provider_r;
    always @(posedge clk_i) begin
        tage_d_provider_r <= stimulus_r[24 +: 3];
    end
    (* keep = "true", syn_preserve = 1 *) reg tage_d_prediction_r;
    always @(posedge clk_i) begin
        tage_d_prediction_r <= stimulus_r[39 +: 1];
    end
    (* keep = "true", syn_preserve = 1 *) reg tage_d_alternate_r;
    always @(posedge clk_i) begin
        tage_d_alternate_r <= stimulus_r[58 +: 1];
    end
    (* keep = "true", syn_preserve = 1 *) reg tage_ex_resolve_r;
    always @(posedge clk_i) begin
        tage_ex_resolve_r <= stimulus_r[77 +: 1];
    end
    (* keep = "true", syn_preserve = 1 *) reg tage_ex_taken_r;
    always @(posedge clk_i) begin
        tage_ex_taken_r <= stimulus_r[96 +: 1];
    end
    (* keep = "true", syn_preserve = 1 *) reg tage_mem_resolve_r;
    always @(posedge clk_i) begin
        tage_mem_resolve_r <= stimulus_r[115 +: 1];
    end
    (* keep = "true", syn_preserve = 1 *) reg tage_mem_taken_r;
    always @(posedge clk_i) begin
        tage_mem_taken_r <= stimulus_r[134 +: 1];
    end
    (* keep = "true", syn_preserve = 1 *) reg tage_fast_update_r;
    always @(posedge clk_i) begin
        tage_fast_update_r <= stimulus_r[153 +: 1];
    end
    (* keep = "true", syn_preserve = 1 *) reg [11:0] tage_fast_index_r;
    always @(posedge clk_i) begin
        tage_fast_index_r <= stimulus_r[194 +: 12];
    end
    (* keep = "true", syn_preserve = 1 *) reg tage_fast_taken_r;
    always @(posedge clk_i) begin
        tage_fast_taken_r <= stimulus_r[191 +: 1];
    end
    wire tage_pending_w;
    reg tage_pending_r;
    always @(posedge clk_i) begin
        tage_pending_r <= tage_pending_w;
    end
    edrv32_cpu2_tage u_tage (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .f1_valid_i(tage_f1_valid_r),
        .f1_pc_i(tage_f1_pc_r),
        .f1_fast_o(tage_f1_fast_w),
        .f2_valid_o(tage_f2_valid_w),
        .f2_prediction_o(tage_f2_prediction_w),
        .f2_alternate_o(tage_f2_alternate_w),
        .f2_provider_o(tage_f2_provider_w),
        .f2_indices_o(tage_f2_indices_w),
        .f2_tags_o(tage_f2_tags_w),
        .f2_base_indices_o(tage_f2_base_indices_w),
        .d_valid_i(tage_d_valid_r),
        .d_indices_i(tage_d_indices_r),
        .d_tags_i(tage_d_tags_r),
        .d_base_index_i(tage_d_base_index_r),
        .d_provider_i(tage_d_provider_r),
        .d_prediction_i(tage_d_prediction_r),
        .d_alternate_i(tage_d_alternate_r),
        .ex_resolve_i(tage_ex_resolve_r),
        .ex_taken_i(tage_ex_taken_r),
        .mem_resolve_i(tage_mem_resolve_r),
        .mem_taken_i(tage_mem_taken_r),
        .fast_update_i(tage_fast_update_r),
        .fast_index_i(tage_fast_index_r),
        .fast_taken_i(tage_fast_taken_r),
        .pending_o(tage_pending_w)
    );
    (* keep = "true", syn_preserve = 1 *) reg id_agu_id_valid_r;
    always @(posedge clk_i) begin
        id_agu_id_valid_r <= stimulus_r[210 +: 1];
    end
    (* keep = "true", syn_preserve = 1 *) reg id_agu_id_load_r;
    always @(posedge clk_i) begin
        id_agu_id_load_r <= stimulus_r[229 +: 1];
    end
    (* keep = "true", syn_preserve = 1 *) reg id_agu_id_store_r;
    always @(posedge clk_i) begin
        id_agu_id_store_r <= stimulus_r[248 +: 1];
    end
    (* keep = "true", syn_preserve = 1 *) reg [4:0] id_agu_id_rs1_r;
    always @(posedge clk_i) begin
        id_agu_id_rs1_r <= stimulus_r[23 +: 5];
    end
    (* keep = "true", syn_preserve = 1 *) reg [4:0] id_agu_id_candidates_r;
    always @(posedge clk_i) begin
        id_agu_id_candidates_r <= stimulus_r[42 +: 5];
    end
    (* keep = "true", syn_preserve = 1 *) reg [31:0] id_agu_id_imm_r;
    always @(posedge clk_i) begin
        id_agu_id_imm_r <= stimulus_r[142 +: 32];
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] id_agu_wb_valid_r;
    always @(posedge clk_i) begin
        id_agu_wb_valid_r <= stimulus_r[71 +: 2];
    end
    (* keep = "true", syn_preserve = 1 *) reg [9:0] id_agu_wb_rd_r;
    always @(posedge clk_i) begin
        id_agu_wb_rd_r <= stimulus_r[114 +: 10];
    end
    (* keep = "true", syn_preserve = 1 *) reg [63:0] id_agu_wb_data_r;
    always @(posedge clk_i) begin
        id_agu_wb_data_r <= stimulus_r[102 +: 64];
    end
    (* keep = "true", syn_preserve = 1 *) reg id_agu_older_valid_r;
    always @(posedge clk_i) begin
        id_agu_older_valid_r <= stimulus_r[125 +: 1];
    end
    (* keep = "true", syn_preserve = 1 *) reg [4:0] id_agu_older_rd_r;
    always @(posedge clk_i) begin
        id_agu_older_rd_r <= stimulus_r[156 +: 5];
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] id_agu_ex_valid_r;
    always @(posedge clk_i) begin
        id_agu_ex_valid_r <= stimulus_r[166 +: 2];
    end
    (* keep = "true", syn_preserve = 1 *) reg [9:0] id_agu_ex_rd_r;
    always @(posedge clk_i) begin
        id_agu_ex_rd_r <= stimulus_r[209 +: 10];
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] id_agu_mem_valid_r;
    always @(posedge clk_i) begin
        id_agu_mem_valid_r <= stimulus_r[204 +: 2];
    end
    (* keep = "true", syn_preserve = 1 *) reg [9:0] id_agu_mem_rd_r;
    always @(posedge clk_i) begin
        id_agu_mem_rd_r <= stimulus_r[0 +: 10];
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] id_agu_wb_mul_pending_r;
    always @(posedge clk_i) begin
        id_agu_wb_mul_pending_r <= stimulus_r[242 +: 2];
    end
    (* keep = "true", syn_preserve = 1 *) reg [9:0] id_agu_wb_mul_rd_r;
    always @(posedge clk_i) begin
        id_agu_wb_mul_rd_r <= stimulus_r[38 +: 10];
    end
    (* keep = "true", syn_preserve = 1 *) reg id_agu_fill_valid_r;
    always @(posedge clk_i) begin
        id_agu_fill_valid_r <= stimulus_r[21 +: 1];
    end
    (* keep = "true", syn_preserve = 1 *) reg id_agu_fill_way_r;
    always @(posedge clk_i) begin
        id_agu_fill_way_r <= stimulus_r[40 +: 1];
    end
    (* keep = "true", syn_preserve = 1 *) reg [31:0] id_agu_fill_addr_r;
    always @(posedge clk_i) begin
        id_agu_fill_addr_r <= stimulus_r[183 +: 32];
    end
    (* keep = "true", syn_preserve = 1 *) reg [31:0] id_agu_fill_data_r;
    always @(posedge clk_i) begin
        id_agu_fill_data_r <= stimulus_r[202 +: 32];
    end
    (* keep = "true", syn_preserve = 1 *) reg id_agu_fill_line_valid_r;
    always @(posedge clk_i) begin
        id_agu_fill_line_valid_r <= stimulus_r[97 +: 1];
    end
    wire id_agu_id_eligible_w;
    reg id_agu_id_eligible_r;
    always @(posedge clk_i) begin
        id_agu_id_eligible_r <= id_agu_id_eligible_w;
    end
    wire [31:0] id_agu_id_addr_w;
    reg [31:0] id_agu_id_addr_r;
    always @(posedge clk_i) begin
        id_agu_id_addr_r <= id_agu_id_addr_w;
    end
    wire id_agu_ex_valid_w;
    reg observed_id_agu_ex_valid_r;
    always @(posedge clk_i) begin
        observed_id_agu_ex_valid_r <= id_agu_ex_valid_w;
    end
    wire [31:0] id_agu_ex_addr_w;
    reg [31:0] id_agu_ex_addr_r;
    always @(posedge clk_i) begin
        id_agu_ex_addr_r <= id_agu_ex_addr_w;
    end
    wire id_agu_operand_valid_w;
    reg id_agu_operand_valid_r;
    always @(posedge clk_i) begin
        id_agu_operand_valid_r <= id_agu_operand_valid_w;
    end
    wire id_agu_operand_hit_w;
    reg id_agu_operand_hit_r;
    always @(posedge clk_i) begin
        id_agu_operand_hit_r <= id_agu_operand_hit_w;
    end
    wire [31:0] id_agu_operand_data_w;
    reg [31:0] id_agu_operand_data_r;
    always @(posedge clk_i) begin
        id_agu_operand_data_r <= id_agu_operand_data_w;
    end
    edrv32_cpu2_id_agu u_id_agu (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .id_valid_i(id_agu_id_valid_r),
        .id_load_i(id_agu_id_load_r),
        .id_store_i(id_agu_id_store_r),
        .id_rs1_i(id_agu_id_rs1_r),
        .id_candidates_i(id_agu_id_candidates_r),
        .id_imm_i(id_agu_id_imm_r),
        .wb_valid_i(id_agu_wb_valid_r),
        .wb_rd_i(id_agu_wb_rd_r),
        .wb_data_i(id_agu_wb_data_r),
        .older_valid_i(id_agu_older_valid_r),
        .older_rd_i(id_agu_older_rd_r),
        .ex_valid_i(id_agu_ex_valid_r),
        .ex_rd_i(id_agu_ex_rd_r),
        .mem_valid_i(id_agu_mem_valid_r),
        .mem_rd_i(id_agu_mem_rd_r),
        .wb_mul_pending_i(id_agu_wb_mul_pending_r),
        .wb_mul_rd_i(id_agu_wb_mul_rd_r),
        .fill_valid_i(id_agu_fill_valid_r),
        .fill_way_i(id_agu_fill_way_r),
        .fill_addr_i(id_agu_fill_addr_r),
        .fill_data_i(id_agu_fill_data_r),
        .fill_line_valid_i(id_agu_fill_line_valid_r),
        .id_eligible_o(id_agu_id_eligible_w),
        .id_addr_o(id_agu_id_addr_w),
        .ex_valid_o(id_agu_ex_valid_w),
        .ex_addr_o(id_agu_ex_addr_w),
        .operand_valid_o(id_agu_operand_valid_w),
        .operand_hit_o(id_agu_operand_hit_w),
        .operand_data_o(id_agu_operand_data_w)
    );
    reg observation_r;
    always @(posedge clk_i) begin
        observation_r <=
            ^rf_lvt_r ^
            ^rf_id_data_r ^
            ^fetch_ib_ready_r ^
            ^fetch_ib_count_r ^
            ^fetch_id_valid_r ^
            ^fetch_id_instr_r ^
            ^fetch_id_candidates_r ^
            ^fetch_f2_valid_r ^
            ^fetch_f2_hit_r ^
            ^fetch_f2_instr_r ^
            ^fetch_f2_taken_r ^
            ^fetch_f2_target_r ^
            ^fetch_f2_type_r ^
            ^tage_f1_fast_r ^
            ^tage_f2_valid_r ^
            ^tage_f2_prediction_r ^
            ^tage_f2_alternate_r ^
            ^tage_f2_provider_r ^
            ^tage_f2_indices_r ^
            ^tage_f2_tags_r ^
            ^tage_f2_base_indices_r ^
            ^tage_pending_r ^
            ^id_agu_id_eligible_r ^
            ^id_agu_id_addr_r ^
            ^observed_id_agu_ex_valid_r ^
            ^id_agu_ex_addr_r ^
            ^id_agu_operand_valid_r ^
            ^id_agu_operand_hit_r ^
            ^id_agu_operand_data_r;
    end
    assign obs_o = observation_r;
endmodule
