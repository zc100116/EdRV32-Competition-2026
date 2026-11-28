// File: edrv32_cpu2_mul.v
// Spec: cpu-v2-spec 2.3, 3.5, 5.2; interface freeze C05/C07 and A00 D05.
// Description: Shared integer mul with local completion storage and inclusive age cancellation.
// Clock domain: clk_sys.
module edrv32_cpu2_mul #(
    parameter ISSUE_WIDTH = 2,
    parameter [31:0] FPU_FORMAT = "NONE"
) (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Age-selected issue request.
    input wire mul_req_valid_i,
    output wire mul_req_ready_o,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] mul_req_tag_i,
    input wire [31:0] mul_req_instr_i,
    input wire [31:0] mul_req_src1_i,
    input wire [31:0] mul_req_src2_i,

    // Local completion source; integer results are zero extended in FD.
    output wire mul_complete_valid_o,
    input wire mul_complete_ready_i,
    output wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] mul_complete_tag_o,
    output wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] mul_complete_data_o,
    output wire [4:0] mul_complete_flags_o,
    output wire mul_complete_exception_o,
    output wire [3:0] mul_complete_cause_o,
    output wire [31:0] mul_complete_tval_o,

    // C05: compare distances from the current head, including the cancel boundary.
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] age_head_i,
    input wire cancel_valid_i,
    input wire [(ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3)-1:0] cancel_tag_i
);
    localparam TAG_WIDTH = ISSUE_WIDTH==2||FPU_FORMAT=="FD"?4:3;
    localparam DATA_WIDTH = FPU_FORMAT == "FD" ? 64 : 32;
    wire [TAG_WIDTH-1:0] cancel_distance_w;
    wire [TAG_WIDTH-1:0] request_distance_w;
    wire request_cancel_w;
    assign cancel_distance_w = cancel_tag_i - age_head_i;
    assign request_distance_w = mul_req_tag_i - age_head_i;
    assign request_cancel_w = cancel_valid_i && request_distance_w >= cancel_distance_w;
    assign mul_complete_flags_o = 5'b0;
    assign mul_complete_exception_o = 1'b0;
    assign mul_complete_cause_o = 4'b0;
    assign mul_complete_tval_o = 32'b0;
    // E0 captures 33-bit signed operands; E1 uses four standard 16/17-bit products.
    // E2 registers cross terms; the E3 final merge is captured at the consumer or local skid.
    reg [2:0] valid_r;
    wire [TAG_WIDTH-1:0] tag_w [0:2];
    wire [2:0] high_w;
    wire signed [32:0] operand_a_w;
    wire signed [32:0] operand_b_w;
    wire [31:0] low_product_w;
    wire signed [32:0] cross_a_w;
    wire signed [32:0] cross_b_w;
    wire signed [33:0] high_product_w;
    wire [31:0] captured_low_product_w;
    wire signed [32:0] captured_cross_a_w;
    wire signed [32:0] captured_cross_b_w;
    wire [31:0] captured_high_product_w;
    wire [63:0] base_w;
    wire signed [33:0] cross_w;
    wire [63:0] product_w;
    reg [1:0] count_r;
    reg [TAG_WIDTH-1:0] result_tag0_r;
    reg [TAG_WIDTH-1:0] result_tag1_r;
    reg [31:0] result_data0_r;
    reg [31:0] result_data1_r;
    reg [1:0] count_w;
    reg [TAG_WIDTH-1:0] result_tag0_w;
    reg [TAG_WIDTH-1:0] result_tag1_w;
    reg [31:0] result_data0_w;
    reg [31:0] result_data1_w;
    reg enable_r;
    wire [2:0] kill_w;
    wire [TAG_WIDTH-1:0] distance_w [0:2];
    wire [TAG_WIDTH-1:0] result_distance0_w;
    wire [TAG_WIDTH-1:0] result_distance1_w;
    wire keep0_w;
    wire keep1_w;
    wire push_w;
    genvar stage;
    generate
        for (stage = 0; stage < 3; stage = stage + 1) begin : g_cancel
            assign distance_w[stage] = tag_w[stage] - age_head_i;
            assign kill_w[stage] = cancel_valid_i &&
                distance_w[stage] >= cancel_distance_w;
        end
    endgenerate
    assign result_distance0_w = result_tag0_r - age_head_i;
    assign result_distance1_w = result_tag1_r - age_head_i;
    assign keep0_w = count_r != 0 && !mul_complete_ready_i &&
        !(cancel_valid_i && result_distance0_w >= cancel_distance_w);
    assign keep1_w = count_r == 2 &&
        !(cancel_valid_i && result_distance1_w >= cancel_distance_w);
    assign push_w = enable_r && valid_r[2] && !kill_w[2] &&
        (count_r != 0 || !mul_complete_ready_i);
    assign mul_req_ready_o = enable_r;
    assign mul_complete_valid_o = count_r != 0 || (enable_r && valid_r[2] && !kill_w[2]);
    assign mul_complete_tag_o = count_r != 0 ? result_tag0_r : tag_w[2];
    assign mul_complete_data_o = {{(DATA_WIDTH-32){1'b0}},
        (count_r != 0 ? result_data0_r : high_w[2] ? product_w[63:32] : product_w[31:0])};

    // Two local skid registers absorb the last enabled beat when registered capacity stops E0-E3.
    // Completion ready only reaches next-cycle capacity, never the multiplier/issue enable directly.
    always @(*) begin
        count_w = 2'd0;
        result_tag0_w = result_tag0_r;
        result_tag1_w = result_tag1_r;
        result_data0_w = result_data0_r;
        result_data1_w = result_data1_r;
        if (keep0_w) begin
            result_tag0_w = result_tag0_r;
            result_data0_w = result_data0_r;
            count_w = 2'd1;
        end
        if (keep1_w) begin
            if (keep0_w) begin
                result_tag1_w = result_tag1_r;
                result_data1_w = result_data1_r;
            end else begin
                result_tag0_w = result_tag1_r;
                result_data0_w = result_data1_r;
            end
            count_w = count_w + 2'd1;
        end
        if (push_w) begin
            if (count_w == 0) begin
                result_tag0_w = tag_w[2];
                result_data0_w = high_w[2] ? product_w[63:32] : product_w[31:0];
            end else begin
                result_tag1_w = tag_w[2];
                result_data1_w = high_w[2] ? product_w[63:32] : product_w[31:0];
            end
            count_w = count_w + 2'd1;
        end
    end

    integer index;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            valid_r <= 3'b0;
            count_r <= 2'b0;
            enable_r <= 1'b1;
        end else begin
            count_r <= count_w;
            enable_r <= count_w < 2;
            if (enable_r) begin
                valid_r[0] <= mul_req_valid_i && !request_cancel_w;
                for (index = 1; index < 3; index = index + 1)
                    valid_r[index] <= valid_r[index-1] && !kill_w[index-1];
            end else
                valid_r <= valid_r & ~kill_w;
        end
    end

    always @(posedge clk_i) begin
        result_tag0_r <= result_tag0_w;
        result_tag1_r <= result_tag1_w;
        result_data0_r <= result_data0_w;
        result_data1_r <= result_data1_w;
    end

    // Five regional capacity decodes drive at most eight leaf enable copies each.
    // Preserved leaf registers each control at most sixteen payload FFs; no global CE net.
    // All copies sample the same next capacity, so their logical enable matches enable_r.
    localparam PAYLOAD0_WIDTH = 66+TAG_WIDTH+1;
    wire [PAYLOAD0_WIDTH-1:0] payload0_w;
    wire [PAYLOAD0_WIDTH-1:0] next_payload0_w;
    (* syn_keep = 1 *) wire region0_0_w = count_w < 2;
    localparam PAYLOAD1_WIDTH = 130+TAG_WIDTH+1;
    wire [PAYLOAD1_WIDTH-1:0] payload1_w;
    wire [PAYLOAD1_WIDTH-1:0] next_payload1_w;
    (* syn_keep = 1 *) wire region1_0_w = count_w < 2;
    (* syn_keep = 1 *) wire region1_1_w = count_w < 2;
    localparam PAYLOAD2_WIDTH = 98+TAG_WIDTH+1;
    wire [PAYLOAD2_WIDTH-1:0] payload2_w;
    wire [PAYLOAD2_WIDTH-1:0] next_payload2_w;
    (* syn_keep = 1 *) wire region2_0_w = count_w < 2;
    assign next_payload0_w = {mul_req_tag_i, (|mul_req_instr_i[13:12]),
        (mul_req_src1_i[31] && mul_req_instr_i[13:12] != 2'b11), mul_req_src1_i,
        (mul_req_src2_i[31] && mul_req_instr_i[13:12] == 2'b01), mul_req_src2_i};
    assign {tag_w[0], high_w[0], operand_a_w, operand_b_w} = payload0_w;
    assign low_product_w = operand_a_w[15:0] * operand_b_w[15:0];
    assign cross_a_w = $signed({1'b0, operand_a_w[15:0]}) * $signed(operand_b_w[32:16]);
    assign cross_b_w = $signed(operand_a_w[32:16]) * $signed({1'b0, operand_b_w[15:0]});
    assign high_product_w = $signed(operand_a_w[32:16]) * $signed(operand_b_w[32:16]);
    assign next_payload1_w = {tag_w[0], high_w[0], low_product_w,
        cross_a_w, cross_b_w, high_product_w[31:0]};
    assign {tag_w[1], high_w[1], captured_low_product_w, captured_cross_a_w,
        captured_cross_b_w, captured_high_product_w} = payload1_w;
    assign next_payload2_w = {tag_w[1], high_w[1], captured_high_product_w,
        captured_low_product_w, ({captured_cross_a_w[32], captured_cross_a_w} +
        {captured_cross_b_w[32], captured_cross_b_w})};
    assign {tag_w[2], high_w[2], base_w, cross_w} = payload2_w;
    assign product_w = base_w + {{14{cross_w[33]}}, cross_w, 16'b0};
    genvar chunk0;
    generate
        for (chunk0 = 0; chunk0 < (PAYLOAD0_WIDTH+15)/16; chunk0 = chunk0+1) begin : g_e0
            localparam WORD_WIDTH = PAYLOAD0_WIDTH-chunk0*16 < 16 ?
                PAYLOAD0_WIDTH-chunk0*16 : 16;
            (* syn_preserve = 1, syn_keep = 1 *) reg enable_leaf_r;
            reg [WORD_WIDTH-1:0] data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    enable_leaf_r <= 1'b1;
                else
                    enable_leaf_r <= region0_0_w;
            end
            always @(posedge clk_i) begin
                if (enable_leaf_r)
                    data_r <= next_payload0_w[chunk0*16 +: WORD_WIDTH];
            end
            assign payload0_w[chunk0*16 +: WORD_WIDTH] = data_r;
        end
    endgenerate
    genvar chunk1;
    generate
        for (chunk1 = 0; chunk1 < (PAYLOAD1_WIDTH+15)/16; chunk1 = chunk1+1) begin : g_e1
            localparam WORD_WIDTH = PAYLOAD1_WIDTH-chunk1*16 < 16 ?
                PAYLOAD1_WIDTH-chunk1*16 : 16;
            (* syn_preserve = 1, syn_keep = 1 *) reg enable_leaf_r;
            reg [WORD_WIDTH-1:0] data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    enable_leaf_r <= 1'b1;
                else
                    enable_leaf_r <= chunk1 < 4 ? region1_0_w : region1_1_w;
            end
            always @(posedge clk_i) begin
                if (enable_leaf_r)
                    data_r <= next_payload1_w[chunk1*16 +: WORD_WIDTH];
            end
            assign payload1_w[chunk1*16 +: WORD_WIDTH] = data_r;
        end
    endgenerate
    genvar chunk2;
    generate
        for (chunk2 = 0; chunk2 < (PAYLOAD2_WIDTH+15)/16; chunk2 = chunk2+1) begin : g_e2
            localparam WORD_WIDTH = PAYLOAD2_WIDTH-chunk2*16 < 16 ?
                PAYLOAD2_WIDTH-chunk2*16 : 16;
            (* syn_preserve = 1, syn_keep = 1 *) reg enable_leaf_r;
            reg [WORD_WIDTH-1:0] data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    enable_leaf_r <= 1'b1;
                else
                    enable_leaf_r <= region2_0_w;
            end
            always @(posedge clk_i) begin
                if (enable_leaf_r)
                    data_r <= next_payload2_w[chunk2*16 +: WORD_WIDTH];
            end
            assign payload2_w[chunk2*16 +: WORD_WIDTH] = data_r;
        end
    endgenerate
    wire unused_w = ^{(ISSUE_WIDTH == 1), mul_req_instr_i[31:14], mul_req_instr_i[11:0],
        high_product_w[33:32]};
endmodule
