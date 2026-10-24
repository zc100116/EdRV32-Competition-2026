// ============================================================================
// File        : edrv32_store_queue.v
// Description : Four-entry speculative Store Queue and two-entry commit buffer.
// Notes       : Prepare is side-effect-free and may report a precise error.
//               COMMIT copies successful stores into the committed buffer;
//               its later D-cache write survives a younger-pipeline flush.
// ============================================================================
`include "edrv32_bus.vh"
`include "edrv32_lsu.vh"
`include "edrv32_uop.vh"

module edrv32_store_queue (
    input  wire                         clk_i,
    input  wire                         rst_n_i,

    input  wire                         alloc_valid_i,
    output wire                         alloc_ready_o,
    output wire [`EDRV32_LSU_TOKEN_W-1:0] alloc_token_o,
    input  wire [31:0]                  alloc_pc_i,
    input  wire [31:0]                  alloc_addr_i,
    input  wire [3:0]                   alloc_wstrb_i,
    input  wire [31:0]                  alloc_wdata_i,
    input  wire [`EDRV32_EPOCH_W-1:0]   alloc_epoch_i,
    input  wire [`EDRV32_LSU_SEQUENCE_W-1:0] alloc_sequence_i,

    // Side-effect-free tag/miss/error preparation.
    output wire                         prepare_valid_o,
    input  wire                         prepare_ready_i,
    output wire [`EDRV32_LSU_TOKEN_W-1:0] prepare_token_o,
    output wire [31:0]                  prepare_addr_o,
    output wire [`EDRV32_LSU_SEQUENCE_W-1:0] prepare_sequence_o,
    input  wire                         prepare_response_valid_i,
    output wire                         prepare_response_ready_o,
    input  wire [`EDRV32_LSU_TOKEN_W-1:0] prepare_response_token_i,
    input  wire                         prepare_response_error_i,
    input  wire                         prepare_cancel_valid_i,
    input  wire [`EDRV32_LSU_TOKEN_W-1:0] prepare_cancel_token_i,

    // Oldest uncommitted store reaches architectural COMMIT.
    input  wire                         commit_valid_i,
    input  wire [`EDRV32_LSU_TOKEN_W-1:0] commit_token_i,
    output wire                         commit_ready_o,
    output wire                         commit_error_o,
    input  wire                         commit_fire_i,

    // Oldest committed store applies its already-prepared cache-line update.
    output wire                         drain_valid_o,
    input  wire                         drain_ready_i,
    output wire [`EDRV32_LSU_TOKEN_W-1:0] drain_token_o,
    output wire [31:0]                  drain_addr_o,
    output wire [3:0]                   drain_wstrb_o,
    output wire [31:0]                  drain_wdata_o,
    input  wire                         drain_response_valid_i,
    output wire                         drain_response_ready_o,
    input  wire [`EDRV32_LSU_TOKEN_W-1:0] drain_response_token_i,
    input  wire                         drain_response_error_i,
    output wire                         async_error_o,

    // A younger load checks the newest older store at the same word address.
    input  wire                         load_query_valid_i,
    input  wire [31:0]                  load_query_addr_i,
    input  wire [`BUS_SZ_W-1:0]         load_query_size_i,
    input  wire                         load_query_unsigned_i,
    output wire                         load_match_o,
    output wire                         load_forward_ready_o,
    output wire [31:0]                  load_forward_data_o,
    output wire [`EDRV32_LSU_TOKEN_W-1:0] load_match_token_o,

    output wire                         release_valid_o,
    output wire [`EDRV32_LSU_TOKEN_W-1:0] release_token_o,

    // Flush removes speculative entries only. Committed stores must drain.
    input  wire                         flush_i,
    output wire                         empty_o,
    output wire                         full_o,
    output wire                         committed_empty_o,
    output wire [1:0]                   committed_reservation_count_o
);

    // Speculative entries leave at architectural COMMIT.  The small committed
    // buffer owns the physical D-cache write and survives a younger flush.
    reg [3:0] valid_r;
    reg [3:0] generation_r;
    reg [3:0] prepare_issued_r;
    reg [3:0] prepared_r;
    reg [3:0] prepare_error_r;
    reg [1:0] head_r;
    reg [1:0] tail_r;
    reg [2:0] count_r;

    reg [31:0] pc_r [0:3];
    reg [31:0] addr_r [0:3];
    reg [3:0] wstrb_r [0:3];
    reg [31:0] wdata_r [0:3];
    reg [`EDRV32_EPOCH_W-1:0] epoch_r [0:3];
    reg [`EDRV32_LSU_SEQUENCE_W-1:0] sequence_r [0:3];

    reg [1:0] committed_issued_r;
    reg committed_head_r;
    reg committed_tail_r;
    reg [1:0] committed_count_r;
    reg [`EDRV32_LSU_TOKEN_W-1:0] committed_token_r [0:1];
    reg [31:0] committed_addr_r [0:1];
    reg [3:0] committed_wstrb_r [0:1];
    reg [31:0] committed_wdata_r [0:1];

    wire alloc_fire_w = alloc_valid_i && alloc_ready_o;
    assign full_o = count_r == 3'd4;
    assign empty_o = (count_r == 3'd0) &&
                     (committed_count_r == 2'd0);
    assign committed_empty_o = committed_count_r == 2'd0;
    wire committed_second_slot_w = ~committed_head_r;
    assign committed_reservation_count_o =
        (((committed_count_r != 2'd0) &&
          !committed_issued_r[committed_head_r]) ? 2'd1 : 2'd0) +
        (((committed_count_r == 2'd2) &&
          !committed_issued_r[committed_second_slot_w]) ? 2'd1 : 2'd0);
    assign alloc_ready_o = !full_o;
    assign alloc_token_o = {~generation_r[tail_r], tail_r};

    reg prepare_found_w;
    reg [1:0] prepare_slot_w;
    reg [1:0] scan_slot_w;
    integer scan_i;
    always @(*) begin
        prepare_found_w = 1'b0;
        prepare_slot_w = head_r;
        scan_slot_w = head_r;
        for (scan_i = 0; scan_i < 4; scan_i = scan_i + 1) begin
            scan_slot_w = head_r + scan_i[1:0];
            if ((scan_i < count_r) && valid_r[scan_slot_w] &&
                !prepare_issued_r[scan_slot_w] &&
                !prepared_r[scan_slot_w] && !prepare_found_w) begin
                prepare_found_w = 1'b1;
                prepare_slot_w = scan_slot_w;
            end
        end
    end
    assign prepare_valid_o = prepare_found_w;
    assign prepare_token_o = {
        generation_r[prepare_slot_w], prepare_slot_w
    };
    assign prepare_addr_o = addr_r[prepare_slot_w];
    assign prepare_sequence_o = sequence_r[prepare_slot_w];
    wire prepare_fire_w = prepare_valid_o && prepare_ready_i;

    wire [1:0] prepare_response_slot_w =
        prepare_response_token_i[1:0];
    wire [`EDRV32_LSU_TOKEN_W-1:0] prepare_response_entry_token_w = {
        generation_r[prepare_response_slot_w], prepare_response_slot_w
    };
    wire prepare_response_match_w =
        valid_r[prepare_response_slot_w] &&
        prepare_issued_r[prepare_response_slot_w] &&
        !prepared_r[prepare_response_slot_w] &&
        (prepare_response_entry_token_w == prepare_response_token_i);
    wire prepare_response_fire_w = prepare_response_valid_i &&
                                   prepare_response_ready_o;
    assign prepare_response_ready_o = 1'b1;

    wire [1:0] prepare_cancel_slot_w = prepare_cancel_token_i[1:0];
    wire [`EDRV32_LSU_TOKEN_W-1:0] prepare_cancel_entry_token_w = {
        generation_r[prepare_cancel_slot_w], prepare_cancel_slot_w
    };
    wire prepare_cancel_match_w = prepare_cancel_valid_i &&
        valid_r[prepare_cancel_slot_w] &&
        (prepare_cancel_entry_token_w == prepare_cancel_token_i);

    wire [`EDRV32_LSU_TOKEN_W-1:0] commit_entry_token_w = {
        generation_r[head_r], head_r
    };
    wire commit_match_w = valid_r[head_r] &&
                          (commit_token_i == commit_entry_token_w);
    wire committed_room_w = committed_count_r != 2'd2;
    assign commit_ready_o = commit_valid_i && commit_match_w &&
                            prepared_r[head_r] &&
                            (prepare_error_r[head_r] || committed_room_w);
    assign commit_error_o = prepare_error_r[head_r];
    wire commit_accept_w = commit_fire_i && commit_ready_o;
    wire committed_push_w = commit_accept_w && !commit_error_o;

    assign drain_valid_o = (committed_count_r != 2'd0) &&
                           !committed_issued_r[committed_head_r];
    assign drain_token_o = committed_token_r[committed_head_r];
    assign drain_addr_o = committed_addr_r[committed_head_r];
    assign drain_wstrb_o = committed_wstrb_r[committed_head_r];
    assign drain_wdata_o = committed_wdata_r[committed_head_r];
    wire drain_fire_w = drain_valid_o && drain_ready_i;
    assign drain_response_ready_o = 1'b1;
    wire drain_complete_w = drain_response_valid_i &&
        (committed_count_r != 2'd0) &&
        (drain_response_token_i == committed_token_r[committed_head_r]) &&
        (committed_issued_r[committed_head_r] || drain_fire_w);
    assign async_error_o = drain_complete_w && drain_response_error_i;
    assign release_valid_o = drain_complete_w;
    assign release_token_o = committed_token_r[committed_head_r];

    reg [3:0] load_required_mask_w;
    always @(*) begin
        case (load_query_size_i)
            `BUS_SZ_BYTE: load_required_mask_w =
                4'b0001 << load_query_addr_i[1:0];
            `BUS_SZ_HALF: load_required_mask_w = load_query_addr_i[1]
                ? 4'b1100 : 4'b0011;
            default: load_required_mask_w = 4'b1111;
        endcase
    end

    // Committed entries precede every speculative entry.  Walking each
    // segment oldest to newest makes the last overlapping Store the winner.
    reg load_match_w;
    reg [3:0] load_match_mask_w;
    reg [31:0] load_match_data_w;
    reg [`EDRV32_LSU_TOKEN_W-1:0] load_match_token_w;
    reg committed_scan_slot_w;
    reg [1:0] speculative_scan_slot_w;
    integer query_i;
    always @(*) begin
        load_match_w = 1'b0;
        load_match_mask_w = 4'b0000;
        load_match_data_w = 32'd0;
        load_match_token_w = {`EDRV32_LSU_TOKEN_W{1'b0}};
        committed_scan_slot_w = committed_head_r;
        speculative_scan_slot_w = head_r;
        for (query_i = 0; query_i < 2; query_i = query_i + 1) begin
            committed_scan_slot_w = committed_head_r + query_i[0];
            if (load_query_valid_i && (query_i < committed_count_r) &&
                (committed_addr_r[committed_scan_slot_w][31:2] ==
                 load_query_addr_i[31:2]) &&
                (|(committed_wstrb_r[committed_scan_slot_w] &
                   load_required_mask_w))) begin
                load_match_w = 1'b1;
                load_match_mask_w = committed_wstrb_r[committed_scan_slot_w];
                load_match_data_w = committed_wdata_r[committed_scan_slot_w];
                load_match_token_w = committed_token_r[committed_scan_slot_w];
            end
        end
        for (query_i = 0; query_i < 4; query_i = query_i + 1) begin
            speculative_scan_slot_w = head_r + query_i[1:0];
            if (load_query_valid_i && (query_i < count_r) &&
                valid_r[speculative_scan_slot_w] &&
                (addr_r[speculative_scan_slot_w][31:2] ==
                 load_query_addr_i[31:2]) &&
                (|(wstrb_r[speculative_scan_slot_w] &
                   load_required_mask_w))) begin
                load_match_w = 1'b1;
                load_match_mask_w = wstrb_r[speculative_scan_slot_w];
                load_match_data_w = wdata_r[speculative_scan_slot_w];
                load_match_token_w = {
                    generation_r[speculative_scan_slot_w],
                    speculative_scan_slot_w
                };
            end
        end
    end
    assign load_match_o = load_match_w;
    assign load_forward_ready_o = load_match_w &&
        ((load_match_mask_w & load_required_mask_w) ==
         load_required_mask_w);
    assign load_match_token_o = load_match_token_w;

    reg [7:0] load_forward_byte_w;
    reg [15:0] load_forward_half_w;
    reg [31:0] load_forward_value_w;
    always @(*) begin
        case (load_query_addr_i[1:0])
            2'd0: load_forward_byte_w = load_match_data_w[7:0];
            2'd1: load_forward_byte_w = load_match_data_w[15:8];
            2'd2: load_forward_byte_w = load_match_data_w[23:16];
            default: load_forward_byte_w = load_match_data_w[31:24];
        endcase
        load_forward_half_w = load_query_addr_i[1]
            ? load_match_data_w[31:16] : load_match_data_w[15:0];
        case (load_query_size_i)
            `BUS_SZ_BYTE: load_forward_value_w = load_query_unsigned_i
                ? {24'd0, load_forward_byte_w}
                : {{24{load_forward_byte_w[7]}}, load_forward_byte_w};
            `BUS_SZ_HALF: load_forward_value_w = load_query_unsigned_i
                ? {16'd0, load_forward_half_w}
                : {{16{load_forward_half_w[15]}}, load_forward_half_w};
            default: load_forward_value_w = load_match_data_w;
        endcase
    end
    assign load_forward_data_o = load_forward_value_w;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            valid_r <= 4'b0000;
            generation_r <= 4'b0000;
            prepare_issued_r <= 4'b0000;
            prepared_r <= 4'b0000;
            prepare_error_r <= 4'b0000;
            head_r <= 2'd0;
            tail_r <= 2'd0;
            count_r <= 3'd0;
        end else if (flush_i) begin
            valid_r <= 4'b0000;
            prepare_issued_r <= 4'b0000;
            prepared_r <= 4'b0000;
            prepare_error_r <= 4'b0000;
            head_r <= 2'd0;
            tail_r <= 2'd0;
            count_r <= 3'd0;
        end else begin
            if (commit_accept_w) begin
                valid_r[head_r] <= 1'b0;
                prepare_issued_r[head_r] <= 1'b0;
                prepared_r[head_r] <= 1'b0;
                prepare_error_r[head_r] <= 1'b0;
                head_r <= head_r + 2'd1;
            end
            if (alloc_fire_w) begin
                valid_r[tail_r] <= 1'b1;
                generation_r[tail_r] <= ~generation_r[tail_r];
                prepare_issued_r[tail_r] <= 1'b0;
                prepared_r[tail_r] <= 1'b0;
                prepare_error_r[tail_r] <= 1'b0;
                tail_r <= tail_r + 2'd1;
            end
            if (prepare_fire_w)
                prepare_issued_r[prepare_slot_w] <= 1'b1;
            if (prepare_response_fire_w && prepare_response_match_w) begin
                prepared_r[prepare_response_slot_w] <= 1'b1;
                prepare_error_r[prepare_response_slot_w] <=
                    prepare_response_error_i;
            end
            if (prepare_cancel_match_w) begin
                prepare_issued_r[prepare_cancel_slot_w] <= 1'b0;
                prepared_r[prepare_cancel_slot_w] <= 1'b0;
                prepare_error_r[prepare_cancel_slot_w] <= 1'b0;
            end
            case ({alloc_fire_w, commit_accept_w})
                2'b10: count_r <= count_r + 3'd1;
                2'b01: count_r <= count_r - 3'd1;
                default: begin end
            endcase
        end
    end

    always @(posedge clk_i) begin
        if (alloc_fire_w) begin
            pc_r[tail_r] <= alloc_pc_i;
            addr_r[tail_r] <= alloc_addr_i;
            wstrb_r[tail_r] <= alloc_wstrb_i;
            wdata_r[tail_r] <= alloc_wdata_i;
            epoch_r[tail_r] <= alloc_epoch_i;
            sequence_r[tail_r] <= alloc_sequence_i;
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            committed_issued_r <= 2'b00;
            committed_head_r <= 1'b0;
            committed_tail_r <= 1'b0;
            committed_count_r <= 2'd0;
        end else begin
            if (drain_fire_w)
                committed_issued_r[committed_head_r] <= 1'b1;
            if (drain_complete_w) begin
                committed_issued_r[committed_head_r] <= 1'b0;
                committed_head_r <= ~committed_head_r;
            end
            if (committed_push_w) begin
                committed_issued_r[committed_tail_r] <= 1'b0;
                committed_tail_r <= ~committed_tail_r;
            end
            case ({committed_push_w, drain_complete_w})
                2'b10: committed_count_r <= committed_count_r + 2'd1;
                2'b01: committed_count_r <= committed_count_r - 2'd1;
                default: begin end
            endcase
        end
    end

    always @(posedge clk_i) begin
        if (committed_push_w) begin
            committed_token_r[committed_tail_r] <= commit_entry_token_w;
            committed_addr_r[committed_tail_r] <= addr_r[head_r];
            committed_wstrb_r[committed_tail_r] <= wstrb_r[head_r];
            committed_wdata_r[committed_tail_r] <= wdata_r[head_r];
        end
    end

    wire unused_payload_w = ^{pc_r[head_r], epoch_r[head_r]};

endmodule
