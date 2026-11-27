// File: edrv32_cpu2_tage.v
// Spec: cpu-v2-spec 5.4, 7.
// Description: Banked F1 RAM requests, F2 provider selection, D training and one pending write.
// Clock domain: clk_sys.
module edrv32_cpu2_tage (
    // Clock and control.
    input wire clk_i,
    input wire rst_n_i,
    // Adjacent F1 words; both queries use the same resolved-history snapshot.
    input wire f1_valid_i,
    input wire [31:0] f1_pc_i,
    output wire [1:0] f1_fast_o,
    output wire f2_valid_o,
    output wire [1:0] f2_prediction_o,
    output wire [1:0] f2_alternate_o,
    output wire [5:0] f2_provider_o,
    output wire [71:0] f2_indices_o,
    output wire [79:0] f2_tags_o,
    output wire [23:0] f2_base_indices_o,
    // D pre-read of a live branch with an F1 query token; never a BTB cold miss.
    input wire d_valid_i,
    input wire [35:0] d_indices_i,
    input wire [39:0] d_tags_i,
    input wire [11:0] d_base_index_i,
    input wire [2:0] d_provider_i,
    input wire d_prediction_i,
    input wire d_alternate_i,
    // Resolve at EX or MEM; each token resolves exactly once.
    input wire ex_resolve_i,
    input wire ex_taken_i,
    input wire mem_resolve_i,
    input wire mem_taken_i,
    // Fast gshare trains on all resolved conditional branches, including cold misses.
    input wire fast_update_i,
    input wire [11:0] fast_index_i,
    input wire fast_taken_i,
    output wire pending_o
);
    wire [31:0] query_pc_w [0:1];
    wire [35:0] query_indices_w [0:1];
    wire [11:0] query_base_w [0:1];
    wire unused_w;
    assign unused_w = ^{f1_pc_i[31:21], f1_pc_i[1:0]};
    assign query_pc_w[0] = f1_pc_i;
    assign query_pc_w[1] = f1_pc_i + 32'd4;
    reg [95:0] history_r;
    reg [95:0] history_next_w;
    wire [35:0] fold_index_flat_w;
    wire [39:0] fold_tag_flat_w;
    wire [35:0] fold_shift_flat_w;
    reg ex_token_r;
    reg mem_token_r;
    reg [35:0] ex_indices_r;
    reg [35:0] mem_indices_r;
    reg [39:0] ex_tags_r;
    reg [39:0] mem_tags_r;
    reg [11:0] ex_base_index_r;
    reg [11:0] mem_base_index_r;
    reg [2:0] ex_provider_r;
    reg [2:0] mem_provider_r;
    reg ex_prediction_r;
    reg mem_prediction_r;
    reg ex_alternate_r;
    reg mem_alternate_r;
    wire ex_update_w;
    wire mem_update_w;
    assign ex_update_w = ex_token_r && ex_resolve_i;
    assign mem_update_w = mem_token_r && mem_resolve_i;
    always @(*) begin
        history_next_w = history_r;
        if (mem_update_w)
            history_next_w = {history_next_w[94:0], mem_taken_i};
        if (ex_update_w)
            history_next_w = {history_next_w[94:0], ex_taken_i};
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            history_r <= 96'd0;
            ex_token_r <= 1'b0;
            mem_token_r <= 1'b0;
        end else begin
            history_r <= history_next_w;
            ex_token_r <= d_valid_i;
            mem_token_r <= ex_token_r && !ex_resolve_i;
        end
    end
    always @(posedge clk_i) begin
        ex_indices_r <= d_indices_i;
        ex_tags_r <= d_tags_i;
        ex_base_index_r <= d_base_index_i;
        ex_provider_r <= d_provider_i;
        ex_prediction_r <= d_prediction_i;
        ex_alternate_r <= d_alternate_i;
        mem_indices_r <= ex_indices_r;
        mem_tags_r <= ex_tags_r;
        mem_base_index_r <= ex_base_index_r;
        mem_provider_r <= ex_provider_r;
        mem_prediction_r <= ex_prediction_r;
        mem_alternate_r <= ex_alternate_r;
    end
    // One pending branch bundle; each table still has only one physical write port.
    reg pending_valid_r;
    reg [35:0] pending_indices_r;
    reg [11:0] pending_base_index_r;
    reg [63:0] pending_rows_r;
    reg [3:0] pending_mask_r;
    reg [1:0] pending_base_r;
    wire write_valid_w;
    wire [35:0] write_indices_w;
    wire [11:0] write_base_index_w;
    wire [63:0] write_rows_w;
    wire [3:0] write_mask_w;
    wire [1:0] write_base_w;
    wire pending_next_valid_w;
    wire [35:0] pending_next_indices_w;
    wire [11:0] pending_next_base_index_w;
    wire [63:0] pending_next_rows_w;
    wire [3:0] pending_next_mask_w;
    wire [1:0] pending_next_base_w;
    wire [63:0] ex_new_rows_w;
    wire [63:0] mem_new_rows_w;
    wire [3:0] ex_mask_w;
    wire [3:0] mem_mask_w;
    wire [1:0] ex_new_base_w;
    wire [1:0] mem_new_base_w;
    assign write_valid_w = pending_valid_r || mem_update_w || ex_update_w;
    assign write_indices_w = pending_valid_r ? pending_indices_r :
        mem_update_w ? mem_indices_r : ex_indices_r;
    assign write_base_index_w = pending_valid_r ? pending_base_index_r :
        mem_update_w ? mem_base_index_r : ex_base_index_r;
    assign write_rows_w = pending_valid_r ? pending_rows_r :
        mem_update_w ? mem_new_rows_w : ex_new_rows_w;
    assign write_mask_w = pending_valid_r ? pending_mask_r :
        mem_update_w ? mem_mask_w : ex_mask_w;
    assign write_base_w = pending_valid_r ? pending_base_r :
        mem_update_w ? mem_new_base_w : ex_new_base_w;
    assign pending_next_valid_w = pending_valid_r ? (mem_update_w || ex_update_w) :
        (mem_update_w && ex_update_w);
    assign pending_next_indices_w = ex_update_w ? ex_indices_r : mem_indices_r;
    assign pending_next_base_index_w = ex_update_w ? ex_base_index_r : mem_base_index_r;
    assign pending_next_rows_w = ex_update_w ? ex_new_rows_w : mem_new_rows_w;
    assign pending_next_mask_w = ex_update_w ? ex_mask_w : mem_mask_w;
    assign pending_next_base_w = ex_update_w ? ex_new_base_w : mem_new_base_w;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            pending_valid_r <= 1'b0;
        else
            pending_valid_r <= pending_next_valid_w;
    end
    always @(posedge clk_i) begin
        pending_indices_r <= pending_next_indices_w;
        pending_base_index_r <= pending_next_base_index_w;
        pending_rows_r <= pending_next_rows_w;
        pending_mask_r <= pending_next_mask_w;
        pending_base_r <= pending_next_base_w;
    end
    assign pending_o = pending_valid_r;
    // Write-first forwarding around the old-data physical RAMs, without depending on IP mode.
    reg last_write_r;
    reg [35:0] last_indices_r;
    reg [11:0] last_base_index_r;
    reg [63:0] last_rows_r;
    reg [3:0] last_mask_r;
    reg [1:0] last_base_r;
    reg [63:0] mem_rows_r;
    reg [1:0] mem_base_r;
    wire [63:0] d_rows_w;
    wire [1:0] d_base_w;
    wire [63:0] ex_current_rows_w;
    wire [63:0] mem_current_rows_w;
    wire [1:0] ex_current_base_w;
    wire [1:0] mem_current_base_w;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            last_write_r <= 1'b0;
        else
            last_write_r <= write_valid_w;
    end
    always @(posedge clk_i) begin
        last_indices_r <= write_indices_w;
        last_base_index_r <= write_base_index_w;
        last_rows_r <= write_rows_w;
        last_mask_r <= write_mask_w;
        last_base_r <= write_base_w;
        mem_rows_r <= ex_current_rows_w;
        mem_base_r <= ex_current_base_w;
    end
    assign mem_current_base_w =
        (pending_valid_r && (pending_base_index_r == mem_base_index_r)) ? pending_base_r :
        (last_write_r && (last_base_index_r == mem_base_index_r)) ? last_base_r : mem_base_r;
    assign ex_current_base_w =
        (mem_update_w && (mem_base_index_r == ex_base_index_r)) ? mem_new_base_w :
        (pending_valid_r && (pending_base_index_r == ex_base_index_r)) ? pending_base_r :
        (last_write_r && (last_base_index_r == ex_base_index_r)) ? last_base_r : d_base_w;
    edrv32_ram_cpu2_base_train u_base_train (
        .clk_i(clk_i),
        .wr_en_i(write_valid_w),
        .wr_addr_i(write_base_index_w),
        .wr_data_i(write_base_w),
        .rd_en_i(d_valid_i),
        .rd_addr_i(d_base_index_i),
        .rd_data_o(d_base_w)
    );
    edrv32_cpu2_tage_update u_mem_update (
        .rows_i(mem_current_rows_w),
        .tags_i(mem_tags_r),
        .provider_i(mem_provider_r),
        .prediction_i(mem_prediction_r),
        .alternate_i(mem_alternate_r),
        .taken_i(mem_taken_i),
        .base_i(mem_current_base_w),
        .base_o(mem_new_base_w),
        .rows_o(mem_new_rows_w),
        .write_o(mem_mask_w)
    );
    edrv32_cpu2_tage_update u_ex_update (
        .rows_i(ex_current_rows_w),
        .tags_i(ex_tags_r),
        .provider_i(ex_provider_r),
        .prediction_i(ex_prediction_r),
        .alternate_i(ex_alternate_r),
        .taken_i(ex_taken_i),
        .base_i(ex_current_base_w),
        .base_o(ex_new_base_w),
        .rows_o(ex_new_rows_w),
        .write_o(ex_mask_w)
    );
    wire [63:0] prediction_rows_w [0:1];
    wire [1:0] prediction_base_w [0:1];
    wire [71:0] f2_indices_flat_w;
    wire [79:0] f2_tags_flat_w;
    wire [23:0] f2_base_index_flat_w;
    wire [7:0] f2_shadow_index_flat_w;
    wire [7:0] f2_shadow_tag_flat_w;
    wire [7:0] f2_shadow_direction_flat_w;
    wire [1:0] f2_base_shadow_flat_w;
    wire [1:0] f2_base_direction_flat_w;
    wire [5:0] provider_flat_w;
    wire [1:0] prediction_flat_w;
    wire [1:0] alternate_flat_w;
    reg f2_valid_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            f2_valid_r <= 1'b0;
        else
            f2_valid_r <= f1_valid_i;
    end
    assign f2_valid_o = f2_valid_r;
    genvar table_num;
    genvar query;
    genvar bank;
    generate
        for (table_num = 0; table_num < 4; table_num = table_num + 1) begin : g_table
            reg [8:0] fold_shift_r;
            assign fold_shift_flat_w[9*table_num +: 9] = fold_shift_r;
            reg [9:0] fold_tag_r;
            assign fold_tag_flat_w[10*table_num +: 10] = fold_tag_r;
            reg [8:0] fold_index_r;
            assign fold_index_flat_w[9*table_num +: 9] = fold_index_r;
            localparam LENGTH = (table_num == 0) ? 4 : (table_num == 1) ? 12 :
                (table_num == 2) ? 32 : 96;
            wire [107:0] history_index_w;
            wire [99:0] history_tag_w;
            wire [107:0] history_shift_w;
            wire [8:0] folded_index_w;
            wire [9:0] folded_tag_w;
            wire [8:0] folded_shift_w;
            assign history_index_w = {{(108-LENGTH){1'b0}}, history_next_w[LENGTH-1:0]};
            assign history_tag_w = {{(100-LENGTH){1'b0}}, history_next_w[LENGTH-1:0]};
            assign history_shift_w = history_index_w >> 1;
            assign folded_index_w =
                history_index_w[0 +: 9] ^
                history_index_w[9 +: 9] ^
                history_index_w[18 +: 9] ^
                history_index_w[27 +: 9] ^
                history_index_w[36 +: 9] ^
                history_index_w[45 +: 9] ^
                history_index_w[54 +: 9] ^
                history_index_w[63 +: 9] ^
                history_index_w[72 +: 9] ^
                history_index_w[81 +: 9] ^
                history_index_w[90 +: 9] ^
                history_index_w[99 +: 9];
            assign folded_tag_w =
                history_tag_w[0 +: 10] ^
                history_tag_w[10 +: 10] ^
                history_tag_w[20 +: 10] ^
                history_tag_w[30 +: 10] ^
                history_tag_w[40 +: 10] ^
                history_tag_w[50 +: 10] ^
                history_tag_w[60 +: 10] ^
                history_tag_w[70 +: 10] ^
                history_tag_w[80 +: 10] ^
                history_tag_w[90 +: 10];
            assign folded_shift_w =
                history_shift_w[0 +: 9] ^
                history_shift_w[9 +: 9] ^
                history_shift_w[18 +: 9] ^
                history_shift_w[27 +: 9] ^
                history_shift_w[36 +: 9] ^
                history_shift_w[45 +: 9] ^
                history_shift_w[54 +: 9] ^
                history_shift_w[63 +: 9] ^
                history_shift_w[72 +: 9] ^
                history_shift_w[81 +: 9] ^
                history_shift_w[90 +: 9] ^
                history_shift_w[99 +: 9];
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    fold_index_r <= 9'd0;
                    fold_tag_r <= 10'd0;
                    fold_shift_r <= 9'd0;
                end else begin
                    fold_index_r <= folded_index_w;
                    fold_tag_r <= folded_tag_w;
                    fold_shift_r <= folded_shift_w;
                end
            end
            wire [8:0] ex_index_w;
            wire [8:0] mem_index_w;
            wire [8:0] pending_index_w;
            wire [8:0] last_index_w;
            wire [8:0] write_index_w;
            wire [8:0] d_index_w;
            assign ex_index_w = ex_indices_r[9*table_num +: 9];
            assign mem_index_w = mem_indices_r[9*table_num +: 9];
            assign pending_index_w = pending_indices_r[9*table_num +: 9];
            assign last_index_w = last_indices_r[9*table_num +: 9];
            assign write_index_w = write_indices_w[9*table_num +: 9];
            assign d_index_w = d_indices_i[9*table_num +: 9];
            edrv32_ram_cpu2_tage_train u_train (
                .clk_i(clk_i),
                .wr_en_i(write_valid_w && write_mask_w[table_num]),
                .wr_addr_i(write_index_w),
                .wr_data_i(write_rows_w[16*table_num +: 16]),
                .rd_en_i(d_valid_i),
                .rd_addr_i(d_index_w),
                .rd_data_o(d_rows_w[16*table_num +: 16])
            );
            assign mem_current_rows_w[16*table_num +: 16] =
                (pending_valid_r && pending_mask_r[table_num] &&
                    (pending_index_w == mem_index_w)) ? pending_rows_r[16*table_num +: 16] :
                (last_write_r && last_mask_r[table_num] && (last_index_w == mem_index_w)) ?
                    last_rows_r[16*table_num +: 16] : mem_rows_r[16*table_num +: 16];
            assign ex_current_rows_w[16*table_num +: 16] =
                (mem_update_w && mem_mask_w[table_num] && (mem_index_w == ex_index_w)) ?
                    mem_new_rows_w[16*table_num +: 16] :
                (pending_valid_r && pending_mask_r[table_num] &&
                    (pending_index_w == ex_index_w)) ? pending_rows_r[16*table_num +: 16] :
                (last_write_r && last_mask_r[table_num] && (last_index_w == ex_index_w)) ?
                    last_rows_r[16*table_num +: 16] : d_rows_w[16*table_num +: 16];
            wire [8:0] index0_w;
            wire [8:0] index1_w;
            wire unused_index_w;
            assign unused_index_w = index1_w[0];
            wire [31:0] physical_rows_w;
            reg parity_r;
            assign index0_w = query_indices_w[0][9*table_num +: 9];
            assign index1_w = query_indices_w[1][9*table_num +: 9];
            always @(posedge clk_i) begin
                parity_r <= index0_w[0];
            end
            for (bank = 0; bank < 2; bank = bank + 1) begin : g_bank
                localparam BANK = (bank != 0);
                wire [7:0] addr_w;
                assign addr_w = (index0_w[0] == BANK) ? index0_w[8:1] : index1_w[8:1];
                edrv32_ram_cpu2_tage u_predict (
                    .clk_i(clk_i),
                    .wr_en_i(write_valid_w && write_mask_w[table_num] &&
                        (write_index_w[0] == BANK)),
                    .wr_addr_i(write_index_w[8:1]),
                    .wr_data_i(write_rows_w[16*table_num +: 16]),
                    .rd_en_i(f1_valid_i),
                    .rd_addr_i(addr_w),
                    .rd_data_o(physical_rows_w[16*bank +: 16])
                );
            end
            assign prediction_rows_w[0][16*table_num +: 16] = parity_r ?
                physical_rows_w[31:16] : physical_rows_w[15:0];
            assign prediction_rows_w[1][16*table_num +: 16] = parity_r ?
                physical_rows_w[15:0] : physical_rows_w[31:16];
        end
        for (bank = 0; bank < 2; bank = bank + 1) begin : g_base_bank
            localparam BANK = (bank != 0);
            wire [11:0] base0_w;
            wire [11:0] base1_w;
            wire unused_base_w;
            assign unused_base_w = base1_w[0];
            wire [10:0] addr_w;
            wire [1:0] data_w;
            reg parity_r;
            assign base0_w = query_base_w[0];
            assign base1_w = query_base_w[1];
            assign addr_w = (base0_w[0] == BANK) ? base0_w[11:1] : base1_w[11:1];
            always @(posedge clk_i) begin
                parity_r <= base0_w[0];
            end
            edrv32_ram_cpu2_base u_predict (
                .clk_i(clk_i),
                .wr_en_i(write_valid_w && (write_base_index_w[0] == BANK)),
                .wr_addr_i(write_base_index_w[11:1]),
                .wr_data_i(write_base_w),
                .rd_en_i(f1_valid_i),
                .rd_addr_i(addr_w),
                .rd_data_o(data_w)
            );
            // Route bank outputs through flat wires outside this generate scope.
            assign base_physical_w[2*bank +: 2] = data_w;
            assign base_parity_w[bank] = parity_r;
        end
        for (query = 0; query < 2; query = query + 1) begin : g_query
            reg alternate_w;
            assign alternate_flat_w[query] = alternate_w;
            reg prediction_w;
            assign prediction_flat_w[query] = prediction_w;
            reg [2:0] provider_w;
            assign provider_flat_w[3*query +: 3] = provider_w;
            reg f2_base_direction_r;
            assign f2_base_direction_flat_w[query] = f2_base_direction_r;
            reg f2_base_shadow_r;
            assign f2_base_shadow_flat_w[query] = f2_base_shadow_r;
            reg [11:0] f2_base_index_r;
            assign f2_base_index_flat_w[12*query +: 12] = f2_base_index_r;
            reg [39:0] f2_tags_r;
            assign f2_tags_flat_w[40*query +: 40] = f2_tags_r;
            reg [35:0] f2_indices_r;
            assign f2_indices_flat_w[36*query +: 36] = f2_indices_r;
            wire [31:0] pc_w;
            wire [35:0] indices_w;
            wire [39:0] tags_w;
            wire [11:0] base_index_w;
            wire [63:0] rows_w;
            wire [3:0] hits_w;
            wire [3:0] directions_w;
            integer select_num;
            assign pc_w = query_pc_w[query];
            assign base_index_w = pc_w[13:2];
            assign query_base_w[query] = base_index_w;
            assign query_indices_w[query] = indices_w;
            assign rows_w = prediction_rows_w[query];
            wire unused_pc_w;
            assign unused_pc_w = ^{pc_w[31:21], pc_w[1:0]};
            for (table_num = 0; table_num < 4; table_num = table_num + 1) begin : g_key
                reg f2_shadow_direction_r;
                assign f2_shadow_direction_flat_w[4*query+table_num] = f2_shadow_direction_r;
                reg f2_shadow_tag_r;
                assign f2_shadow_tag_flat_w[4*query+table_num] = f2_shadow_tag_r;
                reg f2_shadow_index_r;
                assign f2_shadow_index_flat_w[4*query+table_num] = f2_shadow_index_r;
                wire [8:0] index_w;
                wire [9:0] tag_w;
                wire [8:0] write_index_w;
                wire [8:0] pending_index_w;
                wire [15:0] write_row_w;
                wire [15:0] pending_row_w;
                wire [15:0] row_w;
                wire [9:0] saved_tag_w;
                wire pending_match_w;
                wire write_match_w;
                assign index_w = pc_w[10:2] ^ fold_index_flat_w[9*table_num +: 9];
                assign tag_w = pc_w[20:11] ^ fold_tag_flat_w[10*table_num +: 10] ^
                    {1'b0, fold_shift_flat_w[9*table_num +: 9]};
                assign indices_w[9*table_num +: 9] = index_w;
                assign tags_w[10*table_num +: 10] = tag_w;
                assign write_index_w = write_indices_w[9*table_num +: 9];
                assign pending_index_w = pending_next_indices_w[9*table_num +: 9];
                assign write_row_w = write_rows_w[16*table_num +: 16];
                assign pending_row_w = pending_next_rows_w[16*table_num +: 16];
                assign pending_match_w = pending_next_valid_w && pending_next_mask_w[table_num] &&
                    (pending_index_w == index_w);
                assign write_match_w = write_valid_w && write_mask_w[table_num] &&
                    (write_index_w == index_w);
                // F1 index AND tag compare is registered, not placed after the F2 row mux.
                always @(posedge clk_i) begin
                    f2_shadow_index_r <= pending_match_w || write_match_w;
                    f2_shadow_tag_r <= pending_match_w ?
                        (pending_row_w[15] && (pending_row_w[14:5] == tag_w)) :
                        (write_row_w[15] && (write_row_w[14:5] == tag_w));
                    f2_shadow_direction_r <= pending_match_w ?
                        pending_row_w[4] : write_row_w[4];
                end
                assign row_w = rows_w[16*table_num +: 16];
                assign saved_tag_w = f2_tags_flat_w[40*query+10*table_num +: 10];
                assign hits_w[table_num] = f2_shadow_index_flat_w[4*query+table_num] ?
                    f2_shadow_tag_flat_w[4*query+table_num] :
                    (row_w[15] && (row_w[14:5] == saved_tag_w));
                assign directions_w[table_num] = f2_shadow_index_flat_w[4*query+table_num] ?
                    f2_shadow_direction_flat_w[4*query+table_num] : row_w[4];
                wire unused_row_w;
                assign unused_row_w = ^{row_w[3:0], pending_row_w[3:0], write_row_w[3:0]};
            end
            always @(posedge clk_i) begin
                f2_indices_r <= indices_w;
                f2_tags_r <= tags_w;
                f2_base_index_r <= base_index_w;
                f2_base_shadow_r <=
                    (pending_next_valid_w && (pending_next_base_index_w == base_index_w)) ||
                    (write_valid_w && (write_base_index_w == base_index_w));
                f2_base_direction_r <=
                    (pending_next_valid_w && (pending_next_base_index_w == base_index_w)) ?
                    pending_next_base_w[1] : write_base_w[1];
            end
            always @(*) begin
                provider_w = 3'd0;
                prediction_w = f2_base_shadow_flat_w[query] ? f2_base_direction_flat_w[query] :
                    prediction_base_w[query][1];
                alternate_w = prediction_w;
                for (select_num = 0; select_num < 4; select_num = select_num + 1) begin
                    if (hits_w[select_num]) begin
                        alternate_w = prediction_w;
                        prediction_w = directions_w[select_num];
                        provider_w = select_num[2:0] + 3'd1;
                    end
                end
            end
            assign f2_prediction_o[query] = prediction_flat_w[query];
            assign f2_alternate_o[query] = alternate_flat_w[query];
            assign f2_provider_o[3*query +: 3] = provider_flat_w[3*query +: 3];
            assign f2_indices_o[36*query +: 36] = f2_indices_flat_w[36*query +: 36];
            assign f2_tags_o[40*query +: 40] = f2_tags_flat_w[40*query +: 40];
            assign f2_base_indices_o[12*query +: 12] = f2_base_index_flat_w[12*query +: 12];
        end
    endgenerate
    wire [3:0] base_physical_w;
    wire [1:0] base_parity_w;
    assign prediction_base_w[0] = base_parity_w[0] ? base_physical_w[3:2] : base_physical_w[1:0];
    assign prediction_base_w[1] = base_parity_w[0] ? base_physical_w[1:0] : base_physical_w[3:2];
    reg [11:0] fast_history_r;
    wire [23:0] fast_indices_w;
    wire [3:0] fast_data_w;
    wire [1:0] fast_current_w;
    wire [1:0] fast_new_w;
    wire [31:0] next_pc_w;
    assign next_pc_w = query_pc_w[1];
    assign fast_indices_w = {next_pc_w[13:2] ^ fast_history_r, f1_pc_i[13:2] ^ fast_history_r};
    assign fast_new_w = fast_taken_i ? ((fast_current_w == 2'd3) ? 2'd3 : fast_current_w + 2'd1) :
        ((fast_current_w == 2'd0) ? 2'd0 : fast_current_w - 2'd1);
    edrv32_ram_cpu2_fast u_fast (
        .clk_i(clk_i),
        .wr_en_i(fast_update_i),
        .wr_addr_i(fast_index_i),
        .wr_data_i(fast_new_w),
        .rd_addr_i(fast_indices_w),
        .rd_data_o(fast_data_w),
        .update_data_o(fast_current_w)
    );
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            fast_history_r <= 12'd0;
        else if (fast_update_i)
            fast_history_r <= {fast_history_r[10:0], fast_taken_i};
    end
    assign f1_fast_o = {fast_data_w[3], fast_data_w[1]};
    wire unused_tail_w;
    assign unused_tail_w = ^{fast_data_w[2], fast_data_w[0], base_parity_w[1],
        next_pc_w[31:14], next_pc_w[1:0], prediction_base_w[0][0], prediction_base_w[1][0]};
endmodule
