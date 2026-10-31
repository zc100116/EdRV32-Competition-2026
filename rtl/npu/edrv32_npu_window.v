// File: edrv32_npu_window.v
// Spec: npu-spec 5.1, 5.4; datapath design 4.2.4, 4.3, 4.4.
// Description: Two prepared command contexts drive incremental D3b window reads.
//              A1-A5 preserve tags and reserve only at pair entry; no global CE.
// Clock: clk_npu.
module edrv32_npu_window (
    // Clock and cancellation.
    input wire clk_i,
    input wire rst_n_i,
    input wire cancel_i,

    // Layer shadow fields.
    input wire cfg_k3_i,
    input wire cfg_s2_i,
    input wire cfg_in_c4_i,
    input wire cfg_half_tail_i,
    input wire cfg_lut_en_i,
    input wire cfg_res_en_i,
    input wire [7:0] cfg_out_zp_i,
    input wire [11:0] cfg_in_w_i,
    input wire [11:0] cfg_out_w_i,
    input wire [5:0] cfg_cin_blocks_i,
    input wire [3:0] cfg_cout_blocks_i,
    input wire [10:0] cfg_k_count_i,

    // Ordered row/block commands.
    input wire cmd_valid_i,
    output wire cmd_ready_o,
    input wire [11:0] cmd_row_i,
    input wire [2:0] cmd_block_i,
    input wire [10:0] cmd_weight_base_i,
    input wire [9:0] cmd_row_base0_i,
    input wire [9:0] cmd_row_base1_i,
    input wire [9:0] cmd_row_base2_i,
    input wire [2:0] cmd_row_valid_i,

    // Pair entry credit and execution control.
    input wire issue_enable_i,
    input wire pair_ready_i,
    input wire [4:0] pair_result_slot_i,
    input wire [4:0] pair_residual_addr_i,
    output wire pair_fire_o,
    output wire pair_half_o,

    // Registered A1 cache requests and A3 return.
    output reg [1:0] cache_rd_en_o,
    output reg [9:0] cache_rd_addr0_o,
    output reg [9:0] cache_rd_addr1_o,
    input wire [255:0] cache_rd_data0_i,
    input wire [255:0] cache_rd_data1_i,

    // Item-skewed weights: input item k returns at A3+k.
    output wire weight_rd_en_o,
    output reg [10:0] weight_rd_addr_o,
    input wire [2047:0] weight_rd_data_i,

    // A5 control/activation; weight item k follows at A5+k.
    output wire term_valid_o,
    output wire term_first_o,
    output wire term_last_o,
    output wire [48:0] term_tag_o,
    output wire [1023:0] term_activation_o,
    output wire [2047:0] term_weight_o,

    // Command lifetime notifications.
    output wire cmd_issued_o,
    output wire [11:0] cmd_issued_row_o,
    output wire [2:0] cmd_issued_block_o,
    output wire cmd_read_done_o,
    output wire [11:0] cmd_read_done_row_o,
    output wire [2:0] cmd_read_done_block_o,

    // Local state.
    output wire idle_o
);
    reg [11:0] current_row_r;
    reg [11:0] next_row_r;
    reg [2:0] current_block_r;
    reg [2:0] next_block_r;
    reg [10:0] current_weight_base_r;
    reg [10:0] next_weight_base_r;
    reg [9:0] current_row_base0_r;
    reg [9:0] next_row_base0_r;
    reg [9:0] current_row_base1_r;
    reg [9:0] next_row_base1_r;
    reg [9:0] current_row_base2_r;
    reg [9:0] next_row_base2_r;
    reg [2:0] current_row_valid_r;
    reg [2:0] next_row_valid_r;
    reg current_k3_r;
    reg next_k3_r;
    reg current_s2_r;
    reg next_s2_r;
    reg current_in_c4_r;
    reg next_in_c4_r;
    reg current_lut_en_r;
    reg next_lut_en_r;
    reg current_res_en_r;
    reg next_res_en_r;
    reg [7:0] current_out_zp_r;
    reg [7:0] next_out_zp_r;
    reg [11:0] current_in_w_r;
    reg [11:0] next_in_w_r;
    reg [10:0] current_pair_limit_r;
    reg [10:0] next_pair_limit_r;
    reg [5:0] current_cin_blocks_r;
    reg [5:0] next_cin_blocks_r;
    reg current_half_r;
    reg next_half_r;
    reg current_d2_r;
    reg next_d2_r;
    reg [10:0] current_k_count_r;
    reg [10:0] next_k_count_r;
    reg [9:0] current_stride_r;
    reg [9:0] next_stride_r;
    reg current_valid_r;
    reg next_valid_r;
    reg [10:0] pair_r;
    reg [1:0] ky_r;
    reg [1:0] kx_r;
    reg [5:0] c16_r;
    reg c8_half_r;
    reg [10:0] k_index_r;
    reg signed [13:0] pair_x_r;
    reg [9:0] channel_offset_r;
    reg [2:0] quant_remaining_r;
    reg [48:0] pair_tag_r;
    wire unused_out_w_w;
    wire cmd_accept_w;
    wire promote_w;
    wire first_w;
    wire last_w;
    wire last_pair_w;
    wire issue_w;
    wire command_last_w;
    wire signed [13:0] x0_w;
    wire signed [13:0] x1_w;
    wire pixel0_valid_w;
    wire pixel1_valid_w;
    reg [9:0] row_base_w;
    wire [9:0] addr0_w;
    wire [9:0] addr1_w;
    reg [1:0] cache_en_w;
    reg [9:0] cache_addr0_w;
    reg [9:0] cache_addr1_w;
    wire [48:0] tag_w;

    // Spec 2.2 guarantees even feature widths; only the pair count is retained.
    assign unused_out_w_w = cfg_out_w_i[0];
    assign cmd_ready_o = !next_valid_r && !cancel_i;
    assign cmd_accept_w = cmd_valid_i && cmd_ready_o;
    assign promote_w = next_valid_r && (!current_valid_r || command_last_w);
    assign first_w = k_index_r == 11'd0;
    assign last_w = k_index_r == current_k_count_r - 11'd1;
    assign last_pair_w = pair_r == current_pair_limit_r;
    // Design 4.4.3: compare the NEW K with the PREVIOUS pair's group calendar.
    assign issue_w = current_valid_r && !cancel_i && (!first_w ||
        (issue_enable_i && pair_ready_i &&
        current_k_count_r >= {8'd0, quant_remaining_r}));
    assign command_last_w = issue_w && last_w && last_pair_w;
    assign pair_fire_o = issue_w && first_w;
    assign pair_half_o = current_half_r;
    assign x0_w = pair_x_r + $signed({12'd0, kx_r});
    assign x1_w = x0_w + (current_s2_r ? 14'sd2 : 14'sd1);
    assign pixel0_valid_w = current_row_valid_r[ky_r] &&
        !x0_w[13] && x0_w < $signed({2'd0, current_in_w_r});
    assign pixel1_valid_w = current_row_valid_r[ky_r] &&
        !x1_w[13] && x1_w < $signed({2'd0, current_in_w_r});
    assign addr0_w = row_base_w + channel_offset_r + x0_w[11:2];
    assign addr1_w = row_base_w + channel_offset_r + x1_w[11:2];
    assign tag_w = first_w ? {current_d2_r, pair_residual_addr_i, pair_result_slot_i,
        last_pair_w, current_out_zp_r, current_res_en_r, current_lut_en_r,
        current_half_r, pair_r, current_block_r, current_row_r} : pair_tag_r;

    always @(*) begin
        row_base_w = current_row_base0_r;
        case (ky_r)
            2'd0: row_base_w = current_row_base0_r;
            2'd1: row_base_w = current_row_base1_r;
            2'd2: row_base_w = current_row_base2_r;
            default: row_base_w = current_row_base0_r;
        endcase
        cache_en_w = 2'b00;
        cache_addr0_w = 10'd0;
        cache_addr1_w = 10'd0;
        if (pixel0_valid_w) begin
            cache_en_w[x0_w[1]] = 1'b1;
            if (x0_w[1]) begin
                cache_addr1_w = addr0_w;
            end else begin
                cache_addr0_w = addr0_w;
            end
        end
        if (pixel1_valid_w) begin
            cache_en_w[x1_w[1]] = 1'b1;
            if (x1_w[1]) begin
                cache_addr1_w = addr1_w;
            end else begin
                cache_addr0_w = addr1_w;
            end
        end
    end

    // Context valid bits are the only ownership state; payload is not reset.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            current_valid_r <= 1'b0;
            next_valid_r <= 1'b0;
        end else if (cancel_i) begin
            current_valid_r <= 1'b0;
            next_valid_r <= 1'b0;
        end else begin
            if (promote_w) begin
                current_valid_r <= 1'b1;
            end else if (command_last_w) begin
                current_valid_r <= 1'b0;
            end
            if (cmd_accept_w) begin
                next_valid_r <= 1'b1;
            end else if (promote_w) begin
                next_valid_r <= 1'b0;
            end
        end
    end

    always @(posedge clk_i) begin
        if (cmd_accept_w) begin
            next_row_r <= cmd_row_i;
            next_block_r <= cmd_block_i;
            next_weight_base_r <= cmd_weight_base_i;
            next_row_base0_r <= cmd_row_base0_i;
            next_row_base1_r <= cmd_row_base1_i;
            next_row_base2_r <= cmd_row_base2_i;
            next_row_valid_r <= cmd_row_valid_i;
            next_k3_r <= cfg_k3_i;
            next_s2_r <= cfg_s2_i;
            next_in_c4_r <= cfg_in_c4_i;
            next_lut_en_r <= cfg_lut_en_i;
            next_res_en_r <= cfg_res_en_i;
            next_out_zp_r <= cfg_out_zp_i;
            next_in_w_r <= cfg_in_w_i;
            next_pair_limit_r <= cfg_out_w_i[11:1] - 11'd1;
            next_cin_blocks_r <= cfg_cin_blocks_i;
            next_half_r <= cfg_half_tail_i && ({1'b0, cmd_block_i} == cfg_cout_blocks_i - 4'd1);
            next_d2_r <= cfg_half_tail_i && !cfg_in_c4_i &&
                ({1'b0, cmd_block_i} == cfg_cout_blocks_i - 4'd1);
            next_k_count_r <= (cfg_half_tail_i && !cfg_in_c4_i &&
                ({1'b0, cmd_block_i} == cfg_cout_blocks_i - 4'd1)) ?
                {1'b0, cfg_k_count_i[10:1]} : cfg_k_count_i;
            next_stride_r <= cfg_in_w_i[11:2];
        end
        if (promote_w) begin
            current_row_r <= next_row_r;
            current_block_r <= next_block_r;
            current_weight_base_r <= next_weight_base_r;
            current_row_base0_r <= next_row_base0_r;
            current_row_base1_r <= next_row_base1_r;
            current_row_base2_r <= next_row_base2_r;
            current_row_valid_r <= next_row_valid_r;
            current_k3_r <= next_k3_r;
            current_s2_r <= next_s2_r;
            current_in_c4_r <= next_in_c4_r;
            current_lut_en_r <= next_lut_en_r;
            current_res_en_r <= next_res_en_r;
            current_out_zp_r <= next_out_zp_r;
            current_in_w_r <= next_in_w_r;
            current_pair_limit_r <= next_pair_limit_r;
            current_cin_blocks_r <= next_cin_blocks_r;
            current_half_r <= next_half_r;
            current_d2_r <= next_d2_r;
            current_k_count_r <= next_k_count_r;
            current_stride_r <= next_stride_r;
        end
        if (pair_fire_o) begin
            pair_tag_r <= tag_w;
        end
    end

    // Geometry advances by additions only. No product or modulo is on A1's path.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            pair_r <= 11'd0;
            ky_r <= 2'd0;
            kx_r <= 2'd0;
            c16_r <= 6'd0;
            c8_half_r <= 1'b0;
            k_index_r <= 11'd0;
            pair_x_r <= 14'sd0;
            channel_offset_r <= 10'd0;
            quant_remaining_r <= 3'd0;
        end else if (cancel_i) begin
            pair_r <= 11'd0;
            ky_r <= 2'd0;
            kx_r <= 2'd0;
            c16_r <= 6'd0;
            c8_half_r <= 1'b0;
            k_index_r <= 11'd0;
            pair_x_r <= 14'sd0;
            channel_offset_r <= 10'd0;
            quant_remaining_r <= 3'd0;
        end else begin
            if (issue_w && last_w) begin
                quant_remaining_r <= current_half_r ? 3'd2 : 3'd4;
            end else if (quant_remaining_r != 3'd0) begin
                quant_remaining_r <= quant_remaining_r - 3'd1;
            end
            if (promote_w) begin
                pair_r <= 11'd0;
                ky_r <= 2'd0;
                kx_r <= 2'd0;
                c16_r <= 6'd0;
                c8_half_r <= 1'b0;
                k_index_r <= 11'd0;
                pair_x_r <= next_k3_r ? -14'sd1 : 14'sd0;
                channel_offset_r <= 10'd0;
            end else if (issue_w) begin
                if (last_w) begin
                    pair_r <= pair_r + 11'd1;
                    ky_r <= 2'd0;
                    kx_r <= 2'd0;
                    c16_r <= 6'd0;
                    c8_half_r <= 1'b0;
                    k_index_r <= 11'd0;
                    pair_x_r <= pair_x_r + (current_s2_r ? 14'sd4 : 14'sd2);
                    channel_offset_r <= 10'd0;
                end else begin
                    k_index_r <= k_index_r + 11'd1;
                    if (!current_d2_r && !current_in_c4_r && !c8_half_r) begin
                        c8_half_r <= 1'b1;
                    end else begin
                        c8_half_r <= 1'b0;
                        if (!current_in_c4_r && c16_r != current_cin_blocks_r - 6'd1) begin
                            c16_r <= c16_r + 6'd1;
                            channel_offset_r <= channel_offset_r + current_stride_r;
                        end else begin
                            c16_r <= 6'd0;
                            channel_offset_r <= 10'd0;
                            if (current_k3_r && kx_r != 2'd2) begin
                                kx_r <= kx_r + 2'd1;
                            end else begin
                                kx_r <= 2'd0;
                                ky_r <= ky_r + 2'd1;
                            end
                        end
                    end
                end
            end
        end
    end

    reg a1_valid_r;
    reg a2_valid_r;
    reg a3_valid_r;
    reg a4_valid_r;
    reg a5_valid_r;
    reg a1_first_r;
    reg a1_last_r;
    reg a1_command_last_r;
    reg [48:0] a1_tag_r;
    reg [1:0] a1_pixel_valid_r;
    reg [1:0] a1_bank_r;
    reg [1:0] a1_pixel_r;
    reg a1_c8_half_r;
    reg a1_d2_r;
    reg a1_in_c4_r;
    reg a2_first_r;
    reg a2_last_r;
    reg a2_command_last_r;
    reg [48:0] a2_tag_r;
    reg [1:0] a2_pixel_valid_r;
    reg [1:0] a2_bank_r;
    reg [1:0] a2_pixel_r;
    reg a2_c8_half_r;
    reg a2_d2_r;
    reg a2_in_c4_r;
    reg a3_first_r;
    reg a3_last_r;
    reg a3_command_last_r;
    reg [48:0] a3_tag_r;
    reg [1:0] a3_pixel_valid_r;
    reg [1:0] a3_bank_r;
    reg [1:0] a3_pixel_r;
    reg a3_c8_half_r;
    reg a3_d2_r;
    reg a3_in_c4_r;
    reg a4_first_r;
    reg a4_last_r;
    reg [48:0] a4_tag_r;
    reg a5_first_r;
    reg a5_last_r;
    reg [48:0] a5_tag_r;
    reg [255:0] a4_activation_r;
    reg [2047:0] a4_weight_r;
    wire [255:0] pixel0_beat_w;
    wire [255:0] pixel1_beat_w;
    wire [127:0] pixel0_data_w;
    wire [127:0] pixel1_data_w;
    reg [127:0] pixel0_activation_w;
    reg [127:0] pixel1_activation_w;

    assign pixel0_beat_w = a3_bank_r[0] ? cache_rd_data1_i : cache_rd_data0_i;
    assign pixel1_beat_w = a3_bank_r[1] ? cache_rd_data1_i : cache_rd_data0_i;
    assign pixel0_data_w = a3_pixel_r[0] ? pixel0_beat_w[255:128] : pixel0_beat_w[127:0];
    assign pixel1_data_w = a3_pixel_r[1] ? pixel1_beat_w[255:128] : pixel1_beat_w[127:0];
    always @(*) begin
        pixel0_activation_w = 128'd0;
        pixel1_activation_w = 128'd0;
        if (a3_pixel_valid_r[0]) begin
            if (a3_in_c4_r) begin
                pixel0_activation_w = {96'd0, pixel0_data_w[31:0]};
            end else if (a3_d2_r) begin
                pixel0_activation_w = pixel0_data_w;
            end else begin
                pixel0_activation_w = {64'd0, a3_c8_half_r ?
                    pixel0_data_w[127:64] : pixel0_data_w[63:0]};
            end
        end
        if (a3_pixel_valid_r[1]) begin
            if (a3_in_c4_r) begin
                pixel1_activation_w = {96'd0, pixel1_data_w[31:0]};
            end else if (a3_d2_r) begin
                pixel1_activation_w = pixel1_data_w;
            end else begin
                pixel1_activation_w = {64'd0, a3_c8_half_r ?
                    pixel1_data_w[127:64] : pixel1_data_w[63:0]};
            end
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            a1_valid_r <= 1'b0;
            a2_valid_r <= 1'b0;
            a3_valid_r <= 1'b0;
            a4_valid_r <= 1'b0;
            a5_valid_r <= 1'b0;
            cache_rd_en_o <= 2'd0;
        end else if (cancel_i) begin
            a1_valid_r <= 1'b0;
            a2_valid_r <= 1'b0;
            a3_valid_r <= 1'b0;
            a4_valid_r <= 1'b0;
            a5_valid_r <= 1'b0;
            cache_rd_en_o <= 2'd0;
        end else begin
            a1_valid_r <= issue_w;
            a2_valid_r <= a1_valid_r;
            a3_valid_r <= a2_valid_r;
            a4_valid_r <= a3_valid_r;
            a5_valid_r <= a4_valid_r;
            cache_rd_en_o <= issue_w ? cache_en_w : 2'b00;
        end
    end

    always @(posedge clk_i) begin
        if (issue_w) begin
            cache_rd_addr0_o <= cache_addr0_w;
            cache_rd_addr1_o <= cache_addr1_w;
            weight_rd_addr_o <= current_weight_base_r + k_index_r;
            a1_first_r <= first_w;
            a1_last_r <= last_w;
            a1_command_last_r <= last_w && last_pair_w;
            a1_tag_r <= tag_w;
            a1_pixel_valid_r <= {pixel1_valid_w, pixel0_valid_w};
            a1_bank_r <= {x1_w[1], x0_w[1]};
            a1_pixel_r <= {x1_w[0], x0_w[0]};
            a1_c8_half_r <= c8_half_r;
            a1_d2_r <= current_d2_r;
            a1_in_c4_r <= current_in_c4_r;
        end
        a2_first_r <= a1_first_r;
        a2_last_r <= a1_last_r;
        a2_command_last_r <= a1_command_last_r;
        a2_tag_r <= a1_tag_r;
        a2_pixel_valid_r <= a1_pixel_valid_r;
        a2_bank_r <= a1_bank_r;
        a2_pixel_r <= a1_pixel_r;
        a2_c8_half_r <= a1_c8_half_r;
        a2_d2_r <= a1_d2_r;
        a2_in_c4_r <= a1_in_c4_r;
        a3_first_r <= a2_first_r;
        a3_last_r <= a2_last_r;
        a3_command_last_r <= a2_command_last_r;
        a3_tag_r <= a2_tag_r;
        a3_pixel_valid_r <= a2_pixel_valid_r;
        a3_bank_r <= a2_bank_r;
        a3_pixel_r <= a2_pixel_r;
        a3_c8_half_r <= a2_c8_half_r;
        a3_d2_r <= a2_d2_r;
        a3_in_c4_r <= a2_in_c4_r;
        a4_first_r <= a3_first_r;
        a4_last_r <= a3_last_r;
        a4_tag_r <= a3_tag_r;
        a4_activation_r <= {pixel1_activation_w, pixel0_activation_w};
        a5_first_r <= a4_first_r;
        a5_last_r <= a4_last_r;
        a5_tag_r <= a4_tag_r;
    end

    // Payload advances on every edge; valid alone owns bubbles.
    // Each weight item has its own read skew; A3/A4 valid only describes item zero.
    always @(posedge clk_i) begin
        a4_weight_r <= weight_rd_data_i;
    end

    // Design 4.3.2: retain four physical activation copies, as in the legacy APM layout.
    genvar copy;
    genvar lane;
    generate
        for (copy = 0; copy < 4; copy = copy + 1) begin : g_activation_copy
            (* syn_preserve = 1 *) reg [255:0] activation_r;
            (* syn_keep = 1 *) wire [255:0] activation_w;
            assign activation_w = activation_r;
            assign term_activation_o[256*copy+:256] = activation_w;
            always @(posedge clk_i) begin
                activation_r <= a4_activation_r;
            end
        end
        // Each weight byte feeds one APM; a preserved per-byte register lets PDS place it there.
        for (lane = 0; lane < 256; lane = lane + 1) begin : g_weight_byte
            reg [7:0] weight_r /* synthesis syn_preserve=1 */;
            assign term_weight_o[8*lane+:8] = weight_r;
            always @(posedge clk_i) begin
                weight_r <= a4_weight_r[8*lane+:8];
            end
        end
    endgenerate

    assign weight_rd_en_o = a1_valid_r;
    assign cmd_issued_o = a1_valid_r && a1_command_last_r;
    assign cmd_issued_row_o = a1_tag_r[11:0];
    assign cmd_issued_block_o = a1_tag_r[14:12];
    assign cmd_read_done_o = a3_valid_r && a3_command_last_r;
    assign cmd_read_done_row_o = a3_tag_r[11:0];
    assign cmd_read_done_block_o = a3_tag_r[14:12];
    assign term_valid_o = a5_valid_r;
    assign term_first_o = a5_first_r;
    assign term_last_o = a5_last_r;
    assign term_tag_o = a5_tag_r;
    assign idle_o = !(current_valid_r || next_valid_r || a1_valid_r || a2_valid_r ||
        a3_valid_r || a4_valid_r || a5_valid_r);
endmodule
