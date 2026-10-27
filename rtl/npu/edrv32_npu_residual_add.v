// File: edrv32_npu_residual_add.v
// Spec: npu-spec 2.3, 5.4; npu-datapath design 4.2.4, 4.3.1.
// Description: WB1 computes signed 10-bit y+r-zp for both planes. WB2 saturates
// combinationally into the result RAM write boundary, including equal-latency bypass.
// Clock: clk_npu.
module edrv32_npu_residual_add (
    // Clock and control.
    input wire clk_i,
    input wire rst_n_i,
    input wire cancel_i,

    // Q12 pair and the unstallable residual RAM return.
    input wire quant_valid_i,
    input wire [48:0] quant_tag_i,
    input wire [511:0] quant_data_i,
    input wire residual_rd_valid_i,
    input wire [255:0] residual_rd_data_i,

    // WB2 combinational RAM write inputs.
    output wire writeback_valid_o,
    output wire [48:0] writeback_tag_o,
    output wire [511:0] writeback_data_o,

    // Local status.
    output wire idle_o
);
    reg [255:0] residual_low_r;
    reg wb1_valid_r;
    reg [48:0] wb1_tag_r;

    assign writeback_valid_o = wb1_valid_r && !cancel_i;
    assign writeback_tag_o = wb1_tag_r;
    assign idle_o = !quant_valid_i && !wb1_valid_r;

    // Low is retained at Q12; high returns directly in time for WB1.
    always @(posedge clk_i) begin
        if (residual_rd_valid_i) begin
            residual_low_r <= residual_rd_data_i;
        end
        if (quant_valid_i) begin
            wb1_tag_r <= quant_tag_i;
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            wb1_valid_r <= 1'b0;
        end else if (cancel_i) begin
            wb1_valid_r <= 1'b0;
        end else begin
            wb1_valid_r <= quant_valid_i;
        end
    end

    genvar lane;
    generate
        for (lane = 0; lane < 64; lane = lane + 1) begin : g_lane
            wire [7:0] quant_w;
            wire [7:0] residual_w;
            wire signed [9:0] quant_signed_w;
            wire signed [9:0] residual_signed_w;
            wire signed [9:0] zp_signed_w;
            reg signed [9:0] wb1_sum_r;

            assign quant_w = quant_data_i[8*lane +: 8];
            if (lane < 32) begin : g_low
                assign residual_w = residual_low_r[8*lane +: 8];
            end else begin : g_high
                assign residual_w = residual_rd_data_i[8*(lane-32) +: 8];
            end
            assign quant_signed_w = {{2{quant_w[7]}}, quant_w};
            assign residual_signed_w = {{2{residual_w[7]}}, residual_w};
            assign zp_signed_w = {{2{quant_tag_i[36]}}, quant_tag_i[36:29]};

            always @(posedge clk_i) begin
                if (quant_valid_i) begin
                    if ((lane >= 32) && quant_tag_i[26]) begin
                        wb1_sum_r <= 10'sd0;
                    end else if (quant_tag_i[28]) begin
                        wb1_sum_r <= quant_signed_w + residual_signed_w - zp_signed_w;
                    end else begin
                        wb1_sum_r <= quant_signed_w;
                    end
                end
            end

            assign writeback_data_o[8*lane +: 8] = (wb1_sum_r > 10'sd127) ? 8'h7f
                : (wb1_sum_r < -10'sd128) ? 8'h80 : wb1_sum_r[7:0];
        end
    endgenerate
endmodule
