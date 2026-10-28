// File: edrv32_geo_coords.v
// Spec: geo-spec 2.1, 5.2.
// Description: Accumulate exact Q16.16 coordinates, advancing only on accepted pixels.
// Clock domain: clk_mem.
module edrv32_geo_coords (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,
    // Block setup and cancellation.
    input wire start_i,
    input wire clear_i,
    input wire [5:0] width_i,
    input wire [4:0] height_i,
    input wire [31:0] x_i,
    input wire [31:0] y_i,
    input wire [31:0] a_i,
    input wire [31:0] b_i,
    input wire [31:0] c_i,
    input wire [31:0] d_i,
    // Pixel stream, held under backpressure.
    output reg valid_o,
    input wire ready_i,
    output reg [31:0] x_o,
    output reg [31:0] y_o,
    output wire eol_o,
    output wire last_o
);
    reg [5:0] column_r;
    reg [4:0] row_r;
    reg [31:0] row_x_r;
    reg [31:0] row_y_r;
    assign eol_o = column_r == width_i - 6'd1;
    assign last_o = eol_o && row_r == height_i - 5'd1;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            valid_o <= 1'b0;
            column_r <= 6'd0;
            row_r <= 5'd0;
        end else if (clear_i) begin
            valid_o <= 1'b0;
        end else if (start_i) begin
            valid_o <= 1'b1;
            column_r <= 6'd0;
            row_r <= 5'd0;
        end else if (valid_o && ready_i) begin
            if (eol_o) begin
                column_r <= 6'd0;
                row_r <= row_r + 5'd1;
                if (last_o)
                    valid_o <= 1'b0;
            end else begin
                column_r <= column_r + 6'd1;
            end
        end
    end
    always @(posedge clk_i) begin
        if (start_i) begin
            row_x_r <= x_i;
            row_y_r <= y_i;
            x_o <= x_i;
            y_o <= y_i;
        end else if (valid_o && ready_i) begin
            if (eol_o) begin
                row_x_r <= row_x_r + b_i;
                row_y_r <= row_y_r + d_i;
                x_o <= row_x_r + b_i;
                y_o <= row_y_r + d_i;
            end else begin
                x_o <= x_o + a_i;
                y_o <= y_o + c_i;
            end
        end
    end
endmodule
