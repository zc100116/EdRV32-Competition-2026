// File: edrv32_cpu2_div.v
// Spec: cpu-v2-spec 2.3, 3.5, 5.4; interface freeze C05/C07.
// Description: Shared integer div with local completion storage and inclusive age cancellation.
// Clock domain: clk_sys.
module edrv32_cpu2_div #(
    parameter ISSUE_WIDTH = 2,
    parameter [31:0] FPU_FORMAT = "NONE"
) (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Age-selected issue request.
    input wire div_req_valid_i,
    output wire div_req_ready_o,
    input wire [(FPU_FORMAT == "NONE" ? 2 : FPU_FORMAT == "F" ? 3 : 4)-1:0] div_req_tag_i,
    input wire [31:0] div_req_instr_i,
    input wire [31:0] div_req_src1_i,
    input wire [31:0] div_req_src2_i,

    // Local completion source; integer results are zero extended in FD.
    output wire div_complete_valid_o,
    input wire div_complete_ready_i,
    output wire [(FPU_FORMAT == "NONE" ? 2 : FPU_FORMAT == "F" ? 3 : 4)-1:0] div_complete_tag_o,
    output wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] div_complete_data_o,
    output wire [4:0] div_complete_flags_o,
    output wire div_complete_exception_o,
    output wire [3:0] div_complete_cause_o,
    output wire [31:0] div_complete_tval_o,

    // C05: compare distances from the current head, including the cancel boundary.
    input wire [(FPU_FORMAT == "NONE" ? 2 : FPU_FORMAT == "F" ? 3 : 4)-1:0] age_head_i,
    input wire cancel_valid_i,
    input wire [(FPU_FORMAT == "NONE" ? 2 : FPU_FORMAT == "F" ? 3 : 4)-1:0] cancel_tag_i
);
    localparam TAG_WIDTH = FPU_FORMAT == "NONE" ? 2 : FPU_FORMAT == "F" ? 3 : 4;
    localparam DATA_WIDTH = FPU_FORMAT == "FD" ? 64 : 32;
    wire [TAG_WIDTH-1:0] cancel_distance_w;
    wire [TAG_WIDTH-1:0] request_distance_w;
    wire request_cancel_w;
    assign cancel_distance_w = cancel_tag_i - age_head_i;
    assign request_distance_w = div_req_tag_i - age_head_i;
    assign request_cancel_w = cancel_valid_i && request_distance_w >= cancel_distance_w;
    assign div_complete_flags_o = 5'b0;
    assign div_complete_exception_o = 1'b0;
    assign div_complete_cause_o = 4'b0;
    assign div_complete_tval_o = 32'b0;
    localparam S_IDLE = 3'd0;
    localparam S_PREPARE = 3'd1;
    localparam S_ALIGN = 3'd2;
    localparam S_ITERATE = 3'd3;
    localparam S_CORRECT = 3'd4;
    localparam DIGIT_BITS = ISSUE_WIDTH == 1 ? 1 : 2;
    reg [2:0] state_r;
    reg [TAG_WIDTH-1:0] tag_r;
    reg [31:0] src1_r;
    reg [31:0] src2_r;
    reg signed_r;
    reg remainder_select_r;
    reg quotient_negative_r;
    reg remainder_negative_r;
    reg special_r;
    reg [31:0] special_data_r;
    reg [31:0] magnitude_a_r;
    reg [31:0] magnitude_b_r;
    reg [5:0] rounds_r;
    reg [4:0] alignment_r;
    reg [4:0] difference_r;
    reg zero_work_r;
    reg [34:0] triple_b_r;
    reg [31:0] remainder_r;
    reg [31:0] quotient_r;
    reg [34:0] divisor_r;
    reg [34:0] divisor_three_r;
    reg complete_valid_r;
    reg [TAG_WIDTH-1:0] complete_tag_r;
    reg [31:0] complete_data_r;
    wire [TAG_WIDTH-1:0] run_distance_w;
    wire [TAG_WIDTH-1:0] complete_distance_w;
    wire run_cancel_w;
    wire complete_cancel_w;
    wire accept_w;
    wire finish_w;
    wire final_state_w;
    wire [31:0] length_a_input_w;
    wire [31:0] length_b_input_w;
    wire [4:0] difference_w;
    wire zero_work_w;
    wire [34:0] subtract_one_w;
    wire [34:0] subtract_two_w;
    wire [34:0] subtract_three_w;
    reg [31:0] next_remainder_w;
    reg [1:0] digit_w;
    wire [31:0] corrected_quotient_w;
    wire [31:0] corrected_remainder_w;

    assign run_distance_w = tag_r - age_head_i;
    assign complete_distance_w = complete_tag_r - age_head_i;
    assign run_cancel_w = cancel_valid_i && run_distance_w >= cancel_distance_w;
    assign complete_cancel_w = cancel_valid_i && complete_distance_w >= cancel_distance_w;
    assign final_state_w = state_r == S_CORRECT || (state_r == S_ALIGN && special_r);
    // A separate result register permits the next E0 on the preceding operation's final edge.
    assign div_req_ready_o = state_r == S_IDLE || (final_state_w && !complete_valid_r);
    assign accept_w = div_req_valid_i && div_req_ready_o && !request_cancel_w;
    assign finish_w = final_state_w && !complete_valid_r && !run_cancel_w;
    assign div_complete_valid_o = complete_valid_r;
    assign div_complete_tag_o = complete_tag_r;
    assign div_complete_data_o = {{(DATA_WIDTH-32){1'b0}}, complete_data_r};
    // E0 magnitude capture is parallel to raw operand capture. E1 encodes their
    // leading positions and registers the bit-length difference; E2 forms n and aligns.
    assign length_a_input_w = magnitude_a_r;
    assign length_b_input_w = magnitude_b_r;
    // Four byte encoders run in parallel, followed by two balanced merge levels.
    function [2:0] position8;
        input [7:0] value_i;
        begin
            position8 = 3'd0;
            casez (value_i)
                8'b1???????: position8 = 3'd7;
                8'b01??????: position8 = 3'd6;
                8'b001?????: position8 = 3'd5;
                8'b0001????: position8 = 3'd4;
                8'b00001???: position8 = 3'd3;
                8'b000001??: position8 = 3'd2;
                8'b0000001?: position8 = 3'd1;
                default: position8 = 3'd0;
            endcase
        end
    endfunction
    wire [4:0] top_a_w;
    wire [3:0] low_a_w;
    wire [3:0] high_a_w;
    assign high_a_w = |length_a_input_w[31:24] ?
        {1'b1, position8(length_a_input_w[31:24])} :
        {1'b0, position8(length_a_input_w[23:16])};
    assign low_a_w = |length_a_input_w[15:8] ?
        {1'b1, position8(length_a_input_w[15:8])} :
        {1'b0, position8(length_a_input_w[7:0])};
    assign top_a_w = |length_a_input_w[31:16] ?
        {1'b1, high_a_w} : {1'b0, low_a_w};
    wire [4:0] top_b_w;
    wire [3:0] low_b_w;
    wire [3:0] high_b_w;
    assign high_b_w = |length_b_input_w[31:24] ?
        {1'b1, position8(length_b_input_w[31:24])} :
        {1'b0, position8(length_b_input_w[23:16])};
    assign low_b_w = |length_b_input_w[15:8] ?
        {1'b1, position8(length_b_input_w[15:8])} :
        {1'b0, position8(length_b_input_w[7:0])};
    assign top_b_w = |length_b_input_w[31:16] ?
        {1'b1, high_b_w} : {1'b0, low_b_w};
    assign difference_w = top_a_w - top_b_w;
    assign zero_work_w = magnitude_a_r == 0 || top_a_w < top_b_w;
    // Three parallel carry chains select a radix-4 digit; no cascaded subtract/compare.
    assign subtract_one_w = {3'b0, remainder_r} - divisor_r;
    assign subtract_two_w = {3'b0, remainder_r} - (divisor_r << 1);
    assign subtract_three_w = {3'b0, remainder_r} - divisor_three_r;
    always @(*) begin
        next_remainder_w = remainder_r;
        digit_w = 2'd0;
        if (ISSUE_WIDTH == 2 && !subtract_three_w[34]) begin
            next_remainder_w = subtract_three_w[31:0];
            digit_w = 2'd3;
        end else if (ISSUE_WIDTH == 2 && !subtract_two_w[34]) begin
            next_remainder_w = subtract_two_w[31:0];
            digit_w = 2'd2;
        end else if (!subtract_one_w[34]) begin
            next_remainder_w = subtract_one_w[31:0];
            digit_w = 2'd1;
        end
    end
    assign corrected_quotient_w = quotient_negative_r ? -quotient_r : quotient_r;
    assign corrected_remainder_w = remainder_negative_r ? -remainder_r : remainder_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            complete_valid_r <= 1'b0;
        end else begin
            if (complete_cancel_w || div_complete_ready_i)
                complete_valid_r <= 1'b0;
            if (finish_w)
                complete_valid_r <= 1'b1;
            if (run_cancel_w)
                state_r <= S_IDLE;
            else begin
                case (state_r)
                    S_PREPARE: state_r <= S_ALIGN;
                    S_ALIGN: begin
                        if (special_r) begin
                            if (finish_w)
                                state_r <= S_IDLE;
                        end else
                            state_r <= zero_work_r ? S_CORRECT : S_ITERATE;
                    end
                    S_ITERATE: begin
                        if (rounds_r == 1)
                            state_r <= S_CORRECT;
                    end
                    S_CORRECT: begin
                        if (finish_w)
                            state_r <= S_IDLE;
                    end
                    default: state_r <= state_r;
                endcase
            end
            if (accept_w)
                state_r <= S_PREPARE;
        end
    end

    always @(posedge clk_i) begin
        if (accept_w) begin
            tag_r <= div_req_tag_i;
            src1_r <= div_req_src1_i;
            src2_r <= div_req_src2_i;
            signed_r <= !div_req_instr_i[12];
            remainder_select_r <= div_req_instr_i[13];
            magnitude_a_r <= !div_req_instr_i[12] && div_req_src1_i[31] ?
                -div_req_src1_i : div_req_src1_i;
            magnitude_b_r <= !div_req_instr_i[12] && div_req_src2_i[31] ?
                -div_req_src2_i : div_req_src2_i;
        end
        if (state_r == S_PREPARE) begin
            quotient_negative_r <= signed_r && (src1_r[31] ^ src2_r[31]);
            remainder_negative_r <= signed_r && src1_r[31];
            difference_r <= difference_w;
            zero_work_r <= zero_work_w;
            alignment_r <= ISSUE_WIDTH == 1 ? difference_w : {difference_w[4:1], 1'b0};
            triple_b_r <= {3'b0, magnitude_b_r} + {2'b0, magnitude_b_r, 1'b0};
            special_r <= src2_r == 0 ||
                (signed_r && src1_r == 32'h80000000 && src2_r == 32'hffffffff);
            special_data_r <= remainder_select_r ?
                (src2_r == 0 ? src1_r : 32'b0) :
                (src2_r == 0 ? 32'hffffffff : 32'h80000000);
        end
        if (state_r == S_ALIGN) begin
            remainder_r <= magnitude_a_r;
            quotient_r <= 32'b0;
            divisor_r <= {3'b0, magnitude_b_r} << alignment_r;
            divisor_three_r <= triple_b_r << alignment_r;
            rounds_r <= zero_work_r ? 6'b0 :
                (ISSUE_WIDTH == 1 ? {1'b0, difference_r} + 6'd1 :
                {2'b0, difference_r[4:1]} + 6'd1);
        end
        if (state_r == S_ITERATE) begin
            rounds_r <= rounds_r - 6'd1;
            remainder_r <= next_remainder_w;
            quotient_r <= (quotient_r << DIGIT_BITS) | {30'b0, digit_w};
            divisor_r <= divisor_r >> DIGIT_BITS;
            divisor_three_r <= divisor_three_r >> DIGIT_BITS;
        end
        if (finish_w) begin
            complete_tag_r <= tag_r;
            complete_data_r <= special_r ? special_data_r :
                (remainder_select_r ? corrected_remainder_w : corrected_quotient_w);
        end
    end
    wire unused_w = ^{div_req_instr_i[31:14], div_req_instr_i[11:0],
        subtract_one_w[33:32], subtract_two_w[33:32], subtract_three_w[33:32]};
endmodule
