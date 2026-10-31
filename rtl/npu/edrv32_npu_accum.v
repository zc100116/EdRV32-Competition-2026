// File: edrv32_npu_accum.v
// Spec: npu-spec 5.1, 5.4; design/2026-10-27-npu-datapath 4.2, 4.3.
// Description: R4 folds D2 channel halves or delays ordinary terms, then ACC accumulates.
// R3 last starts parameter preparation at the R4 edge; ACC emits only final vectors.
// Clock: clk_npu.
module edrv32_npu_accum (
    // Clock and control reset; accumulated data is replaced by each first term.
    input wire clk_i,
    input wire rst_n_i,
    input wire cancel_i,

    // Signed R3 sums, one unstallable term per clock.
    input wire sum_valid_i,
    input wire sum_first_i,
    input wire sum_last_i,
    input wire [48:0] sum_tag_i,
    input wire [31:0] sum_fold_i,
    input wire [1215:0] sum_data_i,

    // Combinational R4 preparation and registered final ACC vector.
    output wire quant_prepare_valid_o,
    output wire [48:0] quant_prepare_tag_o,
    output wire accum_valid_o,
    output wire [48:0] accum_tag_o,
    output wire [2047:0] accum_data_o,

    // Occupancy of the R4/ACC valid chain.
    output wire idle_o
);
    wire [31:0] channel_busy_w;
    reg [48:0] r4_tag_r;
    reg [48:0] accum_tag_r;

    always @(posedge clk_i) begin
        r4_tag_r <= sum_tag_i;
        accum_tag_r <= r4_tag_r;
    end

    genvar channel;
    genvar pixel;
    generate
        for (channel = 0; channel < 32; channel = channel + 1) begin : g_channel
            // Keep physical channel controls separate through synthesis.
            (* keep = "true", syn_preserve = 1 *) reg r4_valid_r;
            (* keep = "true", syn_preserve = 1 *) reg r4_first_r;
            reg r4_last_r;
            reg accum_valid_r;

            (* keep = "true" *)
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    r4_valid_r <= 1'b0;
                    accum_valid_r <= 1'b0;
                end else if (cancel_i) begin
                    r4_valid_r <= 1'b0;
                    accum_valid_r <= 1'b0;
                end else begin
                    r4_valid_r <= sum_valid_i;
                    accum_valid_r <= r4_valid_r && r4_last_r;
                end
            end

            (* keep = "true" *)
            always @(posedge clk_i) begin
                r4_first_r <= sum_first_i;
                r4_last_r <= sum_last_i;
            end

            assign channel_busy_w[channel] = r4_valid_r || accum_valid_r;

            for (pixel = 0; pixel < 2; pixel = pixel + 1) begin : g_pixel
                wire signed [18:0] sum_w;
                reg signed [19:0] r4_data_r;
                reg signed [31:0] accum_data_r;
                wire signed [31:0] extended_w;
                assign sum_w = sum_data_i[19*(32*pixel+channel) +: 19];

                if (channel < 16) begin : g_low
                    wire signed [18:0] high_sum_w;
                    assign high_sum_w = sum_data_i[19*(32*pixel+channel+16) +: 19];

                    always @(posedge clk_i) begin
                        r4_data_r <= sum_fold_i[channel] ?
                            ({sum_w[18], sum_w} + {high_sum_w[18], high_sum_w}) :
                            {sum_w[18], sum_w};
                    end
                end else begin : g_high
                    // Folded channels are explicitly zero in the output vector.
                    always @(posedge clk_i) begin
                        r4_data_r <= sum_fold_i[channel] ? 20'sd0 : {sum_w[18], sum_w};
                    end
                end

                assign extended_w = {{12{r4_data_r[19]}}, r4_data_r};

                // spec npu 5.4: first replaces stale data without resetting the datapath.
                always @(posedge clk_i) begin
                    if (r4_valid_r) begin
                        accum_data_r <= r4_first_r ? extended_w : accum_data_r + extended_w;
                    end
                end

                assign accum_data_o[32*(32*pixel+channel) +: 32] = accum_data_r;
            end
        end
    endgenerate

    // This pulse is sampled with R4, not registered before the parameter RAM request.
    assign quant_prepare_valid_o = sum_valid_i && sum_last_i && !cancel_i;
    assign quant_prepare_tag_o = sum_tag_i;
    assign accum_valid_o = g_channel[0].accum_valid_r;
    assign accum_tag_o = accum_tag_r;
    assign idle_o = ~|channel_busy_w;
endmodule
