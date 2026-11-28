// File: edrv32_cpu2_predictor.v
// Spec: cpu-v2-spec 3.3, 5.4, 5.5 and interface-freeze RAS recovery supplement.
// Description: Fixed gshare4096, grouped/word-indexed BTB and speculative full-snapshot RAS.
// Private fast outputs are the F1 context; restore applies pop before push.
// Clock domain: clk_sys.
module edrv32_cpu2_predictor #(
    parameter ISSUE_WIDTH = 2,
    parameter [31:0] FPU_FORMAT = "NONE"
) (
    clk_i,
    rst_n_i,
    predict_req_valid_i,
    predict_req_pc_i,
    query_skip0_i,
    clear0_valid_i,
    clear0_pc_i,
    clear1_valid_i,
    clear1_pc_i,
    fast0_hit_o,
    fast0_taken_o,
    fast0_target_o,
    fast0_type_o,
    fast0_fast_index_o,
    fast0_ras_data_o,
    fast0_ras_ptr_o,
    fast0_ras_count_o,
    fast0_ras_top_o,
    fast1_hit_o,
    fast1_taken_o,
    fast1_target_o,
    fast1_type_o,
    fast1_fast_index_o,
    fast1_ras_data_o,
    fast1_ras_ptr_o,
    fast1_ras_count_o,
    ras_restore_valid_i,
    ras_restore_data_i,
    ras_restore_ptr_i,
    ras_restore_count_i,
    ras_restore_pop_i,
    ras_restore_push_i,
    ras_restore_link_i,
    ex_predict_train_valid_i,
    ex_predict_train_tag_i,
    ex_predict_train_pc_i,
    ex_predict_train_taken_i,
    ex_predict_train_target_i,
    ex_predict_train_type_i,
    ex_predict_train_fast_index_i,
    mem_predict_train_valid_i,
    mem_predict_train_tag_i,
    mem_predict_train_pc_i,
    mem_predict_train_taken_i,
    mem_predict_train_target_i,
    mem_predict_train_type_i,
    mem_predict_train_fast_index_i,
    age_head_i,
    cancel_valid_i,
    cancel_tag_i
);
    localparam TAG_BITS = (ISSUE_WIDTH == 2 || FPU_FORMAT == "FD") ? 4 : 3;
    localparam RAS_DEPTH = (ISSUE_WIDTH == 2) ? 8 : 4;
    localparam RAS_BITS = 32*RAS_DEPTH;
    localparam RAS_PTR_BITS = (ISSUE_WIDTH == 2) ? 3 : 2;
    localparam RAS_COUNT_BITS = RAS_PTR_BITS+1;
    localparam [RAS_COUNT_BITS-1:0] RAS_LIMIT = {1'b1, {RAS_PTR_BITS{1'b0}}};

    // Clock and control reset; counter RAMs retain their initialized contents on reset.
    input wire clk_i;
    input wire rst_n_i;

    // Private F1: valid is an accepted I$ request, fast snapshots are combinational.
    // fast1_taken is raw direction; only the oldest taken word advances speculative RAS.
    input wire predict_req_valid_i;
    input wire [32-1:0] predict_req_pc_i;

    // Skip the lower word of an aligned single-issue group whose first PC is the upper word.
    input wire query_skip0_i;
    // Private F2 non-control BTB invalidation, after registered prefix selection.
    input wire clear0_valid_i;
    input wire [31:0] clear0_pc_i;
    input wire clear1_valid_i;
    input wire [31:0] clear1_pc_i;
    output wire fast0_hit_o;
    output wire fast0_taken_o;
    output wire [32-1:0] fast0_target_o;
    output wire [3-1:0] fast0_type_o;
    output wire [12-1:0] fast0_fast_index_o;
    output wire [RAS_BITS-1:0] fast0_ras_data_o;
    output wire [RAS_PTR_BITS-1:0] fast0_ras_ptr_o;
    output wire [RAS_COUNT_BITS-1:0] fast0_ras_count_o;
    output wire [31:0] fast0_ras_top_o;
    output wire fast1_hit_o;
    output wire fast1_taken_o;
    output wire [32-1:0] fast1_target_o;
    output wire [3-1:0] fast1_type_o;
    output wire [12-1:0] fast1_fast_index_o;
    output wire [RAS_BITS-1:0] fast1_ras_data_o;
    output wire [RAS_PTR_BITS-1:0] fast1_ras_ptr_o;
    output wire [RAS_COUNT_BITS-1:0] fast1_ras_count_o;

    // Private recovery replaces F1 acceptance: restore all words, then pop before push.
    input wire ras_restore_valid_i;
    input wire [RAS_BITS-1:0] ras_restore_data_i;
    input wire [RAS_PTR_BITS-1:0] ras_restore_ptr_i;
    input wire [RAS_COUNT_BITS-1:0] ras_restore_count_i;
    input wire ras_restore_pop_i;
    input wire ras_restore_push_i;
    input wire [32-1:0] ras_restore_link_i;

    // Clean EX/MEM resolution pulses, in increasing age within the same cycle.
    input wire ex_predict_train_valid_i;
    input wire [TAG_BITS-1:0] ex_predict_train_tag_i;
    input wire [32-1:0] ex_predict_train_pc_i;
    input wire ex_predict_train_taken_i;
    input wire [32-1:0] ex_predict_train_target_i;
    input wire [3-1:0] ex_predict_train_type_i;
    input wire [12-1:0] ex_predict_train_fast_index_i;
    input wire mem_predict_train_valid_i;
    input wire [TAG_BITS-1:0] mem_predict_train_tag_i;
    input wire [32-1:0] mem_predict_train_pc_i;
    input wire mem_predict_train_taken_i;
    input wire [32-1:0] mem_predict_train_target_i;
    input wire [3-1:0] mem_predict_train_type_i;
    input wire [12-1:0] mem_predict_train_fast_index_i;
    input wire [TAG_BITS-1:0] age_head_i;
    input wire cancel_valid_i;
    input wire [TAG_BITS-1:0] cancel_tag_i;

    reg [11:0] history_r;
    wire [31:0] query_pc_w [0:1];
    wire [11:0] query_index_w [0:1];
    wire [1:0] query_counter_w [0:1];
    wire [58:0] query_btb_w [0:1];
    wire [1:0] query_hit_w;
    wire [23:0] query_tag_w [0:1];
    wire [3:0] fast_data_w;
    wire [3:0] train_data_w;
    wire [1:0] unused_fast_current_w;
    wire [1:0] unused_train_current_w;
    wire ex_update_w;
    wire ex_table_update_w;
    wire mem_update_w;
    wire [TAG_BITS-1:0] ex_age_w;
    wire [TAG_BITS-1:0] mem_age_w;
    wire [TAG_BITS-1:0] cancel_age_w;
    reg pending_valid_r;
    reg fast_pending_valid_r;
    wire fast_mem_update_w;
    wire fast_ex_update_w;
    wire fast_ex_table_update_w;
    wire fast_write_valid_w;
    reg [31:0] pending_pc_r;
    reg [31:0] pending_target_r;
    reg [2:0] pending_type_r;
    reg [11:0] fast_pending_index_r;
    reg [1:0] fast_pending_counter_r;
    wire write_valid_w;
    wire [31:0] write_pc_w;
    wire [31:0] write_target_w;
    wire [2:0] write_type_w;
    wire [11:0] write_index_w;
    wire [1:0] write_counter_w;
    wire [1:0] ex_counter_w;
    wire [1:0] mem_counter_w;
    wire [1:0] ex_old_counter_w;
    wire [1:0] mem_old_counter_w;
    genvar word;
    wire [117:0] bank_data_w;
    wire [1:0] bank_valid_w;
    wire [RAS_BITS-1:0] ras_data_r;
    reg [RAS_PTR_BITS-1:0] ras_ptr_r;
    reg [RAS_COUNT_BITS-1:0] ras_count_r;
    wire [RAS_BITS-1:0] ras_data0_w;
    wire [RAS_PTR_BITS-1:0] ras_ptr0_w;
    wire [RAS_COUNT_BITS-1:0] ras_count0_w;
    wire [RAS_BITS-1:0] ras_data1_w;
    wire [RAS_PTR_BITS-1:0] ras_ptr1_w;
    wire [RAS_COUNT_BITS-1:0] ras_count1_w;
    wire [RAS_BITS-1:0] ras_data2_w;
    wire [RAS_PTR_BITS-1:0] ras_ptr2_w;
    wire [RAS_COUNT_BITS-1:0] ras_count2_w;
    wire taken0_w;
    wire taken1_w;
    wire [63:0] target_w;
    wire restore_pop_w;
    wire [RAS_PTR_BITS-1:0] restore_write_ptr_w;
    genvar ras_entry;
    wire [RAS_BITS-1:0] ras_data_w_out;
    wire unused_w;





    assign ex_age_w = ex_predict_train_tag_i - age_head_i;
    assign mem_age_w = mem_predict_train_tag_i - age_head_i;
    assign cancel_age_w = cancel_tag_i - age_head_i;
    assign ex_update_w = ex_predict_train_valid_i &&
        !(cancel_valid_i && ex_age_w >= cancel_age_w);
    // spec 5.4: table contention drops EX data, but never its conditional GHR bit.
    assign ex_table_update_w = ex_update_w && !(pending_valid_r && mem_update_w);
    assign mem_update_w = (ISSUE_WIDTH == 2) && mem_predict_train_valid_i &&
        !(cancel_valid_i && mem_age_w >= cancel_age_w);
    function [1:0] step_counter;
        input [1:0] value_i;
        input taken_i;
        begin
            step_counter = taken_i ? (value_i == 2'd3 ? value_i : value_i + 2'd1) :
                (value_i == 2'd0 ? value_i : value_i - 2'd1);
        end
    endfunction
    // BTB and fast each own one pending entry; non-conditional BTB writes do not occupy fast.
    assign fast_mem_update_w = mem_update_w && mem_predict_train_type_i == 3'd0;
    assign fast_ex_update_w = ex_update_w && ex_predict_train_type_i == 3'd0;
    assign fast_ex_table_update_w = fast_ex_update_w && !(fast_pending_valid_r &&
        fast_mem_update_w);
    assign fast_write_valid_w = fast_pending_valid_r || fast_mem_update_w || fast_ex_table_update_w;
    assign mem_old_counter_w = fast_pending_valid_r &&
        fast_pending_index_r == mem_predict_train_fast_index_i ? fast_pending_counter_r :
            train_data_w[1:0];
    assign ex_old_counter_w = fast_mem_update_w &&
        mem_predict_train_fast_index_i == ex_predict_train_fast_index_i ? mem_counter_w :
        fast_pending_valid_r &&
        fast_pending_index_r == ex_predict_train_fast_index_i ? fast_pending_counter_r :
            train_data_w[3:2];
    assign mem_counter_w = step_counter(mem_old_counter_w, mem_predict_train_taken_i);
    assign ex_counter_w = step_counter(ex_old_counter_w, ex_predict_train_taken_i);
    assign write_valid_w = pending_valid_r || mem_update_w || ex_table_update_w;
    assign write_pc_w = pending_valid_r ? pending_pc_r :
        mem_update_w ? mem_predict_train_pc_i : ex_predict_train_pc_i;
    assign write_target_w = pending_valid_r ? pending_target_r :
        mem_update_w ? mem_predict_train_target_i : ex_predict_train_target_i;
    assign write_type_w = pending_valid_r ? pending_type_r :
        mem_update_w ? mem_predict_train_type_i : ex_predict_train_type_i;
    assign write_index_w = fast_pending_valid_r ? fast_pending_index_r :
        fast_mem_update_w ? mem_predict_train_fast_index_i : ex_predict_train_fast_index_i;
    assign write_counter_w = fast_pending_valid_r ? fast_pending_counter_r :
        fast_mem_update_w ? mem_counter_w : ex_counter_w;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            history_r <= 12'd0;
            pending_valid_r <= 1'b0;
            fast_pending_valid_r <= 1'b0;
        end else begin
            pending_valid_r <= pending_valid_r ? (mem_update_w || ex_table_update_w) :
                (mem_update_w && ex_table_update_w);
            fast_pending_valid_r <= fast_pending_valid_r ?
                (fast_mem_update_w || fast_ex_table_update_w) :
                (fast_mem_update_w && fast_ex_table_update_w);
            if (mem_update_w && mem_predict_train_type_i == 3'd0) begin
                if (ex_update_w && ex_predict_train_type_i == 3'd0)
                    history_r <= {history_r[9:0], mem_predict_train_taken_i,
                        ex_predict_train_taken_i};
                else
                    history_r <= {history_r[10:0], mem_predict_train_taken_i};
            end else if (ex_update_w && ex_predict_train_type_i == 3'd0)
                history_r <= {history_r[10:0], ex_predict_train_taken_i};
        end
    end
    always @(posedge clk_i) begin
        pending_pc_r <= ex_table_update_w ? ex_predict_train_pc_i : mem_predict_train_pc_i;
        pending_target_r <= ex_table_update_w ? ex_predict_train_target_i :
            mem_predict_train_target_i;
        pending_type_r <= ex_table_update_w ? ex_predict_train_type_i : mem_predict_train_type_i;
        fast_pending_index_r <= fast_ex_table_update_w ? ex_predict_train_fast_index_i :
            mem_predict_train_fast_index_i;
        fast_pending_counter_r <= fast_ex_table_update_w ? ex_counter_w : mem_counter_w;
    end
    // Two F1 reads plus two independent current-counter training reads.
    edrv32_ram_cpu2_fast u_fast (
        .clk_i(clk_i),
        .wr_en_i(fast_write_valid_w),
        .wr_addr_i(write_index_w),
        .wr_data_i(write_counter_w),
        .rd_addr_i({query_index_w[1], query_index_w[0]}),
        .rd_data_o(fast_data_w),
        .update_data_o(unused_fast_current_w)
    );
    edrv32_ram_cpu2_fast u_fast_training (
        .clk_i(clk_i),
        .wr_en_i(fast_write_valid_w),
        .wr_addr_i(write_index_w),
        .wr_data_i(write_counter_w),
        .rd_addr_i({ex_predict_train_fast_index_i, mem_predict_train_fast_index_i}),
        .rd_data_o(train_data_w),
        .update_data_o(unused_train_current_w)
    );
    assign query_pc_w[0] = predict_req_pc_i;
    assign query_pc_w[1] = predict_req_pc_i + 32'd4;
    generate
        for (word = 0; word < 2; word = word + 1) begin : g_word
            wire [31:0] pc_w;
            wire [58:0] data_w;
            wire [5:0] read_addr_w;
            wire [5:0] write_addr_w;
            wire [23:0] tag_w;
            wire [23:0] write_tag_w;
            wire bank_write_w;
            wire valid_w;
            reg [63:0] valid_r;
            wire [5:0] clear0_addr_w;
            wire [5:0] clear1_addr_w;
            assign clear0_addr_w = clear0_pc_i[8:3];
            assign clear1_addr_w = clear1_pc_i[8:3];
            wire [31:0] selected_pc_w;
            wire [58:0] selected_data_w;
            wire selected_valid_w;
            assign pc_w = query_pc_w[word];
            assign query_index_w[word] = pc_w[13:2] ^ history_r;
            assign query_counter_w[word] =
                fast_ex_table_update_w &&
                    ex_predict_train_fast_index_i == query_index_w[word] ? ex_counter_w :
                fast_mem_update_w &&
                    mem_predict_train_fast_index_i == query_index_w[word] ? mem_counter_w :
                fast_pending_valid_r &&
                    fast_pending_index_r == query_index_w[word] ? fast_pending_counter_r :
                fast_data_w[2*word +: 2];
            if (ISSUE_WIDTH == 2) begin : g_banked
                // The two logical words read opposite physical parity banks.
                assign selected_pc_w = pc_w[2] == (word != 0) ? pc_w : query_pc_w[1-word];
                assign read_addr_w = selected_pc_w[8:3];
                assign write_addr_w = write_pc_w[8:3];
                assign write_tag_w = {1'b0, write_pc_w[31:9]};
                assign bank_write_w = write_valid_w && write_pc_w[2] == (word != 0);
                assign tag_w = {1'b0, pc_w[31:9]};
            end else begin : g_replicated
                // CPU5.5: 64 aligned groups; freed tag bit stores the control word position.
                assign selected_pc_w = pc_w;
                assign read_addr_w = pc_w[8:3];
                assign write_addr_w = write_pc_w[8:3];
                assign write_tag_w = {write_pc_w[31:9], write_pc_w[2]};
                assign bank_write_w = write_valid_w;
                assign tag_w = {pc_w[31:9], pc_w[2]};
            end
            edrv32_ram_cpu2_btb u_btb (
                .clk_i(clk_i),
                .wr_en_i(bank_write_w),
                .wr_addr_i(write_addr_w),
                .wr_data_i({write_tag_w, write_type_w, write_target_w}),
                .rd_addr_i(read_addr_w),
                .rd_data_o(data_w)
            );
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    valid_r <= 64'd0;
                else begin
                    if (bank_write_w)
                        valid_r[write_addr_w] <= 1'b1;
                    if (clear0_valid_i && (ISSUE_WIDTH == 1 || clear0_pc_i[2] == (word != 0)))
                        valid_r[clear0_addr_w] <= 1'b0;
                    if (clear1_valid_i && (ISSUE_WIDTH == 1 || clear1_pc_i[2] == (word != 0)))
                        valid_r[clear1_addr_w] <= 1'b0;
                end
            end
            assign bank_data_w[59*word +: 59] = data_w;
            assign bank_valid_w[word] = valid_r[read_addr_w];
            if (ISSUE_WIDTH == 2) begin : g_route
                assign selected_data_w = pc_w[2] ? bank_data_w[59 +: 59] : bank_data_w[0 +: 59];
                assign selected_valid_w = pc_w[2] ? bank_valid_w[1] : bank_valid_w[0];
            end else begin : g_direct
                assign selected_data_w = data_w;
                assign selected_valid_w = valid_r[read_addr_w];
            end
            wire [23:0] pending_tag_w;
            wire pending_hit_w;
            assign pending_tag_w = (ISSUE_WIDTH == 2) ? {1'b0, pending_pc_r[31:9]} :
                {pending_pc_r[31:9], pending_pc_r[2]};
            // F1 reads the state preceding this edge; only registered pending writes bypass.
            assign pending_hit_w = pending_valid_r && ((ISSUE_WIDTH == 2) ?
                pending_pc_r[8:2] == pc_w[8:2] : pending_pc_r[8:3] == pc_w[8:3]);
            assign query_btb_w[word] = pending_hit_w ?
                {pending_tag_w, pending_type_r, pending_target_r} : selected_data_w;
            assign valid_w = pending_hit_w || selected_valid_w;
            assign query_tag_w[word] = tag_w;
            wire [58:0] selected_btb_w;
            assign selected_btb_w = query_btb_w[word];
            assign query_hit_w[word] = valid_w && selected_btb_w[58:35] == tag_w;
            wire unused_word_w;
            assign unused_word_w = ^{selected_pc_w, pc_w[1:0],
                selected_btb_w[34:0]};
        end
    endgenerate
    wire [RAS_BITS-1:0] restore_data_w;
    wire [RAS_PTR_BITS-1:0] restore_ptr_w = restore_write_ptr_w +
        {{(RAS_PTR_BITS-1){1'b0}}, ras_restore_push_i};
    wire [RAS_COUNT_BITS-1:0] restore_count_w = ras_restore_push_i ?
        (restore_pop_w || ras_restore_count_i == RAS_LIMIT ? ras_restore_count_i :
        ras_restore_count_i + 1'b1) :
        ras_restore_count_i - {{(RAS_COUNT_BITS-1){1'b0}}, restore_pop_w};
    assign ras_data0_w = ras_restore_valid_i ? restore_data_w : ras_data_r;
    assign ras_ptr0_w = ras_restore_valid_i ? restore_ptr_w : ras_ptr_r;
    assign ras_count0_w = ras_restore_valid_i ? restore_count_w : ras_count_r;
    generate
        begin : g_ras_step0
            wire [58:0] btb_w;
            wire [1:0] counter_w;
            wire [RAS_PTR_BITS-1:0] top_ptr_w;
            wire pop_w;
            wire push_w;
            wire active_w;
            wire [31:0] top_w;
            wire [RAS_PTR_BITS-1:0] pointer_w;
            wire [RAS_PTR_BITS-1:0] write_ptr_w;
            wire [RAS_COUNT_BITS-1:0] count_w;
            wire unused_ras_w;
            assign unused_ras_w = ^{btb_w[58:35], counter_w[0]};
            assign btb_w = query_btb_w[0];
            assign counter_w = query_counter_w[0];
            assign pointer_w = ras_ptr0_w;
            assign count_w = ras_count0_w;
            assign top_ptr_w = pointer_w - {{(RAS_PTR_BITS-1){1'b0}}, 1'b1};
            assign active_w = !query_skip0_i;
            assign taken0_w = active_w && query_hit_w[0] &&
                (btb_w[34:32] != 3'd0 || counter_w[1]);
            assign pop_w = taken0_w && count_w != 0 &&
                (btb_w[34:32] == 3'd4 || btb_w[34:32] == 3'd5);
            assign push_w = taken0_w &&
                (btb_w[34:32] == 3'd3 || btb_w[34:32] == 3'd5);
            assign write_ptr_w = pointer_w - {{(RAS_PTR_BITS-1){1'b0}}, pop_w};
            assign ras_ptr1_w = write_ptr_w + {{(RAS_PTR_BITS-1){1'b0}}, push_w};
            assign ras_count1_w = push_w ?
                (pop_w || count_w == RAS_LIMIT ? count_w : count_w + 1'b1) :
                (pop_w ? count_w - 1'b1 : count_w);
            wire [31:0] top_words_w [0:RAS_DEPTH-1];
            genvar entry;
            for (entry = 0; entry < RAS_DEPTH; entry = entry + 1) begin : g_entry
                wire [RAS_BITS-1:0] prior_data_w;
                wire unused_data_w;
                assign unused_data_w = ^prior_data_w;
                assign prior_data_w = ras_data0_w;
                assign top_words_w[entry] = prior_data_w[32*entry +: 32];
                assign ras_data1_w[32*entry +: 32] = push_w && write_ptr_w == entry ?
                    query_pc_w[0] + 32'd4 : top_words_w[entry];
            end
            assign top_w = top_words_w[top_ptr_w];
            assign fast0_ras_top_o = top_w;
            assign target_w[0 +: 32] =
                (btb_w[34:32] == 3'd4 || btb_w[34:32] == 3'd5) && count_w != 0 ?
                top_w : btb_w[31:0];
        end
        begin : g_ras_step1
            wire [58:0] btb_w;
            wire [1:0] counter_w;
            wire [RAS_PTR_BITS-1:0] top_ptr_w;
            wire pop_w;
            wire push_w;
            wire active_w;
            wire [31:0] top_w;
            wire [RAS_PTR_BITS-1:0] pointer_w;
            wire [RAS_PTR_BITS-1:0] write_ptr_w;
            wire [RAS_COUNT_BITS-1:0] count_w;
            wire unused_ras_w;
            assign unused_ras_w = ^{btb_w[58:35], counter_w[0]};
            assign btb_w = query_btb_w[1];
            assign counter_w = query_counter_w[1];
            assign pointer_w = ras_ptr1_w;
            assign count_w = ras_count1_w;
            assign top_ptr_w = pointer_w - {{(RAS_PTR_BITS-1){1'b0}}, 1'b1};
            assign active_w = !taken0_w;
            assign taken1_w = active_w && query_hit_w[1] &&
                (btb_w[34:32] != 3'd0 || counter_w[1]);
            assign pop_w = taken1_w && count_w != 0 &&
                (btb_w[34:32] == 3'd4 || btb_w[34:32] == 3'd5);
            assign push_w = taken1_w &&
                (btb_w[34:32] == 3'd3 || btb_w[34:32] == 3'd5);
            assign write_ptr_w = pointer_w - {{(RAS_PTR_BITS-1){1'b0}}, pop_w};
            assign ras_ptr2_w = write_ptr_w + {{(RAS_PTR_BITS-1){1'b0}}, push_w};
            assign ras_count2_w = push_w ?
                (pop_w || count_w == RAS_LIMIT ? count_w : count_w + 1'b1) :
                (pop_w ? count_w - 1'b1 : count_w);
            wire [31:0] top_words_w [0:RAS_DEPTH-1];
            genvar entry;
            for (entry = 0; entry < RAS_DEPTH; entry = entry + 1) begin : g_entry
                wire [RAS_BITS-1:0] prior_data_w;
                wire unused_data_w;
                assign unused_data_w = ^prior_data_w;
                assign prior_data_w = ras_data1_w;
                assign top_words_w[entry] = prior_data_w[32*entry +: 32];
                assign ras_data2_w[32*entry +: 32] = push_w && write_ptr_w == entry ?
                    query_pc_w[1] + 32'd4 : top_words_w[entry];
            end
            assign top_w = top_words_w[top_ptr_w];
            assign target_w[32 +: 32] =
                (btb_w[34:32] == 3'd4 || btb_w[34:32] == 3'd5) && count_w != 0 ?
                top_w : btb_w[31:0];
        end
    endgenerate
    assign restore_pop_w = ras_restore_pop_i && ras_restore_count_i != 0;
    assign restore_write_ptr_w = ras_restore_ptr_i - {{(RAS_PTR_BITS-1){1'b0}}, restore_pop_w};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            ras_ptr_r <= {RAS_PTR_BITS{1'b0}};
            ras_count_r <= {RAS_COUNT_BITS{1'b0}};
        end else if (ras_restore_valid_i && !predict_req_valid_i) begin
            ras_ptr_r <= restore_ptr_w;
            ras_count_r <= restore_count_w;
        end else if (predict_req_valid_i) begin
            ras_ptr_r <= ras_ptr2_w;
            ras_count_r <= ras_count2_w;
        end
    end
    generate
        for (ras_entry = 0; ras_entry < RAS_DEPTH; ras_entry = ras_entry + 1) begin : g_ras_data
            wire [RAS_BITS-1:0] advanced_w;
            wire unused_data_w;
            assign unused_data_w = ^advanced_w;
            assign advanced_w = ras_data2_w;
            genvar half;
            for (half = 0; half < 2; half = half + 1) begin : g_half
                reg [15:0] data_r;
                assign restore_data_w[32*ras_entry+16*half +: 16] =
                    ras_restore_push_i && restore_write_ptr_w == ras_entry ?
                    ras_restore_link_i[16*half +: 16] :
                    ras_restore_data_i[32*ras_entry+16*half +: 16];
                always @(posedge clk_i) begin
                    if (ras_restore_valid_i || predict_req_valid_i)
                        data_r <= predict_req_valid_i ? advanced_w[32*ras_entry+16*half +: 16] :
                            restore_data_w[32*ras_entry+16*half +: 16];
                end
                assign ras_data_w_out[32*ras_entry+16*half +: 16] = data_r;
            end
        end
    endgenerate
    assign ras_data_r = ras_data_w_out;
    assign fast0_hit_o = query_hit_w[0];
    assign fast0_taken_o = taken0_w;
    assign fast0_target_o = target_w[0 +: 32];
    assign fast0_type_o = query_btb_w[0][34:32];
    assign fast0_fast_index_o = query_index_w[0];
    assign fast0_ras_data_o = ras_data0_w;
    assign fast0_ras_ptr_o = ras_ptr0_w;
    assign fast0_ras_count_o = ras_count0_w;
    assign fast1_hit_o = query_hit_w[1];
    assign fast1_taken_o = query_hit_w[1] &&
        (query_btb_w[1][34:32] != 3'd0 || query_counter_w[1][1]);
    assign fast1_target_o = target_w[32 +: 32];
    assign fast1_type_o = query_btb_w[1][34:32];
    assign fast1_fast_index_o = query_index_w[1];
    assign fast1_ras_data_o = ras_data1_w;
    assign fast1_ras_ptr_o = ras_ptr1_w;
    assign fast1_ras_count_o = ras_count1_w;
    assign unused_w = ^{unused_fast_current_w, unused_train_current_w,
        fast_data_w[2], fast_data_w[0], query_tag_w[0], query_tag_w[1], write_pc_w[1:0],
            bank_data_w, bank_valid_w,
        clear0_pc_i, clear1_pc_i};
endmodule
