// ============================================================================
// File        : edrv32_yolo_dfl16.v
// Description : One YOLOv8 DFL expectation from sixteen signed INT8 logits.
// Notes       : Uses a model-specific exp lookup and a serial restoring divide.
//               Output is unsigned Q8.8 in bin units; 0..15 maps to 0..3840.
// ============================================================================

module edrv32_yolo_dfl16 (
    input  wire         clk_i,
    input  wire         rst_n_i,
    input  wire         start_i,
    output wire         start_ready_o,
    input  wire [1:0]   scale_i,
    input  wire [127:0] logits_i,
    output wire         busy_o,
    output wire         done_o,
    output wire [11:0]  distance_o
);

    localparam [2:0] S_IDLE   = 3'd0;
    localparam [2:0] S_MAX    = 3'd1;
    localparam [2:0] S_DIFF   = 3'd2;
    localparam [2:0] S_LOOKUP = 3'd3;
    localparam [2:0] S_ACC    = 3'd4;
    localparam [2:0] S_DIV    = 3'd5;

    reg [2:0] state_r;
    reg [1:0] scale_r;
    reg [127:0] logits_r;
    reg [4:0] index_r;
    reg signed [7:0] maximum_r;
    reg [7:0] diff_r;
    reg [15:0] exp_r;
    reg [20:0] sum_r;
    reg [24:0] weighted_r;
    reg [31:0] dividend_r;
    reg [31:0] quotient_r;
    reg [21:0] remainder_r;
    reg [5:0] div_index_r;
    reg [11:0] distance_r;
    reg done_r;

    wire signed [7:0] selected_w =
        $signed(logits_r[{index_r[3:0], 3'b000} +: 8]);
    wire signed [8:0] signed_diff_w =
        $signed({maximum_r[7], maximum_r}) -
        $signed({selected_w[7], selected_w});
    wire [7:0] diff_w = signed_diff_w[7:0];
    wire [15:0] exp_w;
    wire [19:0] weighted_term_w =
        (index_r[0] ? {4'd0, exp_r} : 20'd0) +
        (index_r[1] ? {3'd0, exp_r, 1'd0} : 20'd0) +
        (index_r[2] ? {2'd0, exp_r, 2'd0} : 20'd0) +
        (index_r[3] ? {1'd0, exp_r, 3'd0} : 20'd0);
    wire [21:0] trial_w = {remainder_r[20:0], dividend_r[31]};
    wire subtract_w = trial_w >= {1'b0, sum_r};
    wire [21:0] remainder_next_w = subtract_w ?
        trial_w - {1'b0, sum_r} : trial_w;
    wire [31:0] quotient_next_w = {quotient_r[30:0], subtract_w};

    edrv32_yolo_v8n_post_lut u_lut (
        .scale_i(scale_r), .diff_i(diff_r), .cls_code_i(8'd0),
        .exp_o(exp_w), .confidence_o()
    );

    assign start_ready_o = state_r == S_IDLE;
    assign busy_o = state_r != S_IDLE;
    assign done_o = done_r;
    assign distance_o = distance_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            scale_r <= 2'd0;
            logits_r <= 128'd0;
            index_r <= 5'd0;
            maximum_r <= 8'sh80;
            diff_r <= 8'd0;
            exp_r <= 16'd0;
            sum_r <= 21'd0;
            weighted_r <= 25'd0;
            dividend_r <= 32'd0;
            quotient_r <= 32'd0;
            remainder_r <= 22'd0;
            div_index_r <= 6'd0;
            distance_r <= 12'd0;
            done_r <= 1'b0;
        end else begin
            done_r <= 1'b0;
            case (state_r)
                S_IDLE: if (start_i) begin
                    scale_r <= scale_i;
                    logits_r <= logits_i;
                    index_r <= 5'd0;
                    maximum_r <= 8'sh80;
                    state_r <= S_MAX;
                end
                S_MAX: begin
                    if (selected_w > maximum_r)
                        maximum_r <= selected_w;
                    if (index_r == 5'd15) begin
                        index_r <= 5'd0;
                        sum_r <= 21'd0;
                        weighted_r <= 25'd0;
                        state_r <= S_DIFF;
                    end else
                        index_r <= index_r + 5'd1;
                end
                S_DIFF: begin
                    diff_r <= diff_w;
                    state_r <= S_LOOKUP;
                end
                S_LOOKUP: begin
                    exp_r <= exp_w;
                    state_r <= S_ACC;
                end
                S_ACC: begin
                    sum_r <= sum_r + {5'd0, exp_r};
                    weighted_r <= weighted_r + {5'd0, weighted_term_w};
                    if (index_r == 5'd15) begin
                        index_r <= 5'd0;
                        state_r <= S_DIV;
                        dividend_r <=
                            {weighted_r[23:0] + {4'd0, weighted_term_w}, 8'd0};
                        quotient_r <= 32'd0;
                        remainder_r <= 22'd0;
                        div_index_r <= 6'd0;
                    end else begin
                        index_r <= index_r + 5'd1;
                        state_r <= S_DIFF;
                    end
                end
                S_DIV: begin
                    dividend_r <= {dividend_r[30:0], 1'b0};
                    quotient_r <= quotient_next_w;
                    remainder_r <= remainder_next_w;
                    if (div_index_r == 6'd31) begin
                        distance_r <= quotient_next_w[11:0];
                        done_r <= 1'b1;
                        state_r <= S_IDLE;
                    end else
                        div_index_r <= div_index_r + 6'd1;
                end
                default: state_r <= S_IDLE;
            endcase
        end
    end
endmodule
