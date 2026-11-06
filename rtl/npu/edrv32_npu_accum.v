// File: edrv32_npu_accum.v
// Spec: npu-spec 5.1, 5.4; design/2026-10-27-npu-datapath 4.2, 4.3.
// Description: R4 adds D2 halves, R5 selects folded/plain terms, then ACC accumulates.
// R4 arithmetic precedes R5 selection; ACC emits only final vectors.
// Clock: clk_npu.
module edrv32_npu_accum (
    // Clock and control reset; accumulated data is replaced by each first term.
    input wire clk_i,
    input wire rst_n_i,
    input wire cancel_i,

    // Signed chain-tail sums, one unstallable term per clock.
    input wire sum_valid_i,
    input wire sum_first_i,
    input wire sum_last_i,
    input wire [48:0] sum_tag_i,
    input wire [63:0] sum_fold_i,
    input wire [1215:0] sum_data_i,

    // Preparation after R4 and registered final ACC vector.
    output wire quant_prepare_valid_o,
    output wire [48:0] quant_prepare_tag_o,
    output wire accum_valid_o,
    output wire [48:0] accum_tag_o,
    output wire [2047:0] accum_data_o,

    // Occupancy of the R4/R5/ACC valid chain.
    output wire idle_o
);
    wire [63:0] pixel_busy_w;
    reg [48:0] r5_tag_r;
    reg r4_prepare_r;
    reg [48:0] r4_tag_r;
    reg [48:0] accum_tag_r;

    always @(posedge clk_i) begin
        r4_tag_r <= sum_tag_i;
        r5_tag_r <= r4_tag_r;
        accum_tag_r <= r5_tag_r;
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) r4_prepare_r <= 1'b0;
        else if (cancel_i) r4_prepare_r <= 1'b0;
        else r4_prepare_r <= sum_valid_i && sum_last_i;
    end

    genvar channel;
    genvar pixel;
    generate
        for (channel = 0; channel < 32; channel = channel + 1) begin : g_channel
            localparam CHANNEL = channel;
            for (pixel = 0; pixel < 2; pixel = pixel + 1) begin : g_pixel
                (* keep = "true", syn_preserve = 1 *) reg r4_valid_r;
                (* keep = "true", syn_preserve = 1 *) reg r5_valid_r;
                (* keep = "true", syn_preserve = 1 *) reg r5_first_r;
                (* keep = "true", syn_preserve = 1 *) reg r4_first_r;
                (* keep = "true", syn_preserve = 1 *) reg r4_last_r;
                (* keep = "true", syn_preserve = 1 *) reg r4_fold_r;
                (* keep = "true", syn_preserve = 1 *) reg r5_last_r;
                reg accum_valid_r;
                wire signed [18:0] sum_w;
                reg signed [19:0] r4_folded_r;
                reg signed [19:0] r4_plain_r;
                reg signed [19:0] r5_data_r;
                reg signed [31:0] accum_data_r;
                wire signed [31:0] extended_w;
                assign sum_w = sum_data_i[19*(32*pixel+CHANNEL) +: 19];
                assign extended_w = {{12{r5_data_r[19]}}, r5_data_r};
                assign pixel_busy_w[32*pixel+CHANNEL] = r4_valid_r || r5_valid_r
                    || accum_valid_r;
                // PDS cannot resolve nested generate names; the owner drives the port.
                if (CHANNEL == 0 && pixel == 0) begin : g_valid_out
                    assign accum_valid_o = accum_valid_r;
                end

                always @(posedge clk_i or negedge rst_n_i) begin
                    if (!rst_n_i) begin
                        r4_valid_r <= 1'b0;
                        r5_valid_r <= 1'b0;
                        accum_valid_r <= 1'b0;
                    end else if (cancel_i) begin
                        r4_valid_r <= 1'b0;
                        r5_valid_r <= 1'b0;
                        accum_valid_r <= 1'b0;
                    end else begin
                        r4_valid_r <= sum_valid_i;
                        r5_valid_r <= r4_valid_r;
                        accum_valid_r <= r5_valid_r && r5_last_r;
                    end
                end
                always @(posedge clk_i) begin
                    r4_first_r <= sum_first_i;
                    r5_first_r <= r4_first_r;
                    r4_last_r <= sum_last_i;
                    r5_last_r <= r4_last_r;
                    r4_fold_r <= sum_fold_i[32*pixel+CHANNEL];
                    r4_plain_r <= {sum_w[18], sum_w};
                    r5_data_r <= r4_fold_r ? r4_folded_r : r4_plain_r;
                end
                if (channel < 16) begin : g_low
                    wire signed [18:0] high_sum_w;
                    assign high_sum_w = sum_data_i[19*(32*pixel+CHANNEL+16) +: 19];
                    // Only one carry addition occupies R4; the wide mux is in R5.
                    always @(posedge clk_i) begin
                        r4_folded_r <= {sum_w[18], sum_w}
                            + {high_sum_w[18], high_sum_w};
                    end
                end else begin : g_high
                    always @(posedge clk_i) begin
                        r4_folded_r <= 20'sd0;
                    end
                end
                // The feedback dependency remains one edge, one item per clock.
                always @(posedge clk_i) begin
                    if (r5_valid_r) begin
                        accum_data_r <= r5_first_r ? extended_w : accum_data_r + extended_w;
                    end
                end
                assign accum_data_o[32*(32*pixel+CHANNEL) +: 32] = accum_data_r;
            end
        end
    endgenerate

    // Preparation follows R4, one edge ahead of the final ACC vector.
    assign quant_prepare_valid_o = r4_prepare_r && !cancel_i;
    assign quant_prepare_tag_o = r4_tag_r;
    assign accum_tag_o = accum_tag_r;
    assign idle_o = ~|pixel_busy_w;
endmodule
