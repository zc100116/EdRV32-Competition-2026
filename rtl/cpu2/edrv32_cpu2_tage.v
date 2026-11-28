// File: edrv32_cpu2_tage.v
// Spec: cpu-v2-spec 3.3, 5.4; interface-freeze implementation supplement.
// Description: Four fixed tagged tables with tag-associated D pre-read records.
// The measured F1 folds and F2 parallel shadow comparisons retain their boundary.
// Clock domain: clk_sys.
module edrv32_cpu2_tage #(
    parameter [31:0] FPU_FORMAT = "NONE"
) (
    clk_i,
    rst_n_i,
    f1_valid_i,
    f1_pc_i,
    f2_valid_o,
    f2_prediction_o,
    f2_alternate_o,
    f2_provider_o,
    f2_indices_o,
    f2_tags_o,
    f2_base_indices_o,
    predict_read0_valid_i,
    predict_read0_tag_i,
    predict_read0_index0_i,
    predict_read0_index1_i,
    predict_read0_index2_i,
    predict_read0_index3_i,
    predict_read0_tag0_i,
    predict_read0_tag1_i,
    predict_read0_tag2_i,
    predict_read0_tag3_i,
    predict_read0_base_index_i,
    predict_read1_valid_i,
    predict_read1_tag_i,
    predict_read1_index0_i,
    predict_read1_index1_i,
    predict_read1_index2_i,
    predict_read1_index3_i,
    predict_read1_tag0_i,
    predict_read1_tag1_i,
    predict_read1_tag2_i,
    predict_read1_tag3_i,
    predict_read1_base_index_i,
    ex_predict_train_valid_i,
    ex_predict_train_tag_i,
    ex_predict_train_taken_i,
    ex_predict_train_token_i,
    ex_predict_train_provider_i,
    ex_predict_train_prediction_i,
    ex_predict_train_alternate_i,
    ex_predict_train_index0_i,
    ex_predict_train_index1_i,
    ex_predict_train_index2_i,
    ex_predict_train_index3_i,
    ex_predict_train_tag0_i,
    ex_predict_train_tag1_i,
    ex_predict_train_tag2_i,
    ex_predict_train_tag3_i,
    ex_predict_train_base_index_i,
    mem_predict_train_valid_i,
    mem_predict_train_tag_i,
    mem_predict_train_taken_i,
    mem_predict_train_token_i,
    mem_predict_train_provider_i,
    mem_predict_train_prediction_i,
    mem_predict_train_alternate_i,
    mem_predict_train_index0_i,
    mem_predict_train_index1_i,
    mem_predict_train_index2_i,
    mem_predict_train_index3_i,
    mem_predict_train_tag0_i,
    mem_predict_train_tag1_i,
    mem_predict_train_tag2_i,
    mem_predict_train_tag3_i,
    mem_predict_train_base_index_i,
    age_head_i,
    cancel_valid_i,
    cancel_tag_i
);
    localparam TAG_BITS = (FPU_FORMAT == "FD") ? 4 : (FPU_FORMAT == "F") ? 3 : 2;
    input wire clk_i;
    input wire rst_n_i;
    // Private frontend query interface; both words share resolved history.
    input wire f1_valid_i;
    input wire [31:0] f1_pc_i;
    output wire f2_valid_o;
    output wire [1:0] f2_prediction_o;
    output wire [1:0] f2_alternate_o;
    output wire [5:0] f2_provider_o;
    output wire [71:0] f2_indices_o;
    output wire [79:0] f2_tags_o;
    output wire [23:0] f2_base_indices_o;

    // Actual token-bearing conditional issue; the single D read serves the selected program slot.
    input wire predict_read0_valid_i;
    input wire [TAG_BITS-1:0] predict_read0_tag_i;
    input wire [9-1:0] predict_read0_index0_i;
    input wire [9-1:0] predict_read0_index1_i;
    input wire [9-1:0] predict_read0_index2_i;
    input wire [9-1:0] predict_read0_index3_i;
    input wire [10-1:0] predict_read0_tag0_i;
    input wire [10-1:0] predict_read0_tag1_i;
    input wire [10-1:0] predict_read0_tag2_i;
    input wire [10-1:0] predict_read0_tag3_i;
    input wire [12-1:0] predict_read0_base_index_i;
    input wire predict_read1_valid_i;
    input wire [TAG_BITS-1:0] predict_read1_tag_i;
    input wire [9-1:0] predict_read1_index0_i;
    input wire [9-1:0] predict_read1_index1_i;
    input wire [9-1:0] predict_read1_index2_i;
    input wire [9-1:0] predict_read1_index3_i;
    input wire [10-1:0] predict_read1_tag0_i;
    input wire [10-1:0] predict_read1_tag1_i;
    input wire [10-1:0] predict_read1_tag2_i;
    input wire [10-1:0] predict_read1_tag3_i;
    input wire [12-1:0] predict_read1_base_index_i;

    // Clean conditional resolution pulses; full contention drops EX data, not its history bit.
    input wire ex_predict_train_valid_i;
    input wire [TAG_BITS-1:0] ex_predict_train_tag_i;
    input wire ex_predict_train_taken_i;
    input wire ex_predict_train_token_i;
    input wire [3-1:0] ex_predict_train_provider_i;
    input wire ex_predict_train_prediction_i;
    input wire ex_predict_train_alternate_i;
    input wire [9-1:0] ex_predict_train_index0_i;
    input wire [9-1:0] ex_predict_train_index1_i;
    input wire [9-1:0] ex_predict_train_index2_i;
    input wire [9-1:0] ex_predict_train_index3_i;
    input wire [10-1:0] ex_predict_train_tag0_i;
    input wire [10-1:0] ex_predict_train_tag1_i;
    input wire [10-1:0] ex_predict_train_tag2_i;
    input wire [10-1:0] ex_predict_train_tag3_i;
    input wire [12-1:0] ex_predict_train_base_index_i;
    input wire mem_predict_train_valid_i;
    input wire [TAG_BITS-1:0] mem_predict_train_tag_i;
    input wire mem_predict_train_taken_i;
    input wire mem_predict_train_token_i;
    input wire [3-1:0] mem_predict_train_provider_i;
    input wire mem_predict_train_prediction_i;
    input wire mem_predict_train_alternate_i;
    input wire [9-1:0] mem_predict_train_index0_i;
    input wire [9-1:0] mem_predict_train_index1_i;
    input wire [9-1:0] mem_predict_train_index2_i;
    input wire [9-1:0] mem_predict_train_index3_i;
    input wire [10-1:0] mem_predict_train_tag0_i;
    input wire [10-1:0] mem_predict_train_tag1_i;
    input wire [10-1:0] mem_predict_train_tag2_i;
    input wire [10-1:0] mem_predict_train_tag3_i;
    input wire [12-1:0] mem_predict_train_base_index_i;
    input wire [TAG_BITS-1:0] age_head_i;
    input wire cancel_valid_i;
    input wire [TAG_BITS-1:0] cancel_tag_i;

    wire [31:0] query_pc_w [0:1];
    wire [35:0] query_indices_w [0:1];
    wire [11:0] query_base_w [0:1];
    reg [95:0] history_r;
    reg [95:0] history_next_w;
    wire [35:0] fold_index_flat_w;
    wire [39:0] fold_tag_flat_w;
    wire [35:0] fold_shift_flat_w;
    wire d_valid_i;
    wire [TAG_BITS-1:0] d_tag_w;
    wire [35:0] d_indices_i;
    wire [11:0] d_base_index_i;
    wire [35:0] ex_indices_r;
    wire [39:0] ex_tags_r;
    wire [11:0] ex_base_index_r;
    wire [2:0] ex_provider_r;
    wire [0:0] ex_prediction_r;
    wire [0:0] ex_alternate_r;
    wire ex_taken_i;
    wire ex_update_w;
    wire ex_table_update_w;
    wire [TAG_BITS-1:0] ex_age_w;
    wire [35:0] mem_indices_r;
    wire [39:0] mem_tags_r;
    wire [11:0] mem_base_index_r;
    wire [2:0] mem_provider_r;
    wire [0:0] mem_prediction_r;
    wire [0:0] mem_alternate_r;
    wire mem_taken_i;
    wire mem_update_w;
    wire [TAG_BITS-1:0] mem_age_w;
    wire [TAG_BITS-1:0] cancel_age_w;
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
    wire [63:0] d_rows_w;
    wire [1:0] d_base_w;
    wire [63:0] ex_current_rows_w;
    wire [63:0] mem_current_rows_w;
    wire [1:0] ex_current_base_w;
    wire [1:0] mem_current_base_w;
    wire [255:0] record_rows_w;
    wire [7:0] record_base_w;
    wire [3:0] record_valid_w;
    wire [4*TAG_BITS-1:0] record_tags_w;
    wire [3:0] record_free_w;
    wire [3:0] record_allocate_w;
    reg [1:0] read_slot_r;
    reg read_valid_r;
    wire [1:0] read_slot_w;
    reg [1:0] read_shadow_base_r;
    reg read_shadow_base_valid_r;
    genvar shadow;
    wire [63:0] read_shadow_rows_w;
    wire [3:0] read_shadow_mask_w;
    wire read_pending_base_w;
    wire read_mem_base_w;
    wire read_ex_base_w;
    genvar record;
    reg [63:0] ex_record_rows_w;
    reg [63:0] mem_record_rows_w;
    reg [1:0] ex_record_base_w;
    reg [1:0] mem_record_base_w;
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
    genvar table_num;
    genvar query;
    genvar bank;
    wire [3:0] base_physical_w;
    wire [1:0] base_parity_w;
    wire unused_w;





    // Four records cover two EX and two MEM branch operand/result holding slots.
    // Pairing allows only one control instruction per group; D has one read port.
    assign query_pc_w[0] = f1_pc_i;
    assign query_pc_w[1] = f1_pc_i + 32'd4;
    assign d_valid_i = predict_read0_valid_i || predict_read1_valid_i;
    assign d_tag_w = predict_read0_valid_i ? predict_read0_tag_i : predict_read1_tag_i;
    assign d_indices_i = predict_read0_valid_i ?
        {predict_read0_index3_i, predict_read0_index2_i, predict_read0_index1_i,
            predict_read0_index0_i} :
        {predict_read1_index3_i, predict_read1_index2_i, predict_read1_index1_i,
            predict_read1_index0_i};
    assign d_base_index_i = predict_read0_valid_i ?
        {predict_read0_base_index_i} :
        {predict_read1_base_index_i};
    assign ex_indices_r =
        {ex_predict_train_index3_i, ex_predict_train_index2_i,
            ex_predict_train_index1_i, ex_predict_train_index0_i};
    assign ex_tags_r =
        {ex_predict_train_tag3_i, ex_predict_train_tag2_i, ex_predict_train_tag1_i,
            ex_predict_train_tag0_i};
    assign ex_base_index_r = {ex_predict_train_base_index_i};
    assign ex_provider_r = {ex_predict_train_provider_i};
    assign ex_prediction_r = {ex_predict_train_prediction_i};
    assign ex_alternate_r = {ex_predict_train_alternate_i};
    assign ex_taken_i = ex_predict_train_taken_i;
    assign ex_age_w = ex_predict_train_tag_i - age_head_i;
    assign ex_update_w = ex_predict_train_valid_i && ex_predict_train_token_i &&
        !(cancel_valid_i && (ex_age_w >= cancel_age_w));
    assign mem_indices_r =
        {mem_predict_train_index3_i, mem_predict_train_index2_i,
            mem_predict_train_index1_i, mem_predict_train_index0_i};
    assign mem_tags_r =
        {mem_predict_train_tag3_i, mem_predict_train_tag2_i,
            mem_predict_train_tag1_i, mem_predict_train_tag0_i};
    assign mem_base_index_r = {mem_predict_train_base_index_i};
    assign mem_provider_r = {mem_predict_train_provider_i};
    assign mem_prediction_r = {mem_predict_train_prediction_i};
    assign mem_alternate_r = {mem_predict_train_alternate_i};
    // spec 5.4: pending > MEM > EX; a dropped EX still advances filtered history.
    assign ex_table_update_w = ex_update_w && !(pending_valid_r && mem_update_w);
    assign mem_taken_i = mem_predict_train_taken_i;
    assign mem_age_w = mem_predict_train_tag_i - age_head_i;
    assign mem_update_w = mem_predict_train_valid_i && mem_predict_train_token_i &&
        !(cancel_valid_i && (mem_age_w >= cancel_age_w));
    assign cancel_age_w = cancel_tag_i - age_head_i;
    always @(*) begin
        history_next_w = history_r;
        if (mem_update_w)
            history_next_w = {history_next_w[94:0], mem_taken_i};
        if (ex_update_w)
            history_next_w = {history_next_w[94:0], ex_taken_i};
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            history_r <= 96'd0;
        else
            history_r <= history_next_w;
    end
    // One pending branch bundle; each table still has only one physical write port.
    assign write_valid_w = pending_valid_r || mem_update_w || ex_table_update_w;
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
    assign pending_next_valid_w = pending_valid_r ? (mem_update_w || ex_table_update_w) :
        (mem_update_w && ex_table_update_w);
    assign pending_next_indices_w = ex_table_update_w ? ex_indices_r : mem_indices_r;
    assign pending_next_base_index_w = ex_table_update_w ? ex_base_index_r : mem_base_index_r;
    assign pending_next_rows_w = ex_table_update_w ? ex_new_rows_w : mem_new_rows_w;
    assign pending_next_mask_w = ex_table_update_w ? ex_mask_w : mem_mask_w;
    assign pending_next_base_w = ex_table_update_w ? ex_new_base_w : mem_new_base_w;
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
    assign read_slot_w = record_free_w[0] ? 2'd0 : record_free_w[1] ? 2'd1 :
        record_free_w[2] ? 2'd2 : 2'd3;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            read_valid_r <= 1'b0;
        else
            read_valid_r <= d_valid_i;
    end
    always @(posedge clk_i) begin
        read_slot_r <= read_slot_w;
    end
    // Old-data RAM collisions at the D read edge are captured separately.
    generate
        for (shadow = 0; shadow < 4; shadow = shadow + 1) begin : g_read_shadow
            wire [8:0] index_w;
            wire pending_w;
            wire mem_w;
            wire ex_w;
            reg [15:0] row_r;
            reg valid_r;
            assign index_w = d_indices_i[9*shadow +: 9];
            assign pending_w = pending_valid_r && pending_mask_r[shadow] &&
                pending_indices_r[9*shadow +: 9] == index_w;
            assign mem_w = mem_update_w && mem_mask_w[shadow] &&
                mem_indices_r[9*shadow +: 9] == index_w;
            assign ex_w = ex_table_update_w && ex_mask_w[shadow] &&
                ex_indices_r[9*shadow +: 9] == index_w;
            always @(posedge clk_i) begin
                row_r <= ex_w ? ex_new_rows_w[16*shadow +: 16] :
                    mem_w ? mem_new_rows_w[16*shadow +: 16] :
                    pending_rows_r[16*shadow +: 16];
                valid_r <= ex_w || mem_w || pending_w;
            end
            assign read_shadow_rows_w[16*shadow +: 16] = row_r;
            assign read_shadow_mask_w[shadow] = valid_r;
        end
    endgenerate
    assign read_pending_base_w = pending_valid_r && pending_base_index_r == d_base_index_i;
    assign read_mem_base_w = mem_update_w && mem_base_index_r == d_base_index_i;
    assign read_ex_base_w = ex_table_update_w && ex_base_index_r == d_base_index_i;
    always @(posedge clk_i) begin
        read_shadow_base_valid_r <= read_ex_base_w || read_mem_base_w || read_pending_base_w;
        read_shadow_base_r <= read_ex_base_w ? ex_new_base_w :
            read_mem_base_w ? mem_new_base_w : pending_base_r;
    end
    generate
        for (record = 0; record < 4; record = record + 1) begin : g_record
            localparam [1:0] SLOT = record;
            reg valid_r;
            reg [TAG_BITS-1:0] tag_r;
            reg [35:0] indices_r;
            reg [11:0] base_index_r;
            reg [1:0] base_r;
            reg [63:0] rows_r;
            wire [TAG_BITS-1:0] age_w;
            wire released_w;
            wire canceled_w;
            wire capture_w;
            wire [63:0] source_rows_w;
            wire [1:0] source_base_w;
            wire [63:0] next_rows_w;
            wire [1:0] next_base_w;
            assign age_w = tag_r - age_head_i;
            assign released_w = (ex_update_w && tag_r == ex_predict_train_tag_i) ||
                (mem_update_w && tag_r == mem_predict_train_tag_i);
            assign canceled_w = cancel_valid_i && age_w >= cancel_age_w;
            assign record_valid_w[record] = valid_r;
            assign record_tags_w[TAG_BITS*record +: TAG_BITS] = tag_r;
            assign record_free_w[record] = !valid_r || released_w || canceled_w;
            assign record_allocate_w[record] = d_valid_i && read_slot_w == SLOT;
            assign capture_w = read_valid_r && read_slot_r == SLOT;
            assign source_base_w = capture_w ?
                (read_shadow_base_valid_r ? read_shadow_base_r : d_base_w) : base_r;
            assign next_base_w = (ex_table_update_w && ex_base_index_r == base_index_r) ?
                ex_new_base_w : (mem_update_w && mem_base_index_r == base_index_r) ?
                mem_new_base_w : (pending_valid_r && pending_base_index_r == base_index_r) ?
                pending_base_r : source_base_w;
            genvar table_record;
            for (table_record = 0; table_record < 4; table_record = table_record + 1)
            begin : g_row
                wire [8:0] index_w;
                assign index_w = indices_r[9*table_record +: 9];
                assign source_rows_w[16*table_record +: 16] = capture_w ?
                    (read_shadow_mask_w[table_record] ?
                        read_shadow_rows_w[16*table_record +: 16] :
                        d_rows_w[16*table_record +: 16]) : rows_r[16*table_record +: 16];
                assign next_rows_w[16*table_record +: 16] =
                    (ex_table_update_w && ex_mask_w[table_record] &&
                        ex_indices_r[9*table_record +: 9] == index_w) ?
                        ex_new_rows_w[16*table_record +: 16] :
                    (mem_update_w && mem_mask_w[table_record] &&
                        mem_indices_r[9*table_record +: 9] == index_w) ?
                        mem_new_rows_w[16*table_record +: 16] :
                    (pending_valid_r && pending_mask_r[table_record] &&
                        pending_indices_r[9*table_record +: 9] == index_w) ?
                        pending_rows_r[16*table_record +: 16] :
                        source_rows_w[16*table_record +: 16];
            end
            // The combinational read exposes the synchronous D return to the earliest EX train.
            assign record_rows_w[64*record +: 64] = source_rows_w;
            assign record_base_w[2*record +: 2] = source_base_w;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    valid_r <= 1'b0;
                else if (record_allocate_w[record])
                    valid_r <= !cancel_valid_i || ((d_tag_w - age_head_i) < cancel_age_w);
                else if (released_w || canceled_w)
                    valid_r <= 1'b0;
            end
            always @(posedge clk_i) begin
                if (record_allocate_w[record]) begin
                    tag_r <= d_tag_w;
                    indices_r <= d_indices_i;
                    base_index_r <= d_base_index_i;
                end
                rows_r <= next_rows_w;
                base_r <= next_base_w;
            end
        end
    endgenerate
    always @(*) begin
        ex_record_rows_w = 64'd0;
        ex_record_base_w = 2'd0;
        mem_record_rows_w = 64'd0;
        mem_record_base_w = 2'd0;
        if (record_valid_w[0] &&
            record_tags_w[0*TAG_BITS +: TAG_BITS] == ex_predict_train_tag_i) begin
            ex_record_rows_w = record_rows_w[0 +: 64];
            ex_record_base_w = record_base_w[0 +: 2];
        end
        if (record_valid_w[0] &&
            record_tags_w[0*TAG_BITS +: TAG_BITS] == mem_predict_train_tag_i) begin
            mem_record_rows_w = record_rows_w[0 +: 64];
            mem_record_base_w = record_base_w[0 +: 2];
        end
        if (record_valid_w[1] &&
            record_tags_w[1*TAG_BITS +: TAG_BITS] == ex_predict_train_tag_i) begin
            ex_record_rows_w = record_rows_w[64 +: 64];
            ex_record_base_w = record_base_w[2 +: 2];
        end
        if (record_valid_w[1] &&
            record_tags_w[1*TAG_BITS +: TAG_BITS] == mem_predict_train_tag_i) begin
            mem_record_rows_w = record_rows_w[64 +: 64];
            mem_record_base_w = record_base_w[2 +: 2];
        end
        if (record_valid_w[2] &&
            record_tags_w[2*TAG_BITS +: TAG_BITS] == ex_predict_train_tag_i) begin
            ex_record_rows_w = record_rows_w[128 +: 64];
            ex_record_base_w = record_base_w[4 +: 2];
        end
        if (record_valid_w[2] &&
            record_tags_w[2*TAG_BITS +: TAG_BITS] == mem_predict_train_tag_i) begin
            mem_record_rows_w = record_rows_w[128 +: 64];
            mem_record_base_w = record_base_w[4 +: 2];
        end
        if (record_valid_w[3] &&
            record_tags_w[3*TAG_BITS +: TAG_BITS] == ex_predict_train_tag_i) begin
            ex_record_rows_w = record_rows_w[192 +: 64];
            ex_record_base_w = record_base_w[6 +: 2];
        end
        if (record_valid_w[3] &&
            record_tags_w[3*TAG_BITS +: TAG_BITS] == mem_predict_train_tag_i) begin
            mem_record_rows_w = record_rows_w[192 +: 64];
            mem_record_base_w = record_base_w[6 +: 2];
        end
    end
    assign mem_current_base_w = (pending_valid_r &&
        pending_base_index_r == mem_base_index_r) ? pending_base_r : mem_record_base_w;
    assign ex_current_base_w = (mem_update_w && mem_base_index_r == ex_base_index_r) ?
        mem_new_base_w : (pending_valid_r && pending_base_index_r == ex_base_index_r) ?
        pending_base_r : ex_record_base_w;
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
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            f2_valid_r <= 1'b0;
        else
            f2_valid_r <= f1_valid_i;
    end
    assign f2_valid_o = f2_valid_r;
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
            wire [8:0] write_index_w;
            assign write_index_w = write_indices_w[9*table_num +: 9];
            edrv32_ram_cpu2_tage_train u_train (
                .clk_i(clk_i),
                .wr_en_i(write_valid_w && write_mask_w[table_num]),
                .wr_addr_i(write_index_w),
                .wr_data_i(write_rows_w[16*table_num +: 16]),
                .rd_en_i(d_valid_i),
                .rd_addr_i(d_indices_i[9*table_num +: 9]),
                .rd_data_o(d_rows_w[16*table_num +: 16])
            );
            assign mem_current_rows_w[16*table_num +: 16] =
                (pending_valid_r && pending_mask_r[table_num] &&
                    pending_indices_r[9*table_num +: 9] == mem_indices_r[9*table_num +: 9]) ?
                    pending_rows_r[16*table_num +: 16] :
                    mem_record_rows_w[16*table_num +: 16];
            assign ex_current_rows_w[16*table_num +: 16] =
                (mem_update_w && mem_mask_w[table_num] &&
                    mem_indices_r[9*table_num +: 9] == ex_indices_r[9*table_num +: 9]) ?
                    mem_new_rows_w[16*table_num +: 16] :
                (pending_valid_r && pending_mask_r[table_num] &&
                    pending_indices_r[9*table_num +: 9] == ex_indices_r[9*table_num +: 9]) ?
                    pending_rows_r[16*table_num +: 16] :
                    ex_record_rows_w[16*table_num +: 16];
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
                wire [15:0] old_pending_row_w;
                wire [15:0] mem_row_w;
                wire [15:0] ex_row_w;
                wire [15:0] row_w;
                wire [9:0] saved_tag_w;
                wire old_pending_match_w;
                wire mem_match_w;
                wire ex_match_w;
                wire pending_match_w;
                wire write_match_w;
                wire old_pending_tag_w;
                wire mem_tag_w;
                wire ex_tag_w;
                assign index_w = pc_w[10:2] ^ fold_index_flat_w[9*table_num +: 9];
                assign tag_w = pc_w[20:11] ^ fold_tag_flat_w[10*table_num +: 10] ^
                    {1'b0, fold_shift_flat_w[9*table_num +: 9]};
                assign indices_w[9*table_num +: 9] = index_w;
                assign tags_w[10*table_num +: 10] = tag_w;
                assign old_pending_row_w = pending_rows_r[16*table_num +: 16];
                assign mem_row_w = mem_new_rows_w[16*table_num +: 16];
                assign ex_row_w = ex_new_rows_w[16*table_num +: 16];
                // Compare each source in parallel, before pending/write arbitration.
                assign old_pending_match_w = pending_mask_r[table_num] &&
                    (pending_indices_r[9*table_num +: 9] == index_w);
                assign mem_match_w = mem_mask_w[table_num] &&
                    (mem_indices_r[9*table_num +: 9] == index_w);
                assign ex_match_w = ex_mask_w[table_num] &&
                    (ex_indices_r[9*table_num +: 9] == index_w);
                assign pending_match_w = pending_next_valid_w &&
                    (ex_table_update_w ? ex_match_w : mem_match_w);
                assign write_match_w = write_valid_w && (pending_valid_r ?
                    old_pending_match_w : mem_update_w ? mem_match_w : ex_match_w);
                assign old_pending_tag_w = old_pending_row_w[15] &&
                    (old_pending_row_w[14:5] == tag_w);
                assign mem_tag_w = mem_row_w[15] && (mem_row_w[14:5] == tag_w);
                assign ex_tag_w = ex_row_w[15] && (ex_row_w[14:5] == tag_w);
                always @(posedge clk_i) begin
                    f2_shadow_index_r <= pending_match_w || write_match_w;
                    f2_shadow_tag_r <= pending_match_w ?
                        (ex_table_update_w ? ex_tag_w : mem_tag_w) :
                        pending_valid_r ? old_pending_tag_w :
                        mem_update_w ? mem_tag_w : ex_tag_w;
                    f2_shadow_direction_r <= pending_match_w ?
                        (ex_table_update_w ? ex_row_w[4] : mem_row_w[4]) :
                        pending_valid_r ? old_pending_row_w[4] :
                        mem_update_w ? mem_row_w[4] : ex_row_w[4];
                end
                assign row_w = rows_w[16*table_num +: 16];
                assign saved_tag_w = f2_tags_flat_w[40*query+10*table_num +: 10];
                assign hits_w[table_num] = f2_shadow_index_flat_w[4*query+table_num] ?
                    f2_shadow_tag_flat_w[4*query+table_num] :
                    (row_w[15] && (row_w[14:5] == saved_tag_w));
                assign directions_w[table_num] = f2_shadow_index_flat_w[4*query+table_num] ?
                    f2_shadow_direction_flat_w[4*query+table_num] : row_w[4];
                wire unused_row_w;
                assign unused_row_w = ^{row_w[3:0], old_pending_row_w[3:0],
                    mem_row_w[3:0], ex_row_w[3:0]};
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
    assign prediction_base_w[0] = base_parity_w[0] ? base_physical_w[3:2] : base_physical_w[1:0];
    assign prediction_base_w[1] = base_parity_w[0] ? base_physical_w[1:0] : base_physical_w[3:2];
    assign unused_w = ^{f1_pc_i[31:21], f1_pc_i[1:0], base_parity_w[1], record_free_w[3],
        predict_read0_tag0_i, predict_read0_tag1_i, predict_read0_tag2_i, predict_read0_tag3_i,
        predict_read1_tag0_i, predict_read1_tag1_i, predict_read1_tag2_i, predict_read1_tag3_i};
endmodule
