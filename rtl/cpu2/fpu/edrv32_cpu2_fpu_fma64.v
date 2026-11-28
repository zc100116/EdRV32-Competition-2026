// File: edrv32_cpu2_fpu_fma64.v
// Spec: fpu-spec 2.1-2.4, 3.1, 5.3-5.4.
// Description: Double-precision ADD/MUL/FMA unit with local completion and age cancellation.
// Clock domain: clk_sys.
module edrv32_cpu2_fpu_fma64 (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Requests: legal decoded operations and resolved rounding mode.
    input wire unit_req_valid_i,
    output wire unit_req_ready_o,
    input wire [31:0] unit_req_instr_i,
    input wire [3:0] unit_req_tag_i,
    input wire [63:0] unit_req_src1_i,
    input wire [63:0] unit_req_src2_i,
    input wire [63:0] unit_req_src3_i,
    input wire [2:0] unit_req_rm_i,

    // Local completion, held through arbitration backpressure.
    output wire unit_resp_valid_o,
    input wire unit_resp_ready_i,
    output wire [3:0] unit_resp_tag_o,
    output wire [63:0] unit_resp_data_o,
    output wire [4:0] unit_resp_flags_o,
    output wire unit_resp_int_dest_o,

    // Head-relative inclusive cancellation.
    input wire [3:0] age_head_i,
    input wire cancel_valid_i,
    input wire [3:0] cancel_tag_i
);
    localparam T = 4;
    wire advance_w;
    wire accept_w;
    wire dispatch_w;
    wire capture_w;
    wire capture_data_w;
    reg class_valid_r;
    reg buffer_valid_r;
    reg req_ready_r;
    reg [31:0] buffer_instr_r;
    reg [63:0] buffer_src1_r;
    reg [63:0] buffer_src2_r;
    reg [63:0] buffer_src3_r;
    reg [2:0] buffer_rm_r;
    reg [T-1:0] buffer_tag_r;
    reg [T-1:0] class_tag_r;
    reg [1:0] class_kind_r;
    wire [31:0] instr_w;
    wire [63:0] a_i;
    wire [63:0] b_i;
    wire [63:0] c_i;
    wire [1:0] op_i;
    wire [2:0] rm_i;
    wire [1:0] kind_w;
    wire [T-1:0] cancel_distance_w;
    wire req_kill_w;
    wire class_kill_w;
    wire buffer_kill_w;
    wire buffer_keep_w;
    wire incoming_w;
    wire class_next_w;
    wire buffer_next_w;
    wire class_pop_w;
    reg [16:0] reservation_r;
    wire reservation_conflict_w;
    wire [16:0] reservation_shift_w;
    assign instr_w = buffer_valid_r ? buffer_instr_r : unit_req_instr_i;
    assign a_i = buffer_valid_r ? buffer_src1_r : unit_req_src1_i;
    assign b_i = buffer_valid_r ? buffer_src2_r : unit_req_src2_i;
    assign c_i = kind_w == 2'd2
        ? (buffer_valid_r ? buffer_src3_r : unit_req_src3_i) : 64'b0;
    assign rm_i = buffer_valid_r ? buffer_rm_r : unit_req_rm_i;
    assign kind_w = instr_w[6:0] != 7'b1010011 ? 2'd2
        : (instr_w[28] ? 2'd1 : 2'd0);
    assign op_i = kind_w == 2'd2 ? instr_w[3:2] : 2'b0;
    assign cancel_distance_w = cancel_tag_i - age_head_i;
    assign req_kill_w = cancel_valid_i
        && ((unit_req_tag_i - age_head_i) >= cancel_distance_w);
    assign class_kill_w = cancel_valid_i
        && ((class_tag_r - age_head_i) >= cancel_distance_w);
    assign buffer_kill_w = cancel_valid_i
        && ((buffer_tag_r - age_head_i) >= cancel_distance_w);
    assign buffer_keep_w = buffer_valid_r && !buffer_kill_w;
    assign unit_req_ready_o = req_ready_r && advance_w;
    assign accept_w = unit_req_valid_i && unit_req_ready_o && !req_kill_w;
    // Reservations identify the normalization input edge, not tail occupancy.
    // From dispatch: ADD +3, MUL +14, FMA +16 enabled edges.
    assign reservation_conflict_w = class_kind_r == 2'd0 ? reservation_r[3]
        : class_kind_r == 2'd1 ? reservation_r[14] : 1'b0;
    assign dispatch_w = advance_w && class_valid_r && !class_kill_w
        && !reservation_conflict_w;
    assign class_pop_w = dispatch_w || (class_valid_r && class_kill_w);
    assign incoming_w = buffer_keep_w || accept_w;
    assign capture_w = advance_w && (!class_valid_r || class_pop_w) && incoming_w;
    // Canceled tags only affect control validity; arithmetic registers may
    // capture discarded bits. This keeps age subtraction out of data enables.
    assign capture_data_w = !class_valid_r || !reservation_conflict_w;
    assign class_next_w = (class_valid_r && !class_pop_w) || capture_w;
    assign buffer_next_w = (buffer_keep_w && !capture_w)
        || (accept_w && (buffer_keep_w || !capture_w));
    assign reservation_shift_w = {1'b0, reservation_r[16:1]};
    wire [16:0] reservation_next_w;
    assign reservation_next_w = reservation_shift_w
                    | (dispatch_w ? (class_kind_r == 2'd0 ? 17'h4
                        : class_kind_r == 2'd1 ? 17'h2000 : 17'h8000) : 17'b0);
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            class_valid_r <= 1'b0;
            buffer_valid_r <= 1'b0;
            req_ready_r <= 1'b1;
            reservation_r <= 17'b0;
        end else begin
            class_valid_r <= class_next_w;
            buffer_valid_r <= buffer_next_w;
            req_ready_r <= !buffer_next_w;
            begin
                if (advance_copy_r[741]) reservation_r[15:0] <= reservation_next_w[15:0];
                if (advance_copy_r[742]) reservation_r[16] <= reservation_next_w[16];
            end
        end
    end
    always @(posedge clk_i) begin
        if (capture_w) begin
            class_tag_r <= buffer_keep_w ? buffer_tag_r : unit_req_tag_i;
            class_kind_r <= kind_w;
        end
        if (accept_w && (buffer_keep_w || !capture_w)) begin
            buffer_instr_r <= unit_req_instr_i;
            buffer_src1_r <= unit_req_src1_i;
            buffer_src2_r <= unit_req_src2_i;
            buffer_src3_r <= unit_req_src3_i;
            buffer_rm_r <= unit_req_rm_i;
            buffer_tag_r <= unit_req_tag_i;
        end
    end
    wire [52:0] a_mantissa_w;
    assign a_mantissa_w = {|a_i[62:52], a_i[51:0]};
    wire a_zero_w;
    assign a_zero_w = ~|a_i[62:0];
    wire a_inf_w;
    assign a_inf_w = (&a_i[62:52]) && !(|a_i[51:0]);
    wire a_nan_w;
    assign a_nan_w = (&a_i[62:52]) && (|a_i[51:0]);
    wire a_snan_w;
    assign a_snan_w = a_nan_w && !a_i[51];
    wire [5:0] a_lz_w;
    edrv32_cpu2_fpu_fma64_lz53 u_lz_a (
        .data_i(a_mantissa_w),
        .count_o(a_lz_w)
    );
    reg [52:0] e1_a_mantissa_r;
    wire [52:0] e1_a_mantissa_next_w;
    assign e1_a_mantissa_next_w = a_mantissa_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[124] && capture_data_w) e1_a_mantissa_r[15:0] <=
        e1_a_mantissa_next_w[15:0];
        if (advance_copy_r[125] && capture_data_w) e1_a_mantissa_r[31:16] <=
        e1_a_mantissa_next_w[31:16];
        if (advance_copy_r[126] && capture_data_w) e1_a_mantissa_r[47:32] <=
        e1_a_mantissa_next_w[47:32];
        if (advance_copy_r[127] && capture_data_w) e1_a_mantissa_r[52:48] <=
        e1_a_mantissa_next_w[52:48];
    end
    reg [5:0] e1_a_lz_r;
    wire [5:0] e1_a_lz_next_w;
    assign e1_a_lz_next_w = a_lz_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[128] && capture_data_w) e1_a_lz_r[5:0] <= e1_a_lz_next_w[5:0];
    end
    reg signed [12:0] e1_a_exp_r;
    wire [12:0] e1_a_exp_next_w;
    assign e1_a_exp_next_w = ((|a_i[62:52]) ? $signed({2'b0, a_i[62:52]}) - 13'sd1023
        : -13'sd1022);
    always @(posedge clk_i) begin
        if (advance_copy_r[129] && capture_data_w) e1_a_exp_r[12:0] <= e1_a_exp_next_w[12:0];
    end
    wire [52:0] b_mantissa_w;
    assign b_mantissa_w = {|b_i[62:52], b_i[51:0]};
    wire b_zero_w;
    assign b_zero_w = ~|b_i[62:0];
    wire b_inf_w;
    assign b_inf_w = (&b_i[62:52]) && !(|b_i[51:0]);
    wire b_nan_w;
    assign b_nan_w = (&b_i[62:52]) && (|b_i[51:0]);
    wire b_snan_w;
    assign b_snan_w = b_nan_w && !b_i[51];
    wire [5:0] b_lz_w;
    edrv32_cpu2_fpu_fma64_lz53 u_lz_b (
        .data_i(b_mantissa_w),
        .count_o(b_lz_w)
    );
    reg [52:0] e1_b_mantissa_r;
    wire [52:0] e1_b_mantissa_next_w;
    assign e1_b_mantissa_next_w = b_mantissa_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[130] && capture_data_w) e1_b_mantissa_r[15:0] <=
        e1_b_mantissa_next_w[15:0];
        if (advance_copy_r[131] && capture_data_w) e1_b_mantissa_r[31:16] <=
        e1_b_mantissa_next_w[31:16];
        if (advance_copy_r[132] && capture_data_w) e1_b_mantissa_r[47:32] <=
        e1_b_mantissa_next_w[47:32];
        if (advance_copy_r[133] && capture_data_w) e1_b_mantissa_r[52:48] <=
        e1_b_mantissa_next_w[52:48];
    end
    reg [5:0] e1_b_lz_r;
    wire [5:0] e1_b_lz_next_w;
    assign e1_b_lz_next_w = b_lz_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[134] && capture_data_w) e1_b_lz_r[5:0] <= e1_b_lz_next_w[5:0];
    end
    reg signed [12:0] e1_b_exp_r;
    wire [12:0] e1_b_exp_next_w;
    assign e1_b_exp_next_w = ((|b_i[62:52]) ? $signed({2'b0, b_i[62:52]}) - 13'sd1023
        : -13'sd1022);
    always @(posedge clk_i) begin
        if (advance_copy_r[135] && capture_data_w) e1_b_exp_r[12:0] <= e1_b_exp_next_w[12:0];
    end
    wire [52:0] c_mantissa_w;
    assign c_mantissa_w = {|c_i[62:52], c_i[51:0]};
    wire c_zero_w;
    assign c_zero_w = ~|c_i[62:0];
    wire c_inf_w;
    assign c_inf_w = (&c_i[62:52]) && !(|c_i[51:0]);
    wire c_nan_w;
    assign c_nan_w = (&c_i[62:52]) && (|c_i[51:0]);
    wire c_snan_w;
    assign c_snan_w = c_nan_w && !c_i[51];
    wire [5:0] c_lz_w;
    edrv32_cpu2_fpu_fma64_lz53 u_lz_c (
        .data_i(c_mantissa_w),
        .count_o(c_lz_w)
    );
    reg [52:0] e1_c_mantissa_r;
    wire [52:0] e1_c_mantissa_next_w;
    assign e1_c_mantissa_next_w = c_mantissa_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[136] && capture_data_w) e1_c_mantissa_r[15:0] <=
        e1_c_mantissa_next_w[15:0];
        if (advance_copy_r[137] && capture_data_w) e1_c_mantissa_r[31:16] <=
        e1_c_mantissa_next_w[31:16];
        if (advance_copy_r[138] && capture_data_w) e1_c_mantissa_r[47:32] <=
        e1_c_mantissa_next_w[47:32];
        if (advance_copy_r[139] && capture_data_w) e1_c_mantissa_r[52:48] <=
        e1_c_mantissa_next_w[52:48];
    end
    reg [5:0] e1_c_lz_r;
    wire [5:0] e1_c_lz_next_w;
    assign e1_c_lz_next_w = c_lz_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[140] && capture_data_w) e1_c_lz_r[5:0] <= e1_c_lz_next_w[5:0];
    end
    reg signed [12:0] e1_c_exp_r;
    wire [12:0] e1_c_exp_next_w;
    assign e1_c_exp_next_w = ((|c_i[62:52]) ? $signed({2'b0, c_i[62:52]}) - 13'sd1023
        : -13'sd1022);
    always @(posedge clk_i) begin
        if (advance_copy_r[141] && capture_data_w) e1_c_exp_r[12:0] <= e1_c_exp_next_w[12:0];
    end
    wire product_sign_w;
    wire c_sign_w;
    wire invalid_product_w;
    wire product_inf_w;
    wire invalid_sum_w;
    wire invalid_w;
    wire nan_w;
    assign product_sign_w = kind_w == 2'd0 ? a_i[63]
        : a_i[63] ^ b_i[63] ^ op_i[1];
    assign c_sign_w = kind_w == 2'd0 ? b_i[63] ^ instr_w[27]
        : (kind_w == 2'd1 ? product_sign_w : c_i[63] ^ op_i[0]);
    assign invalid_product_w = kind_w != 2'd0
        && ((a_zero_w && b_inf_w) || (b_zero_w && a_inf_w));
    assign product_inf_w = kind_w == 2'd0 ? a_inf_w
        : (a_inf_w || b_inf_w) && !a_nan_w && !b_nan_w;
    assign invalid_sum_w = kind_w == 2'd0
        ? (a_inf_w && b_inf_w && (product_sign_w != c_sign_w))
        : kind_w == 2'd2 && product_inf_w && c_inf_w && !invalid_product_w
            && (product_sign_w != c_sign_w);
    assign invalid_w = a_snan_w || b_snan_w || (kind_w == 2'd2 && c_snan_w)
        || invalid_product_w || invalid_sum_w;
    assign nan_w = a_nan_w || b_nan_w || (kind_w == 2'd2 && c_nan_w) || invalid_w;
    wire addend_inf_w;
    assign addend_inf_w = kind_w == 2'd0 ? b_inf_w : kind_w == 2'd2 && c_inf_w;

    reg e1_ps_r;
    wire e1_ps_next_w;
    assign e1_ps_next_w = product_sign_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[142] && capture_data_w) e1_ps_r <= e1_ps_next_w;
    end
    reg e1_cs_r;
    wire e1_cs_next_w;
    assign e1_cs_next_w = c_sign_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[143] && capture_data_w) e1_cs_r <= e1_cs_next_w;
    end
    reg [2:0] e1_rm_r;
    wire [2:0] e1_rm_next_w;
    assign e1_rm_next_w = rm_i;
    always @(posedge clk_i) begin
        if (advance_copy_r[144] && capture_data_w) e1_rm_r[2:0] <= e1_rm_next_w[2:0];
    end
    reg e1_special_r;
    wire e1_special_next_w;
    assign e1_special_next_w = nan_w || product_inf_w || addend_inf_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[145] && capture_data_w) e1_special_r <= e1_special_next_w;
    end
    reg [63:0] e1_result_r;
    wire [63:0] e1_result_next_w;
    assign e1_result_next_w = nan_w ? 64'h7ff8000000000000
        : {product_inf_w ? product_sign_w : c_sign_w, 11'h7ff, 52'b0};
    always @(posedge clk_i) begin
        if (advance_copy_r[146] && capture_data_w) e1_result_r[15:0] <= e1_result_next_w[15:0];
        if (advance_copy_r[147] && capture_data_w) e1_result_r[31:16] <= e1_result_next_w[31:16];
        if (advance_copy_r[148] && capture_data_w) e1_result_r[47:32] <= e1_result_next_w[47:32];
        if (advance_copy_r[149] && capture_data_w) e1_result_r[63:48] <= e1_result_next_w[63:48];
    end
    reg [4:0] e1_flags_r;
    wire [4:0] e1_flags_next_w;
    assign e1_flags_next_w = {invalid_w, 4'b0};
    always @(posedge clk_i) begin
        if (advance_copy_r[150] && capture_data_w) e1_flags_r[4:0] <= e1_flags_next_w[4:0];
    end
    reg e1_product_zero_r;
    wire e1_product_zero_next_w;
    assign e1_product_zero_next_w = a_zero_w || b_zero_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[151] && capture_data_w) e1_product_zero_r <= e1_product_zero_next_w;
    end
    reg e1_c_zero_r;
    wire e1_c_zero_next_w;
    assign e1_c_zero_next_w = c_zero_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[152] && capture_data_w) e1_c_zero_r <= e1_c_zero_next_w;
    end
    wire [52:0] e2_a_w;
    assign e2_a_w = e1_a_mantissa_r << e1_a_lz_r;
    wire [52:0] e2_b_w;
    assign e2_b_w = e1_b_mantissa_r << e1_b_lz_r;
    wire [52:0] e2_c_w;
    assign e2_c_w = e1_c_mantissa_r << e1_c_lz_r;
    wire [105:0] product_w;
    edrv32_apm_cpu2_u53xu53 u_product (
        .clk_i(clk_i),
        .enable_i(advance_copy_r[123:0]),
        .a_i(e2_a_w),
        .b_i(e2_b_w),
        .product_o(product_w)
    );
    wire signed [12:0] product_exp_w;
    assign product_exp_w = e1_a_exp_r + e1_b_exp_r;
    reg signed [12:0] p0_base_r;
    wire [12:0] p0_base_next_w;
    assign p0_base_next_w = product_exp_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[153]) p0_base_r[12:0] <= p0_base_next_w[12:0];
    end
    reg p0_ps_r;
    wire p0_ps_next_w;
    assign p0_ps_next_w = e1_ps_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[154]) p0_ps_r <= p0_ps_next_w;
    end
    reg p0_cs_r;
    wire p0_cs_next_w;
    assign p0_cs_next_w = e1_cs_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[155]) p0_cs_r <= p0_cs_next_w;
    end
    reg [2:0] p0_rm_r;
    wire [2:0] p0_rm_next_w;
    assign p0_rm_next_w = e1_rm_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[156]) p0_rm_r[2:0] <= p0_rm_next_w[2:0];
    end
    reg p0_special_r;
    wire p0_special_next_w;
    assign p0_special_next_w = e1_special_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[157]) p0_special_r <= p0_special_next_w;
    end
    reg [63:0] p0_result_r;
    wire [63:0] p0_result_next_w;
    assign p0_result_next_w = e1_result_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[158]) p0_result_r[15:0] <= p0_result_next_w[15:0];
        if (advance_copy_r[159]) p0_result_r[31:16] <= p0_result_next_w[31:16];
        if (advance_copy_r[160]) p0_result_r[47:32] <= p0_result_next_w[47:32];
        if (advance_copy_r[161]) p0_result_r[63:48] <= p0_result_next_w[63:48];
    end
    reg [4:0] p0_flags_r;
    wire [4:0] p0_flags_next_w;
    assign p0_flags_next_w = e1_flags_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[162]) p0_flags_r[4:0] <= p0_flags_next_w[4:0];
    end
    reg [6:0] p0_product_lz_r;
    wire [6:0] p0_product_lz_next_w;
    assign p0_product_lz_next_w = {1'b0,e1_a_lz_r} + {1'b0,e1_b_lz_r};
    always @(posedge clk_i) begin
        if (advance_copy_r[163]) p0_product_lz_r[6:0] <= p0_product_lz_next_w[6:0];
    end
    reg signed [12:0] p0_c_exp_r;
    wire [12:0] p0_c_exp_next_w;
    assign p0_c_exp_next_w = e1_c_exp_r - $signed({7'b0,e1_c_lz_r});
    always @(posedge clk_i) begin
        if (advance_copy_r[164]) p0_c_exp_r[12:0] <= p0_c_exp_next_w[12:0];
    end
    reg p0_product_zero_r;
    wire p0_product_zero_next_w;
    assign p0_product_zero_next_w = e1_product_zero_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[165]) p0_product_zero_r <= p0_product_zero_next_w;
    end
    reg p0_c_zero_r;
    wire p0_c_zero_next_w;
    assign p0_c_zero_next_w = e1_c_zero_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[166]) p0_c_zero_r <= p0_c_zero_next_w;
    end
    reg signed [12:0] p1_c_exp_r;
    wire [12:0] p1_c_exp_next_w;
    assign p1_c_exp_next_w = p0_c_exp_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[167]) p1_c_exp_r[12:0] <= p1_c_exp_next_w[12:0];
    end
    reg p1_product_zero_r;
    wire p1_product_zero_next_w;
    assign p1_product_zero_next_w = p0_product_zero_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[168]) p1_product_zero_r <= p1_product_zero_next_w;
    end
    reg p1_c_zero_r;
    wire p1_c_zero_next_w;
    assign p1_c_zero_next_w = p0_c_zero_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[169]) p1_c_zero_r <= p1_c_zero_next_w;
    end
    reg signed [12:0] p2_c_exp_r;
    wire [12:0] p2_c_exp_next_w;
    assign p2_c_exp_next_w = p1_c_exp_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[170]) p2_c_exp_r[12:0] <= p2_c_exp_next_w[12:0];
    end
    reg p2_product_zero_r;
    wire p2_product_zero_next_w;
    assign p2_product_zero_next_w = p1_product_zero_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[171]) p2_product_zero_r <= p2_product_zero_next_w;
    end
    reg p2_c_zero_r;
    wire p2_c_zero_next_w;
    assign p2_c_zero_next_w = p1_c_zero_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[172]) p2_c_zero_r <= p2_c_zero_next_w;
    end
    reg signed [12:0] p2_delta_r;
    wire [12:0] p2_delta_next_w;
    assign p2_delta_next_w = p1_c_exp_r - p1_base_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[173]) p2_delta_r[12:0] <= p2_delta_next_w[12:0];
    end
    wire far_w;
    assign far_w = ((p2_delta_r > 13'sd58) || p2_product_zero_r) && !p2_c_zero_r;
    wire signed [12:0] shift_signed_w;
    assign shift_signed_w = p2_delta_r + 13'sd55;
    wire signed [12:0] shift_abs_w;
    assign shift_abs_w = -13'sd55 - p2_delta_r;
    reg [7:0] p3_shift_r;
    wire [7:0] p3_shift_next_w;
    assign p3_shift_next_w = far_w ? 8'd113 : p2_delta_r < -13'sd223 ? 8'd168
        : p2_delta_r < -13'sd55 ? shift_abs_w[7:0] : shift_signed_w[7:0];
    always @(posedge clk_i) begin
        if (advance_copy_r[174]) p3_shift_r[7:0] <= p3_shift_next_w[7:0];
    end
    reg p3_right_r;
    wire p3_right_next_w;
    assign p3_right_next_w = !far_w && p2_delta_r < -13'sd55;
    always @(posedge clk_i) begin
        if (advance_copy_r[175]) p3_right_r <= p3_right_next_w;
    end
    reg [52:0] p0_c_r;
    wire [52:0] p0_c_next_w;
    assign p0_c_next_w = e2_c_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[176]) p0_c_r[15:0] <= p0_c_next_w[15:0];
        if (advance_copy_r[177]) p0_c_r[31:16] <= p0_c_next_w[31:16];
        if (advance_copy_r[178]) p0_c_r[47:32] <= p0_c_next_w[47:32];
        if (advance_copy_r[179]) p0_c_r[52:48] <= p0_c_next_w[52:48];
    end
    reg p1_ps_r;
    wire p1_ps_next_w;
    assign p1_ps_next_w = p0_ps_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[180]) p1_ps_r <= p1_ps_next_w;
    end
    reg p1_cs_r;
    wire p1_cs_next_w;
    assign p1_cs_next_w = p0_cs_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[181]) p1_cs_r <= p1_cs_next_w;
    end
    reg [2:0] p1_rm_r;
    wire [2:0] p1_rm_next_w;
    assign p1_rm_next_w = p0_rm_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[182]) p1_rm_r[2:0] <= p1_rm_next_w[2:0];
    end
    reg p1_special_r;
    wire p1_special_next_w;
    assign p1_special_next_w = p0_special_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[183]) p1_special_r <= p1_special_next_w;
    end
    reg [63:0] p1_result_r;
    wire [63:0] p1_result_next_w;
    assign p1_result_next_w = p0_result_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[184]) p1_result_r[15:0] <= p1_result_next_w[15:0];
        if (advance_copy_r[185]) p1_result_r[31:16] <= p1_result_next_w[31:16];
        if (advance_copy_r[186]) p1_result_r[47:32] <= p1_result_next_w[47:32];
        if (advance_copy_r[187]) p1_result_r[63:48] <= p1_result_next_w[63:48];
    end
    reg [4:0] p1_flags_r;
    wire [4:0] p1_flags_next_w;
    assign p1_flags_next_w = p0_flags_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[188]) p1_flags_r[4:0] <= p1_flags_next_w[4:0];
    end
    reg signed [12:0] p1_base_r;
    wire [12:0] p1_base_next_w;
    assign p1_base_next_w = p0_base_r - $signed({6'b0,p0_product_lz_r});
    always @(posedge clk_i) begin
        if (advance_copy_r[189]) p1_base_r[12:0] <= p1_base_next_w[12:0];
    end
    reg [52:0] p1_c_r;
    wire [52:0] p1_c_next_w;
    assign p1_c_next_w = p0_c_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[190]) p1_c_r[15:0] <= p1_c_next_w[15:0];
        if (advance_copy_r[191]) p1_c_r[31:16] <= p1_c_next_w[31:16];
        if (advance_copy_r[192]) p1_c_r[47:32] <= p1_c_next_w[47:32];
        if (advance_copy_r[193]) p1_c_r[52:48] <= p1_c_next_w[52:48];
    end
    reg p2_ps_r;
    wire p2_ps_next_w;
    assign p2_ps_next_w = p1_ps_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[194]) p2_ps_r <= p2_ps_next_w;
    end
    reg p2_cs_r;
    wire p2_cs_next_w;
    assign p2_cs_next_w = p1_cs_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[195]) p2_cs_r <= p2_cs_next_w;
    end
    reg [2:0] p2_rm_r;
    wire [2:0] p2_rm_next_w;
    assign p2_rm_next_w = p1_rm_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[196]) p2_rm_r[2:0] <= p2_rm_next_w[2:0];
    end
    reg p2_special_r;
    wire p2_special_next_w;
    assign p2_special_next_w = p1_special_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[197]) p2_special_r <= p2_special_next_w;
    end
    reg [63:0] p2_result_r;
    wire [63:0] p2_result_next_w;
    assign p2_result_next_w = p1_result_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[198]) p2_result_r[15:0] <= p2_result_next_w[15:0];
        if (advance_copy_r[199]) p2_result_r[31:16] <= p2_result_next_w[31:16];
        if (advance_copy_r[200]) p2_result_r[47:32] <= p2_result_next_w[47:32];
        if (advance_copy_r[201]) p2_result_r[63:48] <= p2_result_next_w[63:48];
    end
    reg [4:0] p2_flags_r;
    wire [4:0] p2_flags_next_w;
    assign p2_flags_next_w = p1_flags_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[202]) p2_flags_r[4:0] <= p2_flags_next_w[4:0];
    end
    reg signed [12:0] p2_base_r;
    wire [12:0] p2_base_next_w;
    assign p2_base_next_w = p1_base_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[203]) p2_base_r[12:0] <= p2_base_next_w[12:0];
    end
    reg [52:0] p2_c_r;
    wire [52:0] p2_c_next_w;
    assign p2_c_next_w = p1_c_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[204]) p2_c_r[15:0] <= p2_c_next_w[15:0];
        if (advance_copy_r[205]) p2_c_r[31:16] <= p2_c_next_w[31:16];
        if (advance_copy_r[206]) p2_c_r[47:32] <= p2_c_next_w[47:32];
        if (advance_copy_r[207]) p2_c_r[52:48] <= p2_c_next_w[52:48];
    end
    reg p3_ps_r;
    wire p3_ps_next_w;
    assign p3_ps_next_w = p2_ps_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[208]) p3_ps_r <= p3_ps_next_w;
    end
    reg p3_cs_r;
    wire p3_cs_next_w;
    assign p3_cs_next_w = p2_cs_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[209]) p3_cs_r <= p3_cs_next_w;
    end
    reg [2:0] p3_rm_r;
    wire [2:0] p3_rm_next_w;
    assign p3_rm_next_w = p2_rm_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[210]) p3_rm_r[2:0] <= p3_rm_next_w[2:0];
    end
    reg p3_special_r;
    wire p3_special_next_w;
    assign p3_special_next_w = p2_special_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[211]) p3_special_r <= p3_special_next_w;
    end
    reg [63:0] p3_result_r;
    wire [63:0] p3_result_next_w;
    assign p3_result_next_w = p2_result_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[212]) p3_result_r[15:0] <= p3_result_next_w[15:0];
        if (advance_copy_r[213]) p3_result_r[31:16] <= p3_result_next_w[31:16];
        if (advance_copy_r[214]) p3_result_r[47:32] <= p3_result_next_w[47:32];
        if (advance_copy_r[215]) p3_result_r[63:48] <= p3_result_next_w[63:48];
    end
    reg [4:0] p3_flags_r;
    wire [4:0] p3_flags_next_w;
    assign p3_flags_next_w = p2_flags_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[216]) p3_flags_r[4:0] <= p3_flags_next_w[4:0];
    end
    reg signed [12:0] p3_base_r;
    wire [12:0] p3_base_next_w;
    assign p3_base_next_w = far_w ? p2_c_exp_r - 13'sd58 : p2_base_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[217]) p3_base_r[12:0] <= p3_base_next_w[12:0];
    end
    reg p3_far_r;
    wire p3_far_next_w;
    assign p3_far_next_w = far_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[218]) p3_far_r <= p3_far_next_w;
    end
    reg [52:0] p3_c_r;
    wire [52:0] p3_c_next_w;
    assign p3_c_next_w = p2_c_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[219]) p3_c_r[15:0] <= p3_c_next_w[15:0];
        if (advance_copy_r[220]) p3_c_r[31:16] <= p3_c_next_w[31:16];
        if (advance_copy_r[221]) p3_c_r[47:32] <= p3_c_next_w[47:32];
        if (advance_copy_r[222]) p3_c_r[52:48] <= p3_c_next_w[52:48];
    end
    reg p4_ps_r;
    wire p4_ps_next_w;
    assign p4_ps_next_w = p3_ps_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[223]) p4_ps_r <= p4_ps_next_w;
    end
    reg p4_cs_r;
    wire p4_cs_next_w;
    assign p4_cs_next_w = p3_cs_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[224]) p4_cs_r <= p4_cs_next_w;
    end
    reg [2:0] p4_rm_r;
    wire [2:0] p4_rm_next_w;
    assign p4_rm_next_w = p3_rm_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[225]) p4_rm_r[2:0] <= p4_rm_next_w[2:0];
    end
    reg p4_special_r;
    wire p4_special_next_w;
    assign p4_special_next_w = p3_special_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[226]) p4_special_r <= p4_special_next_w;
    end
    reg [63:0] p4_result_r;
    wire [63:0] p4_result_next_w;
    assign p4_result_next_w = p3_result_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[227]) p4_result_r[15:0] <= p4_result_next_w[15:0];
        if (advance_copy_r[228]) p4_result_r[31:16] <= p4_result_next_w[31:16];
        if (advance_copy_r[229]) p4_result_r[47:32] <= p4_result_next_w[47:32];
        if (advance_copy_r[230]) p4_result_r[63:48] <= p4_result_next_w[63:48];
    end
    reg [4:0] p4_flags_r;
    wire [4:0] p4_flags_next_w;
    assign p4_flags_next_w = p3_flags_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[231]) p4_flags_r[4:0] <= p4_flags_next_w[4:0];
    end
    reg signed [12:0] p4_base_r;
    wire [12:0] p4_base_next_w;
    assign p4_base_next_w = p3_base_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[232]) p4_base_r[12:0] <= p4_base_next_w[12:0];
    end
    reg p4_far_r;
    wire p4_far_next_w;
    assign p4_far_next_w = p3_far_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[233]) p4_far_r <= p4_far_next_w;
    end
    reg [52:0] p4_c_r;
    wire [52:0] p4_c_next_w;
    assign p4_c_next_w = p3_c_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[234]) p4_c_r[15:0] <= p4_c_next_w[15:0];
        if (advance_copy_r[235]) p4_c_r[31:16] <= p4_c_next_w[31:16];
        if (advance_copy_r[236]) p4_c_r[47:32] <= p4_c_next_w[47:32];
        if (advance_copy_r[237]) p4_c_r[52:48] <= p4_c_next_w[52:48];
    end
    reg [7:0] p4_shift_r;
    wire [7:0] p4_shift_next_w;
    assign p4_shift_next_w = p3_shift_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[238]) p4_shift_r[7:0] <= p4_shift_next_w[7:0];
    end
    reg p4_right_r;
    wire p4_right_next_w;
    assign p4_right_next_w = p3_right_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[239]) p4_right_r <= p4_right_next_w;
    end
    reg p5_ps_r;
    wire p5_ps_next_w;
    assign p5_ps_next_w = p4_ps_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[240]) p5_ps_r <= p5_ps_next_w;
    end
    reg p5_cs_r;
    wire p5_cs_next_w;
    assign p5_cs_next_w = p4_cs_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[241]) p5_cs_r <= p5_cs_next_w;
    end
    reg [2:0] p5_rm_r;
    wire [2:0] p5_rm_next_w;
    assign p5_rm_next_w = p4_rm_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[242]) p5_rm_r[2:0] <= p5_rm_next_w[2:0];
    end
    reg p5_special_r;
    wire p5_special_next_w;
    assign p5_special_next_w = p4_special_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[243]) p5_special_r <= p5_special_next_w;
    end
    reg [63:0] p5_result_r;
    wire [63:0] p5_result_next_w;
    assign p5_result_next_w = p4_result_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[244]) p5_result_r[15:0] <= p5_result_next_w[15:0];
        if (advance_copy_r[245]) p5_result_r[31:16] <= p5_result_next_w[31:16];
        if (advance_copy_r[246]) p5_result_r[47:32] <= p5_result_next_w[47:32];
        if (advance_copy_r[247]) p5_result_r[63:48] <= p5_result_next_w[63:48];
    end
    reg [4:0] p5_flags_r;
    wire [4:0] p5_flags_next_w;
    assign p5_flags_next_w = p4_flags_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[248]) p5_flags_r[4:0] <= p5_flags_next_w[4:0];
    end
    reg signed [12:0] p5_base_r;
    wire [12:0] p5_base_next_w;
    assign p5_base_next_w = p4_base_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[249]) p5_base_r[12:0] <= p5_base_next_w[12:0];
    end
    reg p5_far_r;
    wire p5_far_next_w;
    assign p5_far_next_w = p4_far_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[250]) p5_far_r <= p5_far_next_w;
    end
    reg [52:0] p5_c_r;
    wire [52:0] p5_c_next_w;
    assign p5_c_next_w = p4_c_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[251]) p5_c_r[15:0] <= p5_c_next_w[15:0];
        if (advance_copy_r[252]) p5_c_r[31:16] <= p5_c_next_w[31:16];
        if (advance_copy_r[253]) p5_c_r[47:32] <= p5_c_next_w[47:32];
        if (advance_copy_r[254]) p5_c_r[52:48] <= p5_c_next_w[52:48];
    end
    reg [7:0] p5_shift_r;
    wire [7:0] p5_shift_next_w;
    assign p5_shift_next_w = p4_shift_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[255]) p5_shift_r[7:0] <= p5_shift_next_w[7:0];
    end
    reg p5_right_r;
    wire p5_right_next_w;
    assign p5_right_next_w = p4_right_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[256]) p5_right_r <= p5_right_next_w;
    end
    reg p6_ps_r;
    wire p6_ps_next_w;
    assign p6_ps_next_w = p5_ps_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[257]) p6_ps_r <= p6_ps_next_w;
    end
    reg p6_cs_r;
    wire p6_cs_next_w;
    assign p6_cs_next_w = p5_cs_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[258]) p6_cs_r <= p6_cs_next_w;
    end
    reg [2:0] p6_rm_r;
    wire [2:0] p6_rm_next_w;
    assign p6_rm_next_w = p5_rm_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[259]) p6_rm_r[2:0] <= p6_rm_next_w[2:0];
    end
    reg p6_special_r;
    wire p6_special_next_w;
    assign p6_special_next_w = p5_special_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[260]) p6_special_r <= p6_special_next_w;
    end
    reg [63:0] p6_result_r;
    wire [63:0] p6_result_next_w;
    assign p6_result_next_w = p5_result_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[261]) p6_result_r[15:0] <= p6_result_next_w[15:0];
        if (advance_copy_r[262]) p6_result_r[31:16] <= p6_result_next_w[31:16];
        if (advance_copy_r[263]) p6_result_r[47:32] <= p6_result_next_w[47:32];
        if (advance_copy_r[264]) p6_result_r[63:48] <= p6_result_next_w[63:48];
    end
    reg [4:0] p6_flags_r;
    wire [4:0] p6_flags_next_w;
    assign p6_flags_next_w = p5_flags_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[265]) p6_flags_r[4:0] <= p6_flags_next_w[4:0];
    end
    reg signed [12:0] p6_base_r;
    wire [12:0] p6_base_next_w;
    assign p6_base_next_w = p5_base_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[266]) p6_base_r[12:0] <= p6_base_next_w[12:0];
    end
    reg p6_far_r;
    wire p6_far_next_w;
    assign p6_far_next_w = p5_far_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[267]) p6_far_r <= p6_far_next_w;
    end
    reg [52:0] p6_c_r;
    wire [52:0] p6_c_next_w;
    assign p6_c_next_w = p5_c_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[268]) p6_c_r[15:0] <= p6_c_next_w[15:0];
        if (advance_copy_r[269]) p6_c_r[31:16] <= p6_c_next_w[31:16];
        if (advance_copy_r[270]) p6_c_r[47:32] <= p6_c_next_w[47:32];
        if (advance_copy_r[271]) p6_c_r[52:48] <= p6_c_next_w[52:48];
    end
    reg [7:0] p6_shift_r;
    wire [7:0] p6_shift_next_w;
    assign p6_shift_next_w = p5_shift_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[272]) p6_shift_r[7:0] <= p6_shift_next_w[7:0];
    end
    reg p6_right_r;
    wire p6_right_next_w;
    assign p6_right_next_w = p5_right_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[273]) p6_right_r <= p6_right_next_w;
    end
    reg p7_ps_r;
    wire p7_ps_next_w;
    assign p7_ps_next_w = p6_ps_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[274]) p7_ps_r <= p7_ps_next_w;
    end
    reg p7_cs_r;
    wire p7_cs_next_w;
    assign p7_cs_next_w = p6_cs_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[275]) p7_cs_r <= p7_cs_next_w;
    end
    reg [2:0] p7_rm_r;
    wire [2:0] p7_rm_next_w;
    assign p7_rm_next_w = p6_rm_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[276]) p7_rm_r[2:0] <= p7_rm_next_w[2:0];
    end
    reg p7_special_r;
    wire p7_special_next_w;
    assign p7_special_next_w = p6_special_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[277]) p7_special_r <= p7_special_next_w;
    end
    reg [63:0] p7_result_r;
    wire [63:0] p7_result_next_w;
    assign p7_result_next_w = p6_result_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[278]) p7_result_r[15:0] <= p7_result_next_w[15:0];
        if (advance_copy_r[279]) p7_result_r[31:16] <= p7_result_next_w[31:16];
        if (advance_copy_r[280]) p7_result_r[47:32] <= p7_result_next_w[47:32];
        if (advance_copy_r[281]) p7_result_r[63:48] <= p7_result_next_w[63:48];
    end
    reg [4:0] p7_flags_r;
    wire [4:0] p7_flags_next_w;
    assign p7_flags_next_w = p6_flags_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[282]) p7_flags_r[4:0] <= p7_flags_next_w[4:0];
    end
    reg signed [12:0] p7_base_r;
    wire [12:0] p7_base_next_w;
    assign p7_base_next_w = p6_base_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[283]) p7_base_r[12:0] <= p7_base_next_w[12:0];
    end
    reg p7_far_r;
    wire p7_far_next_w;
    assign p7_far_next_w = p6_far_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[284]) p7_far_r <= p7_far_next_w;
    end
    reg [52:0] p7_c_r;
    wire [52:0] p7_c_next_w;
    assign p7_c_next_w = p6_c_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[285]) p7_c_r[15:0] <= p7_c_next_w[15:0];
        if (advance_copy_r[286]) p7_c_r[31:16] <= p7_c_next_w[31:16];
        if (advance_copy_r[287]) p7_c_r[47:32] <= p7_c_next_w[47:32];
        if (advance_copy_r[288]) p7_c_r[52:48] <= p7_c_next_w[52:48];
    end
    reg [7:0] p7_shift_r;
    wire [7:0] p7_shift_next_w;
    assign p7_shift_next_w = p6_shift_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[289]) p7_shift_r[7:0] <= p7_shift_next_w[7:0];
    end
    reg p7_right_r;
    wire p7_right_next_w;
    assign p7_right_next_w = p6_right_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[290]) p7_right_r <= p7_right_next_w;
    end
    reg p8_ps_r;
    wire p8_ps_next_w;
    assign p8_ps_next_w = p7_ps_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[291]) p8_ps_r <= p8_ps_next_w;
    end
    reg p8_cs_r;
    wire p8_cs_next_w;
    assign p8_cs_next_w = p7_cs_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[292]) p8_cs_r <= p8_cs_next_w;
    end
    reg [2:0] p8_rm_r;
    wire [2:0] p8_rm_next_w;
    assign p8_rm_next_w = p7_rm_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[293]) p8_rm_r[2:0] <= p8_rm_next_w[2:0];
    end
    reg p8_special_r;
    wire p8_special_next_w;
    assign p8_special_next_w = p7_special_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[294]) p8_special_r <= p8_special_next_w;
    end
    reg [63:0] p8_result_r;
    wire [63:0] p8_result_next_w;
    assign p8_result_next_w = p7_result_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[295]) p8_result_r[15:0] <= p8_result_next_w[15:0];
        if (advance_copy_r[296]) p8_result_r[31:16] <= p8_result_next_w[31:16];
        if (advance_copy_r[297]) p8_result_r[47:32] <= p8_result_next_w[47:32];
        if (advance_copy_r[298]) p8_result_r[63:48] <= p8_result_next_w[63:48];
    end
    reg [4:0] p8_flags_r;
    wire [4:0] p8_flags_next_w;
    assign p8_flags_next_w = p7_flags_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[299]) p8_flags_r[4:0] <= p8_flags_next_w[4:0];
    end
    reg signed [12:0] p8_base_r;
    wire [12:0] p8_base_next_w;
    assign p8_base_next_w = p7_base_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[300]) p8_base_r[12:0] <= p8_base_next_w[12:0];
    end
    reg p8_far_r;
    wire p8_far_next_w;
    assign p8_far_next_w = p7_far_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[301]) p8_far_r <= p8_far_next_w;
    end
    reg [52:0] p8_c_r;
    wire [52:0] p8_c_next_w;
    assign p8_c_next_w = p7_c_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[302]) p8_c_r[15:0] <= p8_c_next_w[15:0];
        if (advance_copy_r[303]) p8_c_r[31:16] <= p8_c_next_w[31:16];
        if (advance_copy_r[304]) p8_c_r[47:32] <= p8_c_next_w[47:32];
        if (advance_copy_r[305]) p8_c_r[52:48] <= p8_c_next_w[52:48];
    end
    reg [7:0] p8_shift_r;
    wire [7:0] p8_shift_next_w;
    assign p8_shift_next_w = p7_shift_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[306]) p8_shift_r[7:0] <= p8_shift_next_w[7:0];
    end
    reg p8_right_r;
    wire p8_right_next_w;
    assign p8_right_next_w = p7_right_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[307]) p8_right_r <= p8_right_next_w;
    end
    reg p9_ps_r;
    wire p9_ps_next_w;
    assign p9_ps_next_w = p8_ps_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[308]) p9_ps_r <= p9_ps_next_w;
    end
    reg p9_cs_r;
    wire p9_cs_next_w;
    assign p9_cs_next_w = p8_cs_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[309]) p9_cs_r <= p9_cs_next_w;
    end
    reg [2:0] p9_rm_r;
    wire [2:0] p9_rm_next_w;
    assign p9_rm_next_w = p8_rm_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[310]) p9_rm_r[2:0] <= p9_rm_next_w[2:0];
    end
    reg p9_special_r;
    wire p9_special_next_w;
    assign p9_special_next_w = p8_special_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[311]) p9_special_r <= p9_special_next_w;
    end
    reg [63:0] p9_result_r;
    wire [63:0] p9_result_next_w;
    assign p9_result_next_w = p8_result_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[312]) p9_result_r[15:0] <= p9_result_next_w[15:0];
        if (advance_copy_r[313]) p9_result_r[31:16] <= p9_result_next_w[31:16];
        if (advance_copy_r[314]) p9_result_r[47:32] <= p9_result_next_w[47:32];
        if (advance_copy_r[315]) p9_result_r[63:48] <= p9_result_next_w[63:48];
    end
    reg [4:0] p9_flags_r;
    wire [4:0] p9_flags_next_w;
    assign p9_flags_next_w = p8_flags_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[316]) p9_flags_r[4:0] <= p9_flags_next_w[4:0];
    end
    reg signed [12:0] p9_base_r;
    wire [12:0] p9_base_next_w;
    assign p9_base_next_w = p8_base_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[317]) p9_base_r[12:0] <= p9_base_next_w[12:0];
    end
    reg p9_far_r;
    wire p9_far_next_w;
    assign p9_far_next_w = p8_far_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[318]) p9_far_r <= p9_far_next_w;
    end
    reg [52:0] p9_c_r;
    wire [52:0] p9_c_next_w;
    assign p9_c_next_w = p8_c_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[319]) p9_c_r[15:0] <= p9_c_next_w[15:0];
        if (advance_copy_r[320]) p9_c_r[31:16] <= p9_c_next_w[31:16];
        if (advance_copy_r[321]) p9_c_r[47:32] <= p9_c_next_w[47:32];
        if (advance_copy_r[322]) p9_c_r[52:48] <= p9_c_next_w[52:48];
    end
    reg [7:0] p9_shift_r;
    wire [7:0] p9_shift_next_w;
    assign p9_shift_next_w = p8_shift_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[323]) p9_shift_r[7:0] <= p9_shift_next_w[7:0];
    end
    reg p9_right_r;
    wire p9_right_next_w;
    assign p9_right_next_w = p8_right_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[324]) p9_right_r <= p9_right_next_w;
    end
    reg p10_ps_r;
    wire p10_ps_next_w;
    assign p10_ps_next_w = p9_ps_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[325]) p10_ps_r <= p10_ps_next_w;
    end
    reg p10_cs_r;
    wire p10_cs_next_w;
    assign p10_cs_next_w = p9_cs_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[326]) p10_cs_r <= p10_cs_next_w;
    end
    reg [2:0] p10_rm_r;
    wire [2:0] p10_rm_next_w;
    assign p10_rm_next_w = p9_rm_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[327]) p10_rm_r[2:0] <= p10_rm_next_w[2:0];
    end
    reg p10_special_r;
    wire p10_special_next_w;
    assign p10_special_next_w = p9_special_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[328]) p10_special_r <= p10_special_next_w;
    end
    reg [63:0] p10_result_r;
    wire [63:0] p10_result_next_w;
    assign p10_result_next_w = p9_result_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[329]) p10_result_r[15:0] <= p10_result_next_w[15:0];
        if (advance_copy_r[330]) p10_result_r[31:16] <= p10_result_next_w[31:16];
        if (advance_copy_r[331]) p10_result_r[47:32] <= p10_result_next_w[47:32];
        if (advance_copy_r[332]) p10_result_r[63:48] <= p10_result_next_w[63:48];
    end
    reg [4:0] p10_flags_r;
    wire [4:0] p10_flags_next_w;
    assign p10_flags_next_w = p9_flags_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[333]) p10_flags_r[4:0] <= p10_flags_next_w[4:0];
    end
    reg signed [12:0] p10_base_r;
    wire [12:0] p10_base_next_w;
    assign p10_base_next_w = p9_base_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[334]) p10_base_r[12:0] <= p10_base_next_w[12:0];
    end
    reg p10_far_r;
    wire p10_far_next_w;
    assign p10_far_next_w = p9_far_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[335]) p10_far_r <= p10_far_next_w;
    end
    reg [52:0] p10_c_r;
    wire [52:0] p10_c_next_w;
    assign p10_c_next_w = p9_c_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[336]) p10_c_r[15:0] <= p10_c_next_w[15:0];
        if (advance_copy_r[337]) p10_c_r[31:16] <= p10_c_next_w[31:16];
        if (advance_copy_r[338]) p10_c_r[47:32] <= p10_c_next_w[47:32];
        if (advance_copy_r[339]) p10_c_r[52:48] <= p10_c_next_w[52:48];
    end
    reg [7:0] p10_shift_r;
    wire [7:0] p10_shift_next_w;
    assign p10_shift_next_w = p9_shift_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[340]) p10_shift_r[7:0] <= p10_shift_next_w[7:0];
    end
    reg p10_right_r;
    wire p10_right_next_w;
    assign p10_right_next_w = p9_right_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[341]) p10_right_r <= p10_right_next_w;
    end
    reg p11_ps_r;
    wire p11_ps_next_w;
    assign p11_ps_next_w = p10_ps_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[342]) p11_ps_r <= p11_ps_next_w;
    end
    reg p11_cs_r;
    wire p11_cs_next_w;
    assign p11_cs_next_w = p10_cs_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[343]) p11_cs_r <= p11_cs_next_w;
    end
    reg [2:0] p11_rm_r;
    wire [2:0] p11_rm_next_w;
    assign p11_rm_next_w = p10_rm_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[344]) p11_rm_r[2:0] <= p11_rm_next_w[2:0];
    end
    reg p11_special_r;
    wire p11_special_next_w;
    assign p11_special_next_w = p10_special_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[345]) p11_special_r <= p11_special_next_w;
    end
    reg [63:0] p11_result_r;
    wire [63:0] p11_result_next_w;
    assign p11_result_next_w = p10_result_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[346]) p11_result_r[15:0] <= p11_result_next_w[15:0];
        if (advance_copy_r[347]) p11_result_r[31:16] <= p11_result_next_w[31:16];
        if (advance_copy_r[348]) p11_result_r[47:32] <= p11_result_next_w[47:32];
        if (advance_copy_r[349]) p11_result_r[63:48] <= p11_result_next_w[63:48];
    end
    reg [4:0] p11_flags_r;
    wire [4:0] p11_flags_next_w;
    assign p11_flags_next_w = p10_flags_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[350]) p11_flags_r[4:0] <= p11_flags_next_w[4:0];
    end
    reg signed [12:0] p11_base_r;
    wire [12:0] p11_base_next_w;
    assign p11_base_next_w = p10_base_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[351]) p11_base_r[12:0] <= p11_base_next_w[12:0];
    end
    reg p11_far_r;
    wire p11_far_next_w;
    assign p11_far_next_w = p10_far_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[352]) p11_far_r <= p11_far_next_w;
    end
    reg p12_ps_r;
    wire p12_ps_next_w;
    assign p12_ps_next_w = p11_ps_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[353]) p12_ps_r <= p12_ps_next_w;
    end
    reg p12_cs_r;
    wire p12_cs_next_w;
    assign p12_cs_next_w = p11_cs_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[354]) p12_cs_r <= p12_cs_next_w;
    end
    reg [2:0] p12_rm_r;
    wire [2:0] p12_rm_next_w;
    assign p12_rm_next_w = p11_rm_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[355]) p12_rm_r[2:0] <= p12_rm_next_w[2:0];
    end
    reg p12_special_r;
    wire p12_special_next_w;
    assign p12_special_next_w = p11_special_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[356]) p12_special_r <= p12_special_next_w;
    end
    reg [63:0] p12_result_r;
    wire [63:0] p12_result_next_w;
    assign p12_result_next_w = p11_result_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[357]) p12_result_r[15:0] <= p12_result_next_w[15:0];
        if (advance_copy_r[358]) p12_result_r[31:16] <= p12_result_next_w[31:16];
        if (advance_copy_r[359]) p12_result_r[47:32] <= p12_result_next_w[47:32];
        if (advance_copy_r[360]) p12_result_r[63:48] <= p12_result_next_w[63:48];
    end
    reg [4:0] p12_flags_r;
    wire [4:0] p12_flags_next_w;
    assign p12_flags_next_w = p11_flags_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[361]) p12_flags_r[4:0] <= p12_flags_next_w[4:0];
    end
    reg signed [12:0] p12_base_r;
    wire [12:0] p12_base_next_w;
    assign p12_base_next_w = p11_base_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[362]) p12_base_r[12:0] <= p12_base_next_w[12:0];
    end
    reg p12_far_r;
    wire p12_far_next_w;
    assign p12_far_next_w = p11_far_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[363]) p12_far_r <= p12_far_next_w;
    end
    reg p13_ps_r;
    wire p13_ps_next_w;
    assign p13_ps_next_w = p12_ps_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[364]) p13_ps_r <= p13_ps_next_w;
    end
    reg p13_cs_r;
    wire p13_cs_next_w;
    assign p13_cs_next_w = p12_cs_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[365]) p13_cs_r <= p13_cs_next_w;
    end
    reg [2:0] p13_rm_r;
    wire [2:0] p13_rm_next_w;
    assign p13_rm_next_w = p12_rm_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[366]) p13_rm_r[2:0] <= p13_rm_next_w[2:0];
    end
    reg p13_special_r;
    wire p13_special_next_w;
    assign p13_special_next_w = p12_special_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[367]) p13_special_r <= p13_special_next_w;
    end
    reg [63:0] p13_result_r;
    wire [63:0] p13_result_next_w;
    assign p13_result_next_w = p12_result_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[368]) p13_result_r[15:0] <= p13_result_next_w[15:0];
        if (advance_copy_r[369]) p13_result_r[31:16] <= p13_result_next_w[31:16];
        if (advance_copy_r[370]) p13_result_r[47:32] <= p13_result_next_w[47:32];
        if (advance_copy_r[371]) p13_result_r[63:48] <= p13_result_next_w[63:48];
    end
    reg [4:0] p13_flags_r;
    wire [4:0] p13_flags_next_w;
    assign p13_flags_next_w = p12_flags_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[372]) p13_flags_r[4:0] <= p13_flags_next_w[4:0];
    end
    reg signed [12:0] p13_base_r;
    wire [12:0] p13_base_next_w;
    assign p13_base_next_w = p12_base_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[373]) p13_base_r[12:0] <= p13_base_next_w[12:0];
    end
    reg p13_far_r;
    wire p13_far_next_w;
    assign p13_far_next_w = p12_far_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[374]) p13_far_r <= p13_far_next_w;
    end
    wire [7:0] c_low_shift_w;
    assign c_low_shift_w = {5'b0,p10_shift_r[2:0]};
    wire [167:0] c_unshifted_w;
    assign c_unshifted_w = {115'b0,p10_c_r};
    wire [167:0] c_low_right_w;
    assign c_low_right_w = c_unshifted_w >> c_low_shift_w;
    wire c_low_lost_w;
    assign c_low_lost_w = |(c_unshifted_w & ~({168{1'b1}} << c_low_shift_w));
    reg [167:0] p11_c_r;
    wire [167:0] p11_c_next_w;
    assign p11_c_next_w = p10_right_r ? (c_low_right_w | {167'b0,c_low_lost_w})
        : (c_unshifted_w << c_low_shift_w);
    always @(posedge clk_i) begin
        if (advance_copy_r[375]) p11_c_r[15:0] <= p11_c_next_w[15:0];
        if (advance_copy_r[376]) p11_c_r[31:16] <= p11_c_next_w[31:16];
        if (advance_copy_r[377]) p11_c_r[47:32] <= p11_c_next_w[47:32];
        if (advance_copy_r[378]) p11_c_r[63:48] <= p11_c_next_w[63:48];
        if (advance_copy_r[379]) p11_c_r[79:64] <= p11_c_next_w[79:64];
        if (advance_copy_r[380]) p11_c_r[95:80] <= p11_c_next_w[95:80];
        if (advance_copy_r[381]) p11_c_r[111:96] <= p11_c_next_w[111:96];
        if (advance_copy_r[382]) p11_c_r[127:112] <= p11_c_next_w[127:112];
        if (advance_copy_r[383]) p11_c_r[143:128] <= p11_c_next_w[143:128];
        if (advance_copy_r[384]) p11_c_r[159:144] <= p11_c_next_w[159:144];
        if (advance_copy_r[385]) p11_c_r[167:160] <= p11_c_next_w[167:160];
    end
    reg [7:0] p11_shift_r;
    wire [7:0] p11_shift_next_w;
    assign p11_shift_next_w = {p10_shift_r[7:3],3'b0};
    always @(posedge clk_i) begin
        if (advance_copy_r[386]) p11_shift_r[7:0] <= p11_shift_next_w[7:0];
    end
    reg p11_right_r;
    wire p11_right_next_w;
    assign p11_right_next_w = p10_right_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[387]) p11_right_r <= p11_right_next_w;
    end
    wire [167:0] c_high_right_w;
    assign c_high_right_w = p11_c_r >> p11_shift_r;
    wire c_high_lost_w;
    assign c_high_lost_w = |(p11_c_r & ~({168{1'b1}} << p11_shift_r));
    reg [167:0] p12_c_r;
    wire [167:0] p12_c_next_w;
    assign p12_c_next_w = p11_right_r ? (c_high_right_w | {167'b0,c_high_lost_w})
        : (p11_c_r << p11_shift_r);
    always @(posedge clk_i) begin
        if (advance_copy_r[388]) p12_c_r[15:0] <= p12_c_next_w[15:0];
        if (advance_copy_r[389]) p12_c_r[31:16] <= p12_c_next_w[31:16];
        if (advance_copy_r[390]) p12_c_r[47:32] <= p12_c_next_w[47:32];
        if (advance_copy_r[391]) p12_c_r[63:48] <= p12_c_next_w[63:48];
        if (advance_copy_r[392]) p12_c_r[79:64] <= p12_c_next_w[79:64];
        if (advance_copy_r[393]) p12_c_r[95:80] <= p12_c_next_w[95:80];
        if (advance_copy_r[394]) p12_c_r[111:96] <= p12_c_next_w[111:96];
        if (advance_copy_r[395]) p12_c_r[127:112] <= p12_c_next_w[127:112];
        if (advance_copy_r[396]) p12_c_r[143:128] <= p12_c_next_w[143:128];
        if (advance_copy_r[397]) p12_c_r[159:144] <= p12_c_next_w[159:144];
        if (advance_copy_r[398]) p12_c_r[167:160] <= p12_c_next_w[167:160];
    end
    reg [167:0] p13_c_r;
    wire [167:0] p13_c_next_w;
    assign p13_c_next_w = p12_c_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[399]) p13_c_r[15:0] <= p13_c_next_w[15:0];
        if (advance_copy_r[400]) p13_c_r[31:16] <= p13_c_next_w[31:16];
        if (advance_copy_r[401]) p13_c_r[47:32] <= p13_c_next_w[47:32];
        if (advance_copy_r[402]) p13_c_r[63:48] <= p13_c_next_w[63:48];
        if (advance_copy_r[403]) p13_c_r[79:64] <= p13_c_next_w[79:64];
        if (advance_copy_r[404]) p13_c_r[95:80] <= p13_c_next_w[95:80];
        if (advance_copy_r[405]) p13_c_r[111:96] <= p13_c_next_w[111:96];
        if (advance_copy_r[406]) p13_c_r[127:112] <= p13_c_next_w[127:112];
        if (advance_copy_r[407]) p13_c_r[143:128] <= p13_c_next_w[143:128];
        if (advance_copy_r[408]) p13_c_r[159:144] <= p13_c_next_w[159:144];
        if (advance_copy_r[409]) p13_c_r[167:160] <= p13_c_next_w[167:160];
    end
    reg signed [12:0] p4_limit_raw_r;
    wire [12:0] p4_limit_raw_next_w;
    assign p4_limit_raw_next_w = p3_base_r + 13'sd1082;
    always @(posedge clk_i) begin
        if (advance_copy_r[410]) p4_limit_raw_r[12:0] <= p4_limit_raw_next_w[12:0];
    end
    reg signed [12:0] p4_tiny_raw_r;
    wire [12:0] p4_tiny_raw_next_w;
    assign p4_tiny_raw_next_w = -13'sd1082 - p3_base_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[411]) p4_tiny_raw_r[12:0] <= p4_tiny_raw_next_w[12:0];
    end
    reg signed [12:0] p4_anchor_r;
    wire [12:0] p4_anchor_next_w;
    assign p4_anchor_next_w = p3_base_r + 13'sd1083;
    always @(posedge clk_i) begin
        if (advance_copy_r[412]) p4_anchor_r[12:0] <= p4_anchor_next_w[12:0];
    end
    reg [7:0] p5_limit_r;
    wire [7:0] p5_limit_next_w;
    assign p5_limit_next_w = p4_limit_raw_r < 0 ? 8'd0 : p4_limit_raw_r >= 13'sd168
        ? 8'd168 : p4_limit_raw_r[7:0];
    always @(posedge clk_i) begin
        if (advance_copy_r[413]) p5_limit_r[7:0] <= p5_limit_next_w[7:0];
    end
    reg [7:0] p5_tiny_r;
    wire [7:0] p5_tiny_next_w;
    assign p5_tiny_next_w = p4_tiny_raw_r > 13'sd168 ? 8'd168 : p4_tiny_raw_r[7:0];
    always @(posedge clk_i) begin
        if (advance_copy_r[414]) p5_tiny_r[7:0] <= p5_tiny_next_w[7:0];
    end
    reg p5_norm_right_r;
    wire p5_norm_right_next_w;
    assign p5_norm_right_next_w = p4_limit_raw_r < 0;
    always @(posedge clk_i) begin
        if (advance_copy_r[415]) p5_norm_right_r <= p5_norm_right_next_w;
    end
    reg [7:0] p5_marker_pos_r;
    wire [7:0] p5_marker_pos_next_w;
    assign p5_marker_pos_next_w = p4_limit_raw_r < 0 ? 8'd167 : 8'd167 - p4_limit_raw_r[7:0];
    always @(posedge clk_i) begin
        if (advance_copy_r[416]) p5_marker_pos_r[7:0] <= p5_marker_pos_next_w[7:0];
    end
    reg p5_marker_valid_r;
    wire p5_marker_valid_next_w;
    assign p5_marker_valid_next_w = p4_limit_raw_r < 13'sd168;
    always @(posedge clk_i) begin
        if (advance_copy_r[417]) p5_marker_valid_r <= p5_marker_valid_next_w;
    end
    reg signed [12:0] p5_anchor_r;
    wire [12:0] p5_anchor_next_w;
    assign p5_anchor_next_w = p4_anchor_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[418]) p5_anchor_r[12:0] <= p5_anchor_next_w[12:0];
    end
    reg [7:0] p6_limit_r;
    wire [7:0] p6_limit_next_w;
    assign p6_limit_next_w = p5_limit_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[419]) p6_limit_r[7:0] <= p6_limit_next_w[7:0];
    end
    reg [7:0] p6_tiny_r;
    wire [7:0] p6_tiny_next_w;
    assign p6_tiny_next_w = p5_tiny_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[420]) p6_tiny_r[7:0] <= p6_tiny_next_w[7:0];
    end
    reg p6_norm_right_r;
    wire p6_norm_right_next_w;
    assign p6_norm_right_next_w = p5_norm_right_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[421]) p6_norm_right_r <= p6_norm_right_next_w;
    end
    reg signed [12:0] p6_anchor_r;
    wire [12:0] p6_anchor_next_w;
    assign p6_anchor_next_w = p5_anchor_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[422]) p6_anchor_r[12:0] <= p6_anchor_next_w[12:0];
    end
    reg [7:0] p6_marker_pos_r;
    wire [7:0] p6_marker_pos_next_w;
    assign p6_marker_pos_next_w = p5_marker_pos_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[423]) p6_marker_pos_r[7:0] <= p6_marker_pos_next_w[7:0];
    end
    reg p6_marker_valid_r;
    wire p6_marker_valid_next_w;
    assign p6_marker_valid_next_w = p5_marker_valid_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[424]) p6_marker_valid_r <= p6_marker_valid_next_w;
    end
    reg [7:0] p7_limit_r;
    wire [7:0] p7_limit_next_w;
    assign p7_limit_next_w = p6_limit_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[425]) p7_limit_r[7:0] <= p7_limit_next_w[7:0];
    end
    reg [7:0] p7_tiny_r;
    wire [7:0] p7_tiny_next_w;
    assign p7_tiny_next_w = p6_tiny_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[426]) p7_tiny_r[7:0] <= p7_tiny_next_w[7:0];
    end
    reg p7_norm_right_r;
    wire p7_norm_right_next_w;
    assign p7_norm_right_next_w = p6_norm_right_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[427]) p7_norm_right_r <= p7_norm_right_next_w;
    end
    reg signed [12:0] p7_anchor_r;
    wire [12:0] p7_anchor_next_w;
    assign p7_anchor_next_w = p6_anchor_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[428]) p7_anchor_r[12:0] <= p7_anchor_next_w[12:0];
    end
    reg [7:0] p7_marker_pos_r;
    wire [7:0] p7_marker_pos_next_w;
    assign p7_marker_pos_next_w = p6_marker_pos_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[429]) p7_marker_pos_r[7:0] <= p7_marker_pos_next_w[7:0];
    end
    reg p7_marker_valid_r;
    wire p7_marker_valid_next_w;
    assign p7_marker_valid_next_w = p6_marker_valid_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[430]) p7_marker_valid_r <= p7_marker_valid_next_w;
    end
    reg [7:0] p8_limit_r;
    wire [7:0] p8_limit_next_w;
    assign p8_limit_next_w = p7_limit_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[431]) p8_limit_r[7:0] <= p8_limit_next_w[7:0];
    end
    reg [7:0] p8_tiny_r;
    wire [7:0] p8_tiny_next_w;
    assign p8_tiny_next_w = p7_tiny_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[432]) p8_tiny_r[7:0] <= p8_tiny_next_w[7:0];
    end
    reg p8_norm_right_r;
    wire p8_norm_right_next_w;
    assign p8_norm_right_next_w = p7_norm_right_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[433]) p8_norm_right_r <= p8_norm_right_next_w;
    end
    reg signed [12:0] p8_anchor_r;
    wire [12:0] p8_anchor_next_w;
    assign p8_anchor_next_w = p7_anchor_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[434]) p8_anchor_r[12:0] <= p8_anchor_next_w[12:0];
    end
    reg [7:0] p8_marker_pos_r;
    wire [7:0] p8_marker_pos_next_w;
    assign p8_marker_pos_next_w = p7_marker_pos_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[435]) p8_marker_pos_r[7:0] <= p8_marker_pos_next_w[7:0];
    end
    reg p8_marker_valid_r;
    wire p8_marker_valid_next_w;
    assign p8_marker_valid_next_w = p7_marker_valid_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[436]) p8_marker_valid_r <= p8_marker_valid_next_w;
    end
    reg [7:0] p9_limit_r;
    wire [7:0] p9_limit_next_w;
    assign p9_limit_next_w = p8_limit_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[437]) p9_limit_r[7:0] <= p9_limit_next_w[7:0];
    end
    reg [7:0] p9_tiny_r;
    wire [7:0] p9_tiny_next_w;
    assign p9_tiny_next_w = p8_tiny_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[438]) p9_tiny_r[7:0] <= p9_tiny_next_w[7:0];
    end
    reg p9_norm_right_r;
    wire p9_norm_right_next_w;
    assign p9_norm_right_next_w = p8_norm_right_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[439]) p9_norm_right_r <= p9_norm_right_next_w;
    end
    reg signed [12:0] p9_anchor_r;
    wire [12:0] p9_anchor_next_w;
    assign p9_anchor_next_w = p8_anchor_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[440]) p9_anchor_r[12:0] <= p9_anchor_next_w[12:0];
    end
    reg [7:0] p9_marker_pos_r;
    wire [7:0] p9_marker_pos_next_w;
    assign p9_marker_pos_next_w = p8_marker_pos_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[441]) p9_marker_pos_r[7:0] <= p9_marker_pos_next_w[7:0];
    end
    reg p9_marker_valid_r;
    wire p9_marker_valid_next_w;
    assign p9_marker_valid_next_w = p8_marker_valid_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[442]) p9_marker_valid_r <= p9_marker_valid_next_w;
    end
    reg [7:0] p10_limit_r;
    wire [7:0] p10_limit_next_w;
    assign p10_limit_next_w = p9_limit_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[443]) p10_limit_r[7:0] <= p10_limit_next_w[7:0];
    end
    reg [7:0] p10_tiny_r;
    wire [7:0] p10_tiny_next_w;
    assign p10_tiny_next_w = p9_tiny_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[444]) p10_tiny_r[7:0] <= p10_tiny_next_w[7:0];
    end
    reg p10_norm_right_r;
    wire p10_norm_right_next_w;
    assign p10_norm_right_next_w = p9_norm_right_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[445]) p10_norm_right_r <= p10_norm_right_next_w;
    end
    reg signed [12:0] p10_anchor_r;
    wire [12:0] p10_anchor_next_w;
    assign p10_anchor_next_w = p9_anchor_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[446]) p10_anchor_r[12:0] <= p10_anchor_next_w[12:0];
    end
    reg [7:0] p10_marker_pos_r;
    wire [7:0] p10_marker_pos_next_w;
    assign p10_marker_pos_next_w = p9_marker_pos_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[447]) p10_marker_pos_r[7:0] <= p10_marker_pos_next_w[7:0];
    end
    reg p10_marker_valid_r;
    wire p10_marker_valid_next_w;
    assign p10_marker_valid_next_w = p9_marker_valid_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[448]) p10_marker_valid_r <= p10_marker_valid_next_w;
    end
    reg [7:0] p11_limit_r;
    wire [7:0] p11_limit_next_w;
    assign p11_limit_next_w = p10_limit_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[449]) p11_limit_r[7:0] <= p11_limit_next_w[7:0];
    end
    reg [7:0] p11_tiny_r;
    wire [7:0] p11_tiny_next_w;
    assign p11_tiny_next_w = p10_tiny_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[450]) p11_tiny_r[7:0] <= p11_tiny_next_w[7:0];
    end
    reg p11_norm_right_r;
    wire p11_norm_right_next_w;
    assign p11_norm_right_next_w = p10_norm_right_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[451]) p11_norm_right_r <= p11_norm_right_next_w;
    end
    reg signed [12:0] p11_anchor_r;
    wire [12:0] p11_anchor_next_w;
    assign p11_anchor_next_w = p10_anchor_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[452]) p11_anchor_r[12:0] <= p11_anchor_next_w[12:0];
    end
    reg [7:0] p11_marker_pos_r;
    wire [7:0] p11_marker_pos_next_w;
    assign p11_marker_pos_next_w = p10_marker_pos_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[453]) p11_marker_pos_r[7:0] <= p11_marker_pos_next_w[7:0];
    end
    reg p11_marker_valid_r;
    wire p11_marker_valid_next_w;
    assign p11_marker_valid_next_w = p10_marker_valid_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[454]) p11_marker_valid_r <= p11_marker_valid_next_w;
    end
    reg [7:0] p12_limit_r;
    wire [7:0] p12_limit_next_w;
    assign p12_limit_next_w = p11_limit_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[455]) p12_limit_r[7:0] <= p12_limit_next_w[7:0];
    end
    reg [7:0] p12_tiny_r;
    wire [7:0] p12_tiny_next_w;
    assign p12_tiny_next_w = p11_tiny_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[456]) p12_tiny_r[7:0] <= p12_tiny_next_w[7:0];
    end
    reg p12_norm_right_r;
    wire p12_norm_right_next_w;
    assign p12_norm_right_next_w = p11_norm_right_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[457]) p12_norm_right_r <= p12_norm_right_next_w;
    end
    reg signed [12:0] p12_anchor_r;
    wire [12:0] p12_anchor_next_w;
    assign p12_anchor_next_w = p11_anchor_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[458]) p12_anchor_r[12:0] <= p12_anchor_next_w[12:0];
    end
    reg [7:0] p13_limit_r;
    wire [7:0] p13_limit_next_w;
    assign p13_limit_next_w = p12_limit_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[459]) p13_limit_r[7:0] <= p13_limit_next_w[7:0];
    end
    reg [7:0] p13_tiny_r;
    wire [7:0] p13_tiny_next_w;
    assign p13_tiny_next_w = p12_tiny_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[460]) p13_tiny_r[7:0] <= p13_tiny_next_w[7:0];
    end
    reg p13_norm_right_r;
    wire p13_norm_right_next_w;
    assign p13_norm_right_next_w = p12_norm_right_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[461]) p13_norm_right_r <= p13_norm_right_next_w;
    end
    reg signed [12:0] p13_anchor_r;
    wire [12:0] p13_anchor_next_w;
    assign p13_anchor_next_w = p12_anchor_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[462]) p13_anchor_r[12:0] <= p13_anchor_next_w[12:0];
    end
    reg [167:0] p12_marker_r;
    wire [167:0] p12_marker_next_w;
    assign p12_marker_next_w = p11_marker_valid_r ? (168'd1 << {p11_marker_pos_r[7:3],3'b0}) :
        168'b0;
    always @(posedge clk_i) begin
        if (advance_copy_r[463]) p12_marker_r[15:0] <= p12_marker_next_w[15:0];
        if (advance_copy_r[464]) p12_marker_r[31:16] <= p12_marker_next_w[31:16];
        if (advance_copy_r[465]) p12_marker_r[47:32] <= p12_marker_next_w[47:32];
        if (advance_copy_r[466]) p12_marker_r[63:48] <= p12_marker_next_w[63:48];
        if (advance_copy_r[467]) p12_marker_r[79:64] <= p12_marker_next_w[79:64];
        if (advance_copy_r[468]) p12_marker_r[95:80] <= p12_marker_next_w[95:80];
        if (advance_copy_r[469]) p12_marker_r[111:96] <= p12_marker_next_w[111:96];
        if (advance_copy_r[470]) p12_marker_r[127:112] <= p12_marker_next_w[127:112];
        if (advance_copy_r[471]) p12_marker_r[143:128] <= p12_marker_next_w[143:128];
        if (advance_copy_r[472]) p12_marker_r[159:144] <= p12_marker_next_w[159:144];
        if (advance_copy_r[473]) p12_marker_r[167:160] <= p12_marker_next_w[167:160];
    end
    reg [2:0] p12_marker_fine_r;
    wire [2:0] p12_marker_fine_next_w;
    assign p12_marker_fine_next_w = p11_marker_pos_r[2:0];
    always @(posedge clk_i) begin
        if (advance_copy_r[474]) p12_marker_fine_r[2:0] <= p12_marker_fine_next_w[2:0];
    end
    reg [167:0] p13_marker_r;
    wire [167:0] p13_marker_next_w;
    assign p13_marker_next_w = p12_marker_r << p12_marker_fine_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[475]) p13_marker_r[15:0] <= p13_marker_next_w[15:0];
        if (advance_copy_r[476]) p13_marker_r[31:16] <= p13_marker_next_w[31:16];
        if (advance_copy_r[477]) p13_marker_r[47:32] <= p13_marker_next_w[47:32];
        if (advance_copy_r[478]) p13_marker_r[63:48] <= p13_marker_next_w[63:48];
        if (advance_copy_r[479]) p13_marker_r[79:64] <= p13_marker_next_w[79:64];
        if (advance_copy_r[480]) p13_marker_r[95:80] <= p13_marker_next_w[95:80];
        if (advance_copy_r[481]) p13_marker_r[111:96] <= p13_marker_next_w[111:96];
        if (advance_copy_r[482]) p13_marker_r[127:112] <= p13_marker_next_w[127:112];
        if (advance_copy_r[483]) p13_marker_r[143:128] <= p13_marker_next_w[143:128];
        if (advance_copy_r[484]) p13_marker_r[159:144] <= p13_marker_next_w[159:144];
        if (advance_copy_r[485]) p13_marker_r[167:160] <= p13_marker_next_w[167:160];
    end
    reg [7:0] p6_mul_count0_r;
    wire [7:0] p6_mul_count0_next_w;
    assign p6_mul_count0_next_w = p5_limit_r < 8'd60 ? p5_limit_r : 8'd60;
    always @(posedge clk_i) begin
        if (advance_copy_r[486]) p6_mul_count0_r[7:0] <= p6_mul_count0_next_w[7:0];
    end
    reg [7:0] p7_mul_count0_r;
    wire [7:0] p7_mul_count0_next_w;
    assign p7_mul_count0_next_w = p6_mul_count0_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[487]) p7_mul_count0_r[7:0] <= p7_mul_count0_next_w[7:0];
    end
    reg [7:0] p8_mul_count0_r;
    wire [7:0] p8_mul_count0_next_w;
    assign p8_mul_count0_next_w = p7_mul_count0_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[488]) p8_mul_count0_r[7:0] <= p8_mul_count0_next_w[7:0];
    end
    reg [7:0] p9_mul_count0_r;
    wire [7:0] p9_mul_count0_next_w;
    assign p9_mul_count0_next_w = p8_mul_count0_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[489]) p9_mul_count0_r[7:0] <= p9_mul_count0_next_w[7:0];
    end
    reg [7:0] p10_mul_count0_r;
    wire [7:0] p10_mul_count0_next_w;
    assign p10_mul_count0_next_w = p9_mul_count0_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[490]) p10_mul_count0_r[7:0] <= p10_mul_count0_next_w[7:0];
    end
    reg [7:0] p11_mul_count0_r;
    wire [7:0] p11_mul_count0_next_w;
    assign p11_mul_count0_next_w = p10_mul_count0_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[491]) p11_mul_count0_r[7:0] <= p11_mul_count0_next_w[7:0];
    end
    reg [7:0] p12_mul_count0_r;
    wire [7:0] p12_mul_count0_next_w;
    assign p12_mul_count0_next_w = p11_mul_count0_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[492]) p12_mul_count0_r[7:0] <= p12_mul_count0_next_w[7:0];
    end
    reg [7:0] p13_mul_count0_r;
    wire [7:0] p13_mul_count0_next_w;
    assign p13_mul_count0_next_w = p12_mul_count0_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[493]) p13_mul_count0_r[7:0] <= p13_mul_count0_next_w[7:0];
    end
    reg [7:0] p6_mul_count1_r;
    wire [7:0] p6_mul_count1_next_w;
    assign p6_mul_count1_next_w = p5_limit_r < 8'd59 ? p5_limit_r : 8'd59;
    always @(posedge clk_i) begin
        if (advance_copy_r[494]) p6_mul_count1_r[7:0] <= p6_mul_count1_next_w[7:0];
    end
    reg [7:0] p7_mul_count1_r;
    wire [7:0] p7_mul_count1_next_w;
    assign p7_mul_count1_next_w = p6_mul_count1_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[495]) p7_mul_count1_r[7:0] <= p7_mul_count1_next_w[7:0];
    end
    reg [7:0] p8_mul_count1_r;
    wire [7:0] p8_mul_count1_next_w;
    assign p8_mul_count1_next_w = p7_mul_count1_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[496]) p8_mul_count1_r[7:0] <= p8_mul_count1_next_w[7:0];
    end
    reg [7:0] p9_mul_count1_r;
    wire [7:0] p9_mul_count1_next_w;
    assign p9_mul_count1_next_w = p8_mul_count1_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[497]) p9_mul_count1_r[7:0] <= p9_mul_count1_next_w[7:0];
    end
    reg [7:0] p10_mul_count1_r;
    wire [7:0] p10_mul_count1_next_w;
    assign p10_mul_count1_next_w = p9_mul_count1_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[498]) p10_mul_count1_r[7:0] <= p10_mul_count1_next_w[7:0];
    end
    reg [7:0] p11_mul_count1_r;
    wire [7:0] p11_mul_count1_next_w;
    assign p11_mul_count1_next_w = p10_mul_count1_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[499]) p11_mul_count1_r[7:0] <= p11_mul_count1_next_w[7:0];
    end
    reg [7:0] p12_mul_count1_r;
    wire [7:0] p12_mul_count1_next_w;
    assign p12_mul_count1_next_w = p11_mul_count1_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[500]) p12_mul_count1_r[7:0] <= p12_mul_count1_next_w[7:0];
    end
    reg [7:0] p13_mul_count1_r;
    wire [7:0] p13_mul_count1_next_w;
    assign p13_mul_count1_next_w = p12_mul_count1_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[501]) p13_mul_count1_r[7:0] <= p13_mul_count1_next_w[7:0];
    end
    wire [167:0] fma_product_w;
    assign fma_product_w = p13_far_r ? {167'b0, |product_w} : {59'b0, product_w, 3'b0};
    wire add_a_big_w;
    assign add_a_big_w = a_i[62:0] >= b_i[62:0];
    wire [10:0] add_a_exp_w;
    assign add_a_exp_w = (|a_i[62:52]) ? a_i[62:52] : 11'd1;
    wire [10:0] add_b_exp_w;
    assign add_b_exp_w = (|b_i[62:52]) ? b_i[62:52] : 11'd1;
    reg [52:0] e1_add_big_r;
    wire [52:0] e1_add_big_next_w;
    assign e1_add_big_next_w = add_a_big_w ? a_mantissa_w : b_mantissa_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[502] && capture_data_w) e1_add_big_r[15:0] <= e1_add_big_next_w[15:0];
        if (advance_copy_r[503] && capture_data_w) e1_add_big_r[31:16] <= e1_add_big_next_w[31:16];
        if (advance_copy_r[504] && capture_data_w) e1_add_big_r[47:32] <= e1_add_big_next_w[47:32];
        if (advance_copy_r[505] && capture_data_w) e1_add_big_r[52:48] <= e1_add_big_next_w[52:48];
    end
    reg [52:0] e1_add_small_r;
    wire [52:0] e1_add_small_next_w;
    assign e1_add_small_next_w = add_a_big_w ? b_mantissa_w : a_mantissa_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[506] && capture_data_w) e1_add_small_r[15:0] <=
        e1_add_small_next_w[15:0];
        if (advance_copy_r[507] && capture_data_w) e1_add_small_r[31:16] <=
        e1_add_small_next_w[31:16];
        if (advance_copy_r[508] && capture_data_w) e1_add_small_r[47:32] <=
        e1_add_small_next_w[47:32];
        if (advance_copy_r[509] && capture_data_w) e1_add_small_r[52:48] <=
        e1_add_small_next_w[52:48];
    end
    reg [10:0] e1_add_delta_r;
    wire [10:0] e1_add_delta_next_w;
    assign e1_add_delta_next_w = add_a_big_w ? add_a_exp_w - add_b_exp_w
        : add_b_exp_w - add_a_exp_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[510] && capture_data_w) e1_add_delta_r[10:0] <=
        e1_add_delta_next_w[10:0];
    end
    reg signed [12:0] e1_add_base_r;
    wire [12:0] e1_add_base_next_w;
    assign e1_add_base_next_w = $signed({2'b0, add_a_big_w ? add_a_exp_w : add_b_exp_w}) - 13'sd971;
    always @(posedge clk_i) begin
        if (advance_copy_r[511] && capture_data_w) e1_add_base_r[12:0] <= e1_add_base_next_w[12:0];
    end
    wire [10:0] add_big_exp_w;
    assign add_big_exp_w = add_a_big_w ? add_a_exp_w : add_b_exp_w;
    reg [5:0] e1_add_marker_pos_r;
    wire [5:0] e1_add_marker_pos_next_w;
    assign e1_add_marker_pos_next_w = 6'd56 - add_big_exp_w[5:0];
    always @(posedge clk_i) begin
        if (advance_copy_r[512] && capture_data_w) e1_add_marker_pos_r[5:0] <=
        e1_add_marker_pos_next_w[5:0];
    end
    reg e1_add_marker_valid_r;
    wire e1_add_marker_valid_next_w;
    assign e1_add_marker_valid_next_w = add_big_exp_w <= 11'd56;
    always @(posedge clk_i) begin
        if (advance_copy_r[513] && capture_data_w) e1_add_marker_valid_r <=
        e1_add_marker_valid_next_w;
    end
    reg [7:0] e1_add_limit_r;
    wire [7:0] e1_add_limit_next_w;
    assign e1_add_limit_next_w = add_big_exp_w > 11'd56 ? 8'd168 : {2'b0,add_big_exp_w[5:0]} +
        8'd111;
    always @(posedge clk_i) begin
        if (advance_copy_r[514] && capture_data_w) e1_add_limit_r[7:0] <= e1_add_limit_next_w[7:0];
    end
    reg [12:0] e1_add_anchor_r;
    wire [12:0] e1_add_anchor_next_w;
    assign e1_add_anchor_next_w = {2'b0,add_big_exp_w} + 13'd112;
    always @(posedge clk_i) begin
        if (advance_copy_r[515] && capture_data_w) e1_add_anchor_r[12:0] <=
        e1_add_anchor_next_w[12:0];
    end
    reg [167:0] a2_marker_r;
    wire [167:0] a2_marker_next_w;
    assign a2_marker_next_w = e1_add_marker_valid_r ? (168'd1 << e1_add_marker_pos_r) : 168'b0;
    always @(posedge clk_i) begin
        if (advance_copy_r[516]) a2_marker_r[15:0] <= a2_marker_next_w[15:0];
        if (advance_copy_r[517]) a2_marker_r[31:16] <= a2_marker_next_w[31:16];
        if (advance_copy_r[518]) a2_marker_r[47:32] <= a2_marker_next_w[47:32];
        if (advance_copy_r[519]) a2_marker_r[63:48] <= a2_marker_next_w[63:48];
        if (advance_copy_r[520]) a2_marker_r[79:64] <= a2_marker_next_w[79:64];
        if (advance_copy_r[521]) a2_marker_r[95:80] <= a2_marker_next_w[95:80];
        if (advance_copy_r[522]) a2_marker_r[111:96] <= a2_marker_next_w[111:96];
        if (advance_copy_r[523]) a2_marker_r[127:112] <= a2_marker_next_w[127:112];
        if (advance_copy_r[524]) a2_marker_r[143:128] <= a2_marker_next_w[143:128];
        if (advance_copy_r[525]) a2_marker_r[159:144] <= a2_marker_next_w[159:144];
        if (advance_copy_r[526]) a2_marker_r[167:160] <= a2_marker_next_w[167:160];
    end
    reg [7:0] a2_limit_r;
    wire [7:0] a2_limit_next_w;
    assign a2_limit_next_w = e1_add_limit_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[527]) a2_limit_r[7:0] <= a2_limit_next_w[7:0];
    end
    reg signed [12:0] a2_anchor_r;
    wire [12:0] a2_anchor_next_w;
    assign a2_anchor_next_w = e1_add_anchor_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[528]) a2_anchor_r[12:0] <= a2_anchor_next_w[12:0];
    end
    reg e1_add_ps_r;
    wire e1_add_ps_next_w;
    assign e1_add_ps_next_w = add_a_big_w ? product_sign_w : c_sign_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[529] && capture_data_w) e1_add_ps_r <= e1_add_ps_next_w;
    end
    reg e1_add_cs_r;
    wire e1_add_cs_next_w;
    assign e1_add_cs_next_w = add_a_big_w ? c_sign_w : product_sign_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[530] && capture_data_w) e1_add_cs_r <= e1_add_cs_next_w;
    end
    wire [5:0] add_shift_w;
    assign add_shift_w = e1_add_delta_r > 11'd56 ? 6'd56 : e1_add_delta_r[5:0];
    wire [55:0] add_small_w;
    assign add_small_w = {e1_add_small_r, 3'b0};
    wire [55:0] add_small_shift_w;
    assign add_small_shift_w = add_small_w >> add_shift_w;
    wire add_lost_w;
    assign add_lost_w = |(add_small_w & ~(56'hffffffffffffff << add_shift_w));
    reg [167:0] a2_big_r;
    wire [167:0] a2_big_next_w;
    assign a2_big_next_w = {112'b0, e1_add_big_r, 3'b0};
    always @(posedge clk_i) begin
        if (advance_copy_r[531]) a2_big_r[15:0] <= a2_big_next_w[15:0];
        if (advance_copy_r[532]) a2_big_r[31:16] <= a2_big_next_w[31:16];
        if (advance_copy_r[533]) a2_big_r[47:32] <= a2_big_next_w[47:32];
        if (advance_copy_r[534]) a2_big_r[63:48] <= a2_big_next_w[63:48];
        if (advance_copy_r[535]) a2_big_r[79:64] <= a2_big_next_w[79:64];
        if (advance_copy_r[536]) a2_big_r[95:80] <= a2_big_next_w[95:80];
        if (advance_copy_r[537]) a2_big_r[111:96] <= a2_big_next_w[111:96];
        if (advance_copy_r[538]) a2_big_r[127:112] <= a2_big_next_w[127:112];
        if (advance_copy_r[539]) a2_big_r[143:128] <= a2_big_next_w[143:128];
        if (advance_copy_r[540]) a2_big_r[159:144] <= a2_big_next_w[159:144];
        if (advance_copy_r[541]) a2_big_r[167:160] <= a2_big_next_w[167:160];
    end
    reg [167:0] a2_small_r;
    wire [167:0] a2_small_next_w;
    assign a2_small_next_w = {112'b0, add_small_shift_w[55:1], (add_small_shift_w[0] | add_lost_w)};
    always @(posedge clk_i) begin
        if (advance_copy_r[542]) a2_small_r[15:0] <= a2_small_next_w[15:0];
        if (advance_copy_r[543]) a2_small_r[31:16] <= a2_small_next_w[31:16];
        if (advance_copy_r[544]) a2_small_r[47:32] <= a2_small_next_w[47:32];
        if (advance_copy_r[545]) a2_small_r[63:48] <= a2_small_next_w[63:48];
        if (advance_copy_r[546]) a2_small_r[79:64] <= a2_small_next_w[79:64];
        if (advance_copy_r[547]) a2_small_r[95:80] <= a2_small_next_w[95:80];
        if (advance_copy_r[548]) a2_small_r[111:96] <= a2_small_next_w[111:96];
        if (advance_copy_r[549]) a2_small_r[127:112] <= a2_small_next_w[127:112];
        if (advance_copy_r[550]) a2_small_r[143:128] <= a2_small_next_w[143:128];
        if (advance_copy_r[551]) a2_small_r[159:144] <= a2_small_next_w[159:144];
        if (advance_copy_r[552]) a2_small_r[167:160] <= a2_small_next_w[167:160];
    end
    reg a2_ps_r;
    wire a2_ps_next_w;
    assign a2_ps_next_w = e1_add_ps_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[553]) a2_ps_r <= a2_ps_next_w;
    end
    reg a2_cs_r;
    wire a2_cs_next_w;
    assign a2_cs_next_w = e1_add_cs_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[554]) a2_cs_r <= a2_cs_next_w;
    end
    reg [2:0] a2_rm_r;
    wire [2:0] a2_rm_next_w;
    assign a2_rm_next_w = e1_rm_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[555]) a2_rm_r[2:0] <= a2_rm_next_w[2:0];
    end
    reg a2_special_r;
    wire a2_special_next_w;
    assign a2_special_next_w = e1_special_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[556]) a2_special_r <= a2_special_next_w;
    end
    reg [63:0] a2_result_r;
    wire [63:0] a2_result_next_w;
    assign a2_result_next_w = e1_result_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[557]) a2_result_r[15:0] <= a2_result_next_w[15:0];
        if (advance_copy_r[558]) a2_result_r[31:16] <= a2_result_next_w[31:16];
        if (advance_copy_r[559]) a2_result_r[47:32] <= a2_result_next_w[47:32];
        if (advance_copy_r[560]) a2_result_r[63:48] <= a2_result_next_w[63:48];
    end
    reg [4:0] a2_flags_r;
    wire [4:0] a2_flags_next_w;
    assign a2_flags_next_w = e1_flags_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[561]) a2_flags_r[4:0] <= a2_flags_next_w[4:0];
    end
    reg signed [12:0] a2_base_r;
    wire [12:0] a2_base_next_w;
    assign a2_base_next_w = e1_add_base_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[562]) a2_base_r[12:0] <= a2_base_next_w[12:0];
    end
    reg [13:0] product_valid_r;
    reg [3:0] product_tag_r [0:13];
    reg [13:0] product_mul_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            product_valid_r <= 0;
        end else begin
            if (advance_copy_r[738]) product_valid_r[0] <= dispatch_w && (class_kind_r != 2'd0);
            else if (cancel_valid_i
                && ((product_tag_r[0] - age_head_i) >= cancel_distance_w))
                product_valid_r[0] <= 1'b0;
            if (advance_copy_r[738]) product_valid_r[1] <= product_valid_r[0] && !(cancel_valid_i
                    && ((product_tag_r[0] - age_head_i) >= cancel_distance_w));
            else if (cancel_valid_i
                && ((product_tag_r[1] - age_head_i) >= cancel_distance_w))
                product_valid_r[1] <= 1'b0;
            if (advance_copy_r[738]) product_valid_r[2] <= product_valid_r[1] && !(cancel_valid_i
                    && ((product_tag_r[1] - age_head_i) >= cancel_distance_w));
            else if (cancel_valid_i
                && ((product_tag_r[2] - age_head_i) >= cancel_distance_w))
                product_valid_r[2] <= 1'b0;
            if (advance_copy_r[738]) product_valid_r[3] <= product_valid_r[2] && !(cancel_valid_i
                    && ((product_tag_r[2] - age_head_i) >= cancel_distance_w));
            else if (cancel_valid_i
                && ((product_tag_r[3] - age_head_i) >= cancel_distance_w))
                product_valid_r[3] <= 1'b0;
            if (advance_copy_r[738]) product_valid_r[4] <= product_valid_r[3] && !(cancel_valid_i
                    && ((product_tag_r[3] - age_head_i) >= cancel_distance_w));
            else if (cancel_valid_i
                && ((product_tag_r[4] - age_head_i) >= cancel_distance_w))
                product_valid_r[4] <= 1'b0;
            if (advance_copy_r[738]) product_valid_r[5] <= product_valid_r[4] && !(cancel_valid_i
                    && ((product_tag_r[4] - age_head_i) >= cancel_distance_w));
            else if (cancel_valid_i
                && ((product_tag_r[5] - age_head_i) >= cancel_distance_w))
                product_valid_r[5] <= 1'b0;
            if (advance_copy_r[738]) product_valid_r[6] <= product_valid_r[5] && !(cancel_valid_i
                    && ((product_tag_r[5] - age_head_i) >= cancel_distance_w));
            else if (cancel_valid_i
                && ((product_tag_r[6] - age_head_i) >= cancel_distance_w))
                product_valid_r[6] <= 1'b0;
            if (advance_copy_r[738]) product_valid_r[7] <= product_valid_r[6] && !(cancel_valid_i
                    && ((product_tag_r[6] - age_head_i) >= cancel_distance_w));
            else if (cancel_valid_i
                && ((product_tag_r[7] - age_head_i) >= cancel_distance_w))
                product_valid_r[7] <= 1'b0;
            if (advance_copy_r[738]) product_valid_r[8] <= product_valid_r[7] && !(cancel_valid_i
                    && ((product_tag_r[7] - age_head_i) >= cancel_distance_w));
            else if (cancel_valid_i
                && ((product_tag_r[8] - age_head_i) >= cancel_distance_w))
                product_valid_r[8] <= 1'b0;
            if (advance_copy_r[738]) product_valid_r[9] <= product_valid_r[8] && !(cancel_valid_i
                    && ((product_tag_r[8] - age_head_i) >= cancel_distance_w));
            else if (cancel_valid_i
                && ((product_tag_r[9] - age_head_i) >= cancel_distance_w))
                product_valid_r[9] <= 1'b0;
            if (advance_copy_r[738]) product_valid_r[10] <= product_valid_r[9] && !(cancel_valid_i
                    && ((product_tag_r[9] - age_head_i) >= cancel_distance_w));
            else if (cancel_valid_i
                && ((product_tag_r[10] - age_head_i) >= cancel_distance_w))
                product_valid_r[10] <= 1'b0;
            if (advance_copy_r[738]) product_valid_r[11] <= product_valid_r[10] && !(cancel_valid_i
                    && ((product_tag_r[10] - age_head_i) >= cancel_distance_w));
            else if (cancel_valid_i
                && ((product_tag_r[11] - age_head_i) >= cancel_distance_w))
                product_valid_r[11] <= 1'b0;
            if (advance_copy_r[738]) product_valid_r[12] <= product_valid_r[11] && !(cancel_valid_i
                    && ((product_tag_r[11] - age_head_i) >= cancel_distance_w));
            else if (cancel_valid_i
                && ((product_tag_r[12] - age_head_i) >= cancel_distance_w))
                product_valid_r[12] <= 1'b0;
            if (advance_copy_r[738]) product_valid_r[13] <= product_valid_r[12] && !(cancel_valid_i
                    && ((product_tag_r[12] - age_head_i) >= cancel_distance_w));
            else if (cancel_valid_i
                && ((product_tag_r[13] - age_head_i) >= cancel_distance_w))
                product_valid_r[13] <= 1'b0;
        end
    end
    always @(posedge clk_i) begin
        begin
            if (advance_copy_r[722]) product_tag_r[0] <= class_tag_r;
            if (advance_copy_r[723]) product_tag_r[1] <= product_tag_r[0];
            if (advance_copy_r[724]) product_tag_r[2] <= product_tag_r[1];
            if (advance_copy_r[725]) product_tag_r[3] <= product_tag_r[2];
            if (advance_copy_r[726]) product_tag_r[4] <= product_tag_r[3];
            if (advance_copy_r[727]) product_tag_r[5] <= product_tag_r[4];
            if (advance_copy_r[728]) product_tag_r[6] <= product_tag_r[5];
            if (advance_copy_r[729]) product_tag_r[7] <= product_tag_r[6];
            if (advance_copy_r[730]) product_tag_r[8] <= product_tag_r[7];
            if (advance_copy_r[731]) product_tag_r[9] <= product_tag_r[8];
            if (advance_copy_r[732]) product_tag_r[10] <= product_tag_r[9];
            if (advance_copy_r[733]) product_tag_r[11] <= product_tag_r[10];
            if (advance_copy_r[734]) product_tag_r[12] <= product_tag_r[11];
            if (advance_copy_r[735]) product_tag_r[13] <= product_tag_r[12];
            if (advance_copy_r[736]) product_mul_r <= {product_mul_r[12:0], class_kind_r == 2'd1};
        end
    end
    reg [0:0] add_valid_r;
    reg [3:0] add_tag_r [0:0];
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            add_valid_r <= 0;
        end else begin
            if (advance_copy_r[739]) add_valid_r[0] <= dispatch_w && (class_kind_r == 2'd0);
            else if (cancel_valid_i
                && ((add_tag_r[0] - age_head_i) >= cancel_distance_w))
                add_valid_r[0] <= 1'b0;
        end
    end
    always @(posedge clk_i) begin
        if (advance_copy_r[737]) begin
            add_tag_r[0] <= class_tag_r;
        end
    end
    wire product_live_w;
    assign product_live_w = product_valid_r[13] && !(cancel_valid_i
        && ((product_tag_r[13] - age_head_i) >= cancel_distance_w));
    wire add_live_w;
    assign add_live_w = add_valid_r[0] && !(cancel_valid_i
        && ((add_tag_r[0] - age_head_i) >= cancel_distance_w));
    wire mul_select_w;
    assign mul_select_w = product_valid_r[13] && product_mul_r[13];
    wire sum_in_w;
    assign sum_in_w = add_live_w || (product_live_w && !product_mul_r[13]);
    (* keep = "true", syn_preserve = 1 *) reg [7:0] add_class_valid_r;
    wire [7:0] add_class_valid_next_w;
    assign add_class_valid_next_w = {8{class_next_w}};
    always @(posedge clk_i) begin
        if (advance_copy_r[563]) add_class_valid_r[7:0] <= add_class_valid_next_w[7:0];
    end
    (* keep = "true", syn_preserve = 1 *) reg [7:0] add_class_kind_r;
    wire [7:0] add_class_kind_next_w;
    assign add_class_kind_next_w = {8{kind_w == 2'd0}};
    always @(posedge clk_i) begin
        if (advance_copy_r[564] && capture_w) add_class_kind_r[7:0] <= add_class_kind_next_w[7:0];
    end
    (* keep = "true", syn_preserve = 1 *) reg [46:0] add_select_r;
    wire [46:0] add_select_next_w;
    assign add_select_next_w = {(add_class_valid_r[7] && add_class_kind_r[7] &&
        !reservation_r[3]),(add_class_valid_r[7] && add_class_kind_r[7] &&
        !reservation_r[3]),(add_class_valid_r[7] && add_class_kind_r[7] &&
        !reservation_r[3]),(add_class_valid_r[7] && add_class_kind_r[7] &&
        !reservation_r[3]),(add_class_valid_r[7] && add_class_kind_r[7] &&
        !reservation_r[3]),(add_class_valid_r[6] && add_class_kind_r[6] &&
        !reservation_r[3]),(add_class_valid_r[6] && add_class_kind_r[6] &&
        !reservation_r[3]),(add_class_valid_r[6] && add_class_kind_r[6] &&
        !reservation_r[3]),(add_class_valid_r[6] && add_class_kind_r[6] &&
        !reservation_r[3]),(add_class_valid_r[6] && add_class_kind_r[6] &&
        !reservation_r[3]),(add_class_valid_r[6] && add_class_kind_r[6] &&
        !reservation_r[3]),(add_class_valid_r[5] && add_class_kind_r[5] &&
        !reservation_r[3]),(add_class_valid_r[5] && add_class_kind_r[5] &&
        !reservation_r[3]),(add_class_valid_r[5] && add_class_kind_r[5] &&
        !reservation_r[3]),(add_class_valid_r[5] && add_class_kind_r[5] &&
        !reservation_r[3]),(add_class_valid_r[5] && add_class_kind_r[5] &&
        !reservation_r[3]),(add_class_valid_r[5] && add_class_kind_r[5] &&
        !reservation_r[3]),(add_class_valid_r[4] && add_class_kind_r[4] &&
        !reservation_r[3]),(add_class_valid_r[4] && add_class_kind_r[4] &&
        !reservation_r[3]),(add_class_valid_r[4] && add_class_kind_r[4] &&
        !reservation_r[3]),(add_class_valid_r[4] && add_class_kind_r[4] &&
        !reservation_r[3]),(add_class_valid_r[4] && add_class_kind_r[4] &&
        !reservation_r[3]),(add_class_valid_r[4] && add_class_kind_r[4] &&
        !reservation_r[3]),(add_class_valid_r[3] && add_class_kind_r[3] &&
        !reservation_r[3]),(add_class_valid_r[3] && add_class_kind_r[3] &&
        !reservation_r[3]),(add_class_valid_r[3] && add_class_kind_r[3] &&
        !reservation_r[3]),(add_class_valid_r[3] && add_class_kind_r[3] &&
        !reservation_r[3]),(add_class_valid_r[3] && add_class_kind_r[3] &&
        !reservation_r[3]),(add_class_valid_r[3] && add_class_kind_r[3] &&
        !reservation_r[3]),(add_class_valid_r[2] && add_class_kind_r[2] &&
        !reservation_r[3]),(add_class_valid_r[2] && add_class_kind_r[2] &&
        !reservation_r[3]),(add_class_valid_r[2] && add_class_kind_r[2] &&
        !reservation_r[3]),(add_class_valid_r[2] && add_class_kind_r[2] &&
        !reservation_r[3]),(add_class_valid_r[2] && add_class_kind_r[2] &&
        !reservation_r[3]),(add_class_valid_r[2] && add_class_kind_r[2] &&
        !reservation_r[3]),(add_class_valid_r[1] && add_class_kind_r[1] &&
        !reservation_r[3]),(add_class_valid_r[1] && add_class_kind_r[1] &&
        !reservation_r[3]),(add_class_valid_r[1] && add_class_kind_r[1] &&
        !reservation_r[3]),(add_class_valid_r[1] && add_class_kind_r[1] &&
        !reservation_r[3]),(add_class_valid_r[1] && add_class_kind_r[1] &&
        !reservation_r[3]),(add_class_valid_r[1] && add_class_kind_r[1] &&
        !reservation_r[3]),(add_class_valid_r[0] && add_class_kind_r[0] &&
        !reservation_r[3]),(add_class_valid_r[0] && add_class_kind_r[0] &&
        !reservation_r[3]),(add_class_valid_r[0] && add_class_kind_r[0] &&
        !reservation_r[3]),(add_class_valid_r[0] && add_class_kind_r[0] &&
        !reservation_r[3]),(add_class_valid_r[0] && add_class_kind_r[0] &&
        !reservation_r[3]),(add_class_valid_r[0] && add_class_kind_r[0] && !reservation_r[3])};
    always @(posedge clk_i) begin
        if (advance_copy_r[565]) add_select_r[15:0] <= add_select_next_w[15:0];
        if (advance_copy_r[566]) add_select_r[31:16] <= add_select_next_w[31:16];
        if (advance_copy_r[567]) add_select_r[46:32] <= add_select_next_w[46:32];
    end
    (* keep = "true", syn_preserve = 1 *) reg [6:0] mul_region_r;
    wire [6:0] mul_region_next_w;
    assign mul_region_next_w = {7{product_valid_r[11] && product_mul_r[11]}};
    always @(posedge clk_i) begin
        if (advance_copy_r[568]) mul_region_r[6:0] <= mul_region_next_w[6:0];
    end
    (* keep = "true", syn_preserve = 1 *) reg [27:0] mul_data_select_r;
    wire [27:0] mul_data_select_next_w;
    assign mul_data_select_next_w = {{4{mul_region_r[6]}},{4{mul_region_r[5]}},
        {4{mul_region_r[4]}},{4{mul_region_r[3]}},{4{mul_region_r[2]}},
        {4{mul_region_r[1]}},{4{mul_region_r[0]}}};
    always @(posedge clk_i) begin
        if (advance_copy_r[569]) mul_data_select_r[15:0] <= mul_data_select_next_w[15:0];
        if (advance_copy_r[570]) mul_data_select_r[27:16] <= mul_data_select_next_w[27:16];
    end
    wire [167:0] sum_a_w;
    wire [167:0] sum_a_w_left_w;
    assign sum_a_w_left_w = a2_big_r;
    wire [167:0] sum_a_w_right_w;
    assign sum_a_w_right_w = fma_product_w;
    assign sum_a_w[15:0] = add_select_r[0] ? sum_a_w_left_w[15:0] : sum_a_w_right_w[15:0];
    assign sum_a_w[31:16] = add_select_r[1] ? sum_a_w_left_w[31:16] : sum_a_w_right_w[31:16];
    assign sum_a_w[47:32] = add_select_r[2] ? sum_a_w_left_w[47:32] : sum_a_w_right_w[47:32];
    assign sum_a_w[63:48] = add_select_r[3] ? sum_a_w_left_w[63:48] : sum_a_w_right_w[63:48];
    assign sum_a_w[79:64] = add_select_r[4] ? sum_a_w_left_w[79:64] : sum_a_w_right_w[79:64];
    assign sum_a_w[95:80] = add_select_r[5] ? sum_a_w_left_w[95:80] : sum_a_w_right_w[95:80];
    assign sum_a_w[111:96] = add_select_r[6] ? sum_a_w_left_w[111:96] : sum_a_w_right_w[111:96];
    assign sum_a_w[127:112] = add_select_r[7] ? sum_a_w_left_w[127:112] : sum_a_w_right_w[127:112];
    assign sum_a_w[143:128] = add_select_r[8] ? sum_a_w_left_w[143:128] : sum_a_w_right_w[143:128];
    assign sum_a_w[159:144] = add_select_r[9] ? sum_a_w_left_w[159:144] : sum_a_w_right_w[159:144];
    assign sum_a_w[167:160] = add_select_r[10] ? sum_a_w_left_w[167:160] : sum_a_w_right_w[167:160];
    wire [167:0] sum_b_w;
    wire [167:0] sum_b_w_left_w;
    assign sum_b_w_left_w = a2_small_r;
    wire [167:0] sum_b_w_right_w;
    assign sum_b_w_right_w = p13_c_r;
    assign sum_b_w[15:0] = add_select_r[11] ? sum_b_w_left_w[15:0] : sum_b_w_right_w[15:0];
    assign sum_b_w[31:16] = add_select_r[12] ? sum_b_w_left_w[31:16] : sum_b_w_right_w[31:16];
    assign sum_b_w[47:32] = add_select_r[13] ? sum_b_w_left_w[47:32] : sum_b_w_right_w[47:32];
    assign sum_b_w[63:48] = add_select_r[14] ? sum_b_w_left_w[63:48] : sum_b_w_right_w[63:48];
    assign sum_b_w[79:64] = add_select_r[15] ? sum_b_w_left_w[79:64] : sum_b_w_right_w[79:64];
    assign sum_b_w[95:80] = add_select_r[16] ? sum_b_w_left_w[95:80] : sum_b_w_right_w[95:80];
    assign sum_b_w[111:96] = add_select_r[17] ? sum_b_w_left_w[111:96] : sum_b_w_right_w[111:96];
    assign sum_b_w[127:112] = add_select_r[18] ? sum_b_w_left_w[127:112] : sum_b_w_right_w[127:112];
    assign sum_b_w[143:128] = add_select_r[19] ? sum_b_w_left_w[143:128] : sum_b_w_right_w[143:128];
    assign sum_b_w[159:144] = add_select_r[20] ? sum_b_w_left_w[159:144] : sum_b_w_right_w[159:144];
    assign sum_b_w[167:160] = add_select_r[21] ? sum_b_w_left_w[167:160] : sum_b_w_right_w[167:160];
    wire sum_ps_w;
    wire sum_ps_w_left_w;
    assign sum_ps_w_left_w = a2_ps_r;
    wire sum_ps_w_right_w;
    assign sum_ps_w_right_w = p13_ps_r;
    assign sum_ps_w = add_select_r[22] ? sum_ps_w_left_w : sum_ps_w_right_w;
    wire sum_cs_w;
    wire sum_cs_w_left_w;
    assign sum_cs_w_left_w = a2_cs_r;
    wire sum_cs_w_right_w;
    assign sum_cs_w_right_w = p13_cs_r;
    assign sum_cs_w = add_select_r[23] ? sum_cs_w_left_w : sum_cs_w_right_w;
    wire [2:0] sum_rm_w;
    wire [2:0] sum_rm_w_left_w;
    assign sum_rm_w_left_w = a2_rm_r;
    wire [2:0] sum_rm_w_right_w;
    assign sum_rm_w_right_w = p13_rm_r;
    assign sum_rm_w[2:0] = add_select_r[24] ? sum_rm_w_left_w[2:0] : sum_rm_w_right_w[2:0];
    wire sum_special_w;
    wire sum_special_w_left_w;
    assign sum_special_w_left_w = a2_special_r;
    wire sum_special_w_right_w;
    assign sum_special_w_right_w = p13_special_r;
    assign sum_special_w = add_select_r[25] ? sum_special_w_left_w : sum_special_w_right_w;
    wire [63:0] sum_result_w;
    wire [63:0] sum_result_w_left_w;
    assign sum_result_w_left_w = a2_result_r;
    wire [63:0] sum_result_w_right_w;
    assign sum_result_w_right_w = p13_result_r;
    assign sum_result_w[15:0] = add_select_r[26] ? sum_result_w_left_w[15:0] :
        sum_result_w_right_w[15:0];
    assign sum_result_w[31:16] = add_select_r[27] ? sum_result_w_left_w[31:16] :
        sum_result_w_right_w[31:16];
    assign sum_result_w[47:32] = add_select_r[28] ? sum_result_w_left_w[47:32] :
        sum_result_w_right_w[47:32];
    assign sum_result_w[63:48] = add_select_r[29] ? sum_result_w_left_w[63:48] :
        sum_result_w_right_w[63:48];
    wire [4:0] sum_flags_w;
    wire [4:0] sum_flags_w_left_w;
    assign sum_flags_w_left_w = a2_flags_r;
    wire [4:0] sum_flags_w_right_w;
    assign sum_flags_w_right_w = p13_flags_r;
    assign sum_flags_w[4:0] = add_select_r[30] ? sum_flags_w_left_w[4:0] : sum_flags_w_right_w[4:0];
    wire signed [12:0] sum_base_w;
    wire [12:0] sum_base_w_left_w;
    assign sum_base_w_left_w = a2_base_r;
    wire [12:0] sum_base_w_right_w;
    assign sum_base_w_right_w = p13_base_r;
    assign sum_base_w[12:0] = add_select_r[31] ? sum_base_w_left_w[12:0] : sum_base_w_right_w[12:0];
    wire sum_sub_w;
    assign sum_sub_w = sum_ps_w ^ sum_cs_w;
    wire [84:0] sum_forward_low_w;
    assign sum_forward_low_w = {1'b0,sum_a_w[83:0]}
        + {1'b0,(sum_b_w[83:0] ^ {84{sum_sub_w}})} + {84'b0,sum_sub_w};
    wire [84:0] sum_reverse_low_w;
    assign sum_reverse_low_w = {1'b0,sum_b_w[83:0]} + {1'b0,~sum_a_w[83:0]} + 85'd1;
    reg [83:0] s1_forward_low_r;
    wire [83:0] s1_forward_low_next_w;
    assign s1_forward_low_next_w = sum_forward_low_w[83:0];
    always @(posedge clk_i) begin
        if (advance_copy_r[571]) s1_forward_low_r[15:0] <= s1_forward_low_next_w[15:0];
        if (advance_copy_r[572]) s1_forward_low_r[31:16] <= s1_forward_low_next_w[31:16];
        if (advance_copy_r[573]) s1_forward_low_r[47:32] <= s1_forward_low_next_w[47:32];
        if (advance_copy_r[574]) s1_forward_low_r[63:48] <= s1_forward_low_next_w[63:48];
        if (advance_copy_r[575]) s1_forward_low_r[79:64] <= s1_forward_low_next_w[79:64];
        if (advance_copy_r[576]) s1_forward_low_r[83:80] <= s1_forward_low_next_w[83:80];
    end
    reg [83:0] s1_reverse_low_r;
    wire [83:0] s1_reverse_low_next_w;
    assign s1_reverse_low_next_w = sum_reverse_low_w[83:0];
    always @(posedge clk_i) begin
        if (advance_copy_r[577]) s1_reverse_low_r[15:0] <= s1_reverse_low_next_w[15:0];
        if (advance_copy_r[578]) s1_reverse_low_r[31:16] <= s1_reverse_low_next_w[31:16];
        if (advance_copy_r[579]) s1_reverse_low_r[47:32] <= s1_reverse_low_next_w[47:32];
        if (advance_copy_r[580]) s1_reverse_low_r[63:48] <= s1_reverse_low_next_w[63:48];
        if (advance_copy_r[581]) s1_reverse_low_r[79:64] <= s1_reverse_low_next_w[79:64];
        if (advance_copy_r[582]) s1_reverse_low_r[83:80] <= s1_reverse_low_next_w[83:80];
    end
    reg s1_forward_carry_r;
    wire s1_forward_carry_next_w;
    assign s1_forward_carry_next_w = sum_forward_low_w[84];
    always @(posedge clk_i) begin
        if (advance_copy_r[583]) s1_forward_carry_r <= s1_forward_carry_next_w;
    end
    reg s1_reverse_carry_r;
    wire s1_reverse_carry_next_w;
    assign s1_reverse_carry_next_w = sum_reverse_low_w[84];
    always @(posedge clk_i) begin
        if (advance_copy_r[584]) s1_reverse_carry_r <= s1_reverse_carry_next_w;
    end
    reg [83:0] s1_a_high_r;
    wire [83:0] s1_a_high_next_w;
    assign s1_a_high_next_w = sum_a_w[167:84];
    always @(posedge clk_i) begin
        if (advance_copy_r[585]) s1_a_high_r[15:0] <= s1_a_high_next_w[15:0];
        if (advance_copy_r[586]) s1_a_high_r[31:16] <= s1_a_high_next_w[31:16];
        if (advance_copy_r[587]) s1_a_high_r[47:32] <= s1_a_high_next_w[47:32];
        if (advance_copy_r[588]) s1_a_high_r[63:48] <= s1_a_high_next_w[63:48];
        if (advance_copy_r[589]) s1_a_high_r[79:64] <= s1_a_high_next_w[79:64];
        if (advance_copy_r[590]) s1_a_high_r[83:80] <= s1_a_high_next_w[83:80];
    end
    reg [83:0] s1_b_high_r;
    wire [83:0] s1_b_high_next_w;
    assign s1_b_high_next_w = sum_b_w[167:84];
    always @(posedge clk_i) begin
        if (advance_copy_r[591]) s1_b_high_r[15:0] <= s1_b_high_next_w[15:0];
        if (advance_copy_r[592]) s1_b_high_r[31:16] <= s1_b_high_next_w[31:16];
        if (advance_copy_r[593]) s1_b_high_r[47:32] <= s1_b_high_next_w[47:32];
        if (advance_copy_r[594]) s1_b_high_r[63:48] <= s1_b_high_next_w[63:48];
        if (advance_copy_r[595]) s1_b_high_r[79:64] <= s1_b_high_next_w[79:64];
        if (advance_copy_r[596]) s1_b_high_r[83:80] <= s1_b_high_next_w[83:80];
    end
    reg s1_sub_r;
    wire s1_sub_next_w;
    assign s1_sub_next_w = sum_sub_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[597]) s1_sub_r <= s1_sub_next_w;
    end
    reg s1_ps_r;
    wire s1_ps_next_w;
    assign s1_ps_next_w = sum_ps_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[598]) s1_ps_r <= s1_ps_next_w;
    end
    reg s1_cs_r;
    wire s1_cs_next_w;
    assign s1_cs_next_w = sum_cs_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[599]) s1_cs_r <= s1_cs_next_w;
    end
    reg [2:0] s1_rm_r;
    wire [2:0] s1_rm_next_w;
    assign s1_rm_next_w = sum_rm_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[600]) s1_rm_r[2:0] <= s1_rm_next_w[2:0];
    end
    reg s1_special_r;
    wire s1_special_next_w;
    assign s1_special_next_w = sum_special_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[601]) s1_special_r <= s1_special_next_w;
    end
    reg [63:0] s1_result_r;
    wire [63:0] s1_result_next_w;
    assign s1_result_next_w = sum_result_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[602]) s1_result_r[15:0] <= s1_result_next_w[15:0];
        if (advance_copy_r[603]) s1_result_r[31:16] <= s1_result_next_w[31:16];
        if (advance_copy_r[604]) s1_result_r[47:32] <= s1_result_next_w[47:32];
        if (advance_copy_r[605]) s1_result_r[63:48] <= s1_result_next_w[63:48];
    end
    reg [4:0] s1_flags_r;
    wire [4:0] s1_flags_next_w;
    assign s1_flags_next_w = sum_flags_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[606]) s1_flags_r[4:0] <= s1_flags_next_w[4:0];
    end
    reg signed [12:0] s1_base_r;
    wire [12:0] s1_base_next_w;
    assign s1_base_next_w = sum_base_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[607]) s1_base_r[12:0] <= s1_base_next_w[12:0];
    end
    wire [167:0] sum_marker_w;
    wire [167:0] sum_marker_w_left_w;
    assign sum_marker_w_left_w = a2_marker_r;
    wire [167:0] sum_marker_w_right_w;
    assign sum_marker_w_right_w = p13_marker_r;
    assign sum_marker_w[15:0] = add_select_r[32] ? sum_marker_w_left_w[15:0] :
        sum_marker_w_right_w[15:0];
    assign sum_marker_w[31:16] = add_select_r[33] ? sum_marker_w_left_w[31:16] :
        sum_marker_w_right_w[31:16];
    assign sum_marker_w[47:32] = add_select_r[34] ? sum_marker_w_left_w[47:32] :
        sum_marker_w_right_w[47:32];
    assign sum_marker_w[63:48] = add_select_r[35] ? sum_marker_w_left_w[63:48] :
        sum_marker_w_right_w[63:48];
    assign sum_marker_w[79:64] = add_select_r[36] ? sum_marker_w_left_w[79:64] :
        sum_marker_w_right_w[79:64];
    assign sum_marker_w[95:80] = add_select_r[37] ? sum_marker_w_left_w[95:80] :
        sum_marker_w_right_w[95:80];
    assign sum_marker_w[111:96] = add_select_r[38] ? sum_marker_w_left_w[111:96] :
        sum_marker_w_right_w[111:96];
    assign sum_marker_w[127:112] = add_select_r[39] ? sum_marker_w_left_w[127:112] :
        sum_marker_w_right_w[127:112];
    assign sum_marker_w[143:128] = add_select_r[40] ? sum_marker_w_left_w[143:128] :
        sum_marker_w_right_w[143:128];
    assign sum_marker_w[159:144] = add_select_r[41] ? sum_marker_w_left_w[159:144] :
        sum_marker_w_right_w[159:144];
    assign sum_marker_w[167:160] = add_select_r[42] ? sum_marker_w_left_w[167:160] :
        sum_marker_w_right_w[167:160];
    wire [7:0] sum_limit_w;
    wire [7:0] sum_limit_w_left_w;
    assign sum_limit_w_left_w = a2_limit_r;
    wire [7:0] sum_limit_w_right_w;
    assign sum_limit_w_right_w = p13_limit_r;
    assign sum_limit_w[7:0] = add_select_r[43] ? sum_limit_w_left_w[7:0] : sum_limit_w_right_w[7:0];
    reg [7:0] s1_limit_r;
    wire [7:0] s1_limit_next_w;
    assign s1_limit_next_w = sum_limit_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[608]) s1_limit_r[7:0] <= s1_limit_next_w[7:0];
    end
    reg [7:0] s2_limit_r;
    wire [7:0] s2_limit_next_w;
    assign s2_limit_next_w = s1_limit_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[609]) s2_limit_r[7:0] <= s2_limit_next_w[7:0];
    end
    wire signed [12:0] sum_anchor_w;
    wire [12:0] sum_anchor_w_left_w;
    assign sum_anchor_w_left_w = a2_anchor_r;
    wire [12:0] sum_anchor_w_right_w;
    assign sum_anchor_w_right_w = p13_anchor_r;
    assign sum_anchor_w[12:0] = add_select_r[44] ? sum_anchor_w_left_w[12:0] :
        sum_anchor_w_right_w[12:0];
    reg signed [12:0] s1_anchor_r;
    wire [12:0] s1_anchor_next_w;
    assign s1_anchor_next_w = sum_anchor_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[610]) s1_anchor_r[12:0] <= s1_anchor_next_w[12:0];
    end
    reg signed [12:0] s2_anchor_r;
    wire [12:0] s2_anchor_next_w;
    assign s2_anchor_next_w = s1_anchor_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[611]) s2_anchor_r[12:0] <= s2_anchor_next_w[12:0];
    end
    wire sum_norm_right_w;
    wire sum_norm_right_w_left_w;
    assign sum_norm_right_w_left_w = 1'b0;
    wire sum_norm_right_w_right_w;
    assign sum_norm_right_w_right_w = p13_norm_right_r;
    assign sum_norm_right_w = add_select_r[45] ? sum_norm_right_w_left_w : sum_norm_right_w_right_w;
    reg s1_norm_right_r;
    wire s1_norm_right_next_w;
    assign s1_norm_right_next_w = sum_norm_right_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[612]) s1_norm_right_r <= s1_norm_right_next_w;
    end
    reg s2_norm_right_r;
    wire s2_norm_right_next_w;
    assign s2_norm_right_next_w = s1_norm_right_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[613]) s2_norm_right_r <= s2_norm_right_next_w;
    end
    wire [7:0] sum_tiny_w;
    wire [7:0] sum_tiny_w_left_w;
    assign sum_tiny_w_left_w = 8'b0;
    wire [7:0] sum_tiny_w_right_w;
    assign sum_tiny_w_right_w = p13_tiny_r;
    assign sum_tiny_w[7:0] = add_select_r[46] ? sum_tiny_w_left_w[7:0] : sum_tiny_w_right_w[7:0];
    reg [7:0] s1_tiny_r;
    wire [7:0] s1_tiny_next_w;
    assign s1_tiny_next_w = sum_tiny_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[614]) s1_tiny_r[7:0] <= s1_tiny_next_w[7:0];
    end
    reg [7:0] s2_tiny_r;
    wire [7:0] s2_tiny_next_w;
    assign s2_tiny_next_w = s1_tiny_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[615]) s2_tiny_r[7:0] <= s2_tiny_next_w[7:0];
    end
    wire [167:0] forward_predict_w;
    assign forward_predict_w = sum_marker_w | (sum_sub_w ? (sum_a_w ^ sum_b_w)
        & ~{(~sum_a_w[166:0] & sum_b_w[166:0]),1'b0} : sum_a_w | sum_b_w);
    wire [167:0] reverse_predict_w;
    assign reverse_predict_w = sum_marker_w | ((sum_b_w ^ sum_a_w) & ~{(~sum_b_w[166:0] &
        sum_a_w[166:0]),1'b0});
    wire [191:0] forward_padded_w;
    assign forward_padded_w = {forward_predict_w,24'b0};
    wire forward_hit0_w;
    wire [4:0] forward_count0_w;
    edrv32_cpu2_fpu_lza32 u_forward0 (
        .data_i(forward_padded_w[191:160]),
        .hit_o(forward_hit0_w),
        .count_o(forward_count0_w)
    );
    reg s1_forward_hit0_r;
    wire s1_forward_hit0_next_w;
    assign s1_forward_hit0_next_w = forward_hit0_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[616]) s1_forward_hit0_r <= s1_forward_hit0_next_w;
    end
    reg [4:0] s1_forward_count0_r;
    wire [4:0] s1_forward_count0_next_w;
    assign s1_forward_count0_next_w = forward_count0_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[617]) s1_forward_count0_r[4:0] <= s1_forward_count0_next_w[4:0];
    end
    wire forward_hit1_w;
    wire [4:0] forward_count1_w;
    edrv32_cpu2_fpu_lza32 u_forward1 (
        .data_i(forward_padded_w[159:128]),
        .hit_o(forward_hit1_w),
        .count_o(forward_count1_w)
    );
    reg s1_forward_hit1_r;
    wire s1_forward_hit1_next_w;
    assign s1_forward_hit1_next_w = forward_hit1_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[618]) s1_forward_hit1_r <= s1_forward_hit1_next_w;
    end
    reg [4:0] s1_forward_count1_r;
    wire [4:0] s1_forward_count1_next_w;
    assign s1_forward_count1_next_w = forward_count1_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[619]) s1_forward_count1_r[4:0] <= s1_forward_count1_next_w[4:0];
    end
    wire forward_hit2_w;
    wire [4:0] forward_count2_w;
    edrv32_cpu2_fpu_lza32 u_forward2 (
        .data_i(forward_padded_w[127:96]),
        .hit_o(forward_hit2_w),
        .count_o(forward_count2_w)
    );
    reg s1_forward_hit2_r;
    wire s1_forward_hit2_next_w;
    assign s1_forward_hit2_next_w = forward_hit2_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[620]) s1_forward_hit2_r <= s1_forward_hit2_next_w;
    end
    reg [4:0] s1_forward_count2_r;
    wire [4:0] s1_forward_count2_next_w;
    assign s1_forward_count2_next_w = forward_count2_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[621]) s1_forward_count2_r[4:0] <= s1_forward_count2_next_w[4:0];
    end
    wire forward_hit3_w;
    wire [4:0] forward_count3_w;
    edrv32_cpu2_fpu_lza32 u_forward3 (
        .data_i(forward_padded_w[95:64]),
        .hit_o(forward_hit3_w),
        .count_o(forward_count3_w)
    );
    reg s1_forward_hit3_r;
    wire s1_forward_hit3_next_w;
    assign s1_forward_hit3_next_w = forward_hit3_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[622]) s1_forward_hit3_r <= s1_forward_hit3_next_w;
    end
    reg [4:0] s1_forward_count3_r;
    wire [4:0] s1_forward_count3_next_w;
    assign s1_forward_count3_next_w = forward_count3_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[623]) s1_forward_count3_r[4:0] <= s1_forward_count3_next_w[4:0];
    end
    wire forward_hit4_w;
    wire [4:0] forward_count4_w;
    edrv32_cpu2_fpu_lza32 u_forward4 (
        .data_i(forward_padded_w[63:32]),
        .hit_o(forward_hit4_w),
        .count_o(forward_count4_w)
    );
    reg s1_forward_hit4_r;
    wire s1_forward_hit4_next_w;
    assign s1_forward_hit4_next_w = forward_hit4_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[624]) s1_forward_hit4_r <= s1_forward_hit4_next_w;
    end
    reg [4:0] s1_forward_count4_r;
    wire [4:0] s1_forward_count4_next_w;
    assign s1_forward_count4_next_w = forward_count4_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[625]) s1_forward_count4_r[4:0] <= s1_forward_count4_next_w[4:0];
    end
    wire forward_hit5_w;
    wire [4:0] forward_count5_w;
    edrv32_cpu2_fpu_lza32 u_forward5 (
        .data_i(forward_padded_w[31:0]),
        .hit_o(forward_hit5_w),
        .count_o(forward_count5_w)
    );
    reg s1_forward_hit5_r;
    wire s1_forward_hit5_next_w;
    assign s1_forward_hit5_next_w = forward_hit5_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[626]) s1_forward_hit5_r <= s1_forward_hit5_next_w;
    end
    reg [4:0] s1_forward_count5_r;
    wire [4:0] s1_forward_count5_next_w;
    assign s1_forward_count5_next_w = forward_count5_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[627]) s1_forward_count5_r[4:0] <= s1_forward_count5_next_w[4:0];
    end
    reg [7:0] s2_forward_count_r;
    wire [7:0] s2_forward_count_next_w;
    assign s2_forward_count_next_w = s1_forward_hit0_r ? (8'd0 + {3'b0,s1_forward_count0_r}) :
        (s1_forward_hit1_r ? (8'd32 + {3'b0,s1_forward_count1_r}) : (s1_forward_hit2_r ? (8'd64 +
        {3'b0,s1_forward_count2_r}) : (s1_forward_hit3_r ? (8'd96 + {3'b0,s1_forward_count3_r}) :
        (s1_forward_hit4_r ? (8'd128 + {3'b0,s1_forward_count4_r}) : (s1_forward_hit5_r ? (8'd160 +
        {3'b0,s1_forward_count5_r}) : (8'd168))))));
    always @(posedge clk_i) begin
        if (advance_copy_r[628]) s2_forward_count_r[7:0] <= s2_forward_count_next_w[7:0];
    end
    wire [191:0] reverse_padded_w;
    assign reverse_padded_w = {reverse_predict_w,24'b0};
    wire reverse_hit0_w;
    wire [4:0] reverse_count0_w;
    edrv32_cpu2_fpu_lza32 u_reverse0 (
        .data_i(reverse_padded_w[191:160]),
        .hit_o(reverse_hit0_w),
        .count_o(reverse_count0_w)
    );
    reg s1_reverse_hit0_r;
    wire s1_reverse_hit0_next_w;
    assign s1_reverse_hit0_next_w = reverse_hit0_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[629]) s1_reverse_hit0_r <= s1_reverse_hit0_next_w;
    end
    reg [4:0] s1_reverse_count0_r;
    wire [4:0] s1_reverse_count0_next_w;
    assign s1_reverse_count0_next_w = reverse_count0_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[630]) s1_reverse_count0_r[4:0] <= s1_reverse_count0_next_w[4:0];
    end
    wire reverse_hit1_w;
    wire [4:0] reverse_count1_w;
    edrv32_cpu2_fpu_lza32 u_reverse1 (
        .data_i(reverse_padded_w[159:128]),
        .hit_o(reverse_hit1_w),
        .count_o(reverse_count1_w)
    );
    reg s1_reverse_hit1_r;
    wire s1_reverse_hit1_next_w;
    assign s1_reverse_hit1_next_w = reverse_hit1_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[631]) s1_reverse_hit1_r <= s1_reverse_hit1_next_w;
    end
    reg [4:0] s1_reverse_count1_r;
    wire [4:0] s1_reverse_count1_next_w;
    assign s1_reverse_count1_next_w = reverse_count1_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[632]) s1_reverse_count1_r[4:0] <= s1_reverse_count1_next_w[4:0];
    end
    wire reverse_hit2_w;
    wire [4:0] reverse_count2_w;
    edrv32_cpu2_fpu_lza32 u_reverse2 (
        .data_i(reverse_padded_w[127:96]),
        .hit_o(reverse_hit2_w),
        .count_o(reverse_count2_w)
    );
    reg s1_reverse_hit2_r;
    wire s1_reverse_hit2_next_w;
    assign s1_reverse_hit2_next_w = reverse_hit2_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[633]) s1_reverse_hit2_r <= s1_reverse_hit2_next_w;
    end
    reg [4:0] s1_reverse_count2_r;
    wire [4:0] s1_reverse_count2_next_w;
    assign s1_reverse_count2_next_w = reverse_count2_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[634]) s1_reverse_count2_r[4:0] <= s1_reverse_count2_next_w[4:0];
    end
    wire reverse_hit3_w;
    wire [4:0] reverse_count3_w;
    edrv32_cpu2_fpu_lza32 u_reverse3 (
        .data_i(reverse_padded_w[95:64]),
        .hit_o(reverse_hit3_w),
        .count_o(reverse_count3_w)
    );
    reg s1_reverse_hit3_r;
    wire s1_reverse_hit3_next_w;
    assign s1_reverse_hit3_next_w = reverse_hit3_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[635]) s1_reverse_hit3_r <= s1_reverse_hit3_next_w;
    end
    reg [4:0] s1_reverse_count3_r;
    wire [4:0] s1_reverse_count3_next_w;
    assign s1_reverse_count3_next_w = reverse_count3_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[636]) s1_reverse_count3_r[4:0] <= s1_reverse_count3_next_w[4:0];
    end
    wire reverse_hit4_w;
    wire [4:0] reverse_count4_w;
    edrv32_cpu2_fpu_lza32 u_reverse4 (
        .data_i(reverse_padded_w[63:32]),
        .hit_o(reverse_hit4_w),
        .count_o(reverse_count4_w)
    );
    reg s1_reverse_hit4_r;
    wire s1_reverse_hit4_next_w;
    assign s1_reverse_hit4_next_w = reverse_hit4_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[637]) s1_reverse_hit4_r <= s1_reverse_hit4_next_w;
    end
    reg [4:0] s1_reverse_count4_r;
    wire [4:0] s1_reverse_count4_next_w;
    assign s1_reverse_count4_next_w = reverse_count4_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[638]) s1_reverse_count4_r[4:0] <= s1_reverse_count4_next_w[4:0];
    end
    wire reverse_hit5_w;
    wire [4:0] reverse_count5_w;
    edrv32_cpu2_fpu_lza32 u_reverse5 (
        .data_i(reverse_padded_w[31:0]),
        .hit_o(reverse_hit5_w),
        .count_o(reverse_count5_w)
    );
    reg s1_reverse_hit5_r;
    wire s1_reverse_hit5_next_w;
    assign s1_reverse_hit5_next_w = reverse_hit5_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[639]) s1_reverse_hit5_r <= s1_reverse_hit5_next_w;
    end
    reg [4:0] s1_reverse_count5_r;
    wire [4:0] s1_reverse_count5_next_w;
    assign s1_reverse_count5_next_w = reverse_count5_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[640]) s1_reverse_count5_r[4:0] <= s1_reverse_count5_next_w[4:0];
    end
    reg [7:0] s2_reverse_count_r;
    wire [7:0] s2_reverse_count_next_w;
    assign s2_reverse_count_next_w = s1_reverse_hit0_r ? (8'd0 + {3'b0,s1_reverse_count0_r}) :
        (s1_reverse_hit1_r ? (8'd32 + {3'b0,s1_reverse_count1_r}) : (s1_reverse_hit2_r ? (8'd64 +
        {3'b0,s1_reverse_count2_r}) : (s1_reverse_hit3_r ? (8'd96 + {3'b0,s1_reverse_count3_r}) :
        (s1_reverse_hit4_r ? (8'd128 + {3'b0,s1_reverse_count4_r}) : (s1_reverse_hit5_r ? (8'd160 +
        {3'b0,s1_reverse_count5_r}) : (8'd168))))));
    always @(posedge clk_i) begin
        if (advance_copy_r[641]) s2_reverse_count_r[7:0] <= s2_reverse_count_next_w[7:0];
    end
    wire [84:0] forward_high_w;
    assign forward_high_w = {1'b0,s1_a_high_r} + {1'b0,(s1_b_high_r ^ {84{s1_sub_r}})}
        + {84'b0,s1_forward_carry_r};
    wire [84:0] reverse_high_w;
    assign reverse_high_w = {1'b0,s1_b_high_r} + {1'b0,~s1_a_high_r} + {84'b0,s1_reverse_carry_r};
    reg [167:0] s2_forward_r;
    wire [167:0] s2_forward_next_w;
    assign s2_forward_next_w = {forward_high_w[83:0],s1_forward_low_r};
    always @(posedge clk_i) begin
        if (advance_copy_r[642]) s2_forward_r[15:0] <= s2_forward_next_w[15:0];
        if (advance_copy_r[643]) s2_forward_r[31:16] <= s2_forward_next_w[31:16];
        if (advance_copy_r[644]) s2_forward_r[47:32] <= s2_forward_next_w[47:32];
        if (advance_copy_r[645]) s2_forward_r[63:48] <= s2_forward_next_w[63:48];
        if (advance_copy_r[646]) s2_forward_r[79:64] <= s2_forward_next_w[79:64];
        if (advance_copy_r[647]) s2_forward_r[95:80] <= s2_forward_next_w[95:80];
        if (advance_copy_r[648]) s2_forward_r[111:96] <= s2_forward_next_w[111:96];
        if (advance_copy_r[649]) s2_forward_r[127:112] <= s2_forward_next_w[127:112];
        if (advance_copy_r[650]) s2_forward_r[143:128] <= s2_forward_next_w[143:128];
        if (advance_copy_r[651]) s2_forward_r[159:144] <= s2_forward_next_w[159:144];
        if (advance_copy_r[652]) s2_forward_r[167:160] <= s2_forward_next_w[167:160];
    end
    reg [167:0] s2_reverse_r;
    wire [167:0] s2_reverse_next_w;
    assign s2_reverse_next_w = {reverse_high_w[83:0],s1_reverse_low_r};
    always @(posedge clk_i) begin
        if (advance_copy_r[653]) s2_reverse_r[15:0] <= s2_reverse_next_w[15:0];
        if (advance_copy_r[654]) s2_reverse_r[31:16] <= s2_reverse_next_w[31:16];
        if (advance_copy_r[655]) s2_reverse_r[47:32] <= s2_reverse_next_w[47:32];
        if (advance_copy_r[656]) s2_reverse_r[63:48] <= s2_reverse_next_w[63:48];
        if (advance_copy_r[657]) s2_reverse_r[79:64] <= s2_reverse_next_w[79:64];
        if (advance_copy_r[658]) s2_reverse_r[95:80] <= s2_reverse_next_w[95:80];
        if (advance_copy_r[659]) s2_reverse_r[111:96] <= s2_reverse_next_w[111:96];
        if (advance_copy_r[660]) s2_reverse_r[127:112] <= s2_reverse_next_w[127:112];
        if (advance_copy_r[661]) s2_reverse_r[143:128] <= s2_reverse_next_w[143:128];
        if (advance_copy_r[662]) s2_reverse_r[159:144] <= s2_reverse_next_w[159:144];
        if (advance_copy_r[663]) s2_reverse_r[167:160] <= s2_reverse_next_w[167:160];
    end
    (* keep = "true", syn_preserve = 1 *) reg [12:0] s2_reverse_select_r;
    wire [12:0] s2_reverse_select_next_w;
    assign s2_reverse_select_next_w = {13{s1_sub_r && !forward_high_w[84]}};
    always @(posedge clk_i) begin
        if (advance_copy_r[664]) s2_reverse_select_r[12:0] <= s2_reverse_select_next_w[12:0];
    end
    reg s2_ps_r;
    wire s2_ps_next_w;
    assign s2_ps_next_w = s1_ps_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[665]) s2_ps_r <= s2_ps_next_w;
    end
    reg s2_cs_r;
    wire s2_cs_next_w;
    assign s2_cs_next_w = s1_cs_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[666]) s2_cs_r <= s2_cs_next_w;
    end
    reg [2:0] s2_rm_r;
    wire [2:0] s2_rm_next_w;
    assign s2_rm_next_w = s1_rm_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[667]) s2_rm_r[2:0] <= s2_rm_next_w[2:0];
    end
    reg s2_special_r;
    wire s2_special_next_w;
    assign s2_special_next_w = s1_special_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[668]) s2_special_r <= s2_special_next_w;
    end
    reg [63:0] s2_result_r;
    wire [63:0] s2_result_next_w;
    assign s2_result_next_w = s1_result_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[669]) s2_result_r[15:0] <= s2_result_next_w[15:0];
        if (advance_copy_r[670]) s2_result_r[31:16] <= s2_result_next_w[31:16];
        if (advance_copy_r[671]) s2_result_r[47:32] <= s2_result_next_w[47:32];
        if (advance_copy_r[672]) s2_result_r[63:48] <= s2_result_next_w[63:48];
    end
    reg [4:0] s2_flags_r;
    wire [4:0] s2_flags_next_w;
    assign s2_flags_next_w = s1_flags_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[673]) s2_flags_r[4:0] <= s2_flags_next_w[4:0];
    end
    reg signed [12:0] s2_base_r;
    wire [12:0] s2_base_next_w;
    assign s2_base_next_w = s1_base_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[674]) s2_base_r[12:0] <= s2_base_next_w[12:0];
    end
    reg s1_valid_r;
    reg [3:0] s1_tag_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) s1_valid_r <= 1'b0;
        else if (advance_copy_r[739]) s1_valid_r <= (sum_in_w)
            && !(cancel_valid_i && (((add_valid_r[0] ? add_tag_r[0] : product_tag_r[13]) -
        age_head_i) >= cancel_distance_w));
        else if (cancel_valid_i && ((s1_tag_r - age_head_i) >= cancel_distance_w))
            s1_valid_r <= 1'b0;
    end
    wire [3:0] s1_tag_next_w;
    assign s1_tag_next_w = add_valid_r[0] ? add_tag_r[0] : product_tag_r[13];
    always @(posedge clk_i) begin
        if (advance_copy_r[675]) s1_tag_r[3:0] <= s1_tag_next_w[3:0];
    end
    reg s2_valid_r;
    reg [3:0] s2_tag_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) s2_valid_r <= 1'b0;
        else if (advance_copy_r[740]) s2_valid_r <= (s1_valid_r)
            && !(cancel_valid_i && (((s1_tag_r) - age_head_i) >= cancel_distance_w));
        else if (cancel_valid_i && ((s2_tag_r - age_head_i) >= cancel_distance_w))
            s2_valid_r <= 1'b0;
    end
    wire [3:0] s2_tag_next_w;
    assign s2_tag_next_w = s1_tag_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[676]) s2_tag_r[3:0] <= s2_tag_next_w[3:0];
    end
    reg t1_valid_r;
    reg [3:0] t1_tag_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) t1_valid_r <= 1'b0;
        else if (advance_copy_r[740]) t1_valid_r <= (s2_valid_r || mul_select_w)
            && !(cancel_valid_i && (((mul_select_w ? product_tag_r[13] : s2_tag_r) - age_head_i) >=
        cancel_distance_w));
        else if (cancel_valid_i && ((t1_tag_r - age_head_i) >= cancel_distance_w))
            t1_valid_r <= 1'b0;
    end
    wire [3:0] t1_tag_next_w;
    assign t1_tag_next_w = mul_select_w ? product_tag_r[13] : s2_tag_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[677]) t1_tag_r[3:0] <= t1_tag_next_w[3:0];
    end
    reg t2_valid_r;
    reg [3:0] t2_tag_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) t2_valid_r <= 1'b0;
        else if (advance_copy_r[740]) t2_valid_r <= (t1_valid_r)
            && !(cancel_valid_i && (((t1_tag_r) - age_head_i) >= cancel_distance_w));
        else if (cancel_valid_i && ((t2_tag_r - age_head_i) >= cancel_distance_w))
            t2_valid_r <= 1'b0;
    end
    wire [3:0] t2_tag_next_w;
    assign t2_tag_next_w = t1_tag_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[678]) t2_tag_r[3:0] <= t2_tag_next_w[3:0];
    end
    wire [167:0] s2_magnitude_w;
    assign s2_magnitude_w[15:0] = s2_reverse_select_r[0] ? s2_reverse_r[15:0] : s2_forward_r[15:0];
    assign s2_magnitude_w[31:16] = s2_reverse_select_r[1] ? s2_reverse_r[31:16] :
        s2_forward_r[31:16];
    assign s2_magnitude_w[47:32] = s2_reverse_select_r[2] ? s2_reverse_r[47:32] :
        s2_forward_r[47:32];
    assign s2_magnitude_w[63:48] = s2_reverse_select_r[3] ? s2_reverse_r[63:48] :
        s2_forward_r[63:48];
    assign s2_magnitude_w[79:64] = s2_reverse_select_r[4] ? s2_reverse_r[79:64] :
        s2_forward_r[79:64];
    assign s2_magnitude_w[95:80] = s2_reverse_select_r[5] ? s2_reverse_r[95:80] :
        s2_forward_r[95:80];
    assign s2_magnitude_w[111:96] = s2_reverse_select_r[6] ? s2_reverse_r[111:96] :
        s2_forward_r[111:96];
    assign s2_magnitude_w[127:112] = s2_reverse_select_r[7] ? s2_reverse_r[127:112] :
        s2_forward_r[127:112];
    assign s2_magnitude_w[143:128] = s2_reverse_select_r[8] ? s2_reverse_r[143:128] :
        s2_forward_r[143:128];
    assign s2_magnitude_w[159:144] = s2_reverse_select_r[9] ? s2_reverse_r[159:144] :
        s2_forward_r[159:144];
    assign s2_magnitude_w[167:160] = s2_reverse_select_r[10] ? s2_reverse_r[167:160] :
        s2_forward_r[167:160];
    wire [167:0] tail_magnitude_w;
    wire [167:0] tail_magnitude_w_left_w;
    assign tail_magnitude_w_left_w = {59'b0,product_w,3'b0};
    wire [167:0] tail_magnitude_w_right_w;
    assign tail_magnitude_w_right_w = s2_magnitude_w;
    assign tail_magnitude_w[15:0] = mul_data_select_r[0] ? tail_magnitude_w_left_w[15:0] :
        tail_magnitude_w_right_w[15:0];
    assign tail_magnitude_w[31:16] = mul_data_select_r[1] ? tail_magnitude_w_left_w[31:16] :
        tail_magnitude_w_right_w[31:16];
    assign tail_magnitude_w[47:32] = mul_data_select_r[2] ? tail_magnitude_w_left_w[47:32] :
        tail_magnitude_w_right_w[47:32];
    assign tail_magnitude_w[63:48] = mul_data_select_r[3] ? tail_magnitude_w_left_w[63:48] :
        tail_magnitude_w_right_w[63:48];
    assign tail_magnitude_w[79:64] = mul_data_select_r[4] ? tail_magnitude_w_left_w[79:64] :
        tail_magnitude_w_right_w[79:64];
    assign tail_magnitude_w[95:80] = mul_data_select_r[5] ? tail_magnitude_w_left_w[95:80] :
        tail_magnitude_w_right_w[95:80];
    assign tail_magnitude_w[111:96] = mul_data_select_r[6] ? tail_magnitude_w_left_w[111:96] :
        tail_magnitude_w_right_w[111:96];
    assign tail_magnitude_w[127:112] = mul_data_select_r[7] ? tail_magnitude_w_left_w[127:112] :
        tail_magnitude_w_right_w[127:112];
    assign tail_magnitude_w[143:128] = mul_data_select_r[8] ? tail_magnitude_w_left_w[143:128] :
        tail_magnitude_w_right_w[143:128];
    assign tail_magnitude_w[159:144] = mul_data_select_r[9] ? tail_magnitude_w_left_w[159:144] :
        tail_magnitude_w_right_w[159:144];
    assign tail_magnitude_w[167:160] = mul_data_select_r[10] ? tail_magnitude_w_left_w[167:160] :
        tail_magnitude_w_right_w[167:160];
    wire [7:0] tail_count_w;
    assign tail_count_w = mul_data_select_r[25] ? (product_w[105] ? p13_mul_count1_r :
        p13_mul_count0_r)
        : s2_reverse_select_r[11] ? s2_reverse_count_r : s2_forward_count_r;
    wire tail_ps_w;
    wire tail_ps_w_left_w;
    assign tail_ps_w_left_w = p13_ps_r;
    wire tail_ps_w_right_w;
    assign tail_ps_w_right_w = s2_ps_r;
    assign tail_ps_w = mul_data_select_r[11] ? tail_ps_w_left_w : tail_ps_w_right_w;
    wire tail_cs_w;
    wire tail_cs_w_left_w;
    assign tail_cs_w_left_w = p13_cs_r;
    wire tail_cs_w_right_w;
    assign tail_cs_w_right_w = s2_cs_r;
    assign tail_cs_w = mul_data_select_r[12] ? tail_cs_w_left_w : tail_cs_w_right_w;
    wire [2:0] tail_rm_w;
    wire [2:0] tail_rm_w_left_w;
    assign tail_rm_w_left_w = p13_rm_r;
    wire [2:0] tail_rm_w_right_w;
    assign tail_rm_w_right_w = s2_rm_r;
    assign tail_rm_w[2:0] = mul_data_select_r[13] ? tail_rm_w_left_w[2:0] : tail_rm_w_right_w[2:0];
    wire tail_special_w;
    wire tail_special_w_left_w;
    assign tail_special_w_left_w = p13_special_r;
    wire tail_special_w_right_w;
    assign tail_special_w_right_w = s2_special_r;
    assign tail_special_w = mul_data_select_r[14] ? tail_special_w_left_w : tail_special_w_right_w;
    wire [63:0] tail_result_w;
    wire [63:0] tail_result_w_left_w;
    assign tail_result_w_left_w = p13_result_r;
    wire [63:0] tail_result_w_right_w;
    assign tail_result_w_right_w = s2_result_r;
    assign tail_result_w[15:0] = mul_data_select_r[15] ? tail_result_w_left_w[15:0] :
        tail_result_w_right_w[15:0];
    assign tail_result_w[31:16] = mul_data_select_r[16] ? tail_result_w_left_w[31:16] :
        tail_result_w_right_w[31:16];
    assign tail_result_w[47:32] = mul_data_select_r[17] ? tail_result_w_left_w[47:32] :
        tail_result_w_right_w[47:32];
    assign tail_result_w[63:48] = mul_data_select_r[18] ? tail_result_w_left_w[63:48] :
        tail_result_w_right_w[63:48];
    wire [4:0] tail_flags_w;
    wire [4:0] tail_flags_w_left_w;
    assign tail_flags_w_left_w = p13_flags_r;
    wire [4:0] tail_flags_w_right_w;
    assign tail_flags_w_right_w = s2_flags_r;
    assign tail_flags_w[4:0] = mul_data_select_r[19] ? tail_flags_w_left_w[4:0] :
        tail_flags_w_right_w[4:0];
    wire signed [12:0] tail_base_w;
    wire [12:0] tail_base_w_left_w;
    assign tail_base_w_left_w = p13_base_r;
    wire [12:0] tail_base_w_right_w;
    assign tail_base_w_right_w = s2_base_r;
    assign tail_base_w[12:0] = mul_data_select_r[20] ? tail_base_w_left_w[12:0] :
        tail_base_w_right_w[12:0];
    wire [7:0] tail_limit_w;
    wire [7:0] tail_limit_w_left_w;
    assign tail_limit_w_left_w = p13_limit_r;
    wire [7:0] tail_limit_w_right_w;
    assign tail_limit_w_right_w = s2_limit_r;
    assign tail_limit_w[7:0] = mul_data_select_r[21] ? tail_limit_w_left_w[7:0] :
        tail_limit_w_right_w[7:0];
    wire signed [12:0] tail_anchor_w;
    wire [12:0] tail_anchor_w_left_w;
    assign tail_anchor_w_left_w = p13_anchor_r;
    wire [12:0] tail_anchor_w_right_w;
    assign tail_anchor_w_right_w = s2_anchor_r;
    assign tail_anchor_w[12:0] = mul_data_select_r[22] ? tail_anchor_w_left_w[12:0] :
        tail_anchor_w_right_w[12:0];
    wire tail_floor_w;
    assign tail_floor_w = tail_count_w == tail_limit_w;
    wire tail_right_w;
    wire tail_right_w_left_w;
    assign tail_right_w_left_w = p13_norm_right_r;
    wire tail_right_w_right_w;
    assign tail_right_w_right_w = s2_norm_right_r;
    assign tail_right_w = mul_data_select_r[23] ? tail_right_w_left_w : tail_right_w_right_w;
    wire [7:0] tail_tiny_w;
    wire [7:0] tail_tiny_w_left_w;
    assign tail_tiny_w_left_w = p13_tiny_r;
    wire [7:0] tail_tiny_w_right_w;
    assign tail_tiny_w_right_w = s2_tiny_r;
    assign tail_tiny_w[7:0] = mul_data_select_r[24] ? tail_tiny_w_left_w[7:0] :
        tail_tiny_w_right_w[7:0];
    wire [7:0] tail_shift_w;
    assign tail_shift_w = tail_right_w ? tail_tiny_w : tail_count_w;
    wire [7:0] tail_coarse_w;
    assign tail_coarse_w = {tail_shift_w[7:3],3'b0};
    wire [168:0] coarse_left_w;
    assign coarse_left_w = {1'b0,tail_magnitude_w} << tail_coarse_w;
    wire [168:0] coarse_right_w;
    assign coarse_right_w = {1'b0,tail_magnitude_w} >> tail_coarse_w;
    wire coarse_lost_w;
    assign coarse_lost_w = |(tail_magnitude_w & ~(168'hffffffffffffffffffffffffffffffffffffffffff
        << tail_coarse_w));
    reg [64:0] t1_magnitude_r;
    wire [64:0] t1_magnitude_next_w;
    assign t1_magnitude_next_w = tail_right_w ? {coarse_right_w[168:105],(|coarse_right_w[104:0]) |
        coarse_lost_w}
        : {coarse_left_w[168:105],|coarse_left_w[104:0]};
    always @(posedge clk_i) begin
        if (advance_copy_r[679]) t1_magnitude_r[15:0] <= t1_magnitude_next_w[15:0];
        if (advance_copy_r[680]) t1_magnitude_r[31:16] <= t1_magnitude_next_w[31:16];
        if (advance_copy_r[681]) t1_magnitude_r[47:32] <= t1_magnitude_next_w[47:32];
        if (advance_copy_r[682]) t1_magnitude_r[63:48] <= t1_magnitude_next_w[63:48];
        if (advance_copy_r[683]) t1_magnitude_r[64:64] <= t1_magnitude_next_w[64:64];
    end
    reg signed [12:0] t1_bias_r;
    wire [12:0] t1_bias_next_w;
    assign t1_bias_next_w = tail_right_w ? 13'sd1 : tail_anchor_w - $signed({5'b0,tail_count_w});
    always @(posedge clk_i) begin
        if (advance_copy_r[684]) t1_bias_r[12:0] <= t1_bias_next_w[12:0];
    end
    reg [2:0] t1_fine_r;
    wire [2:0] t1_fine_next_w;
    assign t1_fine_next_w = tail_shift_w[2:0];
    always @(posedge clk_i) begin
        if (advance_copy_r[685]) t1_fine_r[2:0] <= t1_fine_next_w[2:0];
    end
    reg t1_right_r;
    wire t1_right_next_w;
    assign t1_right_next_w = tail_right_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[686]) t1_right_r <= t1_right_next_w;
    end
    reg t1_floor_r;
    wire t1_floor_next_w;
    assign t1_floor_next_w = tail_floor_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[687]) t1_floor_r <= t1_floor_next_w;
    end
    reg t1_sign_r;
    wire t1_sign_next_w;
    assign t1_sign_next_w = mul_data_select_r[26] ? p13_ps_r : s2_reverse_select_r[12] ? s2_cs_r :
        s2_ps_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[688]) t1_sign_r <= t1_sign_next_w;
    end
    reg t1_zero_sign_r;
    wire t1_zero_sign_next_w;
    assign t1_zero_sign_next_w = mul_data_select_r[27] ? p13_ps_r
        : (s2_ps_r == s2_cs_r) ? s2_ps_r : s2_rm_r == 3'b010;
    always @(posedge clk_i) begin
        if (advance_copy_r[689]) t1_zero_sign_r <= t1_zero_sign_next_w;
    end
    reg [2:0] t1_rm_r;
    wire [2:0] t1_rm_next_w;
    assign t1_rm_next_w = tail_rm_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[690]) t1_rm_r[2:0] <= t1_rm_next_w[2:0];
    end
    reg t1_special_r;
    wire t1_special_next_w;
    assign t1_special_next_w = tail_special_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[691]) t1_special_r <= t1_special_next_w;
    end
    reg [63:0] t1_result_r;
    wire [63:0] t1_result_next_w;
    assign t1_result_next_w = tail_result_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[692]) t1_result_r[15:0] <= t1_result_next_w[15:0];
        if (advance_copy_r[693]) t1_result_r[31:16] <= t1_result_next_w[31:16];
        if (advance_copy_r[694]) t1_result_r[47:32] <= t1_result_next_w[47:32];
        if (advance_copy_r[695]) t1_result_r[63:48] <= t1_result_next_w[63:48];
    end
    reg [4:0] t1_flags_r;
    wire [4:0] t1_flags_next_w;
    assign t1_flags_next_w = tail_flags_w;
    always @(posedge clk_i) begin
        if (advance_copy_r[696]) t1_flags_r[4:0] <= t1_flags_next_w[4:0];
    end
    wire [64:0] fine_right_w;
    assign fine_right_w = t1_magnitude_r >> t1_fine_r;
    wire fine_lost_w;
    assign fine_lost_w = |(t1_magnitude_r & ~(65'h1ffffffffffffffff << t1_fine_r));
    reg [64:0] t2_magnitude_r;
    wire [64:0] t2_magnitude_next_w;
    assign t2_magnitude_next_w = t1_right_r ? (fine_right_w | {64'b0,fine_lost_w})
        : (t1_magnitude_r << t1_fine_r);
    always @(posedge clk_i) begin
        if (advance_copy_r[697]) t2_magnitude_r[15:0] <= t2_magnitude_next_w[15:0];
        if (advance_copy_r[698]) t2_magnitude_r[31:16] <= t2_magnitude_next_w[31:16];
        if (advance_copy_r[699]) t2_magnitude_r[47:32] <= t2_magnitude_next_w[47:32];
        if (advance_copy_r[700]) t2_magnitude_r[63:48] <= t2_magnitude_next_w[63:48];
        if (advance_copy_r[701]) t2_magnitude_r[64:64] <= t2_magnitude_next_w[64:64];
    end
    reg signed [12:0] t2_bias_r;
    wire [12:0] t2_bias_next_w;
    assign t2_bias_next_w = t1_bias_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[702]) t2_bias_r[12:0] <= t2_bias_next_w[12:0];
    end
    reg t2_floor_r;
    wire t2_floor_next_w;
    assign t2_floor_next_w = t1_floor_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[703]) t2_floor_r <= t2_floor_next_w;
    end
    reg t2_sign_r;
    wire t2_sign_next_w;
    assign t2_sign_next_w = t1_sign_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[704]) t2_sign_r <= t2_sign_next_w;
    end
    reg t2_zero_sign_r;
    wire t2_zero_sign_next_w;
    assign t2_zero_sign_next_w = t1_zero_sign_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[705]) t2_zero_sign_r <= t2_zero_sign_next_w;
    end
    reg [2:0] t2_rm_r;
    wire [2:0] t2_rm_next_w;
    assign t2_rm_next_w = t1_rm_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[706]) t2_rm_r[2:0] <= t2_rm_next_w[2:0];
    end
    reg t2_special_r;
    wire t2_special_next_w;
    assign t2_special_next_w = t1_special_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[707]) t2_special_r <= t2_special_next_w;
    end
    reg [63:0] t2_result_r;
    wire [63:0] t2_result_next_w;
    assign t2_result_next_w = t1_result_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[708]) t2_result_r[15:0] <= t2_result_next_w[15:0];
        if (advance_copy_r[709]) t2_result_r[31:16] <= t2_result_next_w[31:16];
        if (advance_copy_r[710]) t2_result_r[47:32] <= t2_result_next_w[47:32];
        if (advance_copy_r[711]) t2_result_r[63:48] <= t2_result_next_w[63:48];
    end
    reg [4:0] t2_flags_r;
    wire [4:0] t2_flags_next_w;
    assign t2_flags_next_w = t1_flags_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[712]) t2_flags_r[4:0] <= t2_flags_next_w[4:0];
    end
    wire correct_up_w;
    assign correct_up_w = t2_magnitude_r[64];
    wire correct_down_w;
    assign correct_down_w = !t2_magnitude_r[63] && !t2_floor_r;
    wire [63:0] normal0_w;
    assign normal0_w = {t2_magnitude_r[64:2],|t2_magnitude_r[1:0]};
    wire inexact0_w;
    assign inexact0_w = |normal0_w[10:0];
    wire increment0_w;
    assign increment0_w = ((t2_rm_r == 3'b000) && normal0_w[10]
        && ((|normal0_w[9:0]) || normal0_w[11]))
        || ((t2_rm_r == 3'b100) && normal0_w[10])
        || ((t2_rm_r == 3'b010) && t2_sign_r && inexact0_w)
        || ((t2_rm_r == 3'b011) && !t2_sign_r && inexact0_w);
    wire [52:0] rounded0_w;
    assign rounded0_w = {1'b0,normal0_w[62:11]} + {52'b0,increment0_w};
    wire carry0_w;
    assign carry0_w = (&normal0_w[63:11]) && increment0_w;
    wire subnormal0_w;
    assign subnormal0_w = !normal0_w[63] && !rounded0_w[52];
    wire signed [12:0] bias0_w;
    assign bias0_w = t2_bias_r + 13'sd1;
    wire overflow0_w;
    assign overflow0_w = bias0_w >= 13'sd2047 || ((bias0_w == 13'sd2046) && carry0_w);
    wire [10:0] exponent0_w;
    assign exponent0_w = subnormal0_w ? 11'b0 : bias0_w[10:0] + {10'b0,carry0_w};
    wire [63:0] data0_w;
    assign data0_w = overflow0_w ? {t2_sign_r, overflow_inf_w ? 63'h7ff0000000000000
        : 63'h7fefffffffffffff} : {!(|normal0_w) ? t2_zero_sign_r : t2_sign_r,
        exponent0_w, carry0_w ? 52'b0 : rounded0_w[51:0]};
    wire [4:0] flags0_w;
    assign flags0_w = {2'b0,overflow0_w,inexact0_w && !overflow0_w && subnormal0_w,
        inexact0_w || overflow0_w};
    wire [63:0] normal1_w;
    assign normal1_w = {t2_magnitude_r[62:0],1'b0};
    wire inexact1_w;
    assign inexact1_w = |normal1_w[10:0];
    wire increment1_w;
    assign increment1_w = ((t2_rm_r == 3'b000) && normal1_w[10]
        && ((|normal1_w[9:0]) || normal1_w[11]))
        || ((t2_rm_r == 3'b100) && normal1_w[10])
        || ((t2_rm_r == 3'b010) && t2_sign_r && inexact1_w)
        || ((t2_rm_r == 3'b011) && !t2_sign_r && inexact1_w);
    wire [52:0] rounded1_w;
    assign rounded1_w = {1'b0,normal1_w[62:11]} + {52'b0,increment1_w};
    wire carry1_w;
    assign carry1_w = (&normal1_w[63:11]) && increment1_w;
    wire subnormal1_w;
    assign subnormal1_w = !normal1_w[63] && !rounded1_w[52];
    wire signed [12:0] bias1_w;
    assign bias1_w = t2_bias_r - 13'sd1;
    wire overflow1_w;
    assign overflow1_w = bias1_w >= 13'sd2047 || ((bias1_w == 13'sd2046) && carry1_w);
    wire [10:0] exponent1_w;
    assign exponent1_w = subnormal1_w ? 11'b0 : bias1_w[10:0] + {10'b0,carry1_w};
    wire [63:0] data1_w;
    assign data1_w = overflow1_w ? {t2_sign_r, overflow_inf_w ? 63'h7ff0000000000000
        : 63'h7fefffffffffffff} : {!(|normal1_w) ? t2_zero_sign_r : t2_sign_r,
        exponent1_w, carry1_w ? 52'b0 : rounded1_w[51:0]};
    wire [4:0] flags1_w;
    assign flags1_w = {2'b0,overflow1_w,inexact1_w && !overflow1_w && subnormal1_w,
        inexact1_w || overflow1_w};
    wire [63:0] normal2_w;
    assign normal2_w = t2_magnitude_r[63:0];
    wire inexact2_w;
    assign inexact2_w = |normal2_w[10:0];
    wire increment2_w;
    assign increment2_w = ((t2_rm_r == 3'b000) && normal2_w[10]
        && ((|normal2_w[9:0]) || normal2_w[11]))
        || ((t2_rm_r == 3'b100) && normal2_w[10])
        || ((t2_rm_r == 3'b010) && t2_sign_r && inexact2_w)
        || ((t2_rm_r == 3'b011) && !t2_sign_r && inexact2_w);
    wire [52:0] rounded2_w;
    assign rounded2_w = {1'b0,normal2_w[62:11]} + {52'b0,increment2_w};
    wire carry2_w;
    assign carry2_w = (&normal2_w[63:11]) && increment2_w;
    wire subnormal2_w;
    assign subnormal2_w = !normal2_w[63] && !rounded2_w[52];
    wire signed [12:0] bias2_w;
    assign bias2_w = t2_bias_r + 13'sd0;
    wire overflow2_w;
    assign overflow2_w = bias2_w >= 13'sd2047 || ((bias2_w == 13'sd2046) && carry2_w);
    wire [10:0] exponent2_w;
    assign exponent2_w = subnormal2_w ? 11'b0 : bias2_w[10:0] + {10'b0,carry2_w};
    wire [63:0] data2_w;
    assign data2_w = overflow2_w ? {t2_sign_r, overflow_inf_w ? 63'h7ff0000000000000
        : 63'h7fefffffffffffff} : {!(|normal2_w) ? t2_zero_sign_r : t2_sign_r,
        exponent2_w, carry2_w ? 52'b0 : rounded2_w[51:0]};
    wire [4:0] flags2_w;
    assign flags2_w = {2'b0,overflow2_w,inexact2_w && !overflow2_w && subnormal2_w,
        inexact2_w || overflow2_w};
    wire overflow_inf_w;
    assign overflow_inf_w = (t2_rm_r == 3'b000) || (t2_rm_r == 3'b100)
        || ((t2_rm_r == 3'b010) && t2_sign_r) || ((t2_rm_r == 3'b011) && !t2_sign_r);
    wire enqueue_w;
    assign enqueue_w = advance_w && t2_valid_r && !(cancel_valid_i
        && ((t2_tag_r - age_head_i) >= cancel_distance_w));
    wire [3:0] enqueue_tag_w;
    assign enqueue_tag_w = t2_tag_r;
    wire [63:0] enqueue_data_w;
    assign enqueue_data_w = t2_special_r ? t2_result_r
        : correct_up_w ? data0_w : correct_down_w ? data1_w : data2_w;
    wire [4:0] enqueue_flags_w;
    assign enqueue_flags_w = t2_special_r ? t2_flags_r
        : correct_up_w ? flags0_w : correct_down_w ? flags1_w : flags2_w;
    wire enqueue_int_dest_w;
    assign enqueue_int_dest_w = 1'b0;
    reg advance_r;
    assign advance_w = advance_r;
    reg [1:0] skid_valid_r;
    reg [T-1:0] skid_tag_r [0:1];
    reg [63:0] skid_data_r [0:1];
    reg [4:0] skid_flags_r [0:1];
    reg [1:0] skid_int_dest_r;
    wire keep0_w;
    wire keep1_w;
    wire [1:0] kept_count_w;
    wire [1:0] next_count_w;
    wire [1:0] next_valid_w;
    assign keep0_w = skid_valid_r[0] && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w));
    assign keep1_w = skid_valid_r[1]
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w));
    assign kept_count_w = {1'b0, keep0_w} + {1'b0, keep1_w};
    assign next_count_w = kept_count_w + {1'b0, enqueue_w};
    assign next_valid_w = {next_count_w == 2'd2, next_count_w != 2'd0};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            skid_valid_r <= 2'b0;
            advance_r <= 1'b1;
        end else begin
            skid_valid_r <= next_valid_w;
            advance_r <= next_count_w < 2'd2;
        end
    end
    always @(posedge clk_i) begin
        if (!keep0_w && keep1_w) begin
            skid_tag_r[0] <= skid_tag_r[1];
            skid_data_r[0] <= skid_data_r[1];
            skid_flags_r[0] <= skid_flags_r[1];
            skid_int_dest_r[0] <= skid_int_dest_r[1];
        end
        if (enqueue_w) begin
            if (kept_count_w == 2'd0) begin
                skid_tag_r[0] <= enqueue_tag_w;
                skid_data_r[0] <= enqueue_data_w;
                skid_flags_r[0] <= enqueue_flags_w;
                skid_int_dest_r[0] <= enqueue_int_dest_w;
            end else begin
                skid_tag_r[1] <= enqueue_tag_w;
                skid_data_r[1] <= enqueue_data_w;
                skid_flags_r[1] <= enqueue_flags_w;
                skid_int_dest_r[1] <= enqueue_int_dest_w;
            end
        end
    end
    assign unit_resp_valid_o = skid_valid_r[0];
    assign unit_resp_tag_o = skid_tag_r[0];
    assign unit_resp_data_o = skid_data_r[0];
    assign unit_resp_flags_o = skid_flags_r[0];
    assign unit_resp_int_dest_o = skid_int_dest_r[0];
    (* keep = "true", syn_preserve = 1 *) reg [6:0] capacity_t1_valid_r;
    (* keep = "true", syn_preserve = 1 *) reg [6:0] capacity_t2_valid_r;
    wire capacity_t1_kill_w;
    wire capacity_t2_kill_w;
    wire [6:0] capacity_enqueue_w;
    assign capacity_t1_kill_w = cancel_valid_i
        && ((t1_tag_r - age_head_i) >= cancel_distance_w);
    assign capacity_t2_kill_w = cancel_valid_i
        && ((t2_tag_r - age_head_i) >= cancel_distance_w);
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            capacity_t1_valid_r <= 7'b0;
            capacity_t2_valid_r <= 7'b0;
        end else begin
            if (advance_copy_r[713]) capacity_t1_valid_r[0]
                <= (s2_valid_r || mul_select_w) && !(cancel_valid_i
                    && (((mul_select_w ? product_tag_r[13] : s2_tag_r) - age_head_i)
                        >= cancel_distance_w));
            else if (capacity_t1_kill_w) capacity_t1_valid_r[0] <= 1'b0;
            if (advance_copy_r[714]) capacity_t2_valid_r[0]
                <= capacity_t1_valid_r[0] && !capacity_t1_kill_w;
            else if (capacity_t2_kill_w) capacity_t2_valid_r[0] <= 1'b0;
            if (advance_copy_r[713]) capacity_t1_valid_r[1]
                <= (s2_valid_r || mul_select_w) && !(cancel_valid_i
                    && (((mul_select_w ? product_tag_r[13] : s2_tag_r) - age_head_i)
                        >= cancel_distance_w));
            else if (capacity_t1_kill_w) capacity_t1_valid_r[1] <= 1'b0;
            if (advance_copy_r[714]) capacity_t2_valid_r[1]
                <= capacity_t1_valid_r[1] && !capacity_t1_kill_w;
            else if (capacity_t2_kill_w) capacity_t2_valid_r[1] <= 1'b0;
            if (advance_copy_r[713]) capacity_t1_valid_r[2]
                <= (s2_valid_r || mul_select_w) && !(cancel_valid_i
                    && (((mul_select_w ? product_tag_r[13] : s2_tag_r) - age_head_i)
                        >= cancel_distance_w));
            else if (capacity_t1_kill_w) capacity_t1_valid_r[2] <= 1'b0;
            if (advance_copy_r[714]) capacity_t2_valid_r[2]
                <= capacity_t1_valid_r[2] && !capacity_t1_kill_w;
            else if (capacity_t2_kill_w) capacity_t2_valid_r[2] <= 1'b0;
            if (advance_copy_r[713]) capacity_t1_valid_r[3]
                <= (s2_valid_r || mul_select_w) && !(cancel_valid_i
                    && (((mul_select_w ? product_tag_r[13] : s2_tag_r) - age_head_i)
                        >= cancel_distance_w));
            else if (capacity_t1_kill_w) capacity_t1_valid_r[3] <= 1'b0;
            if (advance_copy_r[714]) capacity_t2_valid_r[3]
                <= capacity_t1_valid_r[3] && !capacity_t1_kill_w;
            else if (capacity_t2_kill_w) capacity_t2_valid_r[3] <= 1'b0;
            if (advance_copy_r[713]) capacity_t1_valid_r[4]
                <= (s2_valid_r || mul_select_w) && !(cancel_valid_i
                    && (((mul_select_w ? product_tag_r[13] : s2_tag_r) - age_head_i)
                        >= cancel_distance_w));
            else if (capacity_t1_kill_w) capacity_t1_valid_r[4] <= 1'b0;
            if (advance_copy_r[714]) capacity_t2_valid_r[4]
                <= capacity_t1_valid_r[4] && !capacity_t1_kill_w;
            else if (capacity_t2_kill_w) capacity_t2_valid_r[4] <= 1'b0;
            if (advance_copy_r[713]) capacity_t1_valid_r[5]
                <= (s2_valid_r || mul_select_w) && !(cancel_valid_i
                    && (((mul_select_w ? product_tag_r[13] : s2_tag_r) - age_head_i)
                        >= cancel_distance_w));
            else if (capacity_t1_kill_w) capacity_t1_valid_r[5] <= 1'b0;
            if (advance_copy_r[714]) capacity_t2_valid_r[5]
                <= capacity_t1_valid_r[5] && !capacity_t1_kill_w;
            else if (capacity_t2_kill_w) capacity_t2_valid_r[5] <= 1'b0;
            if (advance_copy_r[713]) capacity_t1_valid_r[6]
                <= (s2_valid_r || mul_select_w) && !(cancel_valid_i
                    && (((mul_select_w ? product_tag_r[13] : s2_tag_r) - age_head_i)
                        >= cancel_distance_w));
            else if (capacity_t1_kill_w) capacity_t1_valid_r[6] <= 1'b0;
            if (advance_copy_r[714]) capacity_t2_valid_r[6]
                <= capacity_t1_valid_r[6] && !capacity_t1_kill_w;
            else if (capacity_t2_kill_w) capacity_t2_valid_r[6] <= 1'b0;
        end
    end
    assign capacity_enqueue_w[0] = advance_copy_r[715]
        && capacity_t2_valid_r[0] && !capacity_t2_kill_w;
    assign capacity_enqueue_w[1] = advance_copy_r[716]
        && capacity_t2_valid_r[1] && !capacity_t2_kill_w;
    assign capacity_enqueue_w[2] = advance_copy_r[717]
        && capacity_t2_valid_r[2] && !capacity_t2_kill_w;
    assign capacity_enqueue_w[3] = advance_copy_r[718]
        && capacity_t2_valid_r[3] && !capacity_t2_kill_w;
    assign capacity_enqueue_w[4] = advance_copy_r[719]
        && capacity_t2_valid_r[4] && !capacity_t2_kill_w;
    assign capacity_enqueue_w[5] = advance_copy_r[720]
        && capacity_t2_valid_r[5] && !capacity_t2_kill_w;
    assign capacity_enqueue_w[6] = advance_copy_r[721]
        && capacity_t2_valid_r[6] && !capacity_t2_kill_w;
    (* keep = "true", syn_preserve = 1 *) reg [742:0] advance_copy_r;
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity0_r;
    wire [1:0] capacity0_next_w;
    assign capacity0_next_w = {1'b0,((capacity0_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity0_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[0]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity0_r <= 0;
        else capacity0_r <= capacity0_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity1_r;
    wire [1:0] capacity1_next_w;
    assign capacity1_next_w = {1'b0,((capacity1_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity1_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[0]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity1_r <= 0;
        else capacity1_r <= capacity1_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity2_r;
    wire [1:0] capacity2_next_w;
    assign capacity2_next_w = {1'b0,((capacity2_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity2_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[0]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity2_r <= 0;
        else capacity2_r <= capacity2_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity3_r;
    wire [1:0] capacity3_next_w;
    assign capacity3_next_w = {1'b0,((capacity3_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity3_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[0]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity3_r <= 0;
        else capacity3_r <= capacity3_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity4_r;
    wire [1:0] capacity4_next_w;
    assign capacity4_next_w = {1'b0,((capacity4_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity4_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[0]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity4_r <= 0;
        else capacity4_r <= capacity4_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity5_r;
    wire [1:0] capacity5_next_w;
    assign capacity5_next_w = {1'b0,((capacity5_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity5_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[0]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity5_r <= 0;
        else capacity5_r <= capacity5_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity6_r;
    wire [1:0] capacity6_next_w;
    assign capacity6_next_w = {1'b0,((capacity6_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity6_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[0]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity6_r <= 0;
        else capacity6_r <= capacity6_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity7_r;
    wire [1:0] capacity7_next_w;
    assign capacity7_next_w = {1'b0,((capacity7_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity7_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[1]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity7_r <= 0;
        else capacity7_r <= capacity7_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity8_r;
    wire [1:0] capacity8_next_w;
    assign capacity8_next_w = {1'b0,((capacity8_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity8_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[1]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity8_r <= 0;
        else capacity8_r <= capacity8_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity9_r;
    wire [1:0] capacity9_next_w;
    assign capacity9_next_w = {1'b0,((capacity9_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity9_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[1]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity9_r <= 0;
        else capacity9_r <= capacity9_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity10_r;
    wire [1:0] capacity10_next_w;
    assign capacity10_next_w = {1'b0,((capacity10_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity10_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[1]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity10_r <= 0;
        else capacity10_r <= capacity10_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity11_r;
    wire [1:0] capacity11_next_w;
    assign capacity11_next_w = {1'b0,((capacity11_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity11_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[1]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity11_r <= 0;
        else capacity11_r <= capacity11_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity12_r;
    wire [1:0] capacity12_next_w;
    assign capacity12_next_w = {1'b0,((capacity12_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity12_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[1]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity12_r <= 0;
        else capacity12_r <= capacity12_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity13_r;
    wire [1:0] capacity13_next_w;
    assign capacity13_next_w = {1'b0,((capacity13_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity13_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[1]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity13_r <= 0;
        else capacity13_r <= capacity13_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity14_r;
    wire [1:0] capacity14_next_w;
    assign capacity14_next_w = {1'b0,((capacity14_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity14_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[2]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity14_r <= 0;
        else capacity14_r <= capacity14_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity15_r;
    wire [1:0] capacity15_next_w;
    assign capacity15_next_w = {1'b0,((capacity15_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity15_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[2]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity15_r <= 0;
        else capacity15_r <= capacity15_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity16_r;
    wire [1:0] capacity16_next_w;
    assign capacity16_next_w = {1'b0,((capacity16_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity16_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[2]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity16_r <= 0;
        else capacity16_r <= capacity16_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity17_r;
    wire [1:0] capacity17_next_w;
    assign capacity17_next_w = {1'b0,((capacity17_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity17_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[2]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity17_r <= 0;
        else capacity17_r <= capacity17_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity18_r;
    wire [1:0] capacity18_next_w;
    assign capacity18_next_w = {1'b0,((capacity18_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity18_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[2]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity18_r <= 0;
        else capacity18_r <= capacity18_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity19_r;
    wire [1:0] capacity19_next_w;
    assign capacity19_next_w = {1'b0,((capacity19_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity19_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[2]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity19_r <= 0;
        else capacity19_r <= capacity19_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity20_r;
    wire [1:0] capacity20_next_w;
    assign capacity20_next_w = {1'b0,((capacity20_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity20_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[2]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity20_r <= 0;
        else capacity20_r <= capacity20_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity21_r;
    wire [1:0] capacity21_next_w;
    assign capacity21_next_w = {1'b0,((capacity21_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity21_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[3]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity21_r <= 0;
        else capacity21_r <= capacity21_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity22_r;
    wire [1:0] capacity22_next_w;
    assign capacity22_next_w = {1'b0,((capacity22_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity22_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[3]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity22_r <= 0;
        else capacity22_r <= capacity22_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity23_r;
    wire [1:0] capacity23_next_w;
    assign capacity23_next_w = {1'b0,((capacity23_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity23_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[3]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity23_r <= 0;
        else capacity23_r <= capacity23_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity24_r;
    wire [1:0] capacity24_next_w;
    assign capacity24_next_w = {1'b0,((capacity24_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity24_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[3]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity24_r <= 0;
        else capacity24_r <= capacity24_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity25_r;
    wire [1:0] capacity25_next_w;
    assign capacity25_next_w = {1'b0,((capacity25_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity25_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[3]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity25_r <= 0;
        else capacity25_r <= capacity25_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity26_r;
    wire [1:0] capacity26_next_w;
    assign capacity26_next_w = {1'b0,((capacity26_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity26_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[3]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity26_r <= 0;
        else capacity26_r <= capacity26_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity27_r;
    wire [1:0] capacity27_next_w;
    assign capacity27_next_w = {1'b0,((capacity27_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity27_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[3]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity27_r <= 0;
        else capacity27_r <= capacity27_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity28_r;
    wire [1:0] capacity28_next_w;
    assign capacity28_next_w = {1'b0,((capacity28_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity28_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[4]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity28_r <= 0;
        else capacity28_r <= capacity28_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity29_r;
    wire [1:0] capacity29_next_w;
    assign capacity29_next_w = {1'b0,((capacity29_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity29_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[4]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity29_r <= 0;
        else capacity29_r <= capacity29_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity30_r;
    wire [1:0] capacity30_next_w;
    assign capacity30_next_w = {1'b0,((capacity30_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity30_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[4]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity30_r <= 0;
        else capacity30_r <= capacity30_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity31_r;
    wire [1:0] capacity31_next_w;
    assign capacity31_next_w = {1'b0,((capacity31_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity31_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[4]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity31_r <= 0;
        else capacity31_r <= capacity31_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity32_r;
    wire [1:0] capacity32_next_w;
    assign capacity32_next_w = {1'b0,((capacity32_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity32_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[4]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity32_r <= 0;
        else capacity32_r <= capacity32_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity33_r;
    wire [1:0] capacity33_next_w;
    assign capacity33_next_w = {1'b0,((capacity33_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity33_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[4]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity33_r <= 0;
        else capacity33_r <= capacity33_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity34_r;
    wire [1:0] capacity34_next_w;
    assign capacity34_next_w = {1'b0,((capacity34_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity34_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[4]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity34_r <= 0;
        else capacity34_r <= capacity34_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity35_r;
    wire [1:0] capacity35_next_w;
    assign capacity35_next_w = {1'b0,((capacity35_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity35_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[5]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity35_r <= 0;
        else capacity35_r <= capacity35_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity36_r;
    wire [1:0] capacity36_next_w;
    assign capacity36_next_w = {1'b0,((capacity36_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity36_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[5]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity36_r <= 0;
        else capacity36_r <= capacity36_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity37_r;
    wire [1:0] capacity37_next_w;
    assign capacity37_next_w = {1'b0,((capacity37_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity37_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[5]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity37_r <= 0;
        else capacity37_r <= capacity37_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity38_r;
    wire [1:0] capacity38_next_w;
    assign capacity38_next_w = {1'b0,((capacity38_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity38_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[5]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity38_r <= 0;
        else capacity38_r <= capacity38_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity39_r;
    wire [1:0] capacity39_next_w;
    assign capacity39_next_w = {1'b0,((capacity39_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity39_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[5]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity39_r <= 0;
        else capacity39_r <= capacity39_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity40_r;
    wire [1:0] capacity40_next_w;
    assign capacity40_next_w = {1'b0,((capacity40_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity40_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[5]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity40_r <= 0;
        else capacity40_r <= capacity40_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity41_r;
    wire [1:0] capacity41_next_w;
    assign capacity41_next_w = {1'b0,((capacity41_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity41_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[5]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity41_r <= 0;
        else capacity41_r <= capacity41_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity42_r;
    wire [1:0] capacity42_next_w;
    assign capacity42_next_w = {1'b0,((capacity42_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity42_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[6]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity42_r <= 0;
        else capacity42_r <= capacity42_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity43_r;
    wire [1:0] capacity43_next_w;
    assign capacity43_next_w = {1'b0,((capacity43_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity43_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[6]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity43_r <= 0;
        else capacity43_r <= capacity43_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity44_r;
    wire [1:0] capacity44_next_w;
    assign capacity44_next_w = {1'b0,((capacity44_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity44_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[6]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity44_r <= 0;
        else capacity44_r <= capacity44_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity45_r;
    wire [1:0] capacity45_next_w;
    assign capacity45_next_w = {1'b0,((capacity45_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity45_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[6]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity45_r <= 0;
        else capacity45_r <= capacity45_next_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity46_r;
    wire [1:0] capacity46_next_w;
    assign capacity46_next_w = {1'b0,((capacity46_r != 0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,((capacity46_r == 2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w)))}
        + {1'b0,capacity_enqueue_w[6]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) capacity46_r <= 0;
        else capacity46_r <= capacity46_next_w;
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) advance_copy_r <= {743{1'b1}};
        else begin
            advance_copy_r[15:0] <= {16{capacity0_next_w < 2}};
            advance_copy_r[31:16] <= {16{capacity1_next_w < 2}};
            advance_copy_r[47:32] <= {16{capacity2_next_w < 2}};
            advance_copy_r[63:48] <= {16{capacity3_next_w < 2}};
            advance_copy_r[79:64] <= {16{capacity4_next_w < 2}};
            advance_copy_r[95:80] <= {16{capacity5_next_w < 2}};
            advance_copy_r[111:96] <= {16{capacity6_next_w < 2}};
            advance_copy_r[127:112] <= {16{capacity7_next_w < 2}};
            advance_copy_r[143:128] <= {16{capacity8_next_w < 2}};
            advance_copy_r[159:144] <= {16{capacity9_next_w < 2}};
            advance_copy_r[175:160] <= {16{capacity10_next_w < 2}};
            advance_copy_r[191:176] <= {16{capacity11_next_w < 2}};
            advance_copy_r[207:192] <= {16{capacity12_next_w < 2}};
            advance_copy_r[223:208] <= {16{capacity13_next_w < 2}};
            advance_copy_r[239:224] <= {16{capacity14_next_w < 2}};
            advance_copy_r[255:240] <= {16{capacity15_next_w < 2}};
            advance_copy_r[271:256] <= {16{capacity16_next_w < 2}};
            advance_copy_r[287:272] <= {16{capacity17_next_w < 2}};
            advance_copy_r[303:288] <= {16{capacity18_next_w < 2}};
            advance_copy_r[319:304] <= {16{capacity19_next_w < 2}};
            advance_copy_r[335:320] <= {16{capacity20_next_w < 2}};
            advance_copy_r[351:336] <= {16{capacity21_next_w < 2}};
            advance_copy_r[367:352] <= {16{capacity22_next_w < 2}};
            advance_copy_r[383:368] <= {16{capacity23_next_w < 2}};
            advance_copy_r[399:384] <= {16{capacity24_next_w < 2}};
            advance_copy_r[415:400] <= {16{capacity25_next_w < 2}};
            advance_copy_r[431:416] <= {16{capacity26_next_w < 2}};
            advance_copy_r[447:432] <= {16{capacity27_next_w < 2}};
            advance_copy_r[463:448] <= {16{capacity28_next_w < 2}};
            advance_copy_r[479:464] <= {16{capacity29_next_w < 2}};
            advance_copy_r[495:480] <= {16{capacity30_next_w < 2}};
            advance_copy_r[511:496] <= {16{capacity31_next_w < 2}};
            advance_copy_r[527:512] <= {16{capacity32_next_w < 2}};
            advance_copy_r[543:528] <= {16{capacity33_next_w < 2}};
            advance_copy_r[559:544] <= {16{capacity34_next_w < 2}};
            advance_copy_r[575:560] <= {16{capacity35_next_w < 2}};
            advance_copy_r[591:576] <= {16{capacity36_next_w < 2}};
            advance_copy_r[607:592] <= {16{capacity37_next_w < 2}};
            advance_copy_r[623:608] <= {16{capacity38_next_w < 2}};
            advance_copy_r[639:624] <= {16{capacity39_next_w < 2}};
            advance_copy_r[655:640] <= {16{capacity40_next_w < 2}};
            advance_copy_r[671:656] <= {16{capacity41_next_w < 2}};
            advance_copy_r[687:672] <= {16{capacity42_next_w < 2}};
            advance_copy_r[703:688] <= {16{capacity43_next_w < 2}};
            advance_copy_r[719:704] <= {16{capacity44_next_w < 2}};
            advance_copy_r[735:720] <= {16{capacity45_next_w < 2}};
            advance_copy_r[742:736] <= {7{capacity46_next_w < 2}};
        end
    end
    wire unused_w;
    assign unused_w = ^{instr_w[31:29],instr_w[26:7],reservation_r[0],
        mul_data_select_r,add_select_r,p4_tiny_raw_r[12:8],shift_abs_w[12:8],
        shift_signed_w[12:8],p2_product_zero_r,
        reverse_high_w[84], tail_ps_w, tail_cs_w,
        tail_base_w,s2_base_r, p13_c_r[0], coarse_left_w[168:0], coarse_right_w[168:0]};
endmodule
