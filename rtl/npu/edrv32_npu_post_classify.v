// File: edrv32_npu_post_classify.v
// Spec: npu-spec 2.6, 5.2, 5.6.
// Description: Twelve-stage, II=1 two-pixel classification with banked best RAM.
// Plane zero initializes storage; three write histories bypass the two-cycle RAM read.
// Clock: clk_npu.
module edrv32_npu_post_classify (
    // Clock and frame lifetime.
    input wire clk_i,
    input wire rst_n_i,
    input wire clear_i,

    // Result RAM stream and conv_write labels.
    input wire valid_i,
    input wire [255:0] data_i,
    input wire [1:0] head_i,
    input wire [11:0] row_i,
    input wire [10:0] pair_i,
    input wire [2:0] block_i,
    input wire plane_i,
    input wire [26:0] int8_th_i,
    input wire [31:0] prob_th_i,

    // Probability table, two-cycle read.
    output wire prob_en_o,
    output wire [9:0] prob_addr0_o,
    output wire [9:0] prob_addr1_o,
    input wire [31:0] prob_data0_i,
    input wire [31:0] prob_data1_i,

    // Up to two candidates, in left/right input order.
    output wire [1:0] candidate_valid_o,
    output wire [31:0] candidate0_o,
    output wire [31:0] candidate1_o,
    output wire idle_o
);
    function [3:0] class_even;
        input [2:0] index_i;
        begin class_even = {index_i, 1'b0}; end
    endfunction
    function [14:0] ordered_key;
        input [14:0] best_i;
        begin ordered_key = {~best_i[7], best_i[6:0], ~best_i[14:8]}; end
    endfunction
    reg [11:0] valid_r;
    reg [1:0] head_r [0:11];
    reg [2:0] plane_r [0:11];
    reg [11:0] cell_r [0:11];
    reg [12:0] anchor_r [0:11];
    reg [11:0] row_pairs_r;
    reg [10:0] pair_r;
    reg [12:0] base_r;
    reg [7:0] max1_r [0:31];
    reg [11:0] max2_r [0:15];
    reg [11:0] max3_r [0:7];
    reg [11:0] max4_r [0:3];
    reg [14:0] best5_r [0:1];
    reg [14:0] best6_r [0:1];
    reg [14:0] best7_r [0:1];
    (* keep = "true", syn_preserve = 1 *) reg [14:0] best8_r [0:1];
    reg [14:0] old8_r [0:1];
    reg [14:0] best9_r [0:1];
    reg [14:0] best10_r [0:1];
    reg [14:0] best11_r [0:1];
    reg [14:0] best12_r [0:1];
    wire [15:0] ram_w [0:1];
    reg [14:0] old_w [0:1];
    reg [14:0] merged_w [0:1];
    reg [1:0] first10_r;
    reg [1:0] first11_r;
    reg [1:0] pass11_r;
    reg [1:0] pass12_r;
    wire signed [8:0] threshold_w;
    integer stage;
    integer lane;
    assign threshold_w = int8_th_i[9*head_r[10]+:9];
    assign idle_o = !(|valid_r);
    assign prob_en_o = valid_r[7] && plane_r[7] == 3'd4;
    assign prob_addr0_o = {head_r[7], merged_w[0][7:0]};
    assign prob_addr1_o = {head_r[7], merged_w[1][7:0]};
    assign candidate_valid_o = pass12_r & {2{valid_r[11]}};
    // Queue layout: low anchor[12:0], class[6:0], best[7:0], zero[3:0].
    assign candidate0_o = {4'd0, best12_r[0][7:0], best12_r[0][14:8], anchor_r[11]};
    assign candidate1_o = {4'd0, best12_r[1][7:0], best12_r[1][14:8],
        anchor_r[11] + 13'd1};

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) valid_r <= 12'd0;
        else if (clear_i) valid_r <= 12'd0;
        else valid_r <= {valid_r[10:0], valid_i};
    end
    // Payload has no reset. Valid bits own every RAM and queue side effect.
    always @(posedge clk_i) begin
        head_r[0] <= head_i;
        plane_r[0] <= {block_i[1:0], plane_i};
        pair_r <= pair_i;
        row_pairs_r <= (head_i == 2'd0) ? (row_i << 5) + (row_i << 3)
            : (head_i == 2'd1) ? (row_i << 4) + (row_i << 2)
            : (row_i << 3) + (row_i << 1);
        base_r <= (head_i == 2'd0) ? 13'd0 : (head_i == 2'd1) ? 13'd3840 : 13'd4800;
        cell_r[1] <= (row_pairs_r + {1'b0, pair_r}) << 1;
        anchor_r[1] <= base_r;
        anchor_r[2] <= anchor_r[1] + {1'b0, cell_r[1]};
        for (stage = 1; stage < 12; stage = stage + 1) begin
            head_r[stage] <= head_r[stage-1];
            plane_r[stage] <= plane_r[stage-1];
            if (stage > 1) cell_r[stage] <= cell_r[stage-1];
            if (stage > 2) anchor_r[stage] <= anchor_r[stage-1];
        end
        for (lane = 0; lane < 32; lane = lane + 1) max1_r[lane] <= data_i[8*lane+:8];
        for (lane = 0; lane < 16; lane = lane + 1) begin
            max2_r[lane] <= ($signed(max1_r[2*lane]) >= $signed(max1_r[2*lane+1]))
                ? {class_even(lane[2:0]), max1_r[2*lane]}
                : {class_even(lane[2:0]) + 4'd1, max1_r[2*lane+1]};
        end
        for (lane = 0; lane < 8; lane = lane + 1) begin
            max3_r[lane] <= ($signed(max2_r[2*lane][7:0])
                >= $signed(max2_r[2*lane+1][7:0])) ? max2_r[2*lane] : max2_r[2*lane+1];
        end
        for (lane = 0; lane < 4; lane = lane + 1) begin
            max4_r[lane] <= ($signed(max3_r[2*lane][7:0])
                >= $signed(max3_r[2*lane+1][7:0])) ? max3_r[2*lane] : max3_r[2*lane+1];
        end
        for (lane = 0; lane < 2; lane = lane + 1) begin
            best5_r[lane] <= {plane_r[3],
                ($signed(max4_r[2*lane][7:0]) >= $signed(max4_r[2*lane+1][7:0]))
                ? max4_r[2*lane] : max4_r[2*lane+1]};
            best6_r[lane] <= best5_r[lane];
            best7_r[lane] <= best6_r[lane];
            old8_r[lane] <= old_w[lane];
            best8_r[lane] <= best7_r[lane];
            best9_r[lane] <= merged_w[lane];
            best10_r[lane] <= best9_r[lane];
            best11_r[lane] <= best10_r[lane];
            best12_r[lane] <= best11_r[lane];
        end
        first10_r[0] <= plane_r[8] == 3'd4
            && $signed({best9_r[0][7], best9_r[0][7:0]})
                >= $signed(int8_th_i[9*head_r[8]+:9]);
        first10_r[1] <= plane_r[8] == 3'd4
            && $signed({best9_r[1][7], best9_r[1][7:0]})
                >= $signed(int8_th_i[9*head_r[8]+:9]);
        first11_r <= first10_r;
        pass11_r[0] <= {7'd0, prob_data0_i[24:0]} > prob_th_i;
        pass11_r[1] <= {7'd0, prob_data1_i[24:0]} > prob_th_i;
        pass12_r <= pass11_r & first11_r;
    end
    integer pixel;
    always @(*) begin
        for (pixel = 0; pixel < 2; pixel = pixel + 1) begin
            old_w[pixel] = ram_w[pixel][14:0];
            if (valid_r[9] && cell_r[9] == cell_r[6]) old_w[pixel] = best10_r[pixel];
            if (valid_r[8] && cell_r[8] == cell_r[6]) old_w[pixel] = best9_r[pixel];
            if (valid_r[7] && cell_r[7] == cell_r[6]) old_w[pixel] = merged_w[pixel];
        end
    end
    integer merge_pixel;
    always @(*) begin
        for (merge_pixel = 0; merge_pixel < 2; merge_pixel = merge_pixel + 1) begin
            merged_w[merge_pixel] = best8_r[merge_pixel];
            if (plane_r[7] != 3'd0
                && ordered_key(old8_r[merge_pixel]) > ordered_key(best8_r[merge_pixel])) begin
                merged_w[merge_pixel] = old8_r[merge_pixel];
            end
        end
    end
    genvar bank;
    generate
        for (bank = 0; bank < 2; bank = bank + 1) begin : g_best
            edrv32_ram_npu_post_best u_ram (
                .clk_i(clk_i),
                .wr_en_i(valid_r[7]),
                .wr_addr_i(cell_r[7][11:1]),
                .wr_data_i({1'b0, merged_w[bank]}),
                .rd_en_i(valid_r[4]),
                .rd_addr_i(cell_r[4][11:1]),
                .rd_data_o(ram_w[bank])
            );
        end
    endgenerate
    wire unused_labels_w;
    assign unused_labels_w = ^{block_i[2], threshold_w, cell_r[0], anchor_r[0],
        prob_data0_i[31:25], prob_data1_i[31:25]};
endmodule
