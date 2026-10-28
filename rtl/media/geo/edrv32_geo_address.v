// File: edrv32_geo_address.v
// Spec: geo-spec 2.5, 5.2; dma2d-spec 2.1.
// Description: Form one block address using a 13-cycle shift/add surface-row product.
// Address setup overlaps block processing and does not occupy the pixel datapath.
// Clock domain: clk_mem.
module edrv32_geo_address (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,
    // Address setup; caller owns the request until done.
    input wire start_i,
    input wire clear_i,
    input wire [31:0] base_i,
    input wire [31:0] stride_i,
    input wire [12:0] row_i,
    input wire [12:0] column_i,
    // Completed byte address.
    output wire done_o,
    output reg [31:0] addr_o
);
    reg [3:0] remaining_r;
    reg [12:0] row_r;
    reg [31:0] stride_r;
    assign done_o = remaining_r == 4'd1;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            remaining_r <= 4'd0;
        else if (clear_i)
            remaining_r <= 4'd0;
        else if (start_i)
            remaining_r <= 4'd13;
        else if (remaining_r != 0)
            remaining_r <= remaining_r - 4'd1;
    end
    always @(posedge clk_i) begin
        if (start_i) begin
            addr_o <= base_i + {18'd0, column_i, 1'b0};
            stride_r <= stride_i;
            row_r <= row_i;
        end else if (remaining_r != 0) begin
            if (row_r[0])
                addr_o <= addr_o + stride_r;
            row_r <= {1'b0, row_r[12:1]};
            stride_r <= {stride_r[30:0], 1'b0};
        end
    end
endmodule
