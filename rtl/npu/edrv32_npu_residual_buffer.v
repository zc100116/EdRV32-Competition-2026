// File: edrv32_npu_residual_buffer.v
// Spec: npu-spec 2.3, 5.2, 5.5; npu-datapath design 4.2.2, 4.2.4.
// Description: Two 16-beat residual banks, committed in begin order. Pair reservation
// advances independently of the Q10 reads that return bank ownership to the loader.
// Clock: clk_npu.
module edrv32_npu_residual_buffer (
    // Clock and control.
    input wire clk_i,
    input wire rst_n_i,
    input wire cancel_i,

    // Residual DMA loader.
    input wire residual_begin_valid_i,
    output wire residual_begin_ready_o,
    input wire residual_begin_bank_i,
    input wire [4:0] residual_begin_pairs_i,
    input wire residual_begin_half_i,
    input wire residual_wr_valid_i,
    input wire residual_wr_bank_i,
    input wire [3:0] residual_wr_index_i,
    input wire [255:0] residual_wr_data_i,
    input wire residual_commit_i,

    // Pair reservation and quantization read port.
    input wire pair_half_i,
    input wire pair_reserve_i,
    output wire pair_residual_ready_o,
    output wire [4:0] pair_residual_addr_o,
    input wire residual_rd_en_i,
    input wire [4:0] residual_rd_addr_i,
    output wire residual_rd_valid_o,
    output wire [255:0] residual_rd_data_o,

    // Local status.
    output wire idle_o
);
    reg [1:0] occupied_r;
    reg [1:0] committed_r;
    reg loading_bank_r;
    reg queue_bank_r [0:1];
    reg queue_head_r;
    reg queue_tail_r;
    reg [1:0] queue_count_r;
    reg [4:0] pairs_left_r [0:1];
    reg [4:0] beats_left_r [0:1];
    reg [3:0] pair_index_r [0:1];
    reg [1:0] rd_valid_r;
    wire begin_w;
    wire head_bank_w;
    wire reserve_last_w;
    wire rd_en_w;

    assign begin_w = residual_begin_valid_i && residual_begin_ready_o;
    assign head_bank_w = queue_bank_r[queue_head_r];
    assign reserve_last_w = pair_reserve_i && (pairs_left_r[head_bank_w] == 5'd1);
    assign rd_en_w = residual_rd_en_i && !cancel_i;
    assign residual_begin_ready_o = !occupied_r[residual_begin_bank_i] && !cancel_i;
    assign pair_residual_ready_o = (queue_count_r != 2'd0)
        && committed_r[head_bank_w] && !cancel_i;
    assign pair_residual_addr_o = {head_bank_w, pair_index_r[head_bank_w]};
    assign residual_rd_valid_o = rd_valid_r[1];
    assign idle_o = (occupied_r == 2'b00) && (rd_valid_r == 2'b00);

    // Queue entries retain begin order even when the loader starts with bank 1.
    always @(posedge clk_i) begin
        if (begin_w) begin
            queue_bank_r[queue_tail_r] <= residual_begin_bank_i;
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            loading_bank_r <= 1'b0;
            queue_head_r <= 1'b0;
            queue_tail_r <= 1'b0;
            queue_count_r <= 2'd0;
            rd_valid_r <= 2'b00;
        end else if (cancel_i) begin
            loading_bank_r <= 1'b0;
            queue_head_r <= 1'b0;
            queue_tail_r <= 1'b0;
            queue_count_r <= 2'd0;
            rd_valid_r <= 2'b00;
        end else begin
            rd_valid_r <= {rd_valid_r[0], rd_en_w};
            if (begin_w) begin
                loading_bank_r <= residual_begin_bank_i;
                queue_tail_r <= !queue_tail_r;
            end
            if (reserve_last_w) begin
                queue_head_r <= !queue_head_r;
            end
            case ({begin_w, reserve_last_w})
                2'b10: queue_count_r <= queue_count_r + 2'd1;
                2'b01: queue_count_r <= queue_count_r - 2'd1;
                default: queue_count_r <= queue_count_r;
            endcase
        end
    end

    genvar bank;
    generate
        for (bank = 0; bank < 2; bank = bank + 1) begin : g_bank
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    occupied_r[bank] <= 1'b0;
                    committed_r[bank] <= 1'b0;
                    pairs_left_r[bank] <= 5'd0;
                    beats_left_r[bank] <= 5'd0;
                    pair_index_r[bank] <= 4'd0;
                end else if (cancel_i) begin
                    occupied_r[bank] <= 1'b0;
                    committed_r[bank] <= 1'b0;
                    pairs_left_r[bank] <= 5'd0;
                    beats_left_r[bank] <= 5'd0;
                    pair_index_r[bank] <= 4'd0;
                end else begin
                    if (begin_w && (residual_begin_bank_i == (bank != 0))) begin
                        occupied_r[bank] <= 1'b1;
                        committed_r[bank] <= 1'b0;
                        pairs_left_r[bank] <= residual_begin_pairs_i;
                        beats_left_r[bank] <= residual_begin_half_i
                            ? residual_begin_pairs_i : {residual_begin_pairs_i[3:0], 1'b0};
                        pair_index_r[bank] <= 4'd0;
                    end
                    if (residual_commit_i && (loading_bank_r == (bank != 0))) begin
                        committed_r[bank] <= 1'b1;
                    end
                    if (pair_reserve_i && (head_bank_w == (bank != 0))) begin
                        pairs_left_r[bank] <= pairs_left_r[bank] - 5'd1;
                        pair_index_r[bank] <= pair_index_r[bank]
                            + (pair_half_i ? 4'd1 : 4'd2);
                    end
                    // The last read is safe to overwrite after its array sampling edge.
                    if (rd_en_w && (residual_rd_addr_i[4] == (bank != 0))) begin
                        beats_left_r[bank] <= beats_left_r[bank] - 5'd1;
                        if (beats_left_r[bank] == 5'd1) begin
                            occupied_r[bank] <= 1'b0;
                            committed_r[bank] <= 1'b0;
                        end
                    end
                end
            end
        end
    endgenerate

    edrv32_ram_npu_residual u_residual_ram (
        .clk_i(clk_i),
        .wr_en_i(residual_wr_valid_i && !cancel_i),
        .wr_addr_i({4'b0000, residual_wr_bank_i, residual_wr_index_i}),
        .wr_data_i(residual_wr_data_i),
        .rd_en_i(rd_en_w),
        .rd_addr_i({4'b0000, residual_rd_addr_i}),
        .rd_data_o(residual_rd_data_o)
    );
endmodule
