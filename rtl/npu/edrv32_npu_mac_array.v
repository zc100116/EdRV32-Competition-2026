// File: edrv32_npu_mac_array.v
// Spec: npu-spec 1, 5.4 C1-C8; design/2026-10-30-npu-apm-cascade 3-6.
// Description: 32 eight-stage SIMD APM chains, with local input and chain-tail registers.
// Local channel control advances through M1/M2/C1-C8 without backpressure.
// Clock: clk_npu.
module edrv32_npu_mac_array (
    // Clock and control reset; payload registers are not reset.
    input wire clk_i,
    input wire rst_n_i,
    input wire cancel_i,

    // A5 terms, with eight local activation copies serving four channels each.
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
    output wire [63:0] sum_fold_o,
    output wire [1215:0] sum_data_o,

    // Activity and pipeline occupancy.
    output wire mac_beat_o,
    output wire idle_o
);
    wire [31:0] channel_busy_w;
    wire [255:0] unused_activation_w;
    reg [48:0] tag_r [0:11];
    (* keep = "true", syn_preserve = 1 *) reg [1:0] fold_source_r;
    integer stage;

    // Copies 0/1 serve low physical channels and never select their upper C8.
    assign unused_activation_w = {term_activation_i[511:448], term_activation_i[383:320],
        term_activation_i[255:192], term_activation_i[127:64]};

    always @(posedge clk_i) begin
        fold_source_r <= {2{tag_r[9][48]}};
        tag_r[0] <= term_tag_i;
        for (stage = 1; stage < 12; stage = stage + 1) begin
            tag_r[stage] <= tag_r[stage-1];
        end
    end

    genvar channel;
    genvar lane;
    genvar copy;
    genvar pixel;
    wire [127:0] activation_w [0:7];
    generate
        // D2 selection belongs to the term before item skew, including across bubbles.
        for (copy = 0; copy < 8; copy = copy + 1) begin : g_activation_copy
            wire [127:0] local_activation_w;
            assign activation_w[copy] = local_activation_w;
            for (lane = 0; lane < 8; lane = lane + 1) begin : g_lane
                localparam BASE = 256 * (copy/2) + 8 * lane;
                wire [15:0] selected_w;
                (* keep = "true", syn_preserve = 1 *) reg [15:0] local_activation_r;
                always @(posedge clk_i) begin
                    local_activation_r <= selected_w;
                end
                if (copy < 4) begin : g_low
                    assign selected_w = {term_activation_i[BASE+128 +: 8],
                        term_activation_i[BASE +: 8]};
                end else begin : g_high
                    assign selected_w = term_tag_i[48] ?
                        {term_activation_i[BASE+192 +: 8],
                            term_activation_i[BASE+64 +: 8]} :
                        {term_activation_i[BASE+128 +: 8], term_activation_i[BASE +: 8]};
                end
                if (lane == 0) begin : g_direct
                    assign local_activation_w[16*lane +: 16] = local_activation_r;
                end else begin : g_skew
                    (* keep = "true", syn_preserve = 1 *)
                    reg [16*lane-1:0] activation_r;
                    always @(posedge clk_i) begin
                        activation_r <= (activation_r << 16) | {{(16*lane-16){1'b0}},
                            local_activation_r};
                    end
                    assign local_activation_w[16*lane +: 16] =
                        activation_r[16*(lane-1) +: 16];
                end
            end
        end
        for (channel = 0; channel < 32; channel = channel + 1) begin : g_channel
            (* keep = "true", syn_preserve = 1 *) reg [11:0] valid_r;
            (* keep = "true", syn_preserve = 1 *) reg [11:0] first_r;
            (* keep = "true", syn_preserve = 1 *) reg [11:0] last_r;
            wire [47:0] cascade_w [1:7];
            wire [47:0] sum_w;
            (* keep = "true", syn_preserve = 1 *) reg [37:0] local_sum_r;
            always @(posedge clk_i) begin
                local_sum_r <= {sum_w[42:24], sum_w[18:0]};
            end
            wire [9:0] unused_sum_w;
            assign unused_sum_w = {sum_w[47:43], sum_w[23:19]};
            wire [1:0] unused_control_w;

            // The scalar interface exports copy 0; other local copies remain identical.
            assign unused_control_w = {first_r[11], last_r[11]};

            // spec npu 5.4: valid is local control, never a global datapath CE.
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    valid_r <= 12'b0;
                end else if (cancel_i) begin
                    valid_r <= 12'b0;
                end else begin
                    valid_r <= {valid_r[10:0], term_valid_i};
                end
            end

            // Each fold copy drives only its own 19-bit pixel sum.
            for (pixel = 0; pixel < 2; pixel = pixel + 1) begin : g_fold_pixel
                (* keep = "true", syn_preserve = 1 *) reg fold_r;
                always @(posedge clk_i) begin
                    fold_r <= fold_source_r[pixel];
                end
                assign sum_fold_o[32*pixel+channel] = fold_r;
            end

            always @(posedge clk_i) begin
                first_r <= {first_r[10:0], term_first_i};
                last_r <= {last_r[10:0], term_last_i};
            end

            assign channel_busy_w[channel] = |valid_r;

            for (lane = 0; lane < 8; lane = lane + 1) begin : g_lane
                wire [15:0] lane_activation_w;
                (* keep = "true", syn_preserve = 1 *) reg [7:0] lane_weight_r;
                assign lane_activation_w = activation_w[channel/4][16*lane +: 16];
                always @(posedge clk_i) begin
                    lane_weight_r <= term_weight_i[8*(8*channel+lane) +: 8];
                end
                if (lane == 0) begin : g_head
                    wire [47:0] unused_p_w;
                    edrv32_mac_npu_int8_head u_mac (
                        // MODEZ selects zero; the head has no cascade input.
                        .clk_i(clk_i),

                        .a0_i(lane_activation_w[7:0]),
                        .b0_i(lane_weight_r),
                        .a1_i(lane_activation_w[15:8]),
                        .b1_i(lane_weight_r),

                        .cpo_o(cascade_w[1]),
                        .p_o(unused_p_w)
                    );
                end else if (lane < 7) begin : g_cascade
                    wire [47:0] unused_p_w;
                    edrv32_mac_npu_int8_chain u_mac (
                        // M1/M2/Ck are inside the APM; each next CPO adds one edge.
                        .clk_i(clk_i),

                        .a0_i(lane_activation_w[7:0]),
                        .b0_i(lane_weight_r),
                        .a1_i(lane_activation_w[15:8]),
                        .b1_i(lane_weight_r),

                        .cpi_i(cascade_w[lane]),
                        .cpo_o(cascade_w[lane+1]),
                        .p_o(unused_p_w)
                    );
                end else begin : g_result
                    wire [47:0] unused_cpo_w;
                    edrv32_mac_npu_int8_chain u_mac (
                        .clk_i(clk_i),

                        .a0_i(lane_activation_w[7:0]),
                        .b0_i(lane_weight_r),
                        .a1_i(lane_activation_w[15:8]),
                        .b1_i(lane_weight_r),

                        // The last P drives logic; CPO only connects APMs.
                        .cpi_i(cascade_w[lane]),
                        .cpo_o(unused_cpo_w),
                        .p_o(sum_w)
                    );
                end
            end

            assign sum_data_o[19*channel +: 19] = local_sum_r[18:0];
            assign sum_data_o[19*(32+channel) +: 19] = local_sum_r[37:19];
        end
    endgenerate

    // All 32 local control chains describe the same term stream.
    assign sum_valid_o = g_channel[0].valid_r[11];
    assign sum_first_o = g_channel[0].first_r[11];
    assign sum_last_o = g_channel[0].last_r[11];
    assign sum_tag_o = tag_r[11];
    assign mac_beat_o = g_channel[0].valid_r[0];
    assign idle_o = ~|channel_busy_w;
endmodule
