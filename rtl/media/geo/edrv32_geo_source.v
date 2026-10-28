// File: edrv32_geo_source.v
// Spec: geo-spec 2.2, 5.2.
// Description: Two source groups, four parity banks each, with simultaneous four-point reads.
// Logical 80x80 coverage uses 96 physical columns to accommodate DDR row-start alignment.
// Clock domain: clk_mem.
module edrv32_geo_source (
    // Clock.
    input wire clk_i,
    // Source fill: aligned DDR words, local row and word indices.
    input wire wr_en_i,
    input wire wr_group_i,
    input wire [6:0] wr_row_i,
    input wire [2:0] wr_word_i,
    input wire [255:0] wr_data_i,
    // Sampling coordinates and source bounds.
    input wire rd_en_i,
    input wire rd_group_i,
    input wire [31:0] x_i,
    input wire [31:0] y_i,
    input wire [11:0] origin_x_i,
    input wire [11:0] origin_y_i,
    input wire [11:0] src_w_i,
    input wire [11:0] src_h_i,
    input wire [15:0] bg_i,
    // Four simultaneous samples, one clock after rd_en.
    output wire [15:0] p00_o,
    output wire [15:0] p01_o,
    output wire [15:0] p10_o,
    output wire [15:0] p11_o
);
    wire signed [16:0] x0_w;
    wire signed [16:0] y0_w;
    wire signed [16:0] x1_w;
    wire signed [16:0] y1_w;
    wire [16:0] local_x_w;
    wire [16:0] local_y_w;
    wire [7:0] wr_addr_w;
    wire [15:0] bank_data_w [0:7];
    reg [3:0] outside_r;
    reg [2:0] select_r;
    wire unused_w;
    assign unused_w = &{x_i[15:0], y_i[15:0], local_x_w[16:7], local_y_w[16:7]};
    assign x0_w = $signed({x_i[31], x_i[31:16]});
    assign y0_w = $signed({y_i[31], y_i[31:16]});
    assign x1_w = x0_w + 17'sd1;
    assign y1_w = y0_w + 17'sd1;
    assign local_x_w = $unsigned(x0_w) - {5'd0, origin_x_i};
    assign local_y_w = $unsigned(y0_w) - {5'd0, origin_y_i};
    assign wr_addr_w = {2'd0, wr_row_i[6:1]} * 8'd6 + {5'd0, wr_word_i};
    assign p00_o = outside_r[0] ? bg_i : bank_data_w[select_r];
    assign p01_o = outside_r[1] ? bg_i : bank_data_w[select_r ^ 3'd1];
    assign p10_o = outside_r[2] ? bg_i : bank_data_w[select_r ^ 3'd2];
    assign p11_o = outside_r[3] ? bg_i : bank_data_w[select_r ^ 3'd3];
    always @(posedge clk_i) begin
        if (rd_en_i) begin
            select_r <= {rd_group_i, local_y_w[0], local_x_w[0]};
            outside_r[0] <= x0_w < 0 || y0_w < 0 ||
                x0_w >= $signed({5'd0, src_w_i}) || y0_w >= $signed({5'd0, src_h_i});
            outside_r[1] <= x1_w < 0 || y0_w < 0 ||
                x1_w >= $signed({5'd0, src_w_i}) || y0_w >= $signed({5'd0, src_h_i});
            outside_r[2] <= x0_w < 0 || y1_w < 0 ||
                x0_w >= $signed({5'd0, src_w_i}) || y1_w >= $signed({5'd0, src_h_i});
            outside_r[3] <= x1_w < 0 || y1_w < 0 ||
                x1_w >= $signed({5'd0, src_w_i}) || y1_w >= $signed({5'd0, src_h_i});
        end
    end
    genvar bank;
    genvar lane;
    generate
        for (bank = 0; bank < 8; bank = bank + 1) begin : g_bank
            localparam X_PARITY = (bank % 2) != 0;
            localparam Y_PARITY = ((bank / 2) % 2) != 0;
            localparam GROUP = (bank / 4) != 0;
            wire [127:0] wr_data_w;
            wire [6:0] sample_x_w;
            wire [6:0] sample_y_w;
            wire [10:0] rd_addr_w;
            wire [6:0] next_x_w;
            wire [6:0] next_y_w;
            assign next_x_w = local_x_w[6:0] + 7'd1;
            assign next_y_w = local_y_w[6:0] + 7'd1;
            assign sample_x_w = local_x_w[0] == X_PARITY ?
                local_x_w[6:0] : next_x_w;
            assign sample_y_w = local_y_w[0] == Y_PARITY ?
                local_y_w[6:0] : next_y_w;
            wire unused_sample_w;
            assign unused_sample_w = &{sample_x_w[0], sample_y_w[0]};
            assign rd_addr_w = {5'd0, sample_y_w[6:1]} * 11'd48 +
                {5'd0, sample_x_w[6:1]};
            for (lane = 0; lane < 8; lane = lane + 1) begin : g_lane
                assign wr_data_w[lane*16 +: 16] =
                    wr_data_i[(lane*2 + bank%2)*16 +: 16];
            end
            edrv32_ram_geo_src u_ram (
                .clk_i(clk_i),
                .wr_en_i(wr_en_i && wr_group_i == GROUP &&
                    wr_row_i[0] == Y_PARITY),
                .wr_addr_i(wr_addr_w),
                .wr_data_i(wr_data_w),
                .rd_en_i(rd_en_i && rd_group_i == GROUP),
                .rd_addr_i(rd_addr_w),
                .rd_data_o(bank_data_w[bank])
            );
        end
    endgenerate
endmodule
