// File: edrv32_cpu_predictor.v
// Spec: cpu-spec 4.4
// Description: Predict one branch per fetch group with a tagged BTB and gshare direction table.
// Speculative return prediction uses a four-entry RAS with explicit recovery state.
// Clock domain: clk_sys.
module edrv32_cpu_predictor (
    // Clock and control reset.
    input wire clk_i,
    input wire rst_n_i,

    // F1 query; accept advances speculative RAS only for an accepted prediction.
    input wire [31:1] query_pc_i,
    input wire query_accept_i,
    output wire predict_hit_o,
    output wire predict_taken_o,
    output wire [31:0] predict_target_o,
    output wire [1:0] predict_position_o,
    output wire [11:0] predict_history_o,
    output wire [36:0] predict_ras_o,
    // F1 captures histories and both gshare directions; F2 reads the second level.
    output wire predict_conditional_o,
    output wire [19:0] predict_local_history_o,
    output wire [1:0] predict_global_o,
    input wire [19:0] f2_local_history_i,
    input wire [11:0] f2_index_i,
    output wire [1:0] f2_local_o,
    output wire f2_use_local_o,
    // E trains only surviving branches, using their original query index.
    // Types: 0 conditional, 1 JAL, 2 JALR, 3 call, 4 return.
    input wire update_valid_i,
    input wire [31:1] update_pc_i,
    input wire [31:0] update_target_i,
    input wire [2:0] update_type_i,
    input wire update_taken_i,
    input wire [11:0] update_index_i,

    input wire [11:0] update_tournament_i,

    // F2 clears the stale fetch-group prediction after boundary or length mismatch.
    input wire clear_valid_i,
    input wire [6:0] clear_index_i,

    // Redirect restores the saved state and applies the actual call/return action.
    input wire restore_valid_i,
    input wire [36:0] restore_ras_i,
    input wire restore_push_i,
    input wire restore_pop_i,
    input wire [31:0] restore_return_pc_i
);
    localparam BTB_ENTRIES = 128;
    localparam RAS_ENTRIES = 4;
    reg [BTB_ENTRIES-1:0] btb_valid_r;
    wire [57:0] btb_data_w;
    wire [3:0] direction_word_w;
    wire [3:0] update_word_w;
    wire [3:0] next_word_w;
    wire [1:0] direction_w;
    wire [1:0] update_counter_w;
    wire [1:0] next_counter_w;
    reg [11:0] history_r;
    reg [127:0] ras_data_r;
    reg [1:0] ras_ptr_r;
    reg [2:0] ras_count_r;
    wire [6:0] query_idx_w;
    wire [11:0] direction_idx_w;
    wire [1:0] ras_top_w;
    wire [31:0] branch_return_pc_w;
    wire [31:0] group_return_pc_w;
    (* keep = 1 *) wire [1:0] tag_half_hit_w /* synthesis syn_keep=1 */;
    wire position_hit_w;
    wire direction_taken_w;
    wire [1:0] restore_ptr_w;
    wire [2:0] restore_count_w;
    wire [1:0] restore_pop_ptr_w;
    wire [1:0] restore_write_ptr_w;
    wire [2:0] unused_query_w;
    assign unused_query_w = {query_pc_i[1], update_pc_i[1], direction_w[0]};
    genvar ras_idx;
    assign query_idx_w = query_pc_i[9:3];
    // cpu-spec 4.9: the LUTRAM position selects precomputed return addresses.
    // In particular it must not start a carry into the RAS write data.
    assign group_return_pc_w = {query_pc_i[31:3] + 29'd1, 3'b0};
    assign branch_return_pc_w = btb_data_w[3] ? group_return_pc_w :
        {query_pc_i[31:3], 3'b100};
    // The word address is independent of BTB; its position selects a counter after both reads.
    assign direction_idx_w = {query_pc_i[13:3] ^ history_r[11:1],
        btb_data_w[3] ^ history_r[0]};
    assign direction_w = direction_idx_w[0] ? direction_word_w[3:2] : direction_word_w[1:0];
    // Two parallel eleven-bit compares leave one LUT for valid/position/direction.
    // Retain the halves so mapping cannot serialize equality and prediction tests.
    assign tag_half_hit_w[0] = btb_data_w[46:36] == query_pc_i[20:10];
    assign tag_half_hit_w[1] = btb_data_w[57:47] == query_pc_i[31:21];
    assign position_hit_w = {btb_data_w[3], 1'b0} >= query_pc_i[2:1];
    assign direction_taken_w = btb_data_w[2:0] != 0 || direction_w[1];
    // Keep the independent tests parallel up to the final prediction decision.
    assign predict_hit_o = btb_valid_r[query_idx_w] && (&tag_half_hit_w) && position_hit_w;
    assign predict_taken_o = btb_valid_r[query_idx_w] && (&tag_half_hit_w) &&
        position_hit_w && direction_taken_w;
    assign ras_top_w = ras_ptr_r - 1'b1;
    assign predict_target_o = btb_data_w[2:0] == 4 && ras_count_r != 0 ?
        ras_data_r[ras_top_w * 32 +: 32] : btb_data_w[35:4];
    assign predict_position_o = {btb_data_w[3], 1'b0};
    assign predict_history_o = history_r;
    assign predict_ras_o = {ras_count_r, ras_ptr_r, ras_data_r[ras_top_w * 32 +: 32]};
    assign restore_ptr_w = restore_ras_i[33:32];
    assign restore_count_w = restore_ras_i[36:34];
    assign restore_pop_ptr_w = restore_ptr_w - 1'b1;
    assign restore_write_ptr_w = restore_pop_i && restore_count_w != 0 ?
        restore_pop_ptr_w : restore_ptr_w;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            btb_valid_r <= 0;
            history_r <= 0;
            ras_ptr_r <= 0;
            ras_count_r <= 0;
        end else begin
            if (update_valid_i) begin
                btb_valid_r[update_pc_i[9:3]] <= 1'b1;
                if (update_type_i == 0) begin
                    history_r <= {history_r[10:0], update_taken_i};

                end
            end
            if (clear_valid_i)
                btb_valid_r[clear_index_i] <= 1'b0;
            if (restore_valid_i) begin
                ras_ptr_r <= restore_ptr_w;
                ras_count_r <= restore_count_w;
                if (restore_pop_i && restore_count_w != 0) begin
                    ras_ptr_r <= restore_pop_ptr_w;
                    ras_count_r <= restore_count_w - 1'b1;
                end
                if (restore_push_i) begin
                    ras_ptr_r <= (restore_pop_i && restore_count_w != 0 ?
                        restore_pop_ptr_w : restore_ptr_w) + 1'b1;
                    if (restore_pop_i && restore_count_w != 0)
                        ras_count_r <= restore_count_w;
                    else
                        ras_count_r <= restore_count_w == RAS_ENTRIES ?
                            restore_count_w : restore_count_w + 1'b1;
                end
            end else if (query_accept_i && predict_taken_o) begin
                if (btb_data_w[2:0] == 3) begin
                    ras_ptr_r <= ras_ptr_r + 1'b1;
                    if (ras_count_r != RAS_ENTRIES)
                        ras_count_r <= ras_count_r + 1'b1;
                end else if (btb_data_w[2:0] == 4 && ras_count_r != 0) begin
                    ras_ptr_r <= ras_ptr_r - 1'b1;
                    ras_count_r <= ras_count_r - 1'b1;
                end
            end
        end
    end
    edrv32_ram_cpu_btb u_btb (
        .clk_i(clk_i),
        .wr_en_i(update_valid_i),
        .wr_addr_i(update_pc_i[9:3]),
        .wr_data_i({update_pc_i[31:10], update_target_i, update_pc_i[2], update_type_i}),
        .rd_addr_i(query_idx_w),
        .rd_data_o(btb_data_w)
    );
    assign update_counter_w = update_index_i[0] ? update_word_w[3:2] : update_word_w[1:0];
    assign next_word_w = update_index_i[0] ?
        {next_counter_w, update_word_w[1:0]} : {update_word_w[3:2], next_counter_w};
    assign next_counter_w = update_taken_i ?
        (update_counter_w == 3 ? 2'b11 : update_counter_w + 1'b1) :
        (update_counter_w == 0 ? 2'b00 : update_counter_w - 1'b1);
    edrv32_ram_cpu_direction u_direction (
        .clk_i(clk_i),
        .wr_en_i(update_valid_i && update_type_i == 0),
        .wr_addr_i(update_index_i[11:1]),
        .wr_data_i(next_word_w),
        .update_data_o(update_word_w),
        .rd_addr_i(direction_idx_w[11:1]),
        .rd_data_o(direction_word_w)
    );
    // cpu-spec 4.4: query tokens retain directions, while training reads current counters.
    wire [2:0] unused_tournament_w;
    assign unused_tournament_w = {update_local_history_w[9], chooser_w[0], 1'b0};
    wire [9:0] update_local_history_w;
    wire [1:0] local_counter_w [0:1];
    wire [1:0] update_local_counter_w;
    wire [1:0] chooser_w;
    wire [1:0] update_chooser_w;
    wire [1:0] next_local_counter_w;
    wire [1:0] next_chooser_w;
    wire conditional_update_w;
    wire local_correct_w;
    assign predict_conditional_o = btb_data_w[2:0] == 0;
    assign predict_global_o = history_r[0] ?
        {direction_word_w[1], direction_word_w[3]} :
        {direction_word_w[3], direction_word_w[1]};
    assign f2_local_o = {local_counter_w[1][1], local_counter_w[0][1]};
    assign f2_use_local_o = chooser_w[1];
    assign conditional_update_w = update_valid_i && update_type_i == 0;
    assign local_correct_w = update_tournament_i[10] == update_taken_i;
    assign next_local_counter_w = update_taken_i ?
        (update_local_counter_w == 3 ? 2'd3 : update_local_counter_w + 1'b1) :
        (update_local_counter_w == 0 ? 2'd0 : update_local_counter_w - 1'b1);
    assign next_chooser_w = local_correct_w ?
        (update_chooser_w == 3 ? 2'd3 : update_chooser_w + 1'b1) :
        (update_chooser_w == 0 ? 2'd0 : update_chooser_w - 1'b1);
    edrv32_ram_cpu_local_history u_local_history (
        .clk_i(clk_i),
        .wr_en_i(conditional_update_w),
        .wr_addr_i(update_pc_i[9:2]),
        .wr_data_i({update_local_history_w[8:0], update_taken_i}),
        .update_data_o(update_local_history_w),
        .rd0_addr_i({query_pc_i[9:3], 1'b0}),
        .rd0_data_o(predict_local_history_o[9:0]),
        .rd1_addr_i({query_pc_i[9:3], 1'b1}),
        .rd1_data_o(predict_local_history_o[19:10])
    );
    edrv32_ram_cpu_local_direction u_local_direction (
        .clk_i(clk_i),
        .wr_en_i(conditional_update_w),
        .wr_addr_i(update_tournament_i[9:0]),
        .wr_data_i(next_local_counter_w),
        .update_data_o(update_local_counter_w),
        .rd0_addr_i(f2_local_history_i[9:0]),
        .rd0_data_o(local_counter_w[0]),
        .rd1_addr_i(f2_local_history_i[19:10]),
        .rd1_data_o(local_counter_w[1])
    );
    edrv32_ram_cpu_chooser u_chooser (
        .clk_i(clk_i),
        .wr_en_i(conditional_update_w && update_tournament_i[10] != update_tournament_i[11]),
        .wr_addr_i(update_index_i),
        .wr_data_i(next_chooser_w),
        .update_data_o(update_chooser_w),
        .rd0_addr_i(f2_index_i),
        .rd0_data_o(chooser_w)
    );
    // Decode each destination before the late redirect/recovery enable arrives.
    // A push still overrides a restored top when both select the same entry.
    generate
        for (ras_idx = 0; ras_idx < RAS_ENTRIES; ras_idx = ras_idx + 1) begin : g_ras
            wire restore_top_w;
            wire restore_link_w;
            wire query_link_w;
            assign restore_top_w = restore_count_w != 0 && restore_pop_ptr_w == ras_idx[1:0];
            assign restore_link_w = restore_push_i && restore_write_ptr_w == ras_idx[1:0];
            assign query_link_w = query_accept_i && predict_taken_o &&
                btb_data_w[2:0] == 3 && ras_ptr_r == ras_idx[1:0];
            always @(posedge clk_i) begin
                if (restore_valid_i && (restore_top_w || restore_link_w))
                    ras_data_r[ras_idx*32 +: 32] <= restore_link_w ?
                        restore_return_pc_i : restore_ras_i[31:0];
                else if (!restore_valid_i && query_link_w)
                    ras_data_r[ras_idx*32 +: 32] <= branch_return_pc_w;
            end
        end
    endgenerate
endmodule
