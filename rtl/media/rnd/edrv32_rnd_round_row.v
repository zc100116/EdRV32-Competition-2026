// File: edrv32_rnd_round_row.v
// Spec: rnd-spec 2.3.
// Description: Pipeline radius/row geometry and factor the Q4 radicand before an iterative
//              square root. Row/edge handshakes absorb the fixed preparation latency.
// Clock domain: clk_mem (clk_i).
module edrv32_rnd_round_row (
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
    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_CLAMP = 3'd1;
    localparam [2:0] S_GEOMETRY = 3'd2;
    localparam [2:0] S_FACTORS = 3'd3;
    localparam [2:0] S_PRODUCT = 3'd4;
    localparam [2:0] S_ROOT = 3'd5;
    localparam [2:0] S_RESULT = 3'd6;
    reg [2:0] state_r;
    reg [4:0] step_r;
    reg [16:0] half_min_r;
    reg [16:0] bottom_distance_r;
    reg [16:0] row_y_r;
    reg [11:0] requested_radius_r;
    reg [11:0] radius_r;
    reg [16:0] jd_r;
    reg [15:0] radius_q4_r;
    reg [15:0] dy_r;
    reg signed [16:0] factor_difference_r;
    reg signed [17:0] factor_sum_r;
    reg [31:0] product_r;
    reg [31:0] radicand_r;
    reg [15:0] root_r;
    reg [17:0] remainder_r;
    reg curved_r;
    wire [11:0] dy_integer_w;
    wire corner_w;
    wire [31:0] root_input_w;
    wire [17:0] remainder_shift_w;
    wire [17:0] trial_w;
    wire [18:0] difference_w;
    wire root_bit_w;
    wire [15:0] root_next_w;
    wire unused_product_w;

    assign dy_integer_w = radius_r - jd_r[11:0] - 12'd1;
    assign corner_w = radius_r != 0 && jd_r < {5'd0, radius_r};
    assign row_ready_o = state_r == S_IDLE;
    assign edge_valid_o = state_r == S_RESULT;
    // Both operands hold through RESULT, including an arbitrarily stalled edge response.
    assign edge_q4_o = curved_r ? radius_q4_r - root_r : 16'd0;
    assign radius_o = radius_q4_r[15:4];
    assign root_input_w = step_r == 5'd16 ? product_r : radicand_r;
    // After n digits, remainder < 2*root+1 < 2^(n+1). Before digit 16 it fits 16 bits;
    // shifting by two therefore needs at most 18 bits, for every 32-bit radicand.
    assign remainder_shift_w = (remainder_r << 2) | {16'd0, root_input_w[31:30]};
    assign trial_w = {root_r, 2'b01};
    assign difference_w = {1'b0, remainder_shift_w} - {1'b0, trial_w};
    assign root_bit_w = !difference_w[18];
    assign root_next_w = {root_r[14:0], root_bit_w};
    assign unused_product_w = ^product_r[29:0];

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            step_r <= 5'd0;
        end else if (clear_i) begin
            state_r <= S_IDLE;
            step_r <= 5'd0;
        end else begin
            case (state_r)
                S_IDLE: if (row_valid_i)
                    state_r <= radius_i == 0 ? S_RESULT : S_CLAMP;
                S_CLAMP: state_r <= S_GEOMETRY;
                S_GEOMETRY: state_r <= corner_w ? S_FACTORS : S_RESULT;
                S_FACTORS: state_r <= S_PRODUCT;
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
            half_min_r <= (width_i < height_i ? width_i : height_i) >> 1;
            bottom_distance_r <= height_i - row_y_i - 17'd1;
            row_y_r <= row_y_i;
            requested_radius_r <= radius_i;
            if (radius_i == 0) begin
                radius_q4_r <= 16'd0;
                curved_r <= 1'b0;
            end
        end
        if (state_r == S_CLAMP) begin
            radius_r <= {5'd0, requested_radius_r} < half_min_r ?
                requested_radius_r : half_min_r[11:0];
            jd_r <= row_y_r < bottom_distance_r ? row_y_r : bottom_distance_r;
        end
        if (state_r == S_GEOMETRY) begin
            radius_q4_r <= {radius_r, 4'd0};
            dy_r <= {dy_integer_w, 4'h8};
            curved_r <= corner_w;
        end
        // (radius-dy)*(radius+dy) preserves the original square difference modulo 2^32.
        if (state_r == S_FACTORS) begin
            factor_difference_r <= $signed({1'b0, radius_q4_r}) - $signed({1'b0, dy_r});
            factor_sum_r <= $signed({2'd0, radius_q4_r}) + $signed({2'd0, dy_r});
        end
        if (state_r == S_PRODUCT) begin
            product_r <= factor_difference_r * factor_sum_r;
            root_r <= 16'd0;
            remainder_r <= 18'd0;
        end
        if (state_r == S_ROOT) begin
            radicand_r <= {root_input_w[29:0], 2'd0};
            root_r <= root_next_w;
            remainder_r <= root_bit_w ? difference_w[17:0] : remainder_shift_w;
        end
    end
endmodule
