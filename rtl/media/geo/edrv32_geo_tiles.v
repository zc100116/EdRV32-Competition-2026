// File: edrv32_geo_tiles.v
// Spec: geo-spec 2.3, 5.2.
// Description: Partition the rectangle into nonoverlapping 32x16 blocks with recurrent origins.
// Clock domain: clk_mem.
module edrv32_geo_tiles (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,
    // Rectangle setup.
    input wire start_i,
    input wire clear_i,
    input wire [11:0] width_i,
    input wire [11:0] height_i,
    input wire [31:0] a_i,
    input wire [31:0] b_i,
    input wire [31:0] tx_i,
    input wire [31:0] c_i,
    input wire [31:0] d_i,
    input wire [31:0] ty_i,
    // Raster ordered blocks, including short right and bottom edges.
    output reg valid_o,
    input wire ready_i,
    output reg [11:0] u_o,
    output reg [11:0] v_o,
    output wire [5:0] width_o,
    output wire [4:0] height_o,
    output reg [31:0] x_o,
    output reg [31:0] y_o,
    output wire last_o
);
    reg [31:0] row_x_r;
    reg [31:0] row_y_r;
    wire [11:0] left_w;
    wire [11:0] rows_w;
    wire end_row_w;
    assign left_w = width_i - u_o;
    assign rows_w = height_i - v_o;
    assign width_o = left_w < 12'd32 ? left_w[5:0] : 6'd32;
    assign height_o = rows_w < 12'd16 ? rows_w[4:0] : 5'd16;
    assign end_row_w = left_w <= 12'd32;
    assign last_o = end_row_w && rows_w <= 12'd16;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            valid_o <= 1'b0;
            u_o <= 12'd0;
            v_o <= 12'd0;
        end else if (clear_i) begin
            valid_o <= 1'b0;
        end else if (start_i) begin
            valid_o <= width_i != 12'd0 && height_i != 12'd0;
            u_o <= 12'd0;
            v_o <= 12'd0;
        end else if (valid_o && ready_i) begin
            if (end_row_w) begin
                u_o <= 12'd0;
                v_o <= v_o + 12'd16;
            end else begin
                u_o <= u_o + 12'd32;
            end
            if (last_o)
                valid_o <= 1'b0;
        end
    end
    always @(posedge clk_i) begin
        if (start_i) begin
            x_o <= tx_i;
            y_o <= ty_i;
            row_x_r <= tx_i;
            row_y_r <= ty_i;
        end else if (valid_o && ready_i) begin
            if (end_row_w) begin
                row_x_r <= row_x_r + (b_i << 4);
                row_y_r <= row_y_r + (d_i << 4);
                x_o <= row_x_r + (b_i << 4);
                y_o <= row_y_r + (d_i << 4);
            end else begin
                x_o <= x_o + (a_i << 5);
                y_o <= y_o + (c_i << 5);
            end
        end
    end
endmodule
