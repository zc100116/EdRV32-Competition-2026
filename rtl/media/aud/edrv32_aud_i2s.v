// File: edrv32_aud_i2s.v
// Spec: aud-spec 2.5, 6.
// Description: Fixed divide-by-four I2S master with 32 BCLK slots per channel.
//              Sample ownership changes at the left-channel frame boundary.
// Clock domain: clk_aud.
module edrv32_aud_i2s (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Sample FIFO and synchronized playback enable.
    input wire enable_i,
    input wire sample_valid_i,
    output wire sample_ready_o,
    input wire [31:0] sample_data_i,

    // Serial output and underrun event.
    output wire aud_bclk_o,
    output wire aud_lrck_o,
    output wire aud_sdata_o,
    output wire underrun_o
);
    reg [7:0] phase_r;
    reg [31:0] sample_r;
    reg frame_valid_r;
    wire frame_w;
    wire [4:0] slot_w;
    wire [4:0] bit_index_w;

    assign frame_w = (phase_r == 8'hff);
    assign slot_w = phase_r[6:2];
    assign bit_index_w = (phase_r[7] ? 5'd0 : 5'd16) - slot_w;
    assign aud_bclk_o = phase_r[1];
    assign aud_lrck_o = phase_r[7];
    assign aud_sdata_o = enable_i && frame_valid_r &&
        (slot_w >= 5'd1) && (slot_w <= 5'd16) ? sample_r[bit_index_w] : 1'b0;
    assign sample_ready_o = enable_i && frame_w;
    assign underrun_o = sample_ready_o && !sample_valid_i;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            phase_r <= 8'd0;
            frame_valid_r <= 1'b0;
        end else begin
            phase_r <= phase_r + 1'b1;
            if (!enable_i) begin
                frame_valid_r <= 1'b0;
            end else if (frame_w) begin
                frame_valid_r <= sample_valid_i;
            end
        end
    end

    always @(posedge clk_i) begin
        if (sample_ready_o && sample_valid_i) begin
            sample_r <= sample_data_i;
        end
    end
endmodule
