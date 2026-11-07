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
    // Identical start decisions, copied by the core for local payload regions.
    input wire [9:0] start_payload_i,
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
    wire [31:0] absolute_a_w;
    wire [31:0] absolute_b_w;
    wire [31:0] exceptional_w;
    wire [31:0] final_w;
    assign absolute_a_w = signed_w && operand_a_i[31] ? -operand_a_i : operand_a_i;
    assign absolute_b_w = signed_w && operand_b_i[31] ? -operand_b_i : operand_b_i;
    assign exceptional_w = operation_i[1] ?
        (operand_b_i == 0 ? operand_a_i : 32'b0) :
        (operand_b_i == 0 ? 32'hffffffff : 32'h80000000);
    assign final_w = remainder_select_r ?
        (remainder_negative_r ? -remainder_w : remainder_w) :
        (quotient_negative_r ? -quotient_w : quotient_w);
    always @(posedge clk_i) begin
        if (start_i && !busy_o) begin
            quotient_negative_r <= signed_w && (operand_a_i[31] ^ operand_b_i[31]);
            remainder_negative_r <= signed_w && operand_a_i[31];
            remainder_select_r <= operation_i[1];
        end
    end
    genvar payload_half;
    genvar result_byte;
    generate
        for (payload_half = 0; payload_half < 2;
            payload_half = payload_half + 1) begin : g_payload
            always @(posedge clk_i) begin
                if (start_payload_i[payload_half] && !busy_o)
                    quotient_r[payload_half*16 +: 16] <= absolute_a_w[payload_half*16 +: 16];
                else if (busy_o)
                    quotient_r[payload_half*16 +: 16] <= quotient_w[payload_half*16 +: 16];
                if (start_payload_i[payload_half+2] && !busy_o)
                    divisor_r[payload_half*16 +: 16] <= absolute_b_w[payload_half*16 +: 16];
                if (start_payload_i[payload_half+4] && !busy_o)
                    remainder_r[payload_half*16 +: 16] <= 0;
                else if (busy_o)
                    remainder_r[payload_half*16 +: 16] <= remainder_w[payload_half*16 +: 16];
            end
        end
        for (result_byte = 0; result_byte < 4;
            result_byte = result_byte + 1) begin : g_result_byte
            // valid_o owns result visibility; each late start gate serves eight bits.
            always @(posedge clk_i) begin
                if (start_payload_i[result_byte+6] && !busy_o)
                    result_o[result_byte*8 +: 8] <= exceptional_w[result_byte*8 +: 8];
                else
                    result_o[result_byte*8 +: 8] <= final_w[result_byte*8 +: 8];
            end
        end
    endgenerate
endmodule
