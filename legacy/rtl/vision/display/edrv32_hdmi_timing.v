// ============================================================================
// File        : edrv32_hdmi_timing.v
// Description : Parameterized progressive HDMI/DVI raster timing generator.
// ============================================================================

module edrv32_hdmi_timing #(
    parameter integer H_ACTIVE = 1280,
    parameter integer H_FP = 110,
    parameter integer H_SYNC = 40,
    parameter integer H_BP = 220,
    parameter integer V_ACTIVE = 720,
    parameter integer V_FP = 5,
    parameter integer V_SYNC = 5,
    parameter integer V_BP = 20,
    parameter integer H_POL = 1,
    parameter integer V_POL = 1
) (
    input  wire        clk_i,
    input  wire        rst_n_i,
    input  wire        enable_i,

    output wire        hs_o,
    output wire        vs_o,
    output wire        de_o,
    output wire [15:0] x_o,
    output wire [15:0] y_o,
    output wire        frame_start_o
);

    localparam integer H_TOTAL = H_SYNC + H_BP + H_ACTIVE + H_FP;
    localparam integer V_TOTAL = V_SYNC + V_BP + V_ACTIVE + V_FP;
    localparam integer H_START = H_SYNC + H_BP;
    localparam integer V_START = V_SYNC + V_BP;

    reg [15:0] h_count_r;
    reg [15:0] v_count_r;

    wire hsync_active_w = h_count_r < H_SYNC;
    wire vsync_active_w = v_count_r < V_SYNC;
    wire hactive_w = (h_count_r >= H_START) &&
        (h_count_r < (H_START + H_ACTIVE));
    wire vactive_w = (v_count_r >= V_START) &&
        (v_count_r < (V_START + V_ACTIVE));

    assign hs_o = H_POL ? hsync_active_w : !hsync_active_w;
    assign vs_o = V_POL ? vsync_active_w : !vsync_active_w;
    assign de_o = enable_i && hactive_w && vactive_w;
    assign x_o = hactive_w ? h_count_r - H_START : 16'b0;
    assign y_o = vactive_w ? v_count_r - V_START : 16'b0;
    assign frame_start_o = enable_i && (h_count_r == 0) &&
        (v_count_r == 0);

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            h_count_r <= 16'b0;
            v_count_r <= 16'b0;
        end else if (!enable_i) begin
            h_count_r <= 16'b0;
            v_count_r <= 16'b0;
        end else if (h_count_r == (H_TOTAL - 1)) begin
            h_count_r <= 16'b0;
            if (v_count_r == (V_TOTAL - 1))
                v_count_r <= 16'b0;
            else
                v_count_r <= v_count_r + 1'b1;
        end else begin
            h_count_r <= h_count_r + 1'b1;
        end
    end

endmodule
