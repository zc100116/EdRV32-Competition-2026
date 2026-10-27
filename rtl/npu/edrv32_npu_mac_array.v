// File: edrv32_npu_mac_array.v
// Spec: npu-spec 1, 5.4; design/2026-10-27-npu-datapath 4.2, 4.3, 4.6.
// Description: 256 fixed SIMD multipliers followed by three signed reduction stages.
// Local channel control advances through M1/M2/R1/R2/R3 without backpressure.
// Clock: clk_npu.
module edrv32_npu_mac_array (
    // Clock and control reset; payload registers are not reset.
    input wire clk_i,
    input wire rst_n_i,
    input wire cancel_i,

    // A5 terms, with four activation copies serving eight channels each.
    input wire term_valid_i,
    input wire term_first_i,
    input wire term_last_i,
    input wire [48:0] term_tag_i,
    input wire [1023:0] term_activation_i,
    input wire [2047:0] term_weight_i,

    // R3 sums: [pixel][physical output channel], each signed 19 bits.
    output wire sum_valid_o,
    output wire sum_first_o,
    output wire sum_last_o,
    output wire [48:0] sum_tag_o,
    output wire [1215:0] sum_data_o,

    // Activity and pipeline occupancy.
    output wire mac_beat_o,
    output wire idle_o
);
    wire [31:0] channel_busy_w;
    wire [255:0] unused_activation_w;
    reg [48:0] tag_r [0:4];
    integer stage;

    // Copies 0/1 serve low physical channels and never select their upper C8.
    assign unused_activation_w = {term_activation_i[511:448], term_activation_i[383:320],
        term_activation_i[255:192], term_activation_i[127:64]};

    always @(posedge clk_i) begin
        tag_r[0] <= term_tag_i;
        for (stage = 1; stage < 5; stage = stage + 1) begin
            tag_r[stage] <= tag_r[stage-1];
        end
    end

    genvar channel;
    genvar lane;
    genvar pixel;
    genvar pair;
    generate
        for (channel = 0; channel < 32; channel = channel + 1) begin : g_channel
            reg [4:0] valid_r;
            reg [4:0] first_r;
            reg [4:0] last_r;
            wire [127:0] product_w [0:1];
            wire [1:0] unused_control_w;

            // The scalar interface exports copy 0; other local copies remain identical.
            assign unused_control_w = {first_r[4], last_r[4]};

            // spec npu 5.4: valid is local control, never a global datapath CE.
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    valid_r <= 5'b0;
                end else if (cancel_i) begin
                    valid_r <= 5'b0;
                end else begin
                    valid_r <= {valid_r[3:0], term_valid_i};
                end
            end

            always @(posedge clk_i) begin
                first_r <= {first_r[3:0], term_first_i};
                last_r <= {last_r[3:0], term_last_i};
            end

            assign channel_busy_w[channel] = |valid_r;

            for (lane = 0; lane < 8; lane = lane + 1) begin : g_lane
                localparam ACTIVATION_BASE = 256 * (channel / 8) + 8 * lane;
                wire [7:0] activation0_w;
                wire [7:0] activation1_w;

                // D2 maps physical c+16 to the high C8 of the same two pixels.
                if (channel < 16) begin : g_low
                    assign activation0_w = term_activation_i[ACTIVATION_BASE +: 8];
                    assign activation1_w = term_activation_i[ACTIVATION_BASE+128 +: 8];
                end else begin : g_high
                    assign activation0_w = term_tag_i[48] ?
                        term_activation_i[ACTIVATION_BASE+64 +: 8] :
                        term_activation_i[ACTIVATION_BASE +: 8];
                    assign activation1_w = term_tag_i[48] ?
                        term_activation_i[ACTIVATION_BASE+192 +: 8] :
                        term_activation_i[ACTIVATION_BASE+128 +: 8];
                end

                edrv32_mul_npu_int8_pair u_multiply (
                    // M1/M2 are the two registers inside the fixed APM wrapper.
                    .clk_i(clk_i),

                    .a0_i(activation0_w),
                    .b0_i(term_weight_i[8*(8*channel+lane) +: 8]),
                    .a1_i(activation1_w),
                    .b1_i(term_weight_i[8*(8*channel+lane) +: 8]),

                    .p0_o(product_w[0][16*lane +: 16]),
                    .p1_o(product_w[1][16*lane +: 16])
                );
            end

            for (pixel = 0; pixel < 2; pixel = pixel + 1) begin : g_pixel
                reg signed [16:0] r1_data_r [0:3];
                reg signed [17:0] r2_data_r [0:1];
                reg signed [18:0] r3_data_r;

                for (pair = 0; pair < 4; pair = pair + 1) begin : g_r1
                    wire signed [15:0] left_w;
                    wire signed [15:0] right_w;
                    assign left_w = product_w[pixel][32*pair +: 16];
                    assign right_w = product_w[pixel][32*pair+16 +: 16];

                    always @(posedge clk_i) begin
                        r1_data_r[pair] <= {left_w[15], left_w} +
                            {right_w[15], right_w};
                    end
                end

                for (pair = 0; pair < 2; pair = pair + 1) begin : g_r2
                    always @(posedge clk_i) begin
                        r2_data_r[pair] <=
                            {r1_data_r[2*pair][16], r1_data_r[2*pair]} +
                            {r1_data_r[2*pair+1][16], r1_data_r[2*pair+1]};
                    end
                end

                always @(posedge clk_i) begin
                    r3_data_r <= {r2_data_r[0][17], r2_data_r[0]} +
                        {r2_data_r[1][17], r2_data_r[1]};
                end

                assign sum_data_o[19*(32*pixel+channel) +: 19] = r3_data_r;
            end
        end
    endgenerate

    // All 32 local control chains describe the same term stream.
    assign sum_valid_o = g_channel[0].valid_r[4];
    assign sum_first_o = g_channel[0].first_r[4];
    assign sum_last_o = g_channel[0].last_r[4];
    assign sum_tag_o = tag_r[4];
    assign mac_beat_o = g_channel[0].valid_r[0];
    assign idle_o = ~|channel_busy_w;
endmodule
