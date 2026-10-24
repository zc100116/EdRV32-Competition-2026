// ============================================================================
// File        : edrv32_yolo_mac_array.v
// Description : 32 output channels x 8 reduction terms x 2 pixels, INT8 MAC.
// Notes       : 512 signed products/cycle from 256 SIMD APMs. Each input beat
//               carries 256 weight bytes and 16 activation bytes. A global
//               clock enable freezes the entire six-cycle pipeline on output
//               backpressure. Preserved local CE drivers serve one output
//               channel each; the scheduler honors in_ready_o.
// ============================================================================

module edrv32_yolo_mac_array #(
    parameter integer ACTIVATION_GROUPS = 1,
    parameter integer FINAL_ONLY_BACKPRESSURE = 0
) (
    input  wire          clk_i,
    input  wire          rst_n_i,
    input  wire          in_valid_i,
    output wire          in_ready_o,
    output wire [31:0]   in_group_ready_o,
    input  wire          in_first_i,
    input  wire          in_last_i,
    input  wire [ACTIVATION_GROUPS*128-1:0] in_activation_i,
    input  wire [2047:0] in_weight_i,
    output wire          out_valid_o,
    input  wire          out_ready_i,
    output wire          out_last_o,
    output wire [2047:0] out_accum_o
);

    wire advance_w;
    reg [4:0] valid_pipe_r;
    reg [4:0] first_pipe_r;
    reg [4:0] last_pipe_r;
    reg out_valid_r;
    reg out_last_r;

    assign advance_w   = out_ready_i || !out_valid_r ||
                         (FINAL_ONLY_BACKPRESSURE && !out_last_r);
    assign in_ready_o  = advance_w;
    assign out_valid_o = out_valid_r;
    assign out_last_o  = out_last_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            valid_pipe_r <= 5'b0;
            first_pipe_r <= 5'b0;
            last_pipe_r  <= 5'b0;
            out_valid_r  <= 1'b0;
            out_last_r   <= 1'b0;
        end else if (advance_w) begin
            valid_pipe_r <= {valid_pipe_r[3:0], in_valid_i};
            first_pipe_r <= {first_pipe_r[3:0], in_first_i};
            last_pipe_r  <= {last_pipe_r[3:0], in_last_i};
            out_valid_r  <= valid_pipe_r[4];
            out_last_r   <= last_pipe_r[4];
        end
    end

    genvar oc;
    genvar k;
    genvar pixel;
    genvar ce_group;
    generate
        for (ce_group = 0; ce_group < 32; ce_group = ce_group + 1) begin : g_ce
            // Each output channel has a separate control driver. Keep the
            // equivalent registers so placement can keep CE routes local.
            (* syn_preserve = 1 *) reg valid_r;
            (* syn_preserve = 1 *) reg last_r;
            (* syn_keep = 1 *) wire local_advance_w =
                out_ready_i || !valid_r ||
                (FINAL_ONLY_BACKPRESSURE && !last_r);
            assign in_group_ready_o[ce_group] = local_advance_w;

            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    valid_r <= 1'b0;
                    last_r  <= 1'b0;
                end else if (advance_w) begin
                    valid_r <= valid_pipe_r[4];
                    last_r  <= last_pipe_r[4];
                end
            end
        end

        for (oc = 0; oc < 32; oc = oc + 1) begin : g_oc
            localparam integer ACTIVATION_OFFSET =
                ACTIVATION_GROUPS == 1 ? 0 : (oc / 8) * 128;
            wire local_advance_w = g_ce[oc].local_advance_w;
            wire signed [15:0] product0_w [0:7];
            wire signed [15:0] product1_w [0:7];

            for (k = 0; k < 8; k = k + 1) begin : g_k
                edrv32_yolo_apm_mul2 u_mul2 (
                    .clk_i   (clk_i),
                    .rst_n_i (rst_n_i),
                    .ce_i    (local_advance_w),
                    .a0_i   (in_activation_i[ACTIVATION_OFFSET+k*8 +: 8]),
                    .b0_i   (in_weight_i[(oc*8+k)*8 +: 8]),
                    .a1_i   (in_activation_i[ACTIVATION_OFFSET+(8+k)*8 +: 8]),
                    .b1_i   (in_weight_i[(oc*8+k)*8 +: 8]),
                    .p0_o   (product0_w[k]),
                    .p1_o   (product1_w[k])
                );
            end

            for (pixel = 0; pixel < 2; pixel = pixel + 1) begin : g_pixel
                wire signed [15:0] product_w [0:7];
                reg signed [16:0] sum2_r [0:3];
                reg signed [17:0] sum4_r [0:1];
                reg signed [18:0] sum8_r;
                reg signed [31:0] accum_r;
                integer j;

                for (k = 0; k < 8; k = k + 1) begin : g_select
                    assign product_w[k] = pixel == 0 ? product0_w[k] : product1_w[k];
                end

                always @(posedge clk_i) begin
                    if (local_advance_w) begin
                        for (j = 0; j < 4; j = j + 1)
                            sum2_r[j] <= $signed(product_w[2*j]) +
                                         $signed(product_w[2*j+1]);
                        sum4_r[0] <= $signed(sum2_r[0]) + $signed(sum2_r[1]);
                        sum4_r[1] <= $signed(sum2_r[2]) + $signed(sum2_r[3]);
                        sum8_r    <= $signed(sum4_r[0]) + $signed(sum4_r[1]);
                    end
                end

                always @(posedge clk_i) begin
                    if (local_advance_w && valid_pipe_r[4]) begin
                        if (first_pipe_r[4])
                            accum_r <= {{13{sum8_r[18]}}, sum8_r};
                        else
                            accum_r <= accum_r + {{13{sum8_r[18]}}, sum8_r};
                    end
                end

                assign out_accum_o[(pixel*32+oc)*32 +: 32] = accum_r;
            end
        end
    endgenerate

endmodule
