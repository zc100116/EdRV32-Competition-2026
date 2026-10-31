// File: edrv32_npu_descriptor.v
// Spec: npu-spec 4.1, 6; datapath design 4.2.3.
// Description: Capture the two descriptor beats and stage address selection and checks.
// Only the three CONV capacity limits and the OP encoding are checked.
// Clock: clk_npu.
module edrv32_npu_descriptor (
    // Clock and local cancellation.
    input wire clk_i,
    input wire rst_n_i,
    input wire cancel_i,

    // Descriptor DMA and four software base registers.
    input wire data_valid_i,
    input wire data_index_i,
    input wire [255:0] data_i,
    input wire decode_i,
    input wire [127:0] bases_i,
    output wire [511:0] desc_o,
    output wire [31:0] in_addr_o,
    output wire [31:0] out_addr_o,
    output wire [31:0] residual_addr_o,
    output wire [31:0] weight_addr_o,
    output wire [31:0] quant_addr_o,
    output wire done_o,
    output wire [2:0] error_o
);
    reg [511:0] desc_r;
    reg [31:0] in_addr_r;
    reg [31:0] out_addr_r;
    reg [31:0] residual_addr_r;
    reg [31:0] weight_addr_r;
    reg [31:0] quant_addr_r;
    reg [31:0] in_base_r;
    reg [31:0] out_base_r;
    reg [31:0] residual_base_r;
    reg pending_r;
    reg done_r;
    reg [2:0] error_r;
    reg [13:0] row_capacity_r;
    reg [23:0] weight_capacity_r;
    wire [31:0] unused_flags_w;
    wire [31:0] unused_blocks_w;
    wire [31:0] unused_row_w;
    assign unused_flags_w = desc_r[31:0];
    assign unused_blocks_w = desc_r[351:320];
    assign unused_row_w = desc_r[383:352];
    assign desc_o = desc_r;
    assign in_addr_o = in_addr_r;
    assign out_addr_o = out_addr_r;
    assign residual_addr_o = residual_addr_r;
    assign weight_addr_o = weight_addr_r;
    assign quant_addr_o = quant_addr_r;
    assign done_o = done_r;
    assign error_o = error_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            pending_r <= 1'b0;
            done_r <= 1'b0;
            error_r <= 3'd0;
        end else if (cancel_i) begin
            pending_r <= 1'b0;
            done_r <= 1'b0;
            error_r <= 3'd0;
        end else begin
            pending_r <= decode_i;
            done_r <= pending_r;
            if (decode_i) begin
                error_r <= 3'd0;
            end
            if (pending_r) begin
                if (unused_flags_w[3:0] > 4'd2) begin
                    error_r <= 3'd3;
                end else if ((unused_flags_w[3:0] == 4'd0) &&
                    ((row_capacity_r > 14'd1024) || (unused_blocks_w[11:8] > 4'd8)
                    || (weight_capacity_r > 24'd294912))) begin
                    error_r <= 3'd4;
                end
            end
        end
    end
    always @(posedge clk_i) begin
        if (data_valid_i) begin
            if (data_index_i) begin
                desc_r[511:256] <= data_i;
            end else begin
                desc_r[255:0] <= data_i;
            end
        end
        // Base selection and address addition occupy the two existing decode edges.
        if (pending_r) begin
            in_addr_r <= in_base_r + desc_r[63:32];
            out_addr_r <= out_base_r + desc_r[127:96];
            residual_addr_r <= residual_base_r + desc_r[191:160];
        end
        if (decode_i) begin
            in_base_r <= bases_i[32*unused_flags_w[13:12]+:32];
            out_base_r <= bases_i[32*unused_flags_w[15:14]+:32];
            residual_base_r <= bases_i[32*unused_flags_w[17:16]+:32];
            weight_addr_r <= bases_i[31:0] + desc_r[223:192];
            quant_addr_r <= bases_i[31:0] + desc_r[255:224];
            row_capacity_r <= {3'd0, unused_row_w[10:0]} * (unused_flags_w[4] ? 14'd5 : 14'd2);
            weight_capacity_r <= {20'd0, unused_blocks_w[11:8]} * {4'd0, desc_r[403:384]};
        end
    end
endmodule
