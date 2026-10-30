// File: edrv32_npu_mac_array.v
// Spec: npu-spec 1, 5.4 C1-C8; design/2026-10-30-npu-apm-cascade 3-6.
// Description: 32 eight-stage SIMD APM chains, with item-skewed activations and weights.
// Local channel control advances through M1/M2/C1-C8 without backpressure.
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
    // Weight item k already arrives k edges later from its resident RAM bank.
    input wire [2047:0] term_weight_i,

    // C8 sums: [pixel][physical output channel], each signed 19 bits.
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
    reg [48:0] tag_r [0:9];
    integer stage;

    // Copies 0/1 serve low physical channels and never select their upper C8.
    assign unused_activation_w = {term_activation_i[511:448], term_activation_i[383:320],
        term_activation_i[255:192], term_activation_i[127:64]};

    always @(posedge clk_i) begin
        tag_r[0] <= term_tag_i;
        for (stage = 1; stage < 10; stage = stage + 1) begin
            tag_r[stage] <= tag_r[stage-1];
        end
    end

    genvar channel;
    genvar lane;
    genvar copy;
    wire [127:0] activation_w [0:3];
    generate
        // D2 selection belongs to the term before item skew, including across bubbles.
        for (copy = 0; copy < 4; copy = copy + 1) begin : g_activation_copy
            wire [127:0] local_activation_w;
            assign activation_w[copy] = local_activation_w;
            for (lane = 0; lane < 8; lane = lane + 1) begin : g_lane
                localparam BASE = 256 * copy + 8 * lane;
                wire [15:0] selected_w;
                if (copy < 2) begin : g_low
                    assign selected_w = {term_activation_i[BASE+128 +: 8],
                        term_activation_i[BASE +: 8]};
                end else begin : g_high
                    assign selected_w = term_tag_i[48] ?
                        {term_activation_i[BASE+192 +: 8],
                            term_activation_i[BASE+64 +: 8]} :
                        {term_activation_i[BASE+128 +: 8], term_activation_i[BASE +: 8]};
                end
                if (lane == 0) begin : g_direct
                    assign local_activation_w[16*lane +: 16] = selected_w;
                end else begin : g_skew
                    reg [16*lane-1:0] activation_r;
                    always @(posedge clk_i) begin
                        activation_r <= (activation_r << 16) | {{(16*lane-16){1'b0}},
                            selected_w};
                    end
                    assign local_activation_w[16*lane +: 16] =
                        activation_r[16*(lane-1) +: 16];
                end
            end
        end
        for (channel = 0; channel < 32; channel = channel + 1) begin : g_channel
            reg [9:0] valid_r;
            reg [9:0] first_r;
            reg [9:0] last_r;
            wire [47:0] cascade_w [0:8];
            wire [9:0] unused_sum_w;
            assign cascade_w[0] = 48'd0;
            assign unused_sum_w = {cascade_w[8][47:43], cascade_w[8][23:19]};
            wire [1:0] unused_control_w;

            // The scalar interface exports copy 0; other local copies remain identical.
            assign unused_control_w = {first_r[9], last_r[9]};

            // spec npu 5.4: valid is local control, never a global datapath CE.
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    valid_r <= 10'b0;
                end else if (cancel_i) begin
                    valid_r <= 10'b0;
                end else begin
                    valid_r <= {valid_r[8:0], term_valid_i};
                end
            end

            always @(posedge clk_i) begin
                first_r <= {first_r[8:0], term_first_i};
                last_r <= {last_r[8:0], term_last_i};
            end

            assign channel_busy_w[channel] = |valid_r;

            for (lane = 0; lane < 8; lane = lane + 1) begin : g_lane
                edrv32_mac_npu_int8_chain u_mac (
                    // M1/M2/Ck are inside the APM; each next CPO adds one edge.
                    .clk_i(clk_i),

                    .a0_i(activation_w[channel/8][16*lane +: 8]),
                    .b0_i(term_weight_i[8*(8*channel+lane) +: 8]),
                    .a1_i(activation_w[channel/8][16*lane+8 +: 8]),
                    .b1_i(term_weight_i[8*(8*channel+lane) +: 8]),

                    .cpi_i(cascade_w[lane]),
                    .cpo_o(cascade_w[lane+1])
                );
            end

            assign sum_data_o[19*channel +: 19] = cascade_w[8][18:0];
            assign sum_data_o[19*(32+channel) +: 19] = cascade_w[8][42:24];
        end
    endgenerate

    // All 32 local control chains describe the same term stream.
    assign sum_valid_o = g_channel[0].valid_r[9];
    assign sum_first_o = g_channel[0].first_r[9];
    assign sum_last_o = g_channel[0].last_r[9];
    assign sum_tag_o = tag_r[9];
    assign mac_beat_o = g_channel[0].valid_r[0];
    assign idle_o = ~|channel_busy_w;
endmodule
