// File: edrv32_rnd_round_row_ref.v
// Reference: unchanged arithmetic from 05088f4b; verification only.
// Spec: rnd-spec 2.3.
// Description: Clamp the radius and compute one Q4 row edge with an iterative square root.
//              Adapted from legacy render_round_row; full 12-bit radii and no border policy.
// Clock domain: clk_mem (clk_i).
module edrv32_rnd_round_row_ref (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,
    input wire clear_i,

    // Row request and edge response.
    input wire row_valid_i,
    output wire row_ready_o,
    input wire [16:0] width_i,
    input wire [16:0] height_i,
    input wire [16:0] row_y_i,
    input wire [11:0] radius_i,
    output wire edge_valid_o,
    input wire edge_ready_i,
    output wire [15:0] edge_q4_o,
    output wire [11:0] radius_o
);
    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_PRODUCT = 2'd1;
    localparam [1:0] S_ROOT = 2'd2;
    localparam [1:0] S_RESULT = 2'd3;
    reg [1:0] state_r;
    reg [4:0] step_r;
    reg [15:0] radius_q4_r;
    reg [15:0] dy_r;
    reg [15:0] root_r;
    reg [31:0] remainder_r;
    reg [31:0] radicand_r;
    reg [15:0] edge_r;
    wire [16:0] half_min_w;
    wire [11:0] radius_w;
    wire [16:0] jd_w;
    wire [15:0] dy_w;
    wire [31:0] remainder_shift_w;
    wire [31:0] trial_w;
    wire root_bit_w;
    wire [15:0] root_next_w;

    assign half_min_w = (width_i < height_i ? width_i : height_i) >> 1;
    assign radius_w = {5'd0, radius_i} < half_min_w ? radius_i : half_min_w[11:0];
    assign jd_w = row_y_i < height_i - 17'd1 - row_y_i ?
        row_y_i : height_i - 17'd1 - row_y_i;
    assign dy_w = (({4'd0, radius_w} - jd_w[15:0]) << 4) - 16'd8;
    assign row_ready_o = state_r == S_IDLE;
    assign edge_valid_o = state_r == S_RESULT;
    assign edge_q4_o = edge_r;
    assign radius_o = radius_q4_r[15:4];
    assign remainder_shift_w = (remainder_r << 2) | {30'd0, radicand_r[31:30]};
    assign trial_w = {14'd0, root_r, 2'b01};
    assign root_bit_w = remainder_shift_w >= trial_w;
    assign root_next_w = {root_r[14:0], root_bit_w};

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            step_r <= 5'd0;
        end else if (clear_i) begin
            state_r <= S_IDLE;
            step_r <= 5'd0;
        end else begin
            case (state_r)
                S_IDLE: if (row_valid_i) begin
                    if (radius_w != 0 && jd_w < {5'd0, radius_w})
                        state_r <= S_PRODUCT;
                    else
                        state_r <= S_RESULT;
                end
                S_PRODUCT: begin
                    step_r <= 5'd16;
                    state_r <= S_ROOT;
                end
                S_ROOT: begin
                    step_r <= step_r - 5'd1;
                    if (step_r == 5'd1)
                        state_r <= S_RESULT;
                end
                S_RESULT: if (edge_ready_i)
                    state_r <= S_IDLE;
                default: state_r <= state_r;
            endcase
        end
    end

    always @(posedge clk_i) begin
        if (state_r == S_IDLE && row_valid_i) begin
            radius_q4_r <= {radius_w, 4'd0};
            dy_r <= dy_w;
            edge_r <= 16'd0;
        end
        if (state_r == S_PRODUCT) begin
            radicand_r <= radius_q4_r * radius_q4_r - dy_r * dy_r;
            root_r <= 16'd0;
            remainder_r <= 32'd0;
        end
        if (state_r == S_ROOT) begin
            radicand_r <= {radicand_r[29:0], 2'd0};
            root_r <= root_next_w;
            remainder_r <= root_bit_w ? remainder_shift_w - trial_w : remainder_shift_w;
            if (step_r == 5'd1)
                edge_r <= radius_q4_r - root_next_w;
        end
    end
endmodule
