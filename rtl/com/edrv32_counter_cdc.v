// ============================================================================
// File        : edrv32_counter_cdc.v
// Description : Gray-coded monotonic counter snapshot across clock domains.
// Notes       : The source counter advances monotonically by at most one per
//               source edge. Software observes an eventually consistent
//               snapshot rather than every intermediate count.
// ============================================================================

module edrv32_counter_cdc #(
    parameter integer WIDTH = 32
) (
    input  wire                 src_clk_i,
    input  wire                 src_rst_n_i,
    input  wire [WIDTH-1:0]     src_count_i,
    input  wire                 dst_clk_i,
    input  wire                 dst_rst_n_i,
    output wire [WIDTH-1:0]     dst_count_o
);

    reg [WIDTH-1:0] src_gray_r;
    reg [WIDTH-1:0] dst_gray_meta_r;
    reg [WIDTH-1:0] dst_gray_sync_r;
    reg [WIDTH-1:0] dst_count_r;
    integer bit_index;

    always @(posedge src_clk_i or negedge src_rst_n_i) begin
        if (!src_rst_n_i)
            src_gray_r <= {WIDTH{1'b0}};
        else
            src_gray_r <= src_count_i ^ (src_count_i >> 1);
    end

    always @(posedge dst_clk_i or negedge dst_rst_n_i) begin
        if (!dst_rst_n_i) begin
            dst_gray_meta_r <= {WIDTH{1'b0}};
            dst_gray_sync_r <= {WIDTH{1'b0}};
        end else begin
            dst_gray_meta_r <= src_gray_r;
            dst_gray_sync_r <= dst_gray_meta_r;
        end
    end

    always @(*) begin
        dst_count_r[WIDTH-1] = dst_gray_sync_r[WIDTH-1];
        for (bit_index = WIDTH - 2; bit_index >= 0;
             bit_index = bit_index - 1)
            dst_count_r[bit_index] =
                dst_count_r[bit_index + 1] ^ dst_gray_sync_r[bit_index];
    end

    assign dst_count_o = dst_count_r;

endmodule
