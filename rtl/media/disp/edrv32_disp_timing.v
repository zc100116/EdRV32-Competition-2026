// File: edrv32_disp_timing.v
// Spec: disp-spec 2.1, 2.4.
// Description: Fixed CEA-861 720p60 raster, running independently of scan enable.
//              Coordinates and sync phase follow the legacy timing core.
// Clock domain: clk_pix (clk_i).
module edrv32_disp_timing (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Raster and frame boundaries.
    output wire hs_o,
    output wire vs_o,
    output wire de_o,
    output wire [10:0] x_o,
    output wire [9:0] y_o,
    output wire frame_start_o,
    output wire vblank_o
);
    reg frame_start_r;
    reg [10:0] horizontal_r;
    reg [9:0] vertical_r;
    wire horizontal_active_w;
    wire vertical_active_w;

    assign horizontal_active_w = horizontal_r >= 11'd260 && horizontal_r < 11'd1540;
    assign vertical_active_w = vertical_r >= 10'd25 && vertical_r < 10'd745;
    assign hs_o = horizontal_r < 11'd40;
    assign vs_o = vertical_r < 10'd5;
    assign de_o = horizontal_active_w && vertical_active_w;
    assign x_o = horizontal_active_w ? horizontal_r - 11'd260 : 11'd0;
    assign y_o = vertical_active_w ? vertical_r - 10'd25 : 10'd0;
    assign frame_start_o = frame_start_r;
    assign vblank_o = horizontal_r == 11'd0 && vertical_r == 10'd745;

    // Decode the next counter value one clock early; pulse phase stays at (260,25).
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            frame_start_r <= 1'b0;
        end else begin
            frame_start_r <= horizontal_r == 11'd259 && vertical_r == 10'd25;
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            horizontal_r <= 11'd0;
            vertical_r <= 10'd0;
        end else if (horizontal_r == 11'd1649) begin
            horizontal_r <= 11'd0;
            if (vertical_r == 10'd749) begin
                vertical_r <= 10'd0;
            end else begin
                vertical_r <= vertical_r + 10'd1;
            end
        end else begin
            horizontal_r <= horizontal_r + 11'd1;
        end
    end
endmodule
