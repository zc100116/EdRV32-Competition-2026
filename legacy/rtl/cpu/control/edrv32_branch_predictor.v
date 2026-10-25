// ============================================================================
// File        : edrv32_branch_predictor.v
// Provenance  : Direct refactor of the validated pre-rewrite branch_predict.v.
// Description : 32-entry halfword-granular BTB, 256-entry bimodal BHT,
//               small loop-direction table and eight-entry return stack.
// Notes       : Prediction is advisory.  EX remains the sole architectural
//               control-flow judge and trains this module after resolution.
// ============================================================================
module edrv32_branch_predictor #(
    parameter integer FETCH_WIDE = 0,
    parameter integer BTB_ENTRIES = 32,
    parameter integer BHT_ENTRIES = 256,
    parameter integer RAS_DEPTH = 8,
    parameter integer BTB_INDEX_W = $clog2(BTB_ENTRIES),
    parameter integer BHT_INDEX_W = $clog2(BHT_ENTRIES)
) (
    // Clock, reset, and global invalidation from a retired FENCE.I.
    input  wire        clk_i,
    input  wire        rst_n_i,
    input  wire        invalidate_i,

    // Two halfword-granular query ports for the possible instruction starts
    // in one 32-bit fetch block.
    input  wire [31:0] query_pc0_i,
    output wire        predicted_taken0_o,
    output wire [31:0] predicted_target0_o,
    output wire [1:0]  query_meta0_o,
    input  wire [31:0] query_pc1_i,
    output wire        predicted_taken1_o,
    output wire [31:0] predicted_target1_o,
    output wire [1:0]  query_meta1_o,

    input  wire [31:0] query_pc2_i,
    output wire        predicted_taken2_o,
    output wire [31:0] predicted_target2_o,
    output wire [1:0]  query_meta2_o,
    input  wire [31:0] query_pc3_i,
    output wire        predicted_taken3_o,
    output wire [31:0] predicted_target3_o,
    output wire [1:0]  query_meta3_o,

    // One resolved branch or jump from EX trains all predictor structures.
    input  wire        update_valid_i,
    input  wire [31:0] update_pc_i,
    input  wire        update_is_conditional_i,
    input  wire        update_is_unconditional_i,
    input  wire        update_is_indirect_i,
    input  wire        update_taken_i,
    input  wire [31:0] update_target_i,
    input  wire        update_ras_push_i,
    input  wire        update_ras_pop_i,
    input  wire [31:0] update_link_addr_i
);

    // Predictor geometry and persistent BTB, BHT, and RAS state.
    localparam integer TAG_W = 32 - (BTB_INDEX_W + 1);
    localparam integer RAS_ENTRIES = (RAS_DEPTH > 0) ? RAS_DEPTH : 1;
    localparam integer RAS_PTR_W = (RAS_ENTRIES <= 1) ? 1 : $clog2(RAS_ENTRIES);
    localparam integer RAS_COUNT_W = $clog2(RAS_ENTRIES + 1);
    localparam [1:0] BHT_STRONGLY_NOT_TAKEN = 2'b00;
    localparam [1:0] BHT_WEAKLY_NOT_TAKEN   = 2'b01;
    localparam [1:0] BHT_WEAKLY_TAKEN       = 2'b10;
    localparam [1:0] BHT_STRONGLY_TAKEN     = 2'b11;

    reg [BTB_ENTRIES-1:0] btb_valid_r;
    reg [TAG_W-1:0] btb_tag_r [0:BTB_ENTRIES-1];
    reg [31:0] btb_target_r [0:BTB_ENTRIES-1];
    reg btb_unconditional_r [0:BTB_ENTRIES-1];
    reg btb_return_r [0:BTB_ENTRIES-1];
    reg [BHT_ENTRIES*2-1:0] bht_r;
    // A direct-mapped loop table overrides the BHT only after the same taken
    // run length has completed repeatedly.  Short tags may alias, but a wrong
    // prediction remains advisory and EX repairs the stream.
    reg [15:0] loop_valid_r;
    reg [7:0] loop_tag_r [0:15];
    reg [7:0] loop_run_r [0:15];
    reg [7:0] loop_trip_r [0:15];
    reg [1:0] loop_conf_r [0:15];
    reg [31:0] ras_stack_r [0:RAS_ENTRIES-1];
    reg [RAS_PTR_W-1:0] ras_stack_pointer_r;
    reg [RAS_COUNT_W-1:0] ras_count_r;

    // EX training is advisory and therefore crosses a registered command
    // boundary before changing predictor state.  BTB/RAS and BHT validity are
    // kept separately to preserve the existing FENCE.I priority: invalidate
    // suppresses same-edge BTB/RAS training, but direction history continues
    // to train because FENCE.I does not invalidate the BHT.
    reg training_btb_ras_valid_r;
    reg training_bht_valid_r;
    reg [BTB_INDEX_W-1:0] training_btb_index_r;
    reg [TAG_W-1:0] training_btb_tag_r;
    reg [BHT_INDEX_W-1:0] training_bht_index_r;
    reg [3:0] training_loop_index_r;
    reg [7:0] training_loop_tag_r;
    reg training_is_unconditional_r;
    reg training_is_indirect_r;
    reg training_taken_r;
    reg [31:0] training_target_r;
    reg training_ras_push_r;
    reg training_ras_pop_r;
    reg [31:0] training_link_addr_r;
    reg [1:0] bht_next_w;
    reg ras_query_nonempty_w;
    reg [31:0] ras_query_top_w;

    // Two combinational query ports share the same BTB, BHT and RAS state.
    // A pending registered write is forwarded locally so the prediction
    // visible after an EX update edge remains identical to the old same-edge
    // table write.  The forwarding source is entirely inside this module; EX
    // itself is not reintroduced into the query or table-control cones.
    wire [BTB_INDEX_W-1:0] query0_btb_index_w =
        query_pc0_i[BTB_INDEX_W:1];
    wire [TAG_W-1:0] query0_btb_tag_w =
        query_pc0_i[31:BTB_INDEX_W+1];
    wire [BHT_INDEX_W-1:0] query0_bht_index_w =
        query_pc0_i[BHT_INDEX_W:1];
    wire query0_btb_forward_w = training_btb_ras_valid_r &&
        training_is_indirect_r &&
        training_taken_r && (training_btb_index_r == query0_btb_index_w);
    wire query0_btb_match_w = query0_btb_forward_w
        ? (training_btb_tag_r == query0_btb_tag_w)
        : (btb_valid_r[query0_btb_index_w] &&
           (btb_tag_r[query0_btb_index_w] == query0_btb_tag_w));
    wire query0_btb_unconditional_w = query0_btb_forward_w
        ? training_is_unconditional_r
        : btb_unconditional_r[query0_btb_index_w];
    wire query0_btb_return_w = query0_btb_forward_w
        ? training_ras_pop_r : btb_return_r[query0_btb_index_w];
    wire [31:0] query0_btb_target_w = query0_btb_forward_w
        ? training_target_r : btb_target_r[query0_btb_index_w];
    wire query0_bht_taken_w =
        (training_bht_valid_r &&
         (training_bht_index_r == query0_bht_index_w))
            ? bht_next_w[1] : bht_r[2*query0_bht_index_w + 1];
    wire [3:0] query0_loop_index_w = query_pc0_i[4:1];
    wire query0_loop_hit_w = loop_valid_r[query0_loop_index_w] &&
        (loop_tag_r[query0_loop_index_w] == query_pc0_i[12:5]) &&
        (loop_conf_r[query0_loop_index_w] >= 2'd2) &&
        (loop_trip_r[query0_loop_index_w] >= 8'd2);
    wire query0_direction_w = query0_loop_hit_w
        ? (loop_run_r[query0_loop_index_w] <
           loop_trip_r[query0_loop_index_w]) : query0_bht_taken_w;

    wire [BTB_INDEX_W-1:0] query1_btb_index_w =
        query_pc1_i[BTB_INDEX_W:1];
    wire [TAG_W-1:0] query1_btb_tag_w =
        query_pc1_i[31:BTB_INDEX_W+1];
    wire [BHT_INDEX_W-1:0] query1_bht_index_w =
        query_pc1_i[BHT_INDEX_W:1];
    wire query1_btb_forward_w = training_btb_ras_valid_r &&
        training_is_indirect_r &&
        training_taken_r && (training_btb_index_r == query1_btb_index_w);
    wire query1_btb_match_w = query1_btb_forward_w
        ? (training_btb_tag_r == query1_btb_tag_w)
        : (btb_valid_r[query1_btb_index_w] &&
           (btb_tag_r[query1_btb_index_w] == query1_btb_tag_w));
    wire query1_btb_unconditional_w = query1_btb_forward_w
        ? training_is_unconditional_r
        : btb_unconditional_r[query1_btb_index_w];
    wire query1_btb_return_w = query1_btb_forward_w
        ? training_ras_pop_r : btb_return_r[query1_btb_index_w];
    wire [31:0] query1_btb_target_w = query1_btb_forward_w
        ? training_target_r : btb_target_r[query1_btb_index_w];
    wire query1_bht_taken_w =
        (training_bht_valid_r &&
         (training_bht_index_r == query1_bht_index_w))
            ? bht_next_w[1] : bht_r[2*query1_bht_index_w + 1];
    wire [3:0] query1_loop_index_w = query_pc1_i[4:1];
    wire query1_loop_hit_w = loop_valid_r[query1_loop_index_w] &&
        (loop_tag_r[query1_loop_index_w] == query_pc1_i[12:5]) &&
        (loop_conf_r[query1_loop_index_w] >= 2'd2) &&
        (loop_trip_r[query1_loop_index_w] >= 8'd2);
    wire query1_direction_w = query1_loop_hit_w
        ? (loop_run_r[query1_loop_index_w] <
           loop_trip_r[query1_loop_index_w]) : query1_bht_taken_w;

    wire ras_nonempty_w = (RAS_DEPTH > 0) &&
                          (ras_count_r != {RAS_COUNT_W{1'b0}});
    wire [RAS_PTR_W-1:0] ras_top_index_w =
        (ras_stack_pointer_r == {RAS_PTR_W{1'b0}})
            ? RAS_ENTRIES - 1'b1 : ras_stack_pointer_r - 1'b1;
    wire [RAS_PTR_W-1:0] ras_below_top_index_w =
        (ras_top_index_w == {RAS_PTR_W{1'b0}})
            ? RAS_ENTRIES - 1'b1 : ras_top_index_w - 1'b1;

    // Project the pending RAS command into the query result.  This is the RAS
    // equivalent of RAM read-after-write forwarding and preserves call/return
    // prediction timing while the physical stack write crosses the new
    // training boundary.
    always @* begin
        ras_query_nonempty_w = ras_nonempty_w;
        ras_query_top_w = ras_stack_r[ras_top_index_w];
        if ((RAS_DEPTH > 0) && training_btb_ras_valid_r) begin
            case ({training_ras_push_r, training_ras_pop_r})
                2'b10: begin
                    ras_query_nonempty_w = 1'b1;
                    ras_query_top_w = training_link_addr_r;
                end
                2'b01: begin
                    if (ras_count_r >
                        {{(RAS_COUNT_W-1){1'b0}}, 1'b1}) begin
                        ras_query_nonempty_w = 1'b1;
                        ras_query_top_w = ras_stack_r[ras_below_top_index_w];
                    end else begin
                        ras_query_nonempty_w = 1'b0;
                    end
                end
                2'b11: begin
                    ras_query_nonempty_w = 1'b1;
                    ras_query_top_w = training_link_addr_r;
                end
                default: begin end
            endcase
        end
    end

    wire query0_return_hit_w = query0_btb_match_w &&
                               query0_btb_return_w &&
                               ras_query_nonempty_w;
    wire query1_return_hit_w = query1_btb_match_w &&
                               query1_btb_return_w &&
                               ras_query_nonempty_w;

    assign predicted_taken0_o = query0_btb_match_w &&
        (query0_btb_unconditional_w || query0_direction_w);
    assign predicted_target0_o = query0_return_hit_w
        ? ras_query_top_w : query0_btb_target_w;
    // Preserve the final direction decision and BTB hit at fetch time.
    // meta[1]=direction taken, meta[0]=BTB hit; EX compares this sampled state
    // with the resolved branch instead of querying tables that may change.
    assign query_meta0_o = {query0_direction_w, query0_btb_match_w};
    assign predicted_taken1_o = query1_btb_match_w &&
        (query1_btb_unconditional_w || query1_direction_w);
    assign predicted_target1_o = query1_return_hit_w
        ? ras_query_top_w : query1_btb_target_w;
    assign query_meta1_o = {query1_direction_w, query1_btb_match_w};

    wire [BTB_INDEX_W-1:0] query2_btb_index_w =
        query_pc2_i[BTB_INDEX_W:1];
    wire [TAG_W-1:0] query2_btb_tag_w =
        query_pc2_i[31:BTB_INDEX_W+1];
    wire [BHT_INDEX_W-1:0] query2_bht_index_w =
        query_pc2_i[BHT_INDEX_W:1];
    wire query2_btb_forward_w = training_btb_ras_valid_r &&
        training_is_indirect_r &&
        training_taken_r && (training_btb_index_r == query2_btb_index_w);
    wire query2_btb_match_w = query2_btb_forward_w
        ? (training_btb_tag_r == query2_btb_tag_w)
        : (btb_valid_r[query2_btb_index_w] &&
           (btb_tag_r[query2_btb_index_w] == query2_btb_tag_w));
    wire query2_btb_unconditional_w = query2_btb_forward_w
        ? training_is_unconditional_r
        : btb_unconditional_r[query2_btb_index_w];
    wire query2_btb_return_w = query2_btb_forward_w
        ? training_ras_pop_r : btb_return_r[query2_btb_index_w];
    wire [31:0] query2_btb_target_w = query2_btb_forward_w
        ? training_target_r : btb_target_r[query2_btb_index_w];
    wire query2_bht_taken_w =
        (training_bht_valid_r &&
         (training_bht_index_r == query2_bht_index_w))
            ? bht_next_w[1] : bht_r[2*query2_bht_index_w + 1];
    wire [3:0] query2_loop_index_w = query_pc2_i[4:1];
    wire query2_loop_hit_w = loop_valid_r[query2_loop_index_w] &&
        (loop_tag_r[query2_loop_index_w] == query_pc2_i[12:5]) &&
        (loop_conf_r[query2_loop_index_w] >= 2'd2) &&
        (loop_trip_r[query2_loop_index_w] >= 8'd2);
    wire query2_direction_w = query2_loop_hit_w
        ? (loop_run_r[query2_loop_index_w] <
           loop_trip_r[query2_loop_index_w]) : query2_bht_taken_w;

    wire query2_return_hit_w = query2_btb_match_w &&
                               query2_btb_return_w &&
                               ras_query_nonempty_w;
    assign predicted_taken2_o = (FETCH_WIDE != 0) && query2_btb_match_w &&
        (query2_btb_unconditional_w || query2_direction_w);
    assign predicted_target2_o = query2_return_hit_w
        ? ras_query_top_w : query2_btb_target_w;
    assign query_meta2_o = {query2_direction_w, query2_btb_match_w};
    wire [BTB_INDEX_W-1:0] query3_btb_index_w =
        query_pc3_i[BTB_INDEX_W:1];
    wire [TAG_W-1:0] query3_btb_tag_w =
        query_pc3_i[31:BTB_INDEX_W+1];
    wire [BHT_INDEX_W-1:0] query3_bht_index_w =
        query_pc3_i[BHT_INDEX_W:1];
    wire query3_btb_forward_w = training_btb_ras_valid_r &&
        training_is_indirect_r &&
        training_taken_r && (training_btb_index_r == query3_btb_index_w);
    wire query3_btb_match_w = query3_btb_forward_w
        ? (training_btb_tag_r == query3_btb_tag_w)
        : (btb_valid_r[query3_btb_index_w] &&
           (btb_tag_r[query3_btb_index_w] == query3_btb_tag_w));
    wire query3_btb_unconditional_w = query3_btb_forward_w
        ? training_is_unconditional_r
        : btb_unconditional_r[query3_btb_index_w];
    wire query3_btb_return_w = query3_btb_forward_w
        ? training_ras_pop_r : btb_return_r[query3_btb_index_w];
    wire [31:0] query3_btb_target_w = query3_btb_forward_w
        ? training_target_r : btb_target_r[query3_btb_index_w];
    wire query3_bht_taken_w =
        (training_bht_valid_r &&
         (training_bht_index_r == query3_bht_index_w))
            ? bht_next_w[1] : bht_r[2*query3_bht_index_w + 1];
    wire [3:0] query3_loop_index_w = query_pc3_i[4:1];
    wire query3_loop_hit_w = loop_valid_r[query3_loop_index_w] &&
        (loop_tag_r[query3_loop_index_w] == query_pc3_i[12:5]) &&
        (loop_conf_r[query3_loop_index_w] >= 2'd2) &&
        (loop_trip_r[query3_loop_index_w] >= 8'd2);
    wire query3_direction_w = query3_loop_hit_w
        ? (loop_run_r[query3_loop_index_w] <
           loop_trip_r[query3_loop_index_w]) : query3_bht_taken_w;

    wire query3_return_hit_w = query3_btb_match_w &&
                               query3_btb_return_w &&
                               ras_query_nonempty_w;
    assign predicted_taken3_o = (FETCH_WIDE != 0) && query3_btb_match_w &&
        (query3_btb_unconditional_w || query3_direction_w);
    assign predicted_target3_o = query3_return_hit_w
        ? ras_query_top_w : query3_btb_target_w;
    assign query_meta3_o = {query3_direction_w, query3_btb_match_w};

    // Capture one resolved control-flow training packet every cycle.  This is
    // a throughput-one boundary rather than a queue, so adjacent branches are
    // retained while EX is removed from all table entry write-enable cones.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            training_btb_ras_valid_r <= 1'b0;
            training_bht_valid_r <= 1'b0;
            training_btb_index_r <= {BTB_INDEX_W{1'b0}};
            training_btb_tag_r <= {TAG_W{1'b0}};
            training_bht_index_r <= {BHT_INDEX_W{1'b0}};
            training_loop_index_r <= 4'd0;
            training_loop_tag_r <= 8'd0;
            training_is_unconditional_r <= 1'b0;
            training_is_indirect_r <= 1'b0;
            training_taken_r <= 1'b0;
            training_target_r <= 32'd0;
            training_ras_push_r <= 1'b0;
            training_ras_pop_r <= 1'b0;
            training_link_addr_r <= 32'd0;
        end else begin
            training_btb_ras_valid_r <= update_valid_i && !invalidate_i;
            training_bht_valid_r <= update_valid_i &&
                                    update_is_conditional_i;
            training_btb_index_r <= update_pc_i[BTB_INDEX_W:1];
            training_btb_tag_r <= update_pc_i[31:BTB_INDEX_W+1];
            training_bht_index_r <= update_pc_i[BHT_INDEX_W:1];
            training_loop_index_r <= update_pc_i[4:1];
            training_loop_tag_r <= update_pc_i[12:5];
            training_is_unconditional_r <= update_is_unconditional_i;
            training_is_indirect_r <= update_is_indirect_i;
            training_taken_r <= update_taken_i;
            training_target_r <= update_target_i;
            training_ras_push_r <= update_ras_push_i;
            training_ras_pop_r <= update_ras_pop_i;
            training_link_addr_r <= update_link_addr_i;
        end
    end

    // Saturating two-bit counter transition for the selected BHT entry.
    always @* begin
        case (bht_r[2*training_bht_index_r +: 2])
            BHT_STRONGLY_NOT_TAKEN:
                bht_next_w = training_taken_r
                    ? BHT_WEAKLY_NOT_TAKEN : BHT_STRONGLY_NOT_TAKEN;
            BHT_WEAKLY_NOT_TAKEN:
                bht_next_w = training_taken_r
                    ? BHT_WEAKLY_TAKEN : BHT_STRONGLY_NOT_TAKEN;
            BHT_WEAKLY_TAKEN:
                bht_next_w = training_taken_r
                    ? BHT_STRONGLY_TAKEN : BHT_WEAKLY_NOT_TAKEN;
            default:
                bht_next_w = training_taken_r
                    ? BHT_STRONGLY_TAKEN : BHT_WEAKLY_TAKEN;
        endcase
    end

    // Express each table as one indexed write port.  Invalidation changes BTB
    // valid bits only; stale tags and targets remain architecturally invisible.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            btb_valid_r <= {BTB_ENTRIES{1'b0}};
        end else if (invalidate_i) begin
            btb_valid_r <= {BTB_ENTRIES{1'b0}};
        end else if (training_btb_ras_valid_r &&
                     training_is_indirect_r && training_taken_r) begin
            btb_valid_r[training_btb_index_r] <= 1'b1;
            btb_tag_r[training_btb_index_r] <= training_btb_tag_r;
            btb_target_r[training_btb_index_r] <= training_target_r;
            btb_unconditional_r[training_btb_index_r] <=
                training_is_unconditional_r;
            btb_return_r[training_btb_index_r] <= training_ras_pop_r;
        end
    end

    // Conditional branches alone train the direction counters.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            bht_r <= {BHT_ENTRIES{BHT_WEAKLY_NOT_TAKEN}};
        end else if (training_bht_valid_r) begin
            bht_r[2*training_bht_index_r +: 2] <= bht_next_w;
        end
    end

    // Long, repeatable taken runs are common in the benchmark.  A mismatched
    // run lowers confidence immediately; saturation disables loop prediction
    // until a new measurable run completes.  The table is advisory only.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            loop_valid_r <= 16'd0;
        end else if (invalidate_i) begin
            loop_valid_r <= 16'd0;
        end else if (training_bht_valid_r) begin
            if (!loop_valid_r[training_loop_index_r] ||
                (loop_tag_r[training_loop_index_r] !=
                 training_loop_tag_r)) begin
                loop_valid_r[training_loop_index_r] <= 1'b1;
                loop_tag_r[training_loop_index_r] <= training_loop_tag_r;
                loop_run_r[training_loop_index_r] <=
                    training_taken_r ? 8'd1 : 8'd0;
                loop_trip_r[training_loop_index_r] <= 8'd0;
                loop_conf_r[training_loop_index_r] <= 2'd0;
            end else if (training_taken_r) begin
                if (loop_run_r[training_loop_index_r] != 8'hff) begin
                    loop_run_r[training_loop_index_r] <=
                        loop_run_r[training_loop_index_r] + 8'd1;
                end else begin
                    loop_trip_r[training_loop_index_r] <= 8'd0;
                    loop_conf_r[training_loop_index_r] <= 2'd0;
                end
            end else begin
                if ((loop_run_r[training_loop_index_r] >= 8'd2) &&
                    (loop_run_r[training_loop_index_r] != 8'hff)) begin
                    if (loop_run_r[training_loop_index_r] ==
                        loop_trip_r[training_loop_index_r]) begin
                        if (loop_conf_r[training_loop_index_r] != 2'd3)
                            loop_conf_r[training_loop_index_r] <=
                                loop_conf_r[training_loop_index_r] + 2'd1;
                    end else begin
                        loop_trip_r[training_loop_index_r] <=
                            loop_run_r[training_loop_index_r];
                        loop_conf_r[training_loop_index_r] <= 2'd0;
                    end
                end else begin
                    loop_conf_r[training_loop_index_r] <= 2'd0;
                end
                loop_run_r[training_loop_index_r] <= 8'd0;
            end
        end
    end

    // RAS pointer/count state is independent from stack payload.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            ras_stack_pointer_r <= {RAS_PTR_W{1'b0}};
            ras_count_r <= {RAS_COUNT_W{1'b0}};
        end else if (invalidate_i) begin
            ras_stack_pointer_r <= {RAS_PTR_W{1'b0}};
            ras_count_r <= {RAS_COUNT_W{1'b0}};
        end else if ((RAS_DEPTH > 0) && training_btb_ras_valid_r) begin
            case ({training_ras_push_r, training_ras_pop_r})
                2'b10: begin
                    ras_stack_pointer_r <=
                        (ras_stack_pointer_r == RAS_ENTRIES - 1'b1)
                            ? {RAS_PTR_W{1'b0}} : ras_stack_pointer_r + 1'b1;
                    if (ras_count_r < RAS_ENTRIES)
                        ras_count_r <= ras_count_r + 1'b1;
                end
                2'b01: begin
                    if (ras_nonempty_w) begin
                        ras_stack_pointer_r <=
                            (ras_stack_pointer_r == {RAS_PTR_W{1'b0}})
                                ? RAS_ENTRIES - 1'b1
                                : ras_stack_pointer_r - 1'b1;
                        ras_count_r <= ras_count_r - 1'b1;
                    end
                end
                2'b11: begin
                    if (!ras_nonempty_w) begin
                        ras_stack_pointer_r <=
                            (ras_stack_pointer_r == RAS_ENTRIES - 1'b1)
                                ? {RAS_PTR_W{1'b0}}
                                : ras_stack_pointer_r + 1'b1;
                        ras_count_r <= {{(RAS_COUNT_W-1){1'b0}}, 1'b1};
                    end
                end
                default: begin end
            endcase
        end
    end

    // RAS payload changes only when a push is architecturally resolved.
    always @(posedge clk_i) begin
        if ((RAS_DEPTH > 0) && training_btb_ras_valid_r &&
            training_ras_push_r) begin
            if (training_ras_pop_r && ras_nonempty_w)
                ras_stack_r[ras_top_index_w] <= training_link_addr_r;
            else
                ras_stack_r[ras_stack_pointer_r] <= training_link_addr_r;
        end
    end

endmodule
