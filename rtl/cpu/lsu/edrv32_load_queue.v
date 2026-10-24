// ============================================================================
// File        : edrv32_load_queue.v
// Description : Four-entry in-order cacheable-load ownership queue.
// Notes       : A token contains {generation, slot}.  A stale response is
//               always drained but cannot modify a reallocated slot.
// ============================================================================
`include "edrv32_bus.vh"
`include "edrv32_lsu.vh"
`include "edrv32_uop.vh"

module edrv32_load_queue (
    input  wire                         clk_i,
    input  wire                         rst_n_i,

    // MEM1 allocation after PMA and alignment checks.
    input  wire                         alloc_valid_i,
    output wire                         alloc_ready_o,
    output wire [`EDRV32_LSU_TOKEN_W-1:0] alloc_token_o,
    input  wire [31:0]                  alloc_pc_i,
    input  wire [4:0]                   alloc_rd_i,
    input  wire [31:0]                  alloc_addr_i,
    input  wire [`BUS_SZ_W-1:0]         alloc_size_i,
    input  wire                         alloc_unsigned_i,
    input  wire [`EDRV32_EPOCH_W-1:0]   alloc_epoch_i,
    input  wire [`EDRV32_LSU_SEQUENCE_W-1:0] alloc_sequence_i,
    input  wire                         alloc_forward_valid_i,
    input  wire [31:0]                  alloc_forward_data_i,
    input  wire                         alloc_block_valid_i,
    input  wire [`EDRV32_LSU_TOKEN_W-1:0] alloc_block_token_i,

    // A blocking older store has completed its committed drain.
    input  wire                         store_release_valid_i,
    input  wire [`EDRV32_LSU_TOKEN_W-1:0] store_release_token_i,

    // Oldest unissued load request to D-cache.
    output wire                         request_valid_o,
    input  wire                         request_ready_i,
    output wire [`EDRV32_LSU_TOKEN_W-1:0] request_token_o,
    output wire [31:0]                  request_addr_o,
    output wire [`BUS_SZ_W-1:0]         request_size_o,
    output wire                         request_unsigned_o,
    output wire [`EDRV32_LSU_SEQUENCE_W-1:0] request_sequence_o,
    output wire                         pending_valid_o,
    output wire [`EDRV32_LSU_SEQUENCE_W-1:0] pending_sequence_o,

    // Tokenized D-cache response. Unknown/stale tokens are consumed and
    // discarded so a killed miss cannot block later architectural work.
    input  wire                         response_valid_i,
    output wire                         response_ready_o,
    input  wire [`EDRV32_LSU_TOKEN_W-1:0] response_token_i,
    input  wire [31:0]                  response_data_i,
    input  wire                         response_error_i,
    output wire                         completion_valid_o,
    output wire [`EDRV32_LSU_TOKEN_W-1:0] completion_token_o,
    output wire [31:0]                  completion_data_o,
    output wire [31:0]                  completion_pc_o,

    // Oldest in-order load at COMMIT.
    input  wire                         commit_valid_i,
    input  wire [`EDRV32_LSU_TOKEN_W-1:0] commit_token_i,
    output wire                         commit_ready_o,
    output wire [31:0]                  commit_data_o,
    output wire                         commit_error_o,
    input  wire                         commit_fire_i,

    // Decode dependency queries. Every live queue entry is older than the
    // current Decode uop; the youngest matching entry wins.
    input  wire [4:0]                   rs1_addr_i,
    input  wire                         uses_rs1_i,
    output wire                         rs1_match_o,
    output wire                         rs1_ready_o,
    output wire [`EDRV32_LSU_TOKEN_W-1:0] rs1_token_o,
    output wire [31:0]                  rs1_pc_o,
    output wire [31:0]                  rs1_value_o,
    input  wire [4:0]                   rs2_addr_i,
    input  wire                         uses_rs2_i,
    output wire                         rs2_match_o,
    output wire                         rs2_ready_o,
    output wire [`EDRV32_LSU_TOKEN_W-1:0] rs2_token_o,
    output wire [31:0]                  rs2_pc_o,
    output wire [31:0]                  rs2_value_o,

    // Exact token observation for a resident pipeline producer.
    input  wire                         observe_token_valid_i,
    input  wire [`EDRV32_LSU_TOKEN_W-1:0] observe_token_i,
    output wire                         observe_match_o,
    output wire                         observe_ready_o,
    output wire [31:0]                  observe_value_o,

    // Exact token observations for the two operands of the resident EX uop.
    input  wire                         operand0_token_valid_i,
    input  wire [`EDRV32_LSU_TOKEN_W-1:0] operand0_token_i,
    output wire                         operand0_match_o,
    output wire                         operand0_ready_o,
    output wire [31:0]                  operand0_value_o,
    output wire                         operand0_stored_ready_o,
    output wire [31:0]                  operand0_stored_value_o,
    input  wire                         operand1_token_valid_i,
    input  wire [`EDRV32_LSU_TOKEN_W-1:0] operand1_token_i,
    output wire                         operand1_match_o,
    output wire                         operand1_ready_o,
    output wire [31:0]                  operand1_value_o,
    output wire                         operand1_stored_ready_o,
    output wire [31:0]                  operand1_stored_value_o,

    // Persistent EX probes for consumers that entered before or after the
    // one-cycle completion pulse. PC is the existing producer identity.
    input  wire [31:0]                  probe0_pc_i,
    output wire                         probe0_ready_o,
    output wire [31:0]                  probe0_value_o,
    input  wire [31:0]                  probe1_pc_i,
    output wire                         probe1_ready_o,
    output wire [31:0]                  probe1_value_o,

    input  wire                         flush_i,
    output wire                         empty_o,
    output wire                         full_o
);

    reg [3:0] valid_r;
    reg [3:0] generation_r;
    reg [3:0] issued_r;
    reg [3:0] done_r;
    reg [3:0] blocked_r;
    reg [`EDRV32_LSU_TOKEN_W-1:0] block_token_r [0:3];
    reg [1:0] head_r;
    reg [1:0] tail_r;
    reg [2:0] count_r;

    reg [31:0] pc_r [0:3];
    reg [4:0] rd_r [0:3];
    reg [31:0] addr_r [0:3];
    reg [`BUS_SZ_W-1:0] size_r [0:3];
    reg unsigned_r [0:3];
    reg [`EDRV32_EPOCH_W-1:0] epoch_r [0:3];
    reg [`EDRV32_LSU_SEQUENCE_W-1:0] sequence_r [0:3];
    reg [31:0] data_r [0:3];
    reg error_r [0:3];

    wire alloc_fire_w = alloc_valid_i && alloc_ready_o;
    wire older_unissued_w = |(valid_r & ~issued_r);
    wire request_alloc_bypass_w = !older_unissued_w && alloc_valid_i && alloc_ready_o &&
                                  !alloc_forward_valid_i &&
                                  !alloc_block_valid_i;
    reg request_found_w;
    reg [1:0] request_slot_w;
    reg pending_found_w;
    reg [1:0] pending_slot_w;
    reg rs1_match_w;
    reg [1:0] rs1_slot_w;
    reg rs2_match_w;
    reg [1:0] rs2_slot_w;
    reg [1:0] scan_slot_w;
    integer scan_i;
    always @(*) begin
        request_found_w = 1'b0;
        request_slot_w = head_r;
        pending_found_w = 1'b0;
        pending_slot_w = head_r;
        rs1_match_w = 1'b0;
        rs1_slot_w = head_r;
        rs2_match_w = 1'b0;
        rs2_slot_w = head_r;
        scan_slot_w = head_r;
        for (scan_i = 0; scan_i < 4; scan_i = scan_i + 1) begin
            scan_slot_w = head_r + scan_i[1:0];
            if ((scan_i < count_r) && valid_r[scan_slot_w]) begin
                if (!issued_r[scan_slot_w]) begin
                    if (!pending_found_w) begin
                        pending_found_w = 1'b1;
                        pending_slot_w = scan_slot_w;
                    end
                end
                if (uses_rs1_i && (rs1_addr_i != 5'd0) &&
                    (rd_r[scan_slot_w] == rs1_addr_i)) begin
                    rs1_match_w = 1'b1;
                    rs1_slot_w = scan_slot_w;
                end
                if (uses_rs2_i && (rs2_addr_i != 5'd0) &&
                    (rd_r[scan_slot_w] == rs2_addr_i)) begin
                    rs2_match_w = 1'b1;
                    rs2_slot_w = scan_slot_w;
                end
            end
        end
        // A blocked older load retains issue priority.  A younger request
        // cannot pass it merely because the older request is not yet valid.
        request_found_w = pending_found_w && !blocked_r[pending_slot_w];
        request_slot_w = pending_slot_w;
    end

    // Probe each physical entry in parallel.  Only the four-bit priority
    // choice depends on head_r; a pointer-controlled PC mux must not precede
    // the 32-bit comparison on the EX late-load bypass path.
    wire [3:0] probe0_hit_w;
    wire [3:0] probe1_hit_w;
    assign probe0_hit_w[0] = valid_r[0] && (pc_r[0] == probe0_pc_i);
    assign probe0_hit_w[1] = valid_r[1] && (pc_r[1] == probe0_pc_i);
    assign probe0_hit_w[2] = valid_r[2] && (pc_r[2] == probe0_pc_i);
    assign probe0_hit_w[3] = valid_r[3] && (pc_r[3] == probe0_pc_i);
    assign probe1_hit_w[0] = valid_r[0] && (pc_r[0] == probe1_pc_i);
    assign probe1_hit_w[1] = valid_r[1] && (pc_r[1] == probe1_pc_i);
    assign probe1_hit_w[2] = valid_r[2] && (pc_r[2] == probe1_pc_i);
    assign probe1_hit_w[3] = valid_r[3] && (pc_r[3] == probe1_pc_i);

    function [3:0] select_newest_hit;
        input [3:0] hit;
        input [1:0] head;
        begin
            select_newest_hit = 4'b0000;
            case (head)
                2'd0: begin
                    if (hit[3]) select_newest_hit = 4'b1000;
                    else if (hit[2]) select_newest_hit = 4'b0100;
                    else if (hit[1]) select_newest_hit = 4'b0010;
                    else if (hit[0]) select_newest_hit = 4'b0001;
                end
                2'd1: begin
                    if (hit[0]) select_newest_hit = 4'b0001;
                    else if (hit[3]) select_newest_hit = 4'b1000;
                    else if (hit[2]) select_newest_hit = 4'b0100;
                    else if (hit[1]) select_newest_hit = 4'b0010;
                end
                2'd2: begin
                    if (hit[1]) select_newest_hit = 4'b0010;
                    else if (hit[0]) select_newest_hit = 4'b0001;
                    else if (hit[3]) select_newest_hit = 4'b1000;
                    else if (hit[2]) select_newest_hit = 4'b0100;
                end
                default: begin
                    if (hit[2]) select_newest_hit = 4'b0100;
                    else if (hit[1]) select_newest_hit = 4'b0010;
                    else if (hit[0]) select_newest_hit = 4'b0001;
                    else if (hit[3]) select_newest_hit = 4'b1000;
                end
            endcase
        end
    endfunction
    wire [3:0] probe0_select_w = select_newest_hit(probe0_hit_w, head_r);
    wire [3:0] probe1_select_w = select_newest_hit(probe1_hit_w, head_r);
    wire [3:0] probe_available_w;
    assign probe_available_w[0] = done_r[0] && !error_r[0];
    assign probe_available_w[1] = done_r[1] && !error_r[1];
    assign probe_available_w[2] = done_r[2] && !error_r[2];
    assign probe_available_w[3] = done_r[3] && !error_r[3];

    // Ready is a direct priority mux.  Computing a one-hot select first and
    // reducing it with done would add another level before EX can execute.
    function select_newest_ready;
        input [3:0] hit;
        input [3:0] available;
        input [1:0] head;
        begin
            select_newest_ready = 1'b0;
            case (head)
                2'd0: begin
                    if (hit[3]) select_newest_ready = available[3];
                    else if (hit[2]) select_newest_ready = available[2];
                    else if (hit[1]) select_newest_ready = available[1];
                    else if (hit[0]) select_newest_ready = available[0];
                end
                2'd1: begin
                    if (hit[0]) select_newest_ready = available[0];
                    else if (hit[3]) select_newest_ready = available[3];
                    else if (hit[2]) select_newest_ready = available[2];
                    else if (hit[1]) select_newest_ready = available[1];
                end
                2'd2: begin
                    if (hit[1]) select_newest_ready = available[1];
                    else if (hit[0]) select_newest_ready = available[0];
                    else if (hit[3]) select_newest_ready = available[3];
                    else if (hit[2]) select_newest_ready = available[2];
                end
                default: begin
                    if (hit[2]) select_newest_ready = available[2];
                    else if (hit[1]) select_newest_ready = available[1];
                    else if (hit[0]) select_newest_ready = available[0];
                    else if (hit[3]) select_newest_ready = available[3];
                end
            endcase
        end
    endfunction

    wire [1:0] selected_request_slot_w = request_alloc_bypass_w
        ? tail_r : request_slot_w;
    wire request_fire_w = request_valid_o && request_ready_i;
    wire [1:0] response_slot_w = response_token_i[1:0];
    wire [`EDRV32_LSU_TOKEN_W-1:0] response_entry_token_w = {
        generation_r[response_slot_w], response_slot_w
    };
    wire response_match_w = valid_r[response_slot_w] &&
                            issued_r[response_slot_w] &&
                            !done_r[response_slot_w] &&
                            (response_entry_token_w == response_token_i);
    wire response_fire_w = response_valid_i && response_ready_o;
    wire response_complete_w = response_fire_w && response_match_w;
    wire rs1_response_ready_w = response_complete_w &&
        (response_slot_w == rs1_slot_w) && !response_error_i;
    wire rs2_response_ready_w = response_complete_w &&
        (response_slot_w == rs2_slot_w) && !response_error_i;
    wire [`EDRV32_LSU_TOKEN_W-1:0] head_token_w = {
        generation_r[head_r], head_r
    };
    wire commit_match_w = valid_r[head_r] &&
                          (commit_token_i == head_token_w);
    wire commit_release_w = commit_valid_i && commit_fire_i &&
                            commit_ready_o;

    assign empty_o = count_r == 3'd0;
    assign full_o = count_r == 3'd4;
    assign alloc_ready_o = !full_o;
    assign alloc_token_o = {~generation_r[tail_r], tail_r};

    assign request_valid_o = request_alloc_bypass_w || request_found_w;
    // Issued older loads may remain here until COMMIT. They do not require
    // another cache request, so a new allocation can launch on the same edge.
    // An older unissued (including store-blocked) load always keeps priority.
    // The mux selects from registered ownership/issue bits, keeping the late
    // allocation handshake out of the address/sequence arbitration datapath.
    wire request_payload_from_alloc_w = !older_unissued_w;
    assign request_token_o = request_payload_from_alloc_w ? alloc_token_o :
        {generation_r[request_slot_w], request_slot_w};
    assign request_addr_o = request_payload_from_alloc_w ? alloc_addr_i :
        addr_r[request_slot_w];
    assign request_size_o = request_payload_from_alloc_w ? alloc_size_i :
        size_r[request_slot_w];
    assign request_unsigned_o = request_payload_from_alloc_w
        ? alloc_unsigned_i : unsigned_r[request_slot_w];
    assign request_sequence_o = request_payload_from_alloc_w
        ? alloc_sequence_i : sequence_r[request_slot_w];
    assign pending_valid_o = pending_found_w;
    assign pending_sequence_o = sequence_r[pending_slot_w];

    assign response_ready_o = 1'b1;
    assign completion_valid_o = response_complete_w && !response_error_i;
    assign completion_token_o = response_token_i;
    assign completion_data_o = response_data_i;
    assign completion_pc_o = pc_r[response_slot_w];

    assign commit_ready_o = commit_valid_i && commit_match_w &&
                            done_r[head_r];
    assign commit_data_o = data_r[head_r];
    assign commit_error_o = error_r[head_r];

    assign rs1_match_o = rs1_match_w;
    assign rs1_ready_o = rs1_match_o &&
        ((done_r[rs1_slot_w] && !error_r[rs1_slot_w]) ||
         rs1_response_ready_w);
    assign rs1_token_o = {generation_r[rs1_slot_w], rs1_slot_w};
    assign rs1_pc_o = pc_r[rs1_slot_w];
    assign rs1_value_o = rs1_response_ready_w
        ? response_data_i : data_r[rs1_slot_w];

    assign rs2_match_o = rs2_match_w;
    assign rs2_ready_o = rs2_match_o &&
        ((done_r[rs2_slot_w] && !error_r[rs2_slot_w]) ||
         rs2_response_ready_w);
    assign rs2_token_o = {generation_r[rs2_slot_w], rs2_slot_w};
    assign rs2_pc_o = pc_r[rs2_slot_w];
    assign rs2_value_o = rs2_response_ready_w
        ? response_data_i : data_r[rs2_slot_w];

    wire [1:0] observe_slot_w = observe_token_i[1:0];
    wire [`EDRV32_LSU_TOKEN_W-1:0] observe_entry_token_w = {
        generation_r[observe_slot_w], observe_slot_w
    };
    wire observe_response_ready_w = response_complete_w &&
        (response_slot_w == observe_slot_w) && !response_error_i;
    assign observe_match_o = observe_token_valid_i &&
        valid_r[observe_slot_w] &&
        (observe_entry_token_w == observe_token_i);
    assign observe_ready_o = observe_match_o &&
        ((done_r[observe_slot_w] && !error_r[observe_slot_w]) ||
         observe_response_ready_w);
    assign observe_value_o = observe_response_ready_w
        ? response_data_i : data_r[observe_slot_w];

    wire [1:0] operand0_slot_w = operand0_token_i[1:0];
    wire [`EDRV32_LSU_TOKEN_W-1:0] operand0_entry_token_w = {
        generation_r[operand0_slot_w], operand0_slot_w
    };
    wire operand0_response_ready_w = response_complete_w &&
        (response_slot_w == operand0_slot_w) && !response_error_i;
    assign operand0_match_o = operand0_token_valid_i &&
        valid_r[operand0_slot_w] &&
        (operand0_entry_token_w == operand0_token_i);
    assign operand0_ready_o = operand0_match_o &&
        ((done_r[operand0_slot_w] && !error_r[operand0_slot_w]) ||
         operand0_response_ready_w);
    assign operand0_value_o = operand0_response_ready_w
        ? response_data_i : data_r[operand0_slot_w];
    assign operand0_stored_ready_o = operand0_match_o &&
        done_r[operand0_slot_w] && !error_r[operand0_slot_w];
    assign operand0_stored_value_o = data_r[operand0_slot_w];

    wire [1:0] operand1_slot_w = operand1_token_i[1:0];
    wire [`EDRV32_LSU_TOKEN_W-1:0] operand1_entry_token_w = {
        generation_r[operand1_slot_w], operand1_slot_w
    };
    wire operand1_response_ready_w = response_complete_w &&
        (response_slot_w == operand1_slot_w) && !response_error_i;
    assign operand1_match_o = operand1_token_valid_i &&
        valid_r[operand1_slot_w] &&
        (operand1_entry_token_w == operand1_token_i);
    assign operand1_ready_o = operand1_match_o &&
        ((done_r[operand1_slot_w] && !error_r[operand1_slot_w]) ||
         operand1_response_ready_w);
    assign operand1_value_o = operand1_response_ready_w
        ? response_data_i : data_r[operand1_slot_w];
    assign operand1_stored_ready_o = operand1_match_o &&
        done_r[operand1_slot_w] && !error_r[operand1_slot_w];
    assign operand1_stored_value_o = data_r[operand1_slot_w];

    assign probe0_ready_o = select_newest_ready(
        probe0_hit_w, probe_available_w, head_r);
    assign probe0_value_o =
        (data_r[0] & {32{probe0_select_w[0]}}) |
        (data_r[1] & {32{probe0_select_w[1]}}) |
        (data_r[2] & {32{probe0_select_w[2]}}) |
        (data_r[3] & {32{probe0_select_w[3]}});

    assign probe1_ready_o = select_newest_ready(
        probe1_hit_w, probe_available_w, head_r);
    assign probe1_value_o =
        (data_r[0] & {32{probe1_select_w[0]}}) |
        (data_r[1] & {32{probe1_select_w[1]}}) |
        (data_r[2] & {32{probe1_select_w[2]}}) |
        (data_r[3] & {32{probe1_select_w[3]}});

    // Queue occupancy, pointers, validity and generation share one owner.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            valid_r <= 4'b0000;
            generation_r <= 4'b0000;
            head_r <= 2'd0;
            tail_r <= 2'd0;
            count_r <= 3'd0;
        end else if (flush_i) begin
            valid_r <= 4'b0000;
            head_r <= 2'd0;
            tail_r <= 2'd0;
            count_r <= 3'd0;
        end else begin
            if (alloc_fire_w) begin
                valid_r[tail_r] <= 1'b1;
                generation_r[tail_r] <= ~generation_r[tail_r];
                tail_r <= tail_r + 2'd1;
            end
            if (commit_release_w) begin
                valid_r[head_r] <= 1'b0;
                head_r <= head_r + 2'd1;
            end
            case ({alloc_fire_w, commit_release_w})
                2'b10: count_r <= count_r + 3'd1;
                2'b01: count_r <= count_r - 3'd1;
                default: begin end
            endcase
        end
    end

    // Request and completion state is observable only while valid_r is set.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            issued_r <= 4'b0000;
            done_r <= 4'b0000;
            blocked_r <= 4'b0000;
        end else if (flush_i) begin
            issued_r <= 4'b0000;
            done_r <= 4'b0000;
            blocked_r <= 4'b0000;
        end else begin
            if (alloc_fire_w) begin
                issued_r[tail_r] <= alloc_forward_valid_i;
                done_r[tail_r] <= alloc_forward_valid_i;
                blocked_r[tail_r] <= alloc_block_valid_i &&
                    !(store_release_valid_i &&
                      (store_release_token_i == alloc_block_token_i));
                block_token_r[tail_r] <= alloc_block_token_i;
            end
            if (request_fire_w)
                issued_r[selected_request_slot_w] <= 1'b1;
            if (response_complete_w)
                done_r[response_slot_w] <= 1'b1;
            if (store_release_valid_i) begin
                if (valid_r[0] && blocked_r[0] &&
                    (block_token_r[0] == store_release_token_i))
                    blocked_r[0] <= 1'b0;
                if (valid_r[1] && blocked_r[1] &&
                    (block_token_r[1] == store_release_token_i))
                    blocked_r[1] <= 1'b0;
                if (valid_r[2] && blocked_r[2] &&
                    (block_token_r[2] == store_release_token_i))
                    blocked_r[2] <= 1'b0;
                if (valid_r[3] && blocked_r[3] &&
                    (block_token_r[3] == store_release_token_i))
                    blocked_r[3] <= 1'b0;
            end
            if (commit_release_w) begin
                issued_r[head_r] <= 1'b0;
                done_r[head_r] <= 1'b0;
                blocked_r[head_r] <= 1'b0;
            end
        end
    end

    // Entry payload is written only on allocation or a matching response.
    always @(posedge clk_i) begin
        if (alloc_fire_w) begin
            pc_r[tail_r] <= alloc_pc_i;
            rd_r[tail_r] <= alloc_rd_i;
            addr_r[tail_r] <= alloc_addr_i;
            size_r[tail_r] <= alloc_size_i;
            unsigned_r[tail_r] <= alloc_unsigned_i;
            epoch_r[tail_r] <= alloc_epoch_i;
            sequence_r[tail_r] <= alloc_sequence_i;
            if (alloc_forward_valid_i) begin
                data_r[tail_r] <= alloc_forward_data_i;
                error_r[tail_r] <= 1'b0;
            end
        end
        if (response_complete_w) begin
            data_r[response_slot_w] <= response_data_i;
            error_r[response_slot_w] <= response_error_i;
        end
    end

endmodule
