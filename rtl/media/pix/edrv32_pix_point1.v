// File: edrv32_pix_point1.v
// Spec: pix-spec 2.1-2.3, 2.6.
// Description: Expand RGB565, apply signed brightness/contrast and shared Gamma.
// Six asynchronous table read ports provide both RGB888 pixels each cycle.
// Clock: clk_mem.
module edrv32_pix_point1 (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Input stream.
    input wire valid_i,
    input wire [31:0] data_i,
    input wire sof_i,
    input wire eol_i,
    input wire eof_i,

    // Output stream.
    output wire valid_o,
    output reg [47:0] data_o,
    output wire sof_o,
    output wire eol_o,
    output wire eof_o,

    // Pipeline and frame configuration.
    input wire advance_i,
    input wire clear_i,
    input wire bc_en_i,
    input wire gamma_en_i,
    input wire gamma_bank_i,
    input wire [8:0] contrast_i,
    input wire [8:0] brightness_i,
    input wire gamma_wr_i,
    input wire [8:0] gamma_addr_i,
    input wire [7:0] gamma_data_i
);
    reg [4:0] valid_r;
    reg [4:0] sof_r;
    reg [4:0] eol_r;
    reg [4:0] eof_r;
    reg [2:0] config_r [0:3];
    reg [47:0] rgb_r [0:3];
    integer stage_r;

    assign valid_o = valid_r[4];
    assign sof_o = sof_r[4];
    assign eol_o = eol_r[4];
    assign eof_o = eof_r[4];

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            valid_r <= 5'd0;
        end else if (clear_i) begin
            valid_r <= 5'd0;
        end else if (advance_i) begin
            valid_r <= {valid_r[3:0], valid_i};
        end
    end

    always @(posedge clk_i) begin
        if (advance_i) begin
            sof_r <= {sof_r[3:0], sof_i};
            eol_r <= {eol_r[3:0], eol_i};
            eof_r <= {eof_r[3:0], eof_i};
            config_r[0] <= {gamma_bank_i, gamma_en_i, bc_en_i};
            rgb_r[0] <= expanded_w;
            for (stage_r = 1; stage_r < 4; stage_r = stage_r + 1) begin
                config_r[stage_r] <= config_r[stage_r-1];
                rgb_r[stage_r] <= rgb_r[stage_r-1];
            end
        end
    end

    reg [7:0] gamma_r [0:511];
    wire [47:0] expanded_w;
    reg signed [9:0] s1_contrast_r;
    reg signed [9:0] bias_r [0:1];
    genvar lane;
    genvar channel;

    // spec pix 2.3: writes remain independent of stream stalls and reset.
    always @(posedge clk_i) begin
        if (gamma_wr_i) begin
            gamma_r[gamma_addr_i] <= gamma_data_i;
        end
        if (advance_i) begin
            s1_contrast_r <= $signed({1'b0, contrast_i});
            bias_r[0] <= $signed({brightness_i[8], brightness_i}) + 10'sd128;
            bias_r[1] <= bias_r[0];
        end
    end

    generate
        for (lane = 0; lane < 2; lane = lane + 1) begin : g_expand
            assign expanded_w[lane*24 +: 24] = {
                data_i[lane*16+11 +: 5], data_i[lane*16+13 +: 3],
                data_i[lane*16+5 +: 6], data_i[lane*16+9 +: 2],
                data_i[lane*16 +: 5], data_i[lane*16+2 +: 3]};
        end
        for (channel = 0; channel < 6; channel = channel + 1) begin : g_channel
            reg signed [7:0] s1_center_r;
            reg signed [17:0] s2_unused_product_r;
            reg signed [10:0] s3_adjusted_r;
            reg [7:0] s4_corrected_r;
            always @(posedge clk_i) begin
                if (advance_i) begin
                    // c-128 is exactly an MSB inversion in signed eight-bit form.
                    s1_center_r <= $signed({!expanded_w[channel*8+7],
                        expanded_w[channel*8 +: 7]});
                    s2_unused_product_r <= s1_center_r * s1_contrast_r;
                    s3_adjusted_r <= $signed({s2_unused_product_r[17],
                        s2_unused_product_r[17:8]})
                        + $signed({bias_r[1][9], bias_r[1]});
                    s4_corrected_r <= !config_r[2][0] ? rgb_r[2][channel*8 +: 8]
                        : (s3_adjusted_r[10] ? 8'd0
                        : (|s3_adjusted_r[9:8] ? 8'd255 : s3_adjusted_r[7:0]));
                    data_o[channel*8 +: 8] <= config_r[3][1]
                        ? gamma_r[{config_r[3][2], s4_corrected_r}] : s4_corrected_r;
                end
            end
        end
    endgenerate
endmodule
