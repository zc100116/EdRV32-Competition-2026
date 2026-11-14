// File: edrv32_npu_writeback.v
// Spec: npu-spec 5.2, 5.4, 5.5; npu-datapath design 4.2.2, 4.2.4, 4.8.
// Description: A 32-pair result ring reserves credit at pair first, completes at WB2,
// and releases only with the granted DMA chunk. Chunk metadata retains command order.
// Clock: clk_npu.
module edrv32_npu_writeback (
    // Clock and control.
    input wire clk_i,
    input wire rst_n_i,
    input wire cancel_i,

    // Pair reservation and WB2 completion.
    input wire writeback_valid_i,
    input wire [48:0] writeback_tag_i,
    input wire [511:0] writeback_data_i,
    input wire pair_reserve_i,
    output wire [4:0] pair_result_slot_o,
    output wire [5:0] result_credit_o,

    // Ordered chunk grant and return of ownership.
    output wire result_chunk_valid_o,
    input wire result_chunk_ready_i,
    output wire [4:0] result_chunk_base_o,
    output wire [4:0] result_chunk_pairs_o,
    output wire [11:0] result_chunk_row_o,
    output wire [2:0] result_chunk_block_o,
    output wire [10:0] result_chunk_pair_o,
    output wire result_chunk_half_o,
    output wire result_chunk_last_o,
    input wire result_release_i,

    // DMA read port; low/high five-bit copies address the two 256-bit RAM halves.
    input wire result_rd_en_i,
    input wire [9:0] result_rd_index_i,
    input wire result_rd_plane_i,
    output wire result_rd_valid_o,
    output wire [255:0] result_rd_data_o,

    // Command completion and local status.
    output reg cmd_done_o,
    output reg [11:0] cmd_done_row_o,
    output reg [2:0] cmd_done_block_o,
    output wire idle_o
);
    reg [4:0] reserve_slot_r;
    reg [5:0] credit_r;
    reg [4:0] chunk_count_r;
    reg [31:0] chunk_start_r;
    reg [37:0] chunk_queue_r [0:31];
    reg [4:0] chunk_head_r;
    reg [4:0] chunk_tail_r;
    reg [5:0] chunk_queued_r;
    reg chunk_granted_r;
    reg [1:0] rd_valid_r;
    reg rd_plane_array_r;
    (* keep = "true", syn_preserve = 1 *) reg [3:0] rd_plane_output_r;
    wire complete_w;
    wire chunk_complete_w;
    wire chunk_grant_w;
    wire rd_en_w;
    wire [31:0] chunk_start_w;
    wire [511:0] rd_data_w;
    wire [15:0] unused_tag_w;

    assign unused_tag_w = {writeback_tag_i[48:43], writeback_tag_i[36:27]};
    assign complete_w = writeback_valid_i && !cancel_i;
    assign chunk_complete_w = complete_w
        && ((chunk_count_r == 5'd15) || writeback_tag_i[37]);
    assign chunk_start_w = (chunk_count_r == 5'd0)
        ? {writeback_tag_i[42:38], writeback_tag_i[11:0], writeback_tag_i[14:12],
            writeback_tag_i[25:15], writeback_tag_i[26]} : chunk_start_r;
    assign chunk_grant_w = result_chunk_valid_o && result_chunk_ready_i;
    assign rd_en_w = result_rd_en_i && !cancel_i;
    assign pair_result_slot_o = reserve_slot_r;
    assign result_credit_o = credit_r;
    assign result_chunk_valid_o = (chunk_queued_r != 6'd0) && !chunk_granted_r
        && !cancel_i;
    assign {result_chunk_base_o, result_chunk_pairs_o, result_chunk_row_o,
        result_chunk_block_o, result_chunk_pair_o, result_chunk_half_o,
        result_chunk_last_o} = chunk_queue_r[chunk_head_r];
    assign result_rd_valid_o = rd_valid_r[1];
    genvar slice;
    generate
        for (slice = 0; slice < 4; slice = slice + 1) begin : g_read_slice
            // Preserve the two-cycle plane tag separately from the classifier label.
            always @(posedge clk_i) begin
                rd_plane_output_r[slice] <= rd_plane_array_r;
            end
            assign result_rd_data_o[64*slice +: 64] = rd_plane_output_r[slice]
                ? rd_data_w[256+64*slice +: 64] : rd_data_w[64*slice +: 64];
        end
    endgenerate
    assign idle_o = (credit_r == 6'd32) && (rd_valid_r == 2'b00);

    // Metadata is payload: ownership counters, not resets, determine its validity.
    always @(posedge clk_i) begin
        if (complete_w && (chunk_count_r == 5'd0)) begin
            chunk_start_r <= chunk_start_w;
        end
        if (chunk_complete_w) begin
            chunk_queue_r[chunk_tail_r] <= {chunk_start_w[31:27], chunk_count_r + 5'd1,
                chunk_start_w[26:0], writeback_tag_i[37]};
        end
        if (complete_w && writeback_tag_i[37]) begin
            cmd_done_row_o <= writeback_tag_i[11:0];
            cmd_done_block_o <= writeback_tag_i[14:12];
        end
        rd_plane_array_r <= result_rd_plane_i;
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            reserve_slot_r <= 5'd0;
            credit_r <= 6'd32;
            chunk_count_r <= 5'd0;
            chunk_head_r <= 5'd0;
            chunk_tail_r <= 5'd0;
            chunk_queued_r <= 6'd0;
            chunk_granted_r <= 1'b0;
            rd_valid_r <= 2'b00;
            cmd_done_o <= 1'b0;
        end else if (cancel_i) begin
            reserve_slot_r <= 5'd0;
            credit_r <= 6'd32;
            chunk_count_r <= 5'd0;
            chunk_head_r <= 5'd0;
            chunk_tail_r <= 5'd0;
            chunk_queued_r <= 6'd0;
            chunk_granted_r <= 1'b0;
            rd_valid_r <= 2'b00;
            cmd_done_o <= 1'b0;
        end else begin
            // spec design 4.8: completion does not release a reserved slot.
            credit_r <= credit_r - {5'd0, pair_reserve_i}
                + (result_release_i ? {1'b0, result_chunk_pairs_o} : 6'd0);
            if (pair_reserve_i) begin
                reserve_slot_r <= reserve_slot_r + 5'd1;
            end
            if (complete_w) begin
                chunk_count_r <= chunk_complete_w ? 5'd0 : chunk_count_r + 5'd1;
            end
            if (chunk_complete_w) begin
                chunk_tail_r <= chunk_tail_r + 5'd1;
            end
            if (result_release_i) begin
                chunk_head_r <= chunk_head_r + 5'd1;
                chunk_granted_r <= 1'b0;
            end else if (chunk_grant_w) begin
                chunk_granted_r <= 1'b1;
            end
            case ({chunk_complete_w, result_release_i})
                2'b10: chunk_queued_r <= chunk_queued_r + 6'd1;
                2'b01: chunk_queued_r <= chunk_queued_r - 6'd1;
                default: chunk_queued_r <= chunk_queued_r;
            endcase
            rd_valid_r <= {rd_valid_r[0], rd_en_w};
            cmd_done_o <= complete_w && writeback_tag_i[37];
        end
    end

    edrv32_ram_npu_result u_result_ram (
        .clk_i(clk_i),
        .wr_en_i(complete_w),
        .wr_addr_i(writeback_tag_i[42:38]),
        .wr_data_i(writeback_data_i),
        .rd_en_i(rd_en_w),
        .rd_addr_i(result_rd_index_i),
        .rd_data_o(rd_data_w)
    );
endmodule
