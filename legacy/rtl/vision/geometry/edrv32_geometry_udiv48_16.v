// ============================================================================
// File        : edrv32_geometry_udiv48_16.v
// Description : Iterative unsigned 48-by-16 divider for geometry setup.
// Notes       : One quotient bit is produced per cycle.  The divider is used
//               only while committing a new geometry configuration.
// ============================================================================

module edrv32_geometry_udiv48_16 (
    input  wire         clk_i,
    input  wire         rst_n_i,
    input  wire         start_i,
    input  wire [47:0]  dividend_i,
    input  wire [15:0]  divisor_i,

    output wire         busy_o,
    output wire         done_o,
    output wire         div_zero_o,
    output wire [47:0]  quotient_o
);

    reg busy_r;
    reg done_r;
    reg div_zero_r;
    reg [5:0] count_r;
    reg [47:0] dividend_r;
    reg [47:0] quotient_r;
    reg [16:0] remainder_r;
    reg [15:0] divisor_r;

    wire [16:0] shifted_remainder_w =
        {remainder_r[15:0], dividend_r[47]};
    wire subtract_w = shifted_remainder_w >= {1'b0, divisor_r};
    wire [16:0] next_remainder_w = subtract_w ?
        shifted_remainder_w - {1'b0, divisor_r} : shifted_remainder_w;
    wire [47:0] next_quotient_w = {quotient_r[46:0], subtract_w};

    assign busy_o = busy_r;
    assign done_o = done_r;
    assign div_zero_o = div_zero_r;
    assign quotient_o = quotient_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            busy_r <= 1'b0;
            done_r <= 1'b0;
            div_zero_r <= 1'b0;
            count_r <= 6'b0;
            dividend_r <= 48'b0;
            quotient_r <= 48'b0;
            remainder_r <= 17'b0;
            divisor_r <= 16'b0;
        end else begin
            done_r <= 1'b0;

            if (start_i && !busy_r) begin
                div_zero_r <= divisor_i == 16'b0;
                dividend_r <= dividend_i;
                quotient_r <= 48'b0;
                remainder_r <= 17'b0;
                divisor_r <= divisor_i;
                count_r <= 6'd48;
                if (divisor_i == 16'b0) begin
                    busy_r <= 1'b0;
                    done_r <= 1'b1;
                end else begin
                    busy_r <= 1'b1;
                end
            end else if (busy_r) begin
                dividend_r <= {dividend_r[46:0], 1'b0};
                quotient_r <= next_quotient_w;
                remainder_r <= next_remainder_w;
                count_r <= count_r - 1'b1;
                if (count_r == 6'd1) begin
                    busy_r <= 1'b0;
                    done_r <= 1'b1;
                end
            end
        end
    end

endmodule
