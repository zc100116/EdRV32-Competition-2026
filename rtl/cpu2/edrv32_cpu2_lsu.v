// File: edrv32_cpu2_lsu.v
// Spec: cpu-v2-spec 3.7, 5.2, 5.6, 6; fpu-spec 5.5.
// Description: Single instruction LSU holds preparation, head authorization and beat completion.
// Hit completion falls through to MEM capture; blocked results stay local. Clock: clk_sys.
module edrv32_cpu2_lsu #(
    parameter [31:0] FPU_FORMAT = "NONE"
) (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Issued instruction and correlated early query.
    input wire lsu_req_valid_i,
    output wire lsu_req_ready_o,
    input wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] lsu_req_tag_i,
    input wire [31:0] lsu_req_instr_i,
    input wire [31:0] lsu_req_addr_i,
    input wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] lsu_req_store_data_i,
    input wire lsu_req_early_i,
    input wire early_req_valid_i,
    input wire [31:0] early_req_addr_i,
    input wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] early_req_tag_i,
    output wire early_resp_valid_o,
    output wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] early_resp_tag_o,
    output wire early_resp_hit_o,
    output wire [31:0] early_resp_data_o,

    // Completion and architectural memory trace.
    output wire lsu_complete_valid_o,
    input wire lsu_complete_ready_i,
    output wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] lsu_complete_tag_o,
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
    input wire commit_lsu_valid_i,
    output wire commit_lsu_ready_o,
    input wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] commit_lsu_tag_i,
    output wire commit_lsu_done_valid_o,
    input wire commit_lsu_done_ready_i,
    output wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] commit_lsu_done_tag_o,
    output wire commit_lsu_done_error_o,
    output wire [31:0] commit_lsu_done_fault_addr_o,
    output wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] commit_lsu_done_data_o,

    // Dcache preparation and beat completion.
    output wire dc_req_valid_o,
    input wire dc_req_ready_i,
    output wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] dc_req_tag_o,
    output wire dc_req_beat_o,
    output wire [31:0] dc_req_addr_o,
    output wire dc_req_store_o,
    output wire [1:0] dc_req_size_o,
    output wire [31:0] dc_req_data_o,
    output wire [3:0] dc_req_mask_o,
    output wire dc_req_early_o,
    input wire dc_resp_valid_i,
    output wire dc_resp_ready_o,
    input wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] dc_resp_tag_i,
    input wire dc_resp_beat_i,
    input wire [1:0] dc_resp_way_hit_i,
    input wire [31:0] dc_resp_way0_data_i,
    input wire [31:0] dc_resp_way1_data_i,
    input wire dc_resp_error_i,
    input wire dc_resp_device_i,
    output wire dc_commit_valid_o,
    input wire dc_commit_ready_i,
    output wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] dc_commit_tag_o,
    output wire dc_commit_beat_o,
    output wire [31:0] dc_commit_data_o,
    output wire [3:0] dc_commit_mask_o,
    input wire dc_done_valid_i,
    output wire dc_done_ready_o,
    input wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] dc_done_tag_i,
    input wire dc_done_beat_i,
    input wire dc_done_error_i,
    input wire [31:0] dc_done_data_i,

    // Dcache early query.
    output wire dc_early_valid_o,
    output wire [31:0] dc_early_addr_o,
    output wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] dc_early_tag_o,
    input wire dc_early_resp_valid_i,
    input wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] dc_early_resp_tag_i,
    input wire [1:0] dc_early_hit_i,
    input wire [31:0] dc_early_way0_data_i,
    input wire [31:0] dc_early_way1_data_i,

    // Age cancellation.
    input wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] age_head_i,
    input wire cancel_valid_i,
    input wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] cancel_tag_i,
    output wire dc_cancel_valid_o,
    output wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] dc_cancel_tag_o,
    output wire [(FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2)-1:0] dc_age_head_o
);
    localparam T = FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2;
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
    assign early_block_w = state_r == S_REQUEST && request_started_r;
    assign ordinary_valid_w = state_r == S_REQUEST ?
        (request_started_r || !early_req_valid_i) : state_r == S_IDLE &&
        lsu_req_valid_i && !misaligned_w && !early_req_valid_i;
    assign early_associate_w = dc_req_valid_o && dc_req_ready_i && dc_req_early_o &&
        dc_req_tag_o == dc_early_resp_tag_i;
    assign early_result_tag_w = early_blocked_r ? early_blocked_tag_r : dc_early_resp_tag_i;
    assign early_funct3_w = lsu_req_valid_i && lsu_req_tag_i == dc_early_resp_tag_i ?
        lsu_req_instr_i[14:12] : funct3_r;
    assign lsu_req_ready_o = state_r == S_IDLE;
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
    assign commit_lsu_ready_o = state_r == S_AUTHORIZE;
    assign commit_lsu_done_valid_o = state_r == S_DONE || done_fallthrough_w;
    assign commit_lsu_done_tag_o = tag_r;
    assign commit_lsu_done_error_o = done_fallthrough_w ? dc_done_error_i : done_error_r;
    assign commit_lsu_done_fault_addr_o = done_fallthrough_w && dc_done_error_i ?
        beat_addr_w : fault_addr_r;
    assign dc_req_valid_o = ordinary_valid_w;
    assign dc_req_tag_o = state_r == S_IDLE ? lsu_req_tag_i : tag_r;
    assign dc_req_beat_o = state_r == S_IDLE ? 1'b0 : beat_r;
    assign dc_req_addr_o = state_r == S_IDLE ? lsu_req_addr_i : beat_addr_w;
    assign dc_req_store_o = state_r == S_IDLE ? req_store_w : store_r;
    assign dc_req_size_o = state_r == S_IDLE ?
        (req_double_w || req_fp_w ? 2'd2 : lsu_req_instr_i[13:12]) :
        (double_r || fp_r ? 2'd2 : funct3_r[1:0]);
    assign dc_req_data_o = state_r == S_IDLE ? lsu_req_store_data_i[31:0] : selected_store_w;
    assign dc_req_mask_o = state_r == S_IDLE ? req_mask_w : mask_w;
    assign dc_req_early_o = state_r == S_IDLE ? lsu_req_early_i : early_r && !beat_r;
    assign dc_resp_ready_o = state_r == S_RESPONSE;
    // I06P: the registered authorization state can forward its granted first beat.
    assign dc_commit_valid_o = state_r == S_COMMIT ||
        (state_r == S_AUTHORIZE && commit_lsu_valid_i && (store_r || device_r));
    assign dc_commit_tag_o = tag_r;
    assign dc_commit_beat_o = state_r == S_AUTHORIZE ? 1'b0 : beat_r;
    assign dc_commit_data_o = state_r == S_AUTHORIZE ?
        store_data_r[31:0] : selected_store_w;
    assign dc_commit_mask_o = mask_w;
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

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            request_started_r <= 1'b0;
            early_blocked_r <= 1'b0;
            beat_r <= 1'b0;
            device_r <= 1'b0;
            exception_r <= 1'b0;
            done_error_r <= 1'b0;
            early_valid_r <= 1'b0;
        end else begin
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
            end else begin
                case (state_r)
                    S_IDLE: begin
                        if (lsu_req_valid_i) begin
                            beat_r <= 1'b0;
                            device_r <= 1'b0;
                            exception_r <= misaligned_w;
                            done_error_r <= 1'b0;
                            request_started_r <= dc_req_valid_o && !dc_req_ready_i;
                            state_r <= misaligned_w ? S_COMPLETE :
                                dc_req_valid_o && dc_req_ready_i ? S_RESPONSE : S_REQUEST;
                        end
                    end
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
                                    (store_r || complete_device_w || double_r) ?
                                    S_AUTHORIZE : S_IDLE;
                            end else begin
                                state_r <= S_COMPLETE;
                            end
                        end
                    end
                    S_COMPLETE: begin
                        if (lsu_complete_ready_i) begin
                            if (!exception_r && (store_r || device_r || double_r))
                                state_r <= S_AUTHORIZE;
                            else
                                state_r <= S_IDLE;
                        end
                    end
                    S_AUTHORIZE: begin
                        if (commit_lsu_valid_i) begin
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
            end
        end
    end
    always @(posedge clk_i) begin
        if (state_r == S_IDLE && lsu_req_valid_i) begin
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
            if (dc_resp_error_i)
                fault_addr_r <= beat_addr_w;
        end
        if (state_r == S_BEAT_DONE && dc_done_valid_i) begin
            if (beat_r)
                high_r <= dc_done_data_i;
            else
                low_r <= dc_done_data_i;
            if (dc_done_error_i)
                fault_addr_r <= beat_addr_w;
        end
        early_blocked_tag_r <= early_req_tag_i;
        early_tag_r <= early_result_tag_w;
        early_hit_r <= !early_blocked_r && early_associate_w && |dc_early_hit_i;
        early_data_r <= early_blocked_r ? 32'd0 : early_extended_w;
    end
endmodule
