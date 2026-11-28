// File: edrv32_cpu2_lsu.v
// Spec: cpu-v2-spec 3.7, 5.2, 5.6, 6; fpu-spec 5.5.
// Description: Pipelined preparation with four cached-store beats marked at retirement.
// Device authorization stays local; hit returns fall through and blocked results retain data.
// Clock domain: clk_sys.
module edrv32_cpu2_lsu #(
    parameter ISSUE_WIDTH = 2,
    parameter [31:0] FPU_FORMAT = "NONE"
) (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Issued instruction and correlated early query.
    input wire lsu_req_valid_i,
    output wire lsu_req_ready_o,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] lsu_req_tag_i,
    input wire [31:0] lsu_req_instr_i,
    input wire [31:0] lsu_req_addr_i,
    input wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] lsu_req_store_data_i,
    input wire lsu_req_early_i,
    input wire early_req_valid_i,
    input wire [31:0] early_req_addr_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] early_req_tag_i,
    output wire early_resp_valid_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] early_resp_tag_o,
    output wire early_resp_hit_o,
    output wire [31:0] early_resp_data_o,

    // Completion and architectural memory trace.
    output wire lsu_complete_valid_o,
    input wire lsu_complete_ready_i,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] lsu_complete_tag_o,
    output wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] lsu_complete_data_o,
    output wire [4:0] lsu_complete_flags_o,
    output wire lsu_complete_exception_o,
    output wire [3:0] lsu_complete_cause_o,
    output wire [31:0] lsu_complete_tval_o,
    output wire lsu_complete_device_o,
    output wire [31:0] lsu_complete_mem_addr_o,
    output wire [63:0] lsu_complete_mem_data_o,
    output wire [7:0] lsu_complete_mem_mask_o,

    // Head authorization and final instruction completion.
    input wire [1:0] commit_store_count_i,
    output wire lsu_store_drained_o,
    input wire commit_lsu_valid_i,
    output wire commit_lsu_ready_o,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] commit_lsu_tag_i,
    output wire commit_lsu_done_valid_o,
    input wire commit_lsu_done_ready_i,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] commit_lsu_done_tag_o,
    output wire commit_lsu_done_error_o,
    output wire [31:0] commit_lsu_done_fault_addr_o,
    output wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] commit_lsu_done_data_o,

    // Dcache preparation and beat completion.
    output wire dc_req_valid_o,
    input wire dc_req_ready_i,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] dc_req_tag_o,
    output wire dc_req_beat_o,
    output wire [31:0] dc_req_addr_o,
    output wire dc_req_store_o,
    output wire [1:0] dc_req_size_o,
    output wire [31:0] dc_req_data_o,
    output wire [3:0] dc_req_mask_o,
    output wire dc_req_early_o,
    input wire dc_resp_valid_i,
    output wire dc_resp_ready_o,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] dc_resp_tag_i,
    input wire dc_resp_beat_i,
    input wire [1:0] dc_resp_way_hit_i,
    input wire [31:0] dc_resp_way0_data_i,
    input wire [31:0] dc_resp_way1_data_i,
    input wire dc_resp_error_i,
    input wire dc_resp_device_i,
    output wire dc_commit_valid_o,
    input wire dc_commit_ready_i,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] dc_commit_tag_o,
    output wire dc_commit_beat_o,
    output wire [31:0] dc_commit_data_o,
    output wire [3:0] dc_commit_mask_o,
    input wire dc_done_valid_i,
    output wire dc_done_ready_o,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] dc_done_tag_i,
    input wire dc_done_beat_i,
    input wire dc_done_error_i,
    input wire [31:0] dc_done_data_i,

    // Dcache early query.
    output wire dc_early_valid_o,
    output wire [31:0] dc_early_addr_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] dc_early_tag_o,
    input wire dc_early_resp_valid_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] dc_early_resp_tag_i,
    input wire [1:0] dc_early_hit_i,
    input wire [31:0] dc_early_way0_data_i,
    input wire [31:0] dc_early_way1_data_i,

    // Age cancellation.
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] age_head_i,
    input wire cancel_valid_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] cancel_tag_i,
    output wire dc_cancel_valid_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] dc_cancel_tag_o,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] dc_age_head_o
);
    localparam T = ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3;
    localparam B = FPU_FORMAT == "FD" ? 64 : 32;
    localparam [3:0] S_IDLE = 4'd0;
    localparam [3:0] S_REQUEST = 4'd1;
    localparam [3:0] S_RESPONSE = 4'd2;
    localparam [3:0] S_COMPLETE = 4'd3;
    localparam [3:0] S_AUTHORIZE = 4'd4;
    localparam [3:0] S_COMMIT = 4'd5;
    localparam [3:0] S_BEAT_DONE = 4'd6;
    localparam [3:0] S_DONE = 4'd7;
    reg [3:0] state_r;
    reg request_started_r;
    reg early_blocked_r;
    reg [T-1:0] early_blocked_tag_r;
    reg [T-1:0] tag_r;
    reg [31:0] addr_r;
    reg [B-1:0] store_data_r;
    reg [2:0] funct3_r;
    reg store_r;
    reg fp_r;
    reg double_r;
    reg early_r;
    reg beat_r;
    reg device_r;
    reg exception_r;
    reg done_error_r;
    reg [31:0] fault_addr_r;
    reg [31:0] low_r;
    reg [31:0] high_r;
    reg early_valid_r;
    reg [T-1:0] early_tag_r;
    reg early_hit_r;
    reg [31:0] early_data_r;
    // One registered lookahead entry absorbs a response/miss or completion stall.
    // Ready depends only on these local capacity/state registers.
    reg queue_valid_r;
    reg queue_sent_r;
    reg queue_started_r;
    reg queue_misaligned_r;
    reg [T-1:0] queue_tag_r;
    reg [31:0] queue_addr_r;
    reg [B-1:0] queue_data_r;
    reg [2:0] queue_funct3_r;
    reg queue_store_r;
    reg queue_fp_r;
    reg queue_double_r;
    reg queue_early_r;
    wire overlap_w;
    wire input_fire_w;
    wire input_cancel_w;
    wire queue_cancel_w;
    wire active_end_w;
    wire queue_promote_w;
    wire input_active_w;
    wire input_queued_w;
    wire queue_request_w;
    wire front_request_w;
    wire front_misaligned_w;
    wire front_started_w;
    wire front_double_w;
    wire front_fp_w;
    wire [1:0] front_size_w;
    wire front_accept_w;
    // Four beat records separate cache preparation from irrevocable draining.
    localparam SQ_DEPTH = 4;
    reg [3:0] sq_valid_r;
    reg [3:0] sq_committed_r;
    reg [1:0] sq_head_r;
    reg [1:0] sq_tail_r;
    reg [2:0] sq_count_r;
    reg [2:0] sq_reserved_r;
    reg [2:0] sq_committed_count_r;
    wire [T-1:0] sq_tag_w [0:SQ_DEPTH-1];
    wire sq_beat_w [0:SQ_DEPTH-1];
    wire sq_last_w [0:SQ_DEPTH-1];
    wire [31:0] sq_addr_w [0:SQ_DEPTH-1];
    wire [31:0] sq_data_w [0:SQ_DEPTH-1];
    wire [3:0] sq_mask_w [0:SQ_DEPTH-1];
    localparam SQ_PAYLOAD = T+70;
    wire [SQ_PAYLOAD-1:0] sq_payload_w [0:SQ_DEPTH-1];
    wire [SQ_PAYLOAD-1:0] sq_payload_next_w;
    assign sq_payload_next_w = {tag_r,beat_r,(!double_r || beat_r),beat_addr_w,
        selected_store_w,mask_w};
    reg [1:0] active_store_left_r;
    reg [1:0] queue_store_left_r;
    wire [3:0] sq_cancel_w;
    wire [3:0] sq_mark_w;
    wire [3:0] sq_load_conflict_w;
    wire [3:0] sq_early_conflict_w;
    wire [3:0] sq_index_conflict_w;
    wire [T-1:0] sq_age_w [0:SQ_DEPTH-1];
    wire [2:0] sq_cancel_count_w;
    wire [2:0] sq_mark_count_w;
    wire [2:0] sq_keep_count_w;
    wire sq_enqueue_w;
    wire sq_drain_w;
    wire sq_output_w;
    wire store_capacity_w;
    wire store_input_w;
    wire prepared_store_w;
    wire [1:0] prepared_release_w;
    wire [1:0] active_release_w;
    wire [1:0] queued_release_w;
    wire front_conflict_w;
    wire early_conflict_w;
    wire serial_store_w;
    wire [T-1:0] front_age_w;
    wire [T-1:0] query_age_w;
    wire [T-1:0] age_w;
    wire [T-1:0] cancel_age_w;
    wire cancel_w;
    wire req_store_w;
    wire response_complete_w;
    wire done_fallthrough_w;
    wire complete_device_w;
    wire complete_exception_w;
    wire complete_access_w;
    wire [31:0] complete_low_w;
    wire [31:0] complete_high_w;
    wire [63:0] store_bits_w;
    wire [63:0] trace_bits_w;
    wire [63:0] trace_bytes_w;
    wire [7:0] trace_mask_w;
    wire [3:0] req_mask_w;
    wire early_block_w;
    wire older_request_w;
    wire early_reuse_w;
    wire early_associate_w;
    wire ordinary_valid_w;
    wire [T-1:0] early_result_tag_w;
    wire [2:0] early_funct3_w;
    wire req_fp_w;
    wire req_double_w;
    wire misaligned_w;
    wire [31:0] beat_addr_w;
    wire [31:0] response_data_w;
    wire [31:0] selected_store_w;
    reg [31:0] extended_load_w;
    wire [31:0] early_selected_w;
    reg [31:0] early_extended_w;
    wire [3:0] mask_w;
    wire unused_w;

    assign age_w = tag_r - age_head_i;
    assign cancel_age_w = cancel_tag_i - age_head_i;
    assign cancel_w = cancel_valid_i && (age_w >= cancel_age_w);
    assign req_store_w = lsu_req_instr_i[5];
    assign req_fp_w = lsu_req_instr_i[2];
    assign req_double_w = FPU_FORMAT == "FD" && req_fp_w &&
        lsu_req_instr_i[14:12] == 3'd3;
    assign misaligned_w = req_double_w ? |lsu_req_addr_i[2:0] :
        (req_fp_w || lsu_req_instr_i[13]) ? |lsu_req_addr_i[1:0] :
        lsu_req_instr_i[12] && lsu_req_addr_i[0];
    assign beat_addr_w = addr_r + (beat_r ? 32'd4 : 32'd0);
    assign response_data_w = dc_resp_way_hit_i[1] ? dc_resp_way1_data_i :
        dc_resp_way0_data_i;
    assign mask_w = (double_r || fp_r || funct3_r[1]) ? 4'hf :
        funct3_r[0] ? 4'h3 : 4'h1;
    generate
        if (FPU_FORMAT == "FD") begin : g_double
            assign selected_store_w = beat_r ? store_data_r[63:32] : store_data_r[31:0];
            assign lsu_complete_data_o = fp_r ?
                (double_r ? {complete_high_w, complete_low_w} :
                {32'hffff_ffff, complete_low_w}) :
                {32'd0, extended_load_w};
            assign commit_lsu_done_data_o = fp_r ?
                (double_r ? {complete_high_w, complete_low_w} :
                {32'hffff_ffff, complete_low_w}) :
                {32'd0, extended_load_w};
            assign store_bits_w = store_data_r;
        end else begin : g_single
            wire unused_high_w;
            assign unused_high_w = ^high_r;
            assign selected_store_w = store_data_r;
            assign lsu_complete_data_o = fp_r ? complete_low_w : extended_load_w;
            assign commit_lsu_done_data_o = fp_r ? complete_low_w : extended_load_w;
            assign store_bits_w = {32'd0, store_data_r};
        end
    endgenerate
    always @(*) begin
        extended_load_w = complete_low_w;
        case (funct3_r)
            3'd0: extended_load_w = {{24{complete_low_w[7]}}, complete_low_w[7:0]};
            3'd1: extended_load_w = {{16{complete_low_w[15]}}, complete_low_w[15:0]};
            3'd4: extended_load_w = {24'd0, complete_low_w[7:0]};
            3'd5: extended_load_w = {16'd0, complete_low_w[15:0]};
            default: extended_load_w = complete_low_w;
        endcase
    end
    assign early_selected_w = dc_early_hit_i[1] ? dc_early_way1_data_i :
        dc_early_way0_data_i;
    always @(*) begin
        early_extended_w = early_selected_w;
        case (early_funct3_w)
            3'd0: early_extended_w = {{24{early_selected_w[7]}}, early_selected_w[7:0]};
            3'd1: early_extended_w = {{16{early_selected_w[15]}}, early_selected_w[15:0]};
            3'd4: early_extended_w = {24'd0, early_selected_w[7:0]};
            3'd5: early_extended_w = {16'd0, early_selected_w[15:0]};
            default: early_extended_w = early_selected_w;
        endcase
    end
    assign response_complete_w = state_r == S_RESPONSE && dc_resp_valid_i &&
        (dc_resp_error_i || !double_r || beat_r);
    assign done_fallthrough_w = state_r == S_BEAT_DONE && dc_done_valid_i &&
        (dc_done_error_i || !double_r || beat_r);
    assign complete_low_w = response_complete_w && !beat_r ? response_data_w :
        done_fallthrough_w && !beat_r ? dc_done_data_i : low_r;
    assign complete_high_w = response_complete_w && beat_r ? response_data_w :
        done_fallthrough_w && beat_r ? dc_done_data_i : high_r;
    assign complete_device_w = device_r || (response_complete_w && dc_resp_device_i);
    assign complete_exception_w = response_complete_w ? dc_resp_error_i : exception_r;
    assign complete_access_w = response_complete_w ? dc_resp_error_i : done_error_r;
    assign req_mask_w = req_double_w || req_fp_w || lsu_req_instr_i[13] ? 4'hf :
        lsu_req_instr_i[12] ? 4'h3 : 4'h1;
    assign trace_mask_w = double_r ? 8'hff : {4'd0, mask_w};
    assign trace_bytes_w = {{8{trace_mask_w[7]}}, {8{trace_mask_w[6]}},
        {8{trace_mask_w[5]}}, {8{trace_mask_w[4]}}, {8{trace_mask_w[3]}},
        {8{trace_mask_w[2]}}, {8{trace_mask_w[1]}}, {8{trace_mask_w[0]}}};
    assign trace_bits_w = store_r ? store_bits_w :
        double_r ? {complete_high_w, complete_low_w} : {32'd0, complete_low_w};
    assign lsu_complete_mem_data_o = trace_bits_w & trace_bytes_w;
    assign overlap_w = state_r == S_RESPONSE && !double_r && !device_r;
    assign store_capacity_w = !req_store_w ||
        (req_double_w ? sq_reserved_r <= 2 : sq_reserved_r < SQ_DEPTH);
    assign lsu_req_ready_o = (state_r == S_IDLE || (overlap_w && !queue_valid_r)) &&
        store_capacity_w;
    assign input_fire_w = lsu_req_valid_i && lsu_req_ready_o;
    assign input_cancel_w = cancel_valid_i &&
        ((lsu_req_tag_i - age_head_i) >= cancel_age_w);
    assign queue_cancel_w = cancel_valid_i &&
        ((queue_tag_r - age_head_i) >= cancel_age_w);
    assign active_end_w =
        (response_complete_w && lsu_complete_ready_i &&
        (dc_resp_error_i || !complete_device_w)) ||
        (state_r == S_COMPLETE && lsu_complete_ready_i &&
        (exception_r || !device_r)) ||
        (state_r == S_DONE && commit_lsu_done_ready_i) ||
        (done_fallthrough_w && commit_lsu_done_ready_i);
    assign queue_promote_w = active_end_w && queue_valid_r && !queue_cancel_w && !cancel_w;
    assign input_active_w = input_fire_w && (state_r == S_IDLE || active_end_w) &&
        !input_cancel_w && !(cancel_w && state_r != S_IDLE);
    assign input_queued_w = input_fire_w && !input_active_w && !input_cancel_w && !cancel_w;
    assign queue_request_w = queue_valid_r && !queue_sent_r &&
        (overlap_w || queue_started_r);
    assign front_request_w = queue_request_w || input_fire_w;
    assign front_misaligned_w = queue_request_w ? queue_misaligned_r : misaligned_w;
    assign front_started_w = queue_request_w && queue_started_r;
    assign front_double_w = queue_request_w ? queue_double_r : req_double_w;
    assign front_fp_w = queue_request_w ? queue_fp_r : req_fp_w;
    assign front_size_w = queue_request_w ? queue_funct3_r[1:0] : lsu_req_instr_i[13:12];
    assign front_accept_w = state_r != S_REQUEST && dc_req_valid_o && dc_req_ready_i;
    // A successful registered early result uses no new RAM read (freeze I05b).
    assign early_reuse_w = dc_early_resp_valid_i && dc_req_early_o &&
        dc_req_tag_o == dc_early_resp_tag_i && |dc_early_hit_i;
    assign older_request_w = (state_r == S_REQUEST ||
        (front_request_w && !front_misaligned_w)) && !front_conflict_w &&
        ((dc_req_tag_o - age_head_i) < (early_req_tag_i - age_head_i));
    assign early_block_w = (((state_r == S_REQUEST && request_started_r) ||
        (queue_request_w && queue_started_r) || older_request_w) && !early_reuse_w) ||
        early_conflict_w;
    assign ordinary_valid_w = state_r == S_REQUEST ?
        (request_started_r || older_request_w || !early_req_valid_i || early_reuse_w) :
        front_request_w && !front_misaligned_w &&
        (front_started_w || older_request_w || !early_req_valid_i || early_reuse_w);
    assign early_associate_w = dc_req_valid_o && dc_req_ready_i && dc_req_early_o &&
        dc_req_tag_o == dc_early_resp_tag_i;
    assign early_result_tag_w = early_blocked_r ? early_blocked_tag_r : dc_early_resp_tag_i;
    assign early_funct3_w = lsu_req_valid_i && lsu_req_tag_i == dc_early_resp_tag_i ?
        lsu_req_instr_i[14:12] :
        queue_valid_r && queue_tag_r == dc_early_resp_tag_i ? queue_funct3_r : funct3_r;
    assign lsu_complete_valid_o = state_r == S_COMPLETE || response_complete_w;
    assign lsu_complete_tag_o = tag_r;
    assign lsu_complete_flags_o = 5'd0;
    assign lsu_complete_exception_o = complete_exception_w;
    assign lsu_complete_cause_o = store_r ?
        (complete_access_w ? 4'd7 : 4'd6) : (complete_access_w ? 4'd5 : 4'd4);
    assign lsu_complete_tval_o = response_complete_w && dc_resp_error_i ?
        beat_addr_w : fault_addr_r;
    assign lsu_complete_device_o = complete_device_w;
    assign lsu_complete_mem_addr_o = addr_r;
    assign lsu_complete_mem_mask_o = trace_mask_w;
    assign commit_lsu_ready_o = state_r == S_AUTHORIZE && lsu_store_drained_o;
    assign commit_lsu_done_valid_o = state_r == S_DONE || done_fallthrough_w;
    assign commit_lsu_done_tag_o = tag_r;
    assign commit_lsu_done_error_o = done_fallthrough_w ? dc_done_error_i : done_error_r;
    assign commit_lsu_done_fault_addr_o = done_fallthrough_w && dc_done_error_i ?
        beat_addr_w : fault_addr_r;
    assign dc_req_valid_o = ordinary_valid_w && !front_conflict_w;
    assign dc_req_tag_o = state_r == S_REQUEST ? tag_r :
        queue_request_w ? queue_tag_r : lsu_req_tag_i;
    assign dc_req_beat_o = state_r == S_REQUEST ? beat_r : 1'b0;
    assign dc_req_addr_o = state_r == S_REQUEST ? beat_addr_w :
        queue_request_w ? queue_addr_r : lsu_req_addr_i;
    assign dc_req_store_o = state_r == S_REQUEST ? store_r :
        queue_request_w ? queue_store_r : req_store_w;
    assign dc_req_size_o = state_r == S_REQUEST ?
        (double_r || fp_r ? 2'd2 : funct3_r[1:0]) :
        (front_double_w || front_fp_w ? 2'd2 : front_size_w);
    assign dc_req_data_o = state_r == S_REQUEST ? selected_store_w :
        queue_request_w ? queue_data_r[31:0] : lsu_req_store_data_i[31:0];
    assign dc_req_mask_o = state_r == S_REQUEST ? mask_w :
        queue_request_w ? (queue_double_r || queue_fp_r || queue_funct3_r[1] ? 4'hf :
        queue_funct3_r[0] ? 4'h3 : 4'h1) : req_mask_w;
    assign dc_req_early_o = state_r == S_REQUEST ? early_r && !beat_r :
        queue_request_w ? queue_early_r : lsu_req_early_i;
    assign dc_resp_ready_o = state_r == S_RESPONSE;
    // I06P: the registered authorization state can forward its granted first beat.
    assign serial_store_w = state_r == S_COMMIT ||
        (state_r == S_AUTHORIZE && commit_lsu_valid_i && commit_lsu_ready_o &&
        (store_r || device_r));
    assign sq_output_w = sq_valid_r[sq_head_r] && sq_committed_r[sq_head_r];
    assign dc_commit_valid_o = sq_output_w || serial_store_w;
    assign dc_commit_tag_o = sq_output_w ? sq_tag_w[sq_head_r] : tag_r;
    assign dc_commit_beat_o = sq_output_w ? sq_beat_w[sq_head_r] :
        state_r == S_AUTHORIZE ? 1'b0 : beat_r;
    assign dc_commit_data_o = sq_output_w ? sq_data_w[sq_head_r] :
        state_r == S_AUTHORIZE ? store_data_r[31:0] : selected_store_w;
    assign dc_commit_mask_o = sq_output_w ? sq_mask_w[sq_head_r] : mask_w;
    assign dc_done_ready_o = state_r == S_BEAT_DONE;
    assign dc_cancel_valid_o = cancel_valid_i;
    assign dc_cancel_tag_o = cancel_tag_i;
    assign dc_age_head_o = age_head_i;
    assign dc_early_valid_o = early_req_valid_i && !early_block_w;
    assign dc_early_addr_o = early_req_addr_i;
    assign dc_early_tag_o = early_req_tag_i;
    assign early_resp_valid_o = early_valid_r;
    assign early_resp_tag_o = early_tag_r;
    assign early_resp_hit_o = early_hit_r;
    assign early_resp_data_o = early_data_r;
    // Tags/beat on returned channels follow the accepted single-instruction contract.
    assign unused_w = ^{dc_resp_way_hit_i[0], dc_resp_tag_i, dc_resp_beat_i,
        dc_done_tag_i, dc_done_beat_i,
        commit_lsu_tag_i, lsu_req_instr_i[31:15], lsu_req_instr_i[11:6],
        lsu_req_instr_i[4:3], lsu_req_instr_i[1:0]};

    assign lsu_store_drained_o = sq_committed_count_r == 0;
    assign front_age_w = dc_req_tag_o - age_head_i;
    assign query_age_w = early_req_tag_i - age_head_i;
    assign store_input_w = input_fire_w && req_store_w && !misaligned_w &&
        !input_cancel_w && !(cancel_w && state_r != S_IDLE);
    assign prepared_store_w = state_r == S_RESPONSE && dc_resp_valid_i && store_r && !cancel_w;
    assign sq_enqueue_w = prepared_store_w && !dc_resp_device_i && !dc_resp_error_i;
    assign prepared_release_w = !prepared_store_w ? 2'd0 :
        dc_resp_error_i ? active_store_left_r : dc_resp_device_i ? 2'd1 : 2'd0;
    assign active_release_w = cancel_w && state_r != S_IDLE ? active_store_left_r : 2'd0;
    assign queued_release_w = queue_valid_r && queue_cancel_w ? queue_store_left_r : 2'd0;
    assign sq_drain_w = sq_output_w && dc_commit_ready_i;
    assign sq_cancel_count_w = {2'd0,sq_cancel_w[0]} + {2'd0,sq_cancel_w[1]} +
        {2'd0,sq_cancel_w[2]} + {2'd0,sq_cancel_w[3]};
    assign sq_mark_count_w = {2'd0,sq_mark_w[0]} + {2'd0,sq_mark_w[1]} +
        {2'd0,sq_mark_w[2]} + {2'd0,sq_mark_w[3]};
    assign sq_keep_count_w = sq_count_r - sq_cancel_count_w;
    assign front_conflict_w = |sq_index_conflict_w || (!dc_req_store_o &&
        ((|sq_load_conflict_w) || (state_r != S_IDLE && store_r &&
        addr_r[31:2] == dc_req_addr_o[31:2] && dc_req_tag_o != tag_r)));
    assign early_conflict_w = |sq_early_conflict_w ||
        (state_r != S_IDLE && store_r && addr_r[31:2] == early_req_addr_i[31:2] &&
        early_req_tag_i != tag_r);
    genvar sq;
    genvar sq_other;
    genvar sq_chunk;
    generate
        for (sq = 0; sq < SQ_DEPTH; sq = sq + 1) begin : g_store_queue
            localparam [1:0] SQ_INDEX = sq;
            wire next_valid_w = sq_enqueue_w && sq_tail_r == SQ_INDEX ? 1'b1 :
                (sq_drain_w && sq_head_r == SQ_INDEX) || sq_cancel_w[sq] ? 1'b0 : sq_valid_r[sq];
            assign {sq_tag_w[sq],sq_beat_w[sq],sq_last_w[sq],sq_addr_w[sq],
                sq_data_w[sq],sq_mask_w[sq]} = sq_payload_w[sq];
            // Invalid slots sample existing LSU registers; valid slots retain their records.
            // Five registered leaves per entry, each driving at most sixteen data FFs.
            for (sq_chunk = 0; sq_chunk < (SQ_PAYLOAD+15)/16; sq_chunk = sq_chunk+1) begin : g_data
                localparam CHUNK_WIDTH = SQ_PAYLOAD-sq_chunk*16 < 16 ?
                    SQ_PAYLOAD-sq_chunk*16 : 16;
                (* syn_preserve = 1, syn_keep = 1 *) reg enable_r;
                reg [CHUNK_WIDTH-1:0] data_r;
                always @(posedge clk_i or negedge rst_n_i) begin
                    if (!rst_n_i) enable_r <= 1'b1;
                    else enable_r <= !next_valid_w;
                end
                always @(posedge clk_i) begin
                    if (enable_r) data_r <= sq_payload_next_w[sq_chunk*16 +: CHUNK_WIDTH];
                end
                assign sq_payload_w[sq][sq_chunk*16 +: CHUNK_WIDTH] = data_r;
            end
            wire [1:0] position_w = SQ_INDEX - sq_head_r;
            wire [3:0] older_last_w;
            wire [2:0] older_count_w;
            assign sq_age_w[sq] = sq_tag_w[sq] - age_head_i;
            assign sq_cancel_w[sq] = sq_valid_r[sq] && !sq_committed_r[sq] &&
                cancel_valid_i && sq_age_w[sq] >= cancel_age_w;
            assign sq_load_conflict_w[sq] = sq_valid_r[sq] &&
                (sq_committed_r[sq] || sq_age_w[sq] < front_age_w) &&
                sq_addr_w[sq][31:2] == dc_req_addr_o[31:2];
            assign sq_early_conflict_w[sq] = sq_valid_r[sq] &&
                (sq_committed_r[sq] || sq_age_w[sq] < query_age_w) &&
                sq_addr_w[sq][31:2] == early_req_addr_i[31:2];
            assign sq_index_conflict_w[sq] = sq_valid_r[sq] &&
                sq_tag_w[sq] == dc_req_tag_o && sq_beat_w[sq] == dc_req_beat_o;
            for (sq_other = 0; sq_other < SQ_DEPTH; sq_other = sq_other + 1) begin : g_older
                localparam [1:0] OTHER_INDEX = sq_other;
                wire [1:0] other_position_w = OTHER_INDEX - sq_head_r;
                assign older_last_w[sq_other] = sq_valid_r[sq_other] &&
                    !sq_committed_r[sq_other] && sq_last_w[sq_other] &&
                    other_position_w < position_w;
            end
            assign older_count_w = {2'd0,older_last_w[0]} + {2'd0,older_last_w[1]} +
                {2'd0,older_last_w[2]} + {2'd0,older_last_w[3]};
            assign sq_mark_w[sq] = sq_valid_r[sq] && !sq_committed_r[sq] &&
                older_count_w < {1'b0,commit_store_count_i};
        end
    endgenerate
    integer sq_i;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            sq_valid_r <= 4'd0;
            sq_committed_r <= 4'd0;
            sq_head_r <= 2'd0;
            sq_tail_r <= 2'd0;
            sq_count_r <= 3'd0;
            sq_reserved_r <= 3'd0;
            sq_committed_count_r <= 3'd0;
        end else begin
            sq_count_r <= sq_keep_count_w + {2'd0,sq_enqueue_w} - {2'd0,sq_drain_w};
            sq_reserved_r <= sq_reserved_r + (store_input_w ?
                (req_double_w ? 3'd2 : 3'd1) : 3'd0) - {2'd0,sq_drain_w} -
                sq_cancel_count_w - {1'b0,prepared_release_w} -
                {1'b0,active_release_w} - {1'b0,queued_release_w};
            sq_committed_count_r <= sq_committed_count_r + sq_mark_count_w - {2'd0,sq_drain_w};
            for (sq_i = 0; sq_i < SQ_DEPTH; sq_i = sq_i + 1) begin
                if (sq_cancel_w[sq_i]) sq_valid_r[sq_i] <= 1'b0;
                if (sq_mark_w[sq_i]) sq_committed_r[sq_i] <= 1'b1;
            end
            if (sq_drain_w) begin
                sq_valid_r[sq_head_r] <= 1'b0;
                sq_committed_r[sq_head_r] <= 1'b0;
                sq_head_r <= sq_head_r + 1'b1;
            end
            if (sq_enqueue_w) begin
                sq_valid_r[sq_tail_r] <= 1'b1;
                sq_committed_r[sq_tail_r] <= 1'b0;
            end
            if (sq_enqueue_w || |sq_cancel_w)
                sq_tail_r <= sq_head_r + sq_keep_count_w[1:0] + {1'b0,sq_enqueue_w};
        end
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            queue_valid_r <= 1'b0;
            queue_sent_r <= 1'b0;
            queue_started_r <= 1'b0;
            active_store_left_r <= 2'd0;
            queue_store_left_r <= 2'd0;
            request_started_r <= 1'b0;
            early_blocked_r <= 1'b0;
            beat_r <= 1'b0;
            device_r <= 1'b0;
            exception_r <= 1'b0;
            done_error_r <= 1'b0;
            early_valid_r <= 1'b0;
        end else begin
            if (queue_cancel_w) begin
                queue_valid_r <= 1'b0;
                queue_store_left_r <= 2'd0;
            end
            if (prepared_store_w)
                active_store_left_r <= dc_resp_error_i ? 2'd0 : active_store_left_r-1'b1;
            if (queue_request_w && dc_req_valid_o) begin
                queue_started_r <= !dc_req_ready_i;
                if (dc_req_ready_i) queue_sent_r <= 1'b1;
            end
            if (input_queued_w) begin
                queue_valid_r <= 1'b1;
                queue_sent_r <= front_accept_w;
                queue_started_r <= dc_req_valid_o && !dc_req_ready_i;
                queue_store_left_r <= req_store_w && !misaligned_w ?
                    (req_double_w ? 2'd2 : 2'd1) : 2'd0;
            end
            if (queue_promote_w) queue_valid_r <= 1'b0;
            early_valid_r <= dc_early_resp_valid_i || early_blocked_r;
            early_blocked_r <= early_req_valid_i && early_block_w &&
                !(cancel_valid_i && ((early_req_tag_i - age_head_i) >= cancel_age_w));
            if (cancel_valid_i &&
                ((early_result_tag_w - age_head_i) >= cancel_age_w))
                early_valid_r <= 1'b0;
            if ((cancel_w && state_r != S_IDLE) ||
                (state_r == S_IDLE && lsu_req_valid_i && cancel_valid_i &&
                ((lsu_req_tag_i - age_head_i) >= cancel_age_w))) begin
                state_r <= S_IDLE;
                queue_valid_r <= 1'b0;
                active_store_left_r <= 2'd0;
                queue_store_left_r <= 2'd0;
            end else begin
                case (state_r)
                    S_IDLE: begin end
                    S_REQUEST: begin
                        if (dc_req_valid_o) begin
                            request_started_r <= !dc_req_ready_i;
                            if (dc_req_ready_i) state_r <= S_RESPONSE;
                        end
                    end
                    S_RESPONSE: begin
                        if (dc_resp_valid_i) begin
                            device_r <= device_r || dc_resp_device_i;
                            if (dc_resp_error_i) begin
                                exception_r <= 1'b1;
                                done_error_r <= 1'b1;
                            end
                            if (!dc_resp_error_i && double_r && !beat_r) begin
                                beat_r <= 1'b1;
                                request_started_r <= 1'b0;
                                state_r <= S_REQUEST;
                            end else if (lsu_complete_ready_i) begin
                                state_r <= !dc_resp_error_i &&
                                    complete_device_w ?
                                    S_AUTHORIZE : S_IDLE;
                            end else begin
                                state_r <= S_COMPLETE;
                            end
                        end
                    end
                    S_COMPLETE: begin
                        if (lsu_complete_ready_i) begin
                            if (!exception_r && device_r)
                                state_r <= S_AUTHORIZE;
                            else
                                state_r <= S_IDLE;
                        end
                    end
                    S_AUTHORIZE: begin
                        if (commit_lsu_valid_i && commit_lsu_ready_o) begin
                            beat_r <= 1'b0;
                            state_r <= store_r || device_r ?
                                (dc_commit_ready_i ? S_BEAT_DONE : S_COMMIT) : S_DONE;
                        end
                    end
                    S_COMMIT: if (dc_commit_ready_i) state_r <= S_BEAT_DONE;
                    S_BEAT_DONE: begin
                        if (dc_done_valid_i) begin
                            done_error_r <= dc_done_error_i;
                            if (!dc_done_error_i && double_r && !beat_r) begin
                                beat_r <= 1'b1;
                                state_r <= S_COMMIT;
                            end else begin
                                state_r <= commit_lsu_done_ready_i ? S_IDLE : S_DONE;
                            end
                        end
                    end
                    S_DONE: if (commit_lsu_done_ready_i) state_r <= S_IDLE;
                    default: begin end
                endcase
                // Replace an outgoing response on its capture edge; no ready feedback.
                begin
                    if (queue_promote_w || input_active_w) begin
                        active_store_left_r <= queue_promote_w ? queue_store_left_r :
                            req_store_w && !misaligned_w ? (req_double_w ? 2'd2 : 2'd1) : 2'd0;
                        beat_r <= 1'b0;
                        device_r <= 1'b0;
                        exception_r <= queue_promote_w ? queue_misaligned_r : misaligned_w;
                        done_error_r <= 1'b0;
                        request_started_r <= queue_promote_w ?
                            queue_started_r && !front_accept_w :
                            dc_req_valid_o && !dc_req_ready_i;
                        if (queue_promote_w)
                            state_r <= queue_misaligned_r ? S_COMPLETE :
                                queue_sent_r || front_accept_w ? S_RESPONSE : S_REQUEST;
                        else
                            state_r <= misaligned_w ? S_COMPLETE :
                                front_accept_w ? S_RESPONSE : S_REQUEST;
                    end
                end
            end
        end
    end
    always @(posedge clk_i) begin
        if (input_queued_w) begin
            queue_tag_r <= lsu_req_tag_i;
            queue_addr_r <= lsu_req_addr_i;
            queue_data_r <= lsu_req_store_data_i;
            queue_funct3_r <= lsu_req_instr_i[14:12];
            queue_store_r <= req_store_w;
            queue_fp_r <= req_fp_w;
            queue_double_r <= req_double_w;
            queue_early_r <= lsu_req_early_i;
            queue_misaligned_r <= misaligned_w;
        end
        if (queue_promote_w) begin
            tag_r <= queue_tag_r;
            addr_r <= queue_addr_r;
            store_data_r <= queue_data_r;
            funct3_r <= queue_funct3_r;
            store_r <= queue_store_r;
            fp_r <= queue_fp_r;
            double_r <= queue_double_r;
            early_r <= queue_early_r;
            fault_addr_r <= queue_addr_r;
        end else if (input_active_w) begin
            tag_r <= lsu_req_tag_i;
            addr_r <= lsu_req_addr_i;
            store_data_r <= lsu_req_store_data_i;
            funct3_r <= lsu_req_instr_i[14:12];
            store_r <= req_store_w;
            fp_r <= req_fp_w;
            double_r <= req_double_w;
            early_r <= lsu_req_early_i;
            fault_addr_r <= lsu_req_addr_i;
        end
        if (state_r == S_RESPONSE && dc_resp_valid_i) begin
            if (beat_r)
                high_r <= response_data_w;
            else
                low_r <= response_data_w;
            if (dc_resp_error_i && !(queue_promote_w || input_active_w))
                fault_addr_r <= beat_addr_w;
        end
        if (state_r == S_BEAT_DONE && dc_done_valid_i) begin
            if (beat_r)
                high_r <= dc_done_data_i;
            else
                low_r <= dc_done_data_i;
            if (dc_done_error_i && !(queue_promote_w || input_active_w))
                fault_addr_r <= beat_addr_w;
        end
        early_blocked_tag_r <= early_req_tag_i;
        early_tag_r <= early_result_tag_w;
        early_hit_r <= !early_blocked_r && early_associate_w && |dc_early_hit_i;
        early_data_r <= early_blocked_r ? 32'd0 : early_extended_w;
    end
endmodule
