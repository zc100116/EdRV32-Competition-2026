// edrv32_cpu_predictor.v
// cpu-spec 4.4
// Predict one branch per fetch group with a tagged BTB and gshare direction table.
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
    input wire [8:0] update_index_i,
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
    reg [DIRECTION_ENTRIES*2-1:0] direction_r;
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
            direction_r <= {DIRECTION_ENTRIES{2'b01}};
        end else begin
            if (update_valid_i) begin
                btb_valid_r[update_pc_i[7:3]] <= 1'b1;
                if (update_type_i == 0) begin
                    history_r <= {history_r[7:0], update_taken_i};
                    if (update_taken_i && direction_r[update_index_i * 2 +: 2] != 3)
                        direction_r[update_index_i * 2 +: 2] <=
                            direction_r[update_index_i * 2 +: 2] + 1'b1;
                    else if (!update_taken_i && direction_r[update_index_i * 2 +: 2] != 0)
                        direction_r[update_index_i * 2 +: 2] <=
                            direction_r[update_index_i * 2 +: 2] - 1'b1;
                end
            end
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
            btb_compressed_r[update_pc_i[7:3]] <= update_compressed_i;
        end
        if (restore_valid_i) begin
            if (restore_count_w != 0)
                ras_data_r[restore_pop_ptr_w * 32 +: 32] <= restore_ras_i[31:0];
            if (restore_push_i)
                ras_data_r[restore_write_ptr_w * 32 +: 32] <= restore_return_pc_i;
        end else if (query_accept_i && predict_taken_o && btb_type_r[query_idx_w] == 3) begin
            ras_data_r[ras_ptr_r * 32 +: 32] <= branch_pc_w +
                (btb_compressed_r[query_idx_w] ? 32'd2 : 32'd4);
        end
    end
endmodule
