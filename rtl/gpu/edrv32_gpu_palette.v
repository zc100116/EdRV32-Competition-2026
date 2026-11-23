// File: edrv32_gpu_palette.v
// Spec: gpu-spec 2.6; GPU microarchitecture 4.2, 4.5, 4.8.
// Description: Two full palettes, four arbitrary reads, eight prepared-group replicas.
// Clock: clk_gpu.
module edrv32_gpu_palette (
    // Clock and command lifetime.
    input wire clk_i,
    input wire rst_n_i,
    input wire finish_i,
    input wire stop_i,
    output reg unit_done_o,

    // Palette loading and triangle preload control.
    input wire palette_load_valid_i,
    output wire palette_load_ready_o,
    input wire [11:0] palette_load_idx_i,
    input wire [19:0] palette_load_data_i,
    input wire palette_prepare_valid_i,
    output wire palette_prepare_ready_o,
    input wire [3:0] palette_prepare_group_i,
    output reg palette_prepared_valid_o,
    input wire palette_prepared_ready_i,

    // Internal fixed-latency sampling ports, four cycles.
    input wire full_read_en_i,
    input wire [47:0] full_read_idx_i,
    output wire [79:0] full_read_data_o,
    input wire current_read_en_i,
    input wire [63:0] current_read_idx_i,
    output wire [159:0] current_read_data_o
);
    reg preparing_r;
    reg [8:0] prepare_count_r;
    reg [3:0] prepare_group_r;
    reg [3:0] prepare_valid_r;
    reg [7:0] prepare_idx_r [0:3];
    wire prepare_issue_w;
    wire current_write_w;
    wire [47:0] read_idx_w;
    wire [79:0] read_data_w;
    assign palette_load_ready_o = 1'b1;
    assign palette_prepare_ready_o = !preparing_r && !palette_prepared_valid_o;
    assign prepare_issue_w = preparing_r && !prepare_count_r[8] && !stop_i;
    assign current_write_w = prepare_valid_r[3] && !stop_i;
    assign read_idx_w = preparing_r ? {36'b0, prepare_group_r, prepare_count_r[7:0]}
                                    : full_read_idx_i;
    assign full_read_data_o = read_data_w;
    integer stage;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            preparing_r <= 1'b0;
            prepare_count_r <= 9'b0;
            prepare_valid_r <= 4'b0;
            palette_prepared_valid_o <= 1'b0;
            unit_done_o <= 1'b0;
        end else begin
            prepare_valid_r <= {prepare_valid_r[2:0], prepare_issue_w};
            if (palette_prepared_valid_o && palette_prepared_ready_i) begin
                palette_prepared_valid_o <= 1'b0;
            end
            if (palette_prepare_valid_i && palette_prepare_ready_o && !stop_i) begin
                preparing_r <= 1'b1;
                prepare_count_r <= 9'b0;
            end else if (prepare_issue_w) begin
                prepare_count_r <= prepare_count_r + 1'b1;
            end
            if (current_write_w && prepare_idx_r[3] == 8'd255) begin
                preparing_r <= 1'b0;
                palette_prepared_valid_o <= 1'b1;
            end
            if (stop_i) begin
                preparing_r <= 1'b0;
                palette_prepared_valid_o <= 1'b0;
            end
            if (!finish_i) begin
                unit_done_o <= 1'b0;
            end else if (!preparing_r && prepare_valid_r == 0
                            && !palette_prepared_valid_o && !palette_load_valid_i) begin
                unit_done_o <= 1'b1;
            end
        end
    end
    always @(posedge clk_i) begin
        if (palette_prepare_valid_i && palette_prepare_ready_o) begin
            prepare_group_r <= palette_prepare_group_i;
        end
        prepare_idx_r[0] <= prepare_count_r[7:0];
        for (stage = 1; stage < 4; stage = stage + 1) begin
            prepare_idx_r[stage] <= prepare_idx_r[stage-1];
        end
    end
    genvar replica;
    genvar segment;
    generate
        for (replica = 0; replica < 2; replica = replica + 1) begin : g_full
            reg [23:0] read_idx_r;
            reg read_en_r;
            reg [7:0] segment_r;
            wire [159:0] segment_data_w;
            reg [39:0] read_data_r;
            assign read_data_w[replica*40 +: 40] = read_data_r;
            always @(posedge clk_i) begin
                read_idx_r <= read_idx_w[replica*24 +: 24];
                read_en_r <= prepare_issue_w || full_read_en_i;
                segment_r <= {segment_r[3:0], read_idx_r[23:22], read_idx_r[11:10]};
                read_data_r[19:0] <= segment_data_w[segment_r[5:4]*40 +: 20];
                read_data_r[39:20] <= segment_data_w[segment_r[7:6]*40+20 +: 20];
            end
            for (segment = 0; segment < 4; segment = segment + 1) begin : g_segment
                edrv32_ram_gpu_palette_segment u_ram (
                    .clk_i(clk_i),
                    .wr_en_i(palette_load_valid_i && !stop_i
                                && palette_load_idx_i[11:10] == segment),
                    .wr_addr_i(palette_load_idx_i[9:0]),
                    .wr_data_i(palette_load_data_i),
                    .rd_a_en_i(read_en_r && read_idx_r[11:10] == segment),
                    .rd_b_en_i(read_en_r && read_idx_r[23:22] == segment),
                    .rd_a_addr_i(read_idx_r[9:0]),
                    .rd_b_addr_i(read_idx_r[21:12]),
                    .rd_a_data_o(segment_data_w[segment*40 +: 20]),
                    .rd_b_data_o(segment_data_w[segment*40+20 +: 20])
                );
            end
        end
        for (replica = 0; replica < 8; replica = replica + 1) begin : g_current
            edrv32_ram_gpu_palette_current u_ram (
                .clk_i(clk_i),
                .wr_en_i(current_write_w),
                .wr_addr_i(prepare_idx_r[3]),
                .wr_data_i(read_data_w[19:0]),
                .rd_en_i(current_read_en_i),
                .rd_addr_i(current_read_idx_i[replica*8 +: 8]),
                .rd_data_o(current_read_data_o[replica*20 +: 20])
            );
        end
    endgenerate
endmodule
