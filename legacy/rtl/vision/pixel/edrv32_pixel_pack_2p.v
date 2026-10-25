// ============================================================================
// File        : edrv32_pixel_pack_2p.v
// Description : Pack eight 2-pixel RGB565 transfers into one 256-bit beat.
// Notes       : Output metadata is {sof,eof,pixels[255:0]}.
// ============================================================================

module edrv32_pixel_pack_2p (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire [15:0]  pixel0_i,
    input  wire [15:0]  pixel1_i,
    input  wire         sof_i,
    input  wire         eof_i,
    input  wire         pair_valid_i,
    output wire         pair_ready_o,

    output wire [257:0] stream_data_o,
    output wire         stream_valid_o,
    input  wire         stream_ready_i
);

    reg [255:0] pack_r;
    reg [2:0] pair_index_r;
    reg beat_sof_r;
    reg [257:0] stream_data_r;
    reg stream_valid_r;

    wire output_slot_w = !stream_valid_r || stream_ready_i;
    wire last_pair_w = pair_index_r == 3'd7;
    wire pair_fire_w = pair_valid_i && pair_ready_o;
    wire stream_fire_w = stream_valid_r && stream_ready_i;

    reg [255:0] completed_word_w;
    always @(*) begin
        completed_word_w = pack_r;
        completed_word_w[pair_index_r*32 +: 32] = {pixel1_i, pixel0_i};
    end

    assign pair_ready_o = !last_pair_w || output_slot_w;
    assign stream_data_o = stream_data_r;
    assign stream_valid_o = stream_valid_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            pack_r <= 256'b0;
            pair_index_r <= 3'b0;
            beat_sof_r <= 1'b0;
            stream_data_r <= 258'b0;
            stream_valid_r <= 1'b0;
        end else begin
            if (stream_fire_w)
                stream_valid_r <= 1'b0;

            if (pair_fire_w) begin
                pack_r[pair_index_r*32 +: 32] <= {pixel1_i, pixel0_i};
                if (pair_index_r == 3'd0)
                    beat_sof_r <= sof_i;

                if (last_pair_w) begin
                    stream_data_r <= {beat_sof_r, eof_i, completed_word_w};
                    stream_valid_r <= 1'b1;
                    pair_index_r <= 3'b0;
                    pack_r <= 256'b0;
                end else begin
                    pair_index_r <= pair_index_r + 1'b1;
                end
            end
        end
    end

endmodule
