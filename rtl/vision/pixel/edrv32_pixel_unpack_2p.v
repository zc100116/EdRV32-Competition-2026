// ============================================================================
// File        : edrv32_pixel_unpack_2p.v
// Description : Convert one packed 16-pixel RGB565 beat into 2-pixel beats.
// Notes       : Input metadata is {sof,eof,pixels[255:0]}; pixel lane 0 is the
//               least-significant 16 bits. Width must be a multiple of 16.
// ============================================================================

module edrv32_pixel_unpack_2p #(
    parameter integer H_ACTIVE = 1280
) (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire [257:0] stream_data_i,
    input  wire         stream_valid_i,
    output wire         stream_ready_o,

    output wire [15:0]  pixel0_o,
    output wire [15:0]  pixel1_o,
    output wire         sof_o,
    output wire         eof_o,
    output wire         sol_o,
    output wire         eol_o,
    output wire         pair_valid_o,
    input  wire         pair_ready_i
);

    localparam integer WORDS_PER_LINE = H_ACTIVE / 16;
    localparam integer WORD_INDEX_W = (WORDS_PER_LINE <= 1) ?
        1 : $clog2(WORDS_PER_LINE);

    reg [255:0] beat_pixels_r;
    reg beat_sof_r;
    reg beat_eof_r;
    reg beat_valid_r;
    reg [2:0] pair_index_r;
    reg [WORD_INDEX_W-1:0] next_word_index_r;
    reg [WORD_INDEX_W-1:0] beat_word_index_r;

    wire last_pair_w = pair_index_r == 3'd7;
    wire pair_fire_w = beat_valid_r && pair_ready_i;
    wire replace_w = pair_fire_w && last_pair_w;
    wire input_fire_w = stream_valid_i && stream_ready_o;
    wire [31:0] selected_pair_w =
        beat_pixels_r[pair_index_r*32 +: 32];

    assign stream_ready_o = !beat_valid_r || replace_w;
    assign pixel0_o = selected_pair_w[15:0];
    assign pixel1_o = selected_pair_w[31:16];
    assign sof_o = beat_valid_r && beat_sof_r && (pair_index_r == 3'd0);
    assign eof_o = beat_valid_r && beat_eof_r && last_pair_w;
    assign sol_o = beat_valid_r &&
        (beat_word_index_r == {WORD_INDEX_W{1'b0}}) &&
        (pair_index_r == 3'd0);
    assign eol_o = beat_valid_r &&
        (beat_word_index_r == WORDS_PER_LINE - 1) && last_pair_w;
    assign pair_valid_o = beat_valid_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            beat_pixels_r <= 256'b0;
            beat_sof_r <= 1'b0;
            beat_eof_r <= 1'b0;
            beat_valid_r <= 1'b0;
            pair_index_r <= 3'b0;
            next_word_index_r <= {WORD_INDEX_W{1'b0}};
            beat_word_index_r <= {WORD_INDEX_W{1'b0}};
        end else begin
            if (input_fire_w) begin
                beat_pixels_r <= stream_data_i[255:0];
                beat_sof_r <= stream_data_i[257];
                beat_eof_r <= stream_data_i[256];
                beat_valid_r <= 1'b1;
                pair_index_r <= 3'b0;

                if (stream_data_i[257]) begin
                    beat_word_index_r <= {WORD_INDEX_W{1'b0}};
                    if (WORDS_PER_LINE == 1)
                        next_word_index_r <= {WORD_INDEX_W{1'b0}};
                    else
                        next_word_index_r <= {{(WORD_INDEX_W-1){1'b0}}, 1'b1};
                end else begin
                    beat_word_index_r <= next_word_index_r;
                    if (next_word_index_r == WORDS_PER_LINE - 1)
                        next_word_index_r <= {WORD_INDEX_W{1'b0}};
                    else
                        next_word_index_r <= next_word_index_r + 1'b1;
                end
            end else if (pair_fire_w) begin
                if (last_pair_w) begin
                    beat_valid_r <= 1'b0;
                    pair_index_r <= 3'b0;
                end else begin
                    pair_index_r <= pair_index_r + 1'b1;
                end
            end
        end
    end

    generate
        if ((H_ACTIVE < 16) || ((H_ACTIVE % 16) != 0)) begin : gen_bad_width
            edrv32_pixel_unpack_width_must_be_a_multiple_of_16
                u_static_assert ();
        end
    endgenerate

endmodule
