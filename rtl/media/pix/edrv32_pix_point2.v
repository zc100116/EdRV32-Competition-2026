// File: edrv32_pix_point2.v
// Spec: pix-spec 2.1, 2.5.
// Description: Ordered grayscale, threshold and per-channel inversion.
// Quantize the resulting RGB888 pair to the external RGB565 stream.
// Clock: clk_mem.
module edrv32_pix_point2 (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Input stream.
    input wire valid_i,
    input wire [47:0] data_i,
    input wire sof_i,
    input wire eol_i,
    input wire eof_i,

    // Output stream.
    output wire valid_o,
    output wire [31:0] data_o,
    output wire sof_o,
    output wire eol_o,
    output wire eof_o,

    // Pipeline and frame configuration.
    input wire [2:0] advance_i,
    input wire clear_i,
    input wire gray_en_i,
    input wire bin_en_i,
    input wire inv_en_i,
    input wire [7:0] thresh_i
);
    reg [3:0] valid_r;
    reg [3:0] sof_r;
    reg [3:0] eol_r;
    reg [3:0] eof_r;
    reg [2:0] config_r [0:3];
    reg [47:0] rgb_r [0:3];
    integer stage_r;

    assign valid_o = valid_r[3];
    assign sof_o = sof_r[3];
    assign eol_o = eol_r[3];
    assign eof_o = eof_r[3];

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            valid_r <= 4'd0;
        end else if (clear_i) begin
            valid_r <= 4'd0;
        end else if (advance_i[0]) begin
            valid_r <= {valid_r[2:0], valid_i};
        end
    end

    always @(posedge clk_i) begin
        if (advance_i[0]) begin
            sof_r <= {sof_r[2:0], sof_i};
            eol_r <= {eol_r[2:0], eol_i};
            eof_r <= {eof_r[2:0], eof_i};
            config_r[0] <= {inv_en_i, bin_en_i, gray_en_i};
            rgb_r[0] <= data_i;
            for (stage_r = 1; stage_r < 4; stage_r = stage_r + 1) begin
                config_r[stage_r] <= config_r[stage_r-1];
                rgb_r[stage_r] <= rgb_r[stage_r-1];
            end
        end
    end

    reg [7:0] thresh_r [0:3];
    genvar lane;
    integer threshold_stage_r;

    always @(posedge clk_i) begin
        if (advance_i[0]) begin
            thresh_r[0] <= thresh_i;
            for (threshold_stage_r = 1; threshold_stage_r < 4;
                threshold_stage_r = threshold_stage_r + 1) begin
                thresh_r[threshold_stage_r] <= thresh_r[threshold_stage_r-1];
            end
        end
    end

    generate
        for (lane = 0; lane < 2; lane = lane + 1) begin : g_lane
            reg [15:0] s2_red_r;
            reg [15:0] s2_green_r;
            reg [15:0] s2_blue_r;
            reg [15:0] s3_rg_r;
            reg [15:0] s3_blue_r;
            reg [15:0] s4_unused_gray_r;
            wire [7:0] gray_w;
            wire [23:0] gray_rgb_w;
            wire [23:0] binary_w;
            wire [23:0] unused_result_w;
            assign gray_w = s4_unused_gray_r[15:8];
            assign gray_rgb_w = config_r[3][0] ? {gray_w, gray_w, gray_w}
                : rgb_r[3][lane*24 +: 24];
            // Coefficients sum to 256: converting a gray pixel again preserves Y.
            assign binary_w = config_r[3][1]
                ? (gray_w >= thresh_r[3] ? 24'hffffff : 24'd0) : gray_rgb_w;
            assign unused_result_w = binary_w ^ {24{config_r[3][2]}};
            // edrv32_pix's two-slot output buffer owns the final result register.
            assign data_o[lane*16 +: 16] = {unused_result_w[23:19],
                unused_result_w[15:10], unused_result_w[7:3]};
            always @(posedge clk_i) begin
                if (advance_i[lane+1]) begin
                    s2_red_r <= 16'd77 * {8'd0, rgb_r[0][lane*24+16 +: 8]};
                    s2_green_r <= 16'd150 * {8'd0, rgb_r[0][lane*24+8 +: 8]};
                    s2_blue_r <= 16'd29 * {8'd0, rgb_r[0][lane*24 +: 8]};
                    s3_rg_r <= s2_red_r + s2_green_r;
                    s3_blue_r <= s2_blue_r + 16'd128;
                    s4_unused_gray_r <= s3_rg_r + s3_blue_r;

                end
            end
        end
    endgenerate
endmodule
