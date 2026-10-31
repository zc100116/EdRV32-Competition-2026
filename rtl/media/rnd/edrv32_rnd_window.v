// File: edrv32_rnd_window.v
// Spec: rnd-spec v0.3 2.6 AFFINE_BLIT, 5.2/5.3.
// Description: Thirty-two decoded 8x8 source blocks; four parity banks supply a
//              four-tap group per cycle, with ordered row fills and locked live hits.
// Clock domain: clk_mem (clk_i).
module edrv32_rnd_window (
    // Clock and per-command invalidation.
    input wire clk_i,
    input wire rst_n_i,
    input wire clear_i,
    input wire start_i,
    input wire [511:0] command_i,

    // Integer tap origin and fractional weights; missing blocks retain this sample.
    input wire in_valid_i,
    output wire in_ready_o,
    input wire signed [31:0] x_i,
    input wire signed [31:0] y_i,
    input wire [7:0] fraction_x_i,
    input wire [7:0] fraction_y_i,
    input wire [31:0] destination_i,
    input wire [31:0] tag_i,
    input wire [7:0] coverage_i,
    output wire out_valid_o,
    input wire out_ready_i,
    output wire [127:0] taps_o,
    output wire [7:0] fraction_x_o,
    output wire [7:0] fraction_y_o,
    output wire [31:0] destination_o,
    output wire [31:0] tag_o,
    output wire [7:0] coverage_o,
    output wire read_wait_o,

    // Raw source-row fill client, at most two beats per row.
    output wire rd_valid_o,
    input wire rd_ready_i,
    output wire [31:0] rd_addr_o,
    output wire [15:0] rd_bytes_o,
    input wire rd_data_valid_i,
    input wire [255:0] rd_data_i,
    input wire rd_done_i,

    // Reuse the two existing palette read ports; one-cycle read response.
    output wire palette_valid_o,
    output wire [15:0] palette_index_o,
    input wire [63:0] palette_data_i
);
    localparam [3:0] S_IDLE = 4'd0;
    localparam [3:0] S_ROW = 4'd1;
    localparam [3:0] S_ADDRESS = 4'd2;
    localparam [3:0] S_READ = 4'd3;
    localparam [3:0] S_DATA = 4'd4;
    localparam [3:0] S_ALIGN = 4'd5;
    localparam [3:0] S_INDEX = 4'd6;
    localparam [3:0] S_INDEX_WAIT = 4'd7;
    localparam [3:0] S_WRITE0 = 4'd8;
    localparam [3:0] S_WRITE1 = 4'd9;
    reg [3:0] state_r;
    reg [31:0] cache_valid_r;
    reg [25:0] cache_tag_r [0:31];
    reg [4:0] replace_r;
    reg sample_valid_r;
    reg [15:0] sample_x_r [0:3];
    reg [15:0] sample_y_r [0:3];
    reg [3:0] sample_inside_r;
    reg [15:0] fraction_r;
    reg [71:0] payload_r;
    reg bank_valid_r;
    reg [3:0] bank_inside_r;
    reg [1:0] bank_select_r [0:3];
    reg [3:0] bank_half_r;
    reg [15:0] bank_fraction_r;
    reg [71:0] bank_payload_r;
    reg [4:0] slot_w [0:3];
    reg [3:0] hit_w;
    reg [31:0] locked_w;
    reg missing_w;
    reg [25:0] missing_tag_w;
    reg [4:0] victim_w;
    reg victim_found_w;
    reg [4:0] fill_slot_r;
    reg [25:0] fill_tag_r;
    reg [2:0] fill_row_r;
    reg [31:0] row_product_r;
    reg [31:0] row_addr_r;
    reg data_beat_r;
    reg [511:0] data_r;
    reg [255:0] row_data_r;
    reg [1:0] palette_pair_r;
    reg [1:0] palette_return_r;
    reg palette_pending_r;
    reg [31:0] indexed_r [0:7];
    wire [3:0] format_w;
    wire [2:0] bits_log2_w;
    wire [15:0] source_width_w;
    wire [15:0] source_height_w;
    wire [15:0] fill_x_w;
    wire [15:0] fill_y_w;
    wire [15:0] remaining_w;
    wire [3:0] columns_w;
    wire [8:0] row_bits_w;
    wire [8:0] row_byte_count_w;
    wire [5:0] row_bytes_w;
    wire [31:0] row_x_bytes_w;
    wire [6:0] row_end_w;
    wire row_last_w;
    wire [511:0] aligned_w;
    wire forward_w;
    wire bank_ready_w;
    wire [31:0] decoded_w [0:7];
    wire [63:0] bank_data_w [0:3];
    reg [7:0] bank_addr_w [0:3];
    reg [3:0] bank_read_w;
    wire cache_write_w;
    wire [7:0] cache_write_addr_w;
    wire [31:0] palette_raw_w [0:1];
    wire signed [32:0] tap_x_w [0:3];
    wire signed [32:0] tap_y_w [0:3];
    integer tap;
    integer entry;
    integer offset;
    integer candidate;
    integer bank;
    wire unused_bits_w;
    assign format_w = command_i[15:12];
    assign bits_log2_w = format_w == 0 ? 3'd4 : format_w == 1 ? 3'd5 :
        format_w == 6 ? 3'd3 : format_w == 7 ? 3'd2 : format_w == 8 ? 3'd1 : 3'd0;
    assign source_width_w = command_i[335:320];
    assign source_height_w = command_i[351:336];
    assign fill_x_w = {fill_tag_r[12:0], 3'd0};
    assign fill_y_w = {fill_tag_r[25:13], 3'd0} + {13'd0, fill_row_r};
    assign remaining_w = source_width_w - fill_x_w;
    assign columns_w = remaining_w >= 16'd8 ? 4'd8 : remaining_w[3:0];
    assign row_bits_w = {5'd0, columns_w} << bits_log2_w;
    assign row_byte_count_w = (row_bits_w + 9'd7) >> 3;
    assign row_bytes_w = row_byte_count_w[5:0];
    assign row_x_bytes_w = ({16'd0, fill_x_w} << bits_log2_w) >> 3;
    assign row_end_w = {2'd0, row_addr_r[4:0]} + {1'b0, row_bytes_w};
    assign row_last_w = fill_row_r == 7 || fill_y_w + 16'd1 >= source_height_w;
    assign aligned_w = data_r >> {row_addr_r[4:0], 3'd0};
    assign rd_valid_o = state_r == S_READ && !clear_i;
    assign rd_addr_o = {row_addr_r[31:5], 5'd0};
    assign rd_bytes_o = row_end_w > 7'd32 ? 16'd64 : 16'd32;
    assign cache_write_w = (state_r == S_WRITE0 || state_r == S_WRITE1) && !clear_i;
    assign cache_write_addr_w = {fill_slot_r, fill_row_r[2:1], state_r == S_WRITE1};
    assign palette_valid_o = state_r == S_INDEX;
    assign palette_index_o = {palette_raw_w[1][7:0], palette_raw_w[0][7:0]};
    assign bank_ready_w = !bank_valid_r || out_ready_i;
    assign forward_w = sample_valid_r && !missing_w && bank_ready_w;
    assign in_ready_o = (!sample_valid_r || forward_w) && !clear_i;
    assign out_valid_o = bank_valid_r;
    assign read_wait_o = sample_valid_r && missing_w;
    assign fraction_x_o = bank_fraction_r[7:0];
    assign fraction_y_o = bank_fraction_r[15:8];
    assign destination_o = bank_payload_r[31:0];
    assign tag_o = bank_payload_r[63:32];
    assign coverage_o = bank_payload_r[71:64];
    assign unused_bits_w = ^{aligned_w[511:256], palette_raw_w[0][31:8],
        palette_raw_w[1][31:8], command_i[511:464], command_i[447:352],
        command_i[319:304], command_i[255:24], command_i[23:19], command_i[17],
        command_i[11:0], row_bits_w[2:0], row_byte_count_w[8:6], candidate[31:5]};

    function automatic [31:0] raw_pixel;
        input [255:0] row_i;
        input [2:0] column_i;
        input [3:0] format_i;
        reg [255:0] shifted;
        reg [7:0] bit_offset;
        reg [223:0] unused_bits;
        begin
            bit_offset = 8'd0;
            raw_pixel = 32'd0;
            case (format_i)
                4'd0: bit_offset = {1'd0, column_i, 4'd0};
                4'd1: bit_offset = {column_i, 5'd0};
                4'd6: bit_offset = {2'd0, column_i, 3'd0};
                4'd7: bit_offset = {3'd0, column_i[2:1], 3'd0} +
                    {5'd0, !column_i[0], 2'd0};
                4'd8: bit_offset = {4'd0, column_i[2], 3'd0} +
                    {5'd0, ~column_i[1:0], 1'd0};
                4'd9: bit_offset = {5'd0, ~column_i};
                default: bit_offset = 8'd0;
            endcase
            shifted = row_i >> bit_offset;
            case (format_i)
                4'd0: raw_pixel = {16'd0, shifted[15:0]};
                4'd1: raw_pixel = shifted[31:0];
                4'd6: raw_pixel = {24'd0, shifted[7:0]};
                4'd7: raw_pixel = {28'd0, shifted[3:0]};
                4'd8: raw_pixel = {30'd0, shifted[1:0]};
                4'd9: raw_pixel = {31'd0, shifted[0]};
                default: raw_pixel = 32'd0;
            endcase
            unused_bits = shifted[255:32];
        end
    endfunction
    always @(*) begin
        locked_w = 32'd0;
        hit_w = 4'd0;
        missing_w = 1'b0;
        missing_tag_w = 26'd0;
        victim_w = replace_r;
        victim_found_w = 1'b0;
        candidate = 0;
        for (tap = 0; tap < 4; tap = tap + 1) begin
            slot_w[tap] = 5'd0;
            for (entry = 0; entry < 32; entry = entry + 1) begin
                if (cache_valid_r[entry] && cache_tag_r[entry] ==
                    {sample_y_r[tap][15:3], sample_x_r[tap][15:3]}) begin
                    slot_w[tap] = entry[4:0];
                    hit_w[tap] = 1'b1;
                    if (sample_inside_r[tap])
                        locked_w[entry] = 1'b1;
                end
            end
            if (sample_inside_r[tap] && !hit_w[tap] && !missing_w) begin
                missing_w = 1'b1;
                missing_tag_w = {sample_y_r[tap][15:3], sample_x_r[tap][15:3]};
            end
        end
        for (offset = 0; offset < 32; offset = offset + 1) begin
            candidate = ({27'd0, replace_r} + offset) & 31;
            if (!victim_found_w && !locked_w[candidate]) begin
                victim_w = candidate[4:0];
                victim_found_w = 1'b1;
            end
        end
        bank_read_w = 4'd0;
        for (bank = 0; bank < 4; bank = bank + 1) begin
            bank_addr_w[bank] = 8'd0;
            for (tap = 0; tap < 4; tap = tap + 1) begin
                if ({sample_y_r[tap][0], sample_x_r[tap][0]} == bank[1:0] &&
                    sample_inside_r[tap]) begin
                    bank_addr_w[bank] = {slot_w[tap], sample_y_r[tap][2:1], sample_x_r[tap][2]};
                    bank_read_w[bank] = forward_w;
                end
            end
        end
    end
    genvar pixel;
    genvar parity;
    generate for (pixel = 0; pixel < 4; pixel = pixel + 1) begin : g_tap
        localparam signed [32:0] X_ADD = pixel % 2;
        localparam signed [32:0] Y_ADD = pixel / 2;
        wire [63:0] selected_w;
        wire [63:0] shifted_w;
        wire unused_selected_w;
        assign tap_x_w[pixel] = $signed({x_i[31], x_i}) + X_ADD;
        assign tap_y_w[pixel] = $signed({y_i[31], y_i}) + Y_ADD;
        assign selected_w = bank_data_w[bank_select_r[pixel]];
        assign shifted_w = selected_w >> {bank_half_r[pixel], 5'd0};
        assign taps_o[pixel*32 +: 32] = bank_inside_r[pixel] ? shifted_w[31:0] : 32'd0;
        assign unused_selected_w = ^shifted_w[63:32];
        always @(posedge clk_i) begin
            if (in_valid_i && in_ready_o) begin
                sample_x_r[pixel] <= tap_x_w[pixel][15:0];
                sample_y_r[pixel] <= tap_y_w[pixel][15:0];
                sample_inside_r[pixel] <= (pixel == 0 || command_i[16]) &&
                    tap_x_w[pixel] >= 0 && tap_y_w[pixel] >= 0 &&
                    tap_x_w[pixel] < $signed({17'd0, source_width_w}) &&
                    tap_y_w[pixel] < $signed({17'd0, source_height_w});
            end
            if (forward_w) begin
                bank_select_r[pixel] <= {sample_y_r[pixel][0], sample_x_r[pixel][0]};
                bank_half_r[pixel] <= sample_x_r[pixel][1];
            end
        end
    end endgenerate
    generate for (pixel = 0; pixel < 8; pixel = pixel + 1) begin : g_decode
        localparam [2:0] COLUMN = pixel;
        wire [31:0] raw_w;
        assign raw_w = raw_pixel(row_data_r, COLUMN, format_w);
        assign decoded_w[pixel] = format_w >= 4'd6 ? indexed_r[pixel] :
            format_w == 4'd1 ? raw_w :
            {command_i[18] && raw_w[15:0] == command_i[463:448] ? 8'd0 : 8'd255,
                raw_w[15:11], raw_w[15:13], raw_w[10:5], raw_w[10:9],
                raw_w[4:0], raw_w[4:2]};
    end endgenerate
    generate for (pixel = 0; pixel < 2; pixel = pixel + 1) begin : g_palette
        localparam [2:0] PARITY = pixel;
        assign palette_raw_w[pixel] = raw_pixel(row_data_r,
            {palette_pair_r, 1'b0} + PARITY, format_w);
    end endgenerate
    generate for (parity = 0; parity < 4; parity = parity + 1) begin : g_bank
        localparam [2:0] COLUMN0 = parity % 2;
        localparam [2:0] COLUMN1 = parity % 2 + 2;
        localparam [2:0] COLUMN2 = parity % 2 + 4;
        localparam [2:0] COLUMN3 = parity % 2 + 6;
        localparam [0:0] ROW_PARITY = parity >= 2;
        edrv32_ram_rnd_window u_memory (
            .clk_i(clk_i),
            .wr_en_i(cache_write_w && fill_row_r[0] == ROW_PARITY),
            .wr_addr_i(cache_write_addr_w),
            .wr_data_i(state_r == S_WRITE0 ? {decoded_w[COLUMN1], decoded_w[COLUMN0]} :
                {decoded_w[COLUMN3], decoded_w[COLUMN2]}),
            .rd_en_i(bank_read_w[parity]),
            .rd_addr_i(bank_addr_w[parity]),
            .rd_data_o(bank_data_w[parity])
        );
    end endgenerate
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            cache_valid_r <= 32'd0;
            replace_r <= 5'd0;
            sample_valid_r <= 1'b0;
            bank_valid_r <= 1'b0;
            fill_row_r <= 3'd0;
            data_beat_r <= 1'b0;
            palette_pair_r <= 2'd0;
            palette_pending_r <= 1'b0;
        end else if (clear_i || start_i) begin
            state_r <= S_IDLE;
            cache_valid_r <= 32'd0;
            replace_r <= 5'd0;
            sample_valid_r <= 1'b0;
            bank_valid_r <= 1'b0;
            palette_pending_r <= 1'b0;
        end else begin
            if (in_ready_o)
                sample_valid_r <= in_valid_i;
            if (bank_ready_w)
                bank_valid_r <= forward_w;
            palette_pending_r <= state_r == S_INDEX;
            case (state_r)
                S_IDLE: if (sample_valid_r && missing_w) begin
                    fill_row_r <= 3'd0;
                    cache_valid_r[victim_w] <= 1'b0;
                    state_r <= S_ROW;
                end
                S_ROW: state_r <= S_ADDRESS;
                S_ADDRESS: state_r <= S_READ;
                S_READ: if (rd_ready_i) begin
                    data_beat_r <= 1'b0;
                    state_r <= S_DATA;
                end
                S_DATA: begin
                    if (rd_data_valid_i)
                        data_beat_r <= 1'b1;
                    if (rd_done_i)
                        state_r <= S_ALIGN;
                end
                S_ALIGN: begin
                    palette_pair_r <= 2'd0;
                    state_r <= format_w >= 4'd6 ? S_INDEX : S_WRITE0;
                end
                S_INDEX: begin
                    palette_pair_r <= palette_pair_r + 2'd1;
                    if (palette_pair_r == 3)
                        state_r <= S_INDEX_WAIT;
                end
                S_INDEX_WAIT: state_r <= S_WRITE0;
                S_WRITE0: state_r <= S_WRITE1;
                S_WRITE1: if (row_last_w) begin
                    cache_valid_r[fill_slot_r] <= 1'b1;
                    replace_r <= fill_slot_r + 5'd1;
                    state_r <= S_IDLE;
                end else begin
                    fill_row_r <= fill_row_r + 3'd1;
                    state_r <= S_ROW;
                end
                default: state_r <= state_r;
            endcase
        end
    end
    always @(posedge clk_i) begin
        if (in_valid_i && in_ready_o) begin
            fraction_r <= {fraction_y_i, fraction_x_i};
            payload_r <= {coverage_i, tag_i, destination_i};
        end
        if (forward_w) begin
            bank_fraction_r <= fraction_r;
            bank_payload_r <= payload_r;
            bank_inside_r <= sample_inside_r;
        end
        if (state_r == S_IDLE && sample_valid_r && missing_w) begin
            fill_slot_r <= victim_w;
            fill_tag_r <= missing_tag_w;
        end
        if (state_r == S_ROW) begin
            row_product_r <= fill_y_w * command_i[303:288];
        end
        if (state_r == S_ADDRESS)
            row_addr_r <= command_i[287:256] + row_product_r + row_x_bytes_w;
        if (state_r == S_DATA && rd_data_valid_i)
            data_r[data_beat_r*256 +: 256] <= rd_data_i;
        if (state_r == S_ALIGN)
            row_data_r <= aligned_w[255:0];
        if (state_r == S_INDEX)
            palette_return_r <= palette_pair_r;
        if (palette_pending_r) begin
            indexed_r[{palette_return_r, 1'b0}] <= palette_data_i[31:0];
            indexed_r[{palette_return_r, 1'b0}+3'd1] <= palette_data_i[63:32];
        end
        if (state_r == S_WRITE1 && row_last_w)
            cache_tag_r[fill_slot_r] <= fill_tag_r;
    end
endmodule
