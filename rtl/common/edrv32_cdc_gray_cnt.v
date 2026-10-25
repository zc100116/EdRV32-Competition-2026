// File: edrv32_cdc_gray_cnt.v
// Spec: edrv32-soc-spec 5.2, 5.3; infra-plan I-06
// Description: Register and synchronize a unit-step binary counter through Gray code.
//              Interface and use constraints are in rtl/common/README.md.
// Clock domain: ports identify the source and destination clocks.
module edrv32_cdc_gray_cnt #(
    parameter WIDTH = 8
) (
    // Clock domains and their resets.
    input wire clk_src_i,
    input wire rst_src_n_i,
    input wire clk_dst_i,
    input wire rst_dst_n_i,

    // Source binary count; changes by at most one per source cycle.
    input wire [WIDTH-1:0] count_i,

    // Destination binary snapshot.
    output wire [WIDTH-1:0] count_o
);
    reg [WIDTH-1:0] gray_r;
    reg [WIDTH-1:0] meta_r;
    reg [WIDTH-1:0] sync_r;
    genvar bit_idx;

    always @(posedge clk_src_i or negedge rst_src_n_i) begin
        if (!rst_src_n_i) begin
            gray_r <= {WIDTH{1'b0}};
        end else begin
            gray_r <= count_i ^ (count_i >> 1);
        end
    end

    always @(posedge clk_dst_i or negedge rst_dst_n_i) begin
        if (!rst_dst_n_i) begin
            meta_r <= {WIDTH{1'b0}};
            sync_r <= {WIDTH{1'b0}};
        end else begin
            meta_r <= gray_r;
            sync_r <= meta_r;
        end
    end

    generate
        for (bit_idx = 0; bit_idx < WIDTH; bit_idx = bit_idx + 1) begin : g_decode
            assign count_o[bit_idx] = ^sync_r[WIDTH-1:bit_idx];
        end
    endgenerate
endmodule
