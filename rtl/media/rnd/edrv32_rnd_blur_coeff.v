// File: edrv32_rnd_blur_coeff.v
// Spec: rnd-spec 2.4.
// Description: Compute floor((65536+R)/(2R+1)) once per command in 17 divide steps.
//              The infrequent setup shares a small divider instead of a coefficient ROM.
// Clock domain: clk_mem (clk_i).
module edrv32_rnd_blur_coeff (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,
    input wire clear_i,

    // Radius request and fixed-point reciprocal response.
    input wire valid_i,
    output wire ready_o,
    input wire [4:0] radius_i,
    output wire valid_o,
    input wire ready_i,
    output wire [16:0] coefficient_o
);
    reg [4:0] step_r;
    reg active_r;
    reg valid_r;
    reg [5:0] divisor_r;
    reg [16:0] numerator_r;
    reg [16:0] quotient_r;
    reg [6:0] remainder_r;
    wire [6:0] shifted_w;
    wire bit_w;
    wire unused_remainder_w;
    assign ready_o = !active_r && !valid_r;
    assign valid_o = valid_r;
    assign coefficient_o = quotient_r;
    assign shifted_w = {remainder_r[5:0], numerator_r[16]};
    assign bit_w = shifted_w >= {1'b0, divisor_r};
    assign unused_remainder_w = remainder_r[6];
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            active_r <= 1'b0;
            valid_r <= 1'b0;
            step_r <= 5'd0;
        end else if (clear_i) begin
            active_r <= 1'b0;
            valid_r <= 1'b0;
            step_r <= 5'd0;
        end else begin
            if (valid_r && ready_i)
                valid_r <= 1'b0;
            if (valid_i && ready_o) begin
                active_r <= 1'b1;
                step_r <= 5'd17;
            end else if (active_r) begin
                step_r <= step_r - 5'd1;
                if (step_r == 1) begin
                    active_r <= 1'b0;
                    valid_r <= 1'b1;
                end
            end
        end
    end
    always @(posedge clk_i) begin
        if (valid_i && ready_o) begin
            divisor_r <= {radius_i, 1'b1};
            numerator_r <= 17'd65536 + {12'd0, radius_i};
            remainder_r <= 7'd0;
            quotient_r <= 17'd0;
        end else if (active_r) begin
            numerator_r <= {numerator_r[15:0], 1'b0};
            quotient_r <= {quotient_r[15:0], bit_w};
            remainder_r <= bit_w ? shifted_w - {1'b0, divisor_r} : shifted_w;
        end
    end
endmodule
