// File: edrv32_cpu_predictor.v
// Spec: cpu-spec 4.4
// Description: Predict one branch per fetch group with a tagged BTB and gshare direction table.
// Speculative return prediction uses a four-entry RAS with explicit recovery state.
// Clock domain: clk_sys.
module edrv32_cpu_predictor (
    // Clock and control reset.
    input wire clk_i,
    input wire rst_n_i,
    input wire [7:0] rst_sys_direction_n_i,

    // F1 query; accept advances speculative RAS only for an accepted prediction.
    input wire [31:1] query_pc_i,
    input wire query_accept_i,
    output wire predict_hit_o,
    output wire predict_taken_o,
    output wire [31:0] predict_target_o,
    output wire [1:0] predict_position_o,
    output wire predict_compressed_o,
    output wire [8:0] predict_history_o,
    output wire [36:0] predict_ras_o,
    // E trains only surviving branches, using their original query index.
    // Types: 0 conditional, 1 JAL, 2 JALR, 3 call, 4 return.
    input wire update_valid_i,
    input wire [31:1] update_pc_i,
    input wire [31:0] update_target_i,
    input wire [2:0] update_type_i,
    input wire update_taken_i,
    input wire update_compressed_i,
    input wire [143:0] update_index_i,

    // F2 clears the stale fetch-group prediction after boundary or length mismatch.
    input wire clear_valid_i,
    input wire [4:0] clear_index_i,

    // Redirect restores the saved state and applies the actual call/return action.
    input wire restore_valid_i,
    input wire [36:0] restore_ras_i,
    input wire restore_push_i,
    input wire restore_pop_i,
    input wire [31:0] restore_return_pc_i
);
    localparam BTB_ENTRIES = 32;
    localparam DIRECTION_ENTRIES = 512;
    localparam RAS_ENTRIES = 4;
    reg [BTB_ENTRIES-1:0] btb_valid_r;
    reg [23:0] btb_tag_r [0:BTB_ENTRIES-1];
    reg [31:0] btb_target_r [0:BTB_ENTRIES-1];
    reg [1:0] btb_position_r [0:BTB_ENTRIES-1];
    reg [2:0] btb_type_r [0:BTB_ENTRIES-1];
    reg btb_compressed_r [0:BTB_ENTRIES-1];
    wire [DIRECTION_ENTRIES*2-1:0] direction_r;
    reg [8:0] history_r;
    reg [127:0] ras_data_r;
    reg [1:0] ras_ptr_r;
    reg [2:0] ras_count_r;
    wire [4:0] query_idx_w;
    wire [8:0] direction_idx_w;
    wire [1:0] ras_top_w;
    wire [31:0] branch_pc_w;
    wire [1:0] restore_ptr_w;
    wire [2:0] restore_count_w;
    wire [1:0] restore_pop_ptr_w;
    wire [1:0] restore_write_ptr_w;
    wire unused_compressed_w;
    assign unused_compressed_w = update_compressed_i;
    genvar ras_idx;
    assign query_idx_w = query_pc_i[7:3];
    assign branch_pc_w = {query_pc_i[31:3], btb_position_r[query_idx_w], 1'b0};
    assign direction_idx_w = branch_pc_w[9:1] ^ history_r;
    assign predict_hit_o = btb_valid_r[query_idx_w] &&
        btb_tag_r[query_idx_w] == query_pc_i[31:8] &&
        btb_position_r[query_idx_w] >= query_pc_i[2:1];
    assign predict_taken_o = predict_hit_o &&
        (btb_type_r[query_idx_w] != 0 || direction_r[direction_idx_w * 2 + 1]);
    assign ras_top_w = ras_ptr_r - 1'b1;
    assign predict_target_o = btb_type_r[query_idx_w] == 4 && ras_count_r != 0 ?
        ras_data_r[ras_top_w * 32 +: 32] : btb_target_r[query_idx_w];
    assign predict_position_o = btb_position_r[query_idx_w];
    assign predict_compressed_o = btb_compressed_r[query_idx_w];
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
                btb_valid_r[update_pc_i[7:3]] <= 1'b1;
                if (update_type_i == 0) begin
                    history_r <= {history_r[7:0], update_taken_i};

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
                if (btb_type_r[query_idx_w] == 3) begin
                    ras_ptr_r <= ras_ptr_r + 1'b1;
                    if (ras_count_r != RAS_ENTRIES)
                        ras_count_r <= ras_count_r + 1'b1;
                end else if (btb_type_r[query_idx_w] == 4 && ras_count_r != 0) begin
                    ras_ptr_r <= ras_ptr_r - 1'b1;
                    ras_count_r <= ras_count_r - 1'b1;
                end
            end
        end
    end
    always @(posedge clk_i) begin
        if (update_valid_i) begin
            btb_tag_r[update_pc_i[7:3]] <= update_pc_i[31:8];
            btb_target_r[update_pc_i[7:3]] <= update_target_i;
            btb_position_r[update_pc_i[7:3]] <= update_pc_i[2:1];
            btb_type_r[update_pc_i[7:3]] <= update_type_i;
            btb_compressed_r[update_pc_i[7:3]] <= 1'b0;
        end
    end
    genvar direction_bank;
    generate
        for (direction_bank = 0; direction_bank < 16;
            direction_bank = direction_bank + 1) begin : g_direction
            reg [63:0] counters_r;
            wire rst_direction_n_w;
            wire [8:0] update_index_w;
            wire [1:0] update_counter_w;
            wire update_w /* synthesis syn_keep=1 */;
            assign direction_r[direction_bank*64 +: 64] = counters_r;
            assign rst_direction_n_w = rst_sys_direction_n_i[direction_bank/2];
            assign update_index_w = update_index_i[direction_bank*9 +: 9];
            // Each bank reads and increments only its own selected counter.
            // No global 512-entry update mux broadcasts its result back to every entry.
            assign update_counter_w = counters_r[update_index_w[4:0]*2 +: 2];
            assign update_w = update_valid_i && update_type_i == 0 &&
                update_index_w[8:5] == direction_bank[3:0];
            always @(posedge clk_i or negedge rst_direction_n_w) begin
                if (!rst_direction_n_w) begin
                    counters_r <= {32{2'b01}};
                end else if (update_w) begin
                    if (update_taken_i && update_counter_w != 3)
                        counters_r[update_index_w[4:0]*2 +: 2] <= update_counter_w + 1'b1;
                    else if (!update_taken_i && update_counter_w != 0)
                        counters_r[update_index_w[4:0]*2 +: 2] <= update_counter_w - 1'b1;
                end
            end
        end
    endgenerate
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
                btb_type_r[query_idx_w] == 3 && ras_ptr_r == ras_idx[1:0];
            always @(posedge clk_i) begin
                if (restore_valid_i && (restore_top_w || restore_link_w))
                    ras_data_r[ras_idx*32 +: 32] <= restore_link_w ?
                        restore_return_pc_i : restore_ras_i[31:0];
                else if (!restore_valid_i && query_link_w)
                    ras_data_r[ras_idx*32 +: 32] <= branch_pc_w +
                        32'd4;
            end
        end
    endgenerate
endmodule
