// File: edrv32_cpu_div.v
// Spec: cpu-spec 4.8
// Description: Execute signed and unsigned division or remainder by radix-two iteration.
// Return divide-by-zero and signed-overflow results without iteration.
// Clock domain: clk_sys.
module edrv32_cpu_div (
    // Clock and reset of iterative control.
    input wire clk_i,
    input wire rst_n_i,
    // Request accepted when busy_o is low; operation is funct3[1:0].
    input wire start_i,
    input wire [31:0] operand_a_i,
    input wire [31:0] operand_b_i,
    input wire [1:0] operation_i,
    // Completion pulse: special cases one edge, ordinary division 33 edges.
    output reg busy_o,
    output reg valid_o,
    output reg [31:0] result_o
);
    reg [31:0] quotient_r;
    reg [31:0] divisor_r;
    reg [31:0] remainder_r;
    reg [5:0] count_r;
    reg quotient_negative_r;
    reg remainder_negative_r;
    reg remainder_select_r;
    wire signed_w;
    wire [32:0] shifted_w;
    wire subtract_w;
    wire [31:0] remainder_w;
    wire [31:0] quotient_w;
    assign signed_w = !operation_i[0];
    assign shifted_w = {remainder_r, quotient_r[31]};
    assign subtract_w = shifted_w >= {1'b0, divisor_r};
    assign remainder_w = subtract_w ? shifted_w[31:0] - divisor_r : shifted_w[31:0];
    assign quotient_w = {quotient_r[30:0], subtract_w};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            busy_o <= 1'b0;
            valid_o <= 1'b0;
            count_r <= 0;
        end else begin
            valid_o <= 1'b0;
            if (start_i && !busy_o) begin
                if (operand_b_i == 0 ||
                    (signed_w && operand_a_i == 32'h80000000 && operand_b_i == 32'hffffffff))
                    valid_o <= 1'b1;
                else begin
                    busy_o <= 1'b1;
                    count_r <= 6'd32;
                end
            end else if (busy_o) begin
                count_r <= count_r - 1'b1;
                if (count_r == 1) begin
                    busy_o <= 1'b0;
                    valid_o <= 1'b1;
                end
            end
        end
    end
    always @(posedge clk_i) begin
        if (start_i && !busy_o) begin
            quotient_r <= signed_w && operand_a_i[31] ? -operand_a_i : operand_a_i;
            divisor_r <= signed_w && operand_b_i[31] ? -operand_b_i : operand_b_i;
            remainder_r <= 0;
            quotient_negative_r <= signed_w && (operand_a_i[31] ^ operand_b_i[31]);
            remainder_negative_r <= signed_w && operand_a_i[31];
            remainder_select_r <= operation_i[1];
            if (operand_b_i == 0)
                result_o <= operation_i[1] ? operand_a_i : 32'hffffffff;
            else if (signed_w && operand_a_i == 32'h80000000 && operand_b_i == 32'hffffffff)
                result_o <= operation_i[1] ? 32'b0 : 32'h80000000;
        end else if (busy_o) begin
            quotient_r <= quotient_w;
            remainder_r <= remainder_w;
            if (count_r == 1) begin
                if (remainder_select_r)
                    result_o <= remainder_negative_r ? -remainder_w : remainder_w;
                else
                    result_o <= quotient_negative_r ? -quotient_w : quotient_w;
            end
        end
    end
endmodule
