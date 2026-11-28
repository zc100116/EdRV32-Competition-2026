// File: edrv32_cpu2_fpu_fma32.v
// Spec: fpu-spec 2.1-2.4, 3.1, 5.3-5.4.
// Description: Single-precision ADD/MUL/FMA unit with local completion and age cancellation.
// Clock domain: clk_sys.
module edrv32_cpu2_fpu_fma32 #(
    parameter [31:0] FPU_FORMAT = "F"
) (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Requests: legal decoded operations and resolved rounding mode.
    input wire unit_req_valid_i,
    output wire unit_req_ready_o,
    input wire [31:0] unit_req_instr_i,
    input wire [(FPU_FORMAT == "FD" ? 4 : 3)-1:0] unit_req_tag_i,
    input wire [31:0] unit_req_src1_i,
    input wire [31:0] unit_req_src2_i,
    input wire [31:0] unit_req_src3_i,
    input wire [2:0] unit_req_rm_i,

    // Local completion, held through arbitration backpressure.
    output wire unit_resp_valid_o,
    input wire unit_resp_ready_i,
    output wire [(FPU_FORMAT == "FD" ? 4 : 3)-1:0] unit_resp_tag_o,
    output wire [31:0] unit_resp_data_o,
    output wire [4:0] unit_resp_flags_o,
    output wire unit_resp_int_dest_o,

    // Head-relative inclusive cancellation.
    input wire [(FPU_FORMAT == "FD" ? 4 : 3)-1:0] age_head_i,
    input wire cancel_valid_i,
    input wire [(FPU_FORMAT == "FD" ? 4 : 3)-1:0] cancel_tag_i
);
    localparam T = FPU_FORMAT == "FD" ? 4 : 3;
    wire advance_w;
    wire accept_w;
    wire dispatch_w;
    wire capture_w;
    wire capture_data_w;
    reg class_valid_r;
    reg buffer_valid_r;
    reg req_ready_r;
    reg [31:0] buffer_instr_r;
    reg [31:0] buffer_src1_r;
    reg [31:0] buffer_src2_r;
    reg [31:0] buffer_src3_r;
    reg [2:0] buffer_rm_r;
    reg [T-1:0] buffer_tag_r;
    reg [T-1:0] class_tag_r;
    reg [1:0] class_kind_r;
    wire [31:0] instr_w;
    wire [31:0] a_i;
    wire [31:0] b_i;
    wire [31:0] c_i;
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
    reg [4:0] reservation_r;
    wire reservation_conflict_w;
    wire [4:0] reservation_shift_w;
    assign instr_w = buffer_valid_r ? buffer_instr_r : unit_req_instr_i;
    assign a_i = buffer_valid_r ? buffer_src1_r : unit_req_src1_i;
    assign b_i = buffer_valid_r ? buffer_src2_r : unit_req_src2_i;
    assign c_i = kind_w == 2'd2
        ? (buffer_valid_r ? buffer_src3_r : unit_req_src3_i) : 32'b0;
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
    // From the dispatch edge: ADD +2, MUL +4, FMA +5 enabled edges.
    assign reservation_conflict_w = class_kind_r == 2'd0 ? reservation_r[2]
        : class_kind_r == 2'd1 ? reservation_r[4] : 1'b0;
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
    assign reservation_shift_w = {1'b0, reservation_r[4:1]};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            class_valid_r <= 1'b0;
            buffer_valid_r <= 1'b0;
            req_ready_r <= 1'b1;
            reservation_r <= 5'b0;
        end else begin
            class_valid_r <= class_next_w;
            buffer_valid_r <= buffer_next_w;
            req_ready_r <= !buffer_next_w;
            if (advance_copy_r[120]) begin
                reservation_r <= reservation_shift_w
                    | (dispatch_w ? (class_kind_r == 2'd0 ? 5'b00010
                        : class_kind_r == 2'd1 ? 5'b01000 : 5'b10000) : 5'b0);
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
    wire [23:0] a_mantissa_w;
    wire [6:0] a_lz_w;
    wire a_zero_w;
    wire a_inf_w;
    wire a_nan_w;
    wire a_snan_w;
    assign a_mantissa_w = {|a_i[30:23], a_i[22:0]};
    assign a_zero_w = ~|a_i[30:0];
    assign a_inf_w = (&a_i[30:23]) && !(|a_i[22:0]);
    assign a_nan_w = (&a_i[30:23]) && (|a_i[22:0]);
    assign a_snan_w = a_nan_w && !a_i[22];
    edrv32_cpu2_fpu_lz24 u_lz_a (
        .data_i(a_mantissa_w),
        .count_o(a_lz_w)
    );
    reg [23:0] e1_a_mantissa_r;
    reg [4:0] e1_a_lz_r;
    reg signed [9:0] e1_a_exp_r;
    wire [23:0] b_mantissa_w;
    wire [6:0] b_lz_w;
    wire b_zero_w;
    wire b_inf_w;
    wire b_nan_w;
    wire b_snan_w;
    assign b_mantissa_w = {|b_i[30:23], b_i[22:0]};
    assign b_zero_w = ~|b_i[30:0];
    assign b_inf_w = (&b_i[30:23]) && !(|b_i[22:0]);
    assign b_nan_w = (&b_i[30:23]) && (|b_i[22:0]);
    assign b_snan_w = b_nan_w && !b_i[22];
    edrv32_cpu2_fpu_lz24 u_lz_b (
        .data_i(b_mantissa_w),
        .count_o(b_lz_w)
    );
    reg [23:0] e1_b_mantissa_r;
    reg [4:0] e1_b_lz_r;
    reg signed [9:0] e1_b_exp_r;
    wire [23:0] c_mantissa_w;
    wire [6:0] c_lz_w;
    wire c_zero_w;
    wire c_inf_w;
    wire c_nan_w;
    wire c_snan_w;
    assign c_mantissa_w = {|c_i[30:23], c_i[22:0]};
    assign c_zero_w = ~|c_i[30:0];
    assign c_inf_w = (&c_i[30:23]) && !(|c_i[22:0]);
    assign c_nan_w = (&c_i[30:23]) && (|c_i[22:0]);
    assign c_snan_w = c_nan_w && !c_i[22];
    edrv32_cpu2_fpu_lz24 u_lz_c (
        .data_i(c_mantissa_w),
        .count_o(c_lz_w)
    );
    reg [23:0] e1_c_mantissa_r;
    reg [4:0] e1_c_lz_r;
    reg signed [9:0] e1_c_exp_r;
    wire [6:0] unused_c_trailing_w;
    edrv32_cpu2_fpu_lz24 u_trailing_c (
        .data_i({
            c_mantissa_w[0], c_mantissa_w[1], c_mantissa_w[2], c_mantissa_w[3],
            c_mantissa_w[4], c_mantissa_w[5], c_mantissa_w[6], c_mantissa_w[7],
            c_mantissa_w[8], c_mantissa_w[9], c_mantissa_w[10], c_mantissa_w[11],
            c_mantissa_w[12], c_mantissa_w[13], c_mantissa_w[14], c_mantissa_w[15],
            c_mantissa_w[16], c_mantissa_w[17], c_mantissa_w[18], c_mantissa_w[19],
            c_mantissa_w[20], c_mantissa_w[21], c_mantissa_w[22], c_mantissa_w[23]}),
        .count_o(unused_c_trailing_w)
    );
    reg [4:0] e1_c_trailing_r;
    reg [5:0] e2_c_trailing_r;
    reg [5:0] e3_c_trailing_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[125] && capture_data_w) begin
            e1_c_trailing_r <= unused_c_trailing_w[4:0];
        end
        if (advance_copy_r[121]) begin
            e2_c_trailing_r <= {1'b0, e1_c_trailing_r} + {1'b0, e1_c_lz_r};
            e3_c_trailing_r <= e2_c_trailing_r;
        end
    end
    wire product_sign_w;
    wire c_sign_w;
    wire invalid_product_w;
    wire product_inf_w;
    wire invalid_sum_w;
    wire invalid_w;
    wire nan_w;
    assign product_sign_w = kind_w == 2'd0 ? a_i[31]
        : a_i[31] ^ b_i[31] ^ op_i[1];
    assign c_sign_w = kind_w == 2'd0 ? b_i[31] ^ instr_w[27]
        : (kind_w == 2'd1 ? product_sign_w : c_i[31] ^ op_i[0]);
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

    reg e1_product_sign_r;
    reg e1_c_sign_r;
    reg e1_product_zero_r;
    reg e1_c_zero_r;
    reg [2:0] e1_rm_r;
    reg e1_special_r;
    reg [31:0] e1_special_result_r;
    reg [4:0] e1_special_flags_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[6] && capture_data_w)
            e1_a_mantissa_r[15:0] <= e1_a_mantissa_next_w[15:0];
        if (advance_copy_r[3] && capture_data_w)
            e1_a_mantissa_r[23:16] <= e1_a_mantissa_next_w[23:16];
        if (advance_copy_r[4] && capture_data_w) begin
            e1_a_lz_r <= a_lz_w[4:0];
        end
        if (advance_copy_r[7] && capture_data_w) begin
            e1_a_exp_r <= ($signed({2'b0, a_i[30:23]}) == 10'sd0
                ? -10'sd126 : $signed({2'b0, a_i[30:23]}) - 10'sd127)
                - $signed({3'b0, a_lz_w});
        end
        if (advance_copy_r[8] && capture_data_w)
            e1_b_mantissa_r[15:0] <= e1_b_mantissa_next_w[15:0];
        if (advance_copy_r[9] && capture_data_w)
            e1_b_mantissa_r[23:16] <= e1_b_mantissa_next_w[23:16];
        if (advance_copy_r[7] && capture_data_w) begin
            e1_b_lz_r <= b_lz_w[4:0];
        end
        if (advance_copy_r[10] && capture_data_w) begin
            e1_b_exp_r <= ($signed({2'b0, b_i[30:23]}) == 10'sd0
                ? -10'sd126 : $signed({2'b0, b_i[30:23]}) - 10'sd127)
                - $signed({3'b0, b_lz_w});
        end
        if (advance_copy_r[11] && capture_data_w)
            e1_c_mantissa_r[15:0] <= e1_c_mantissa_next_w[15:0];
        if (advance_copy_r[9] && capture_data_w)
            e1_c_mantissa_r[23:16] <= e1_c_mantissa_next_w[23:16];
        if (advance_copy_r[10] && capture_data_w) begin
            e1_c_lz_r <= c_lz_w[4:0];
        end
        if (advance_copy_r[12] && capture_data_w) begin
            e1_c_exp_r <= ($signed({2'b0, c_i[30:23]}) == 10'sd0
                ? -10'sd126 : $signed({2'b0, c_i[30:23]}) - 10'sd127)
                - $signed({3'b0, c_lz_w});
        end
        if (advance_copy_r[0] && capture_data_w) begin
            e1_product_sign_r <= product_sign_w;
        end
        if (advance_copy_r[0] && capture_data_w) begin
            e1_c_sign_r <= c_sign_w;
        end
        if (advance_copy_r[0] && capture_data_w) begin
            e1_product_zero_r <= a_zero_w || b_zero_w;
        end
        if (advance_copy_r[1] && capture_data_w) begin
            e1_c_zero_r <= c_zero_w;
        end
        if (advance_copy_r[4] && capture_data_w) begin
            e1_rm_r <= rm_i;
        end
        if (advance_copy_r[1] && capture_data_w) begin
            e1_special_r <= nan_w || product_inf_w || addend_inf_w;
        end
        if (advance_copy_r[13] && capture_data_w)
            e1_special_result_r[15:0] <= e1_special_result_next_w[15:0];
        if (advance_copy_r[14] && capture_data_w)
            e1_special_result_r[31:16] <= e1_special_result_next_w[31:16];
        if (advance_copy_r[12] && capture_data_w) begin
            e1_special_flags_r <= {invalid_w, 4'b0};
        end
    end

    wire [23:0] e2_a_w;
    wire [23:0] e2_b_w;
    wire [23:0] e2_c_w;
    wire [47:0] e5_product_w;
    assign e2_a_w = e1_a_mantissa_r << e1_a_lz_r;
    assign e2_b_w = e1_b_mantissa_r << e1_b_lz_r;
    assign e2_c_w = e1_c_mantissa_r << e1_c_lz_r;
    edrv32_apm_cpu2_u24xu24 u_product (
        .clk_i(clk_i),
        .enable_i(advance_copy_r[5:0]),
        .a_i(e2_a_w),
        .b_i(e2_b_w),
        .product_o(e5_product_w)
    );

    // Product has its binary point below bit 48. C can extend 27 bits above it.
    // Larger C makes all product bits sticky; its sign still participates in the add.
    wire signed [9:0] e2_product_exp_w;
    wire signed [9:0] e2_delta_w;
    assign e2_product_exp_w = e1_a_exp_r + e1_b_exp_r;
    assign e2_delta_w = e1_c_exp_r - e2_product_exp_w;
    reg [23:0] e2_c_r;
    reg signed [9:0] e2_delta_r;
    reg e2_far_r;
    reg signed [9:0] e2_base_exp_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[15]) begin
            e2_delta_r <= e2_delta_w;
        end
        if (advance_copy_r[1]) begin
            e2_far_r <= ((e2_delta_w > 10'sd27) || e1_product_zero_r) && !e1_c_zero_r;
        end
        if (advance_copy_r[16]) begin
            e2_base_exp_r <= (((e2_delta_w > 10'sd27) || e1_product_zero_r) && !e1_c_zero_r)
                ? e1_c_exp_r - 10'sd27 : e2_product_exp_w;
        end
        if (advance_copy_r[17]) e2_c_r[15:0] <= e2_c_next_w[15:0];
        if (advance_copy_r[18]) e2_c_r[23:16] <= e2_c_next_w[23:16];
    end
    wire [6:0] e3_c_shift_w;
    wire [6:0] e3_negative_shift_w;
    assign e3_c_shift_w = 7'd25 + e2_delta_r[6:0];
    assign e3_negative_shift_w = -e3_c_shift_w[6:0];
    reg [76:0] e3_c_r;
    reg [6:0] e3_shift_r;
    reg e3_right_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[19]) e3_c_r[15:0] <= e3_c_next_w[15:0];
        if (advance_copy_r[20]) e3_c_r[31:16] <= e3_c_next_w[31:16];
        if (advance_copy_r[21]) e3_c_r[47:32] <= e3_c_next_w[47:32];
        if (advance_copy_r[22]) e3_c_r[63:48] <= e3_c_next_w[63:48];
        if (advance_copy_r[23]) e3_c_r[76:64] <= e3_c_next_w[76:64];
        if (advance_copy_r[7]) begin
            e3_right_r <= (e2_delta_r < -10'sd25) && !e2_product_zero_r;
        end
        if (advance_copy_r[18]) begin
            e3_shift_r <= e2_product_zero_r ? 7'd52
                : e2_delta_r < -10'sd102 ? 7'd77
                : e2_delta_r > 10'sd27 ? 7'd52
                : e2_delta_r < -10'sd25 ? e3_negative_shift_w : e3_c_shift_w[6:0];
        end
    end
    wire [76:0] e4_shift0_w;
    assign e4_shift0_w = !e3_shift_r[0] ? e3_c_r
        : e3_right_r ? (e3_c_r >> 1) : (e3_c_r << 1);
    wire [76:0] e4_shift1_w;
    assign e4_shift1_w = !e3_shift_r[1] ? e4_shift0_w
        : e3_right_r ? (e4_shift0_w >> 2) : (e4_shift0_w << 2);
    wire [76:0] e4_shift2_w;
    assign e4_shift2_w = !e3_shift_r[2] ? e4_shift1_w
        : e3_right_r ? (e4_shift1_w >> 4) : (e4_shift1_w << 4);
    reg [76:0] e4_c_r;
    reg [6:3] e4_shift_r;
    reg e4_right_r;
    reg e4_sticky_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[24]) e4_c_r[15:0] <= e4_c_next_w[15:0];
        if (advance_copy_r[25]) e4_c_r[31:16] <= e4_c_next_w[31:16];
        if (advance_copy_r[26]) e4_c_r[47:32] <= e4_c_next_w[47:32];
        if (advance_copy_r[27]) e4_c_r[63:48] <= e4_c_next_w[63:48];
        if (advance_copy_r[28]) e4_c_r[76:64] <= e4_c_next_w[76:64];
        if (advance_copy_r[15]) begin
            e4_shift_r <= e3_shift_r[6:3];
        end
        if (advance_copy_r[10]) begin
            e4_right_r <= e3_right_r;
        end
        if (advance_copy_r[12]) begin
            e4_sticky_r <= e3_right_r && (e3_shift_r > {1'b0, e3_c_trailing_r})
                && (|e3_c_r);
        end
    end
    wire [76:0] e5_shift3_w;
    assign e5_shift3_w = !e4_shift_r[3] ? e4_c_r
        : e4_right_r ? (e4_c_r >> 8) : (e4_c_r << 8);
    wire [76:0] e5_shift4_w;
    assign e5_shift4_w = !e4_shift_r[4] ? e5_shift3_w
        : e4_right_r ? (e5_shift3_w >> 16) : (e5_shift3_w << 16);
    wire [76:0] e5_shift5_w;
    assign e5_shift5_w = !e4_shift_r[5] ? e5_shift4_w
        : e4_right_r ? (e5_shift4_w >> 32) : (e5_shift4_w << 32);
    wire [76:0] e5_shift6_w;
    assign e5_shift6_w = !e4_shift_r[6] ? e5_shift5_w
        : e4_right_r ? (e5_shift5_w >> 64) : (e5_shift5_w << 64);
    reg [76:0] e5_c_r;
    reg e3_far_r;
    reg e4_far_r;
    reg e5_far_r;
    reg signed [9:0] e3_base_exp_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[15]) begin
            e3_far_r <= e2_far_r;
        end
        if (advance_copy_r[15]) begin
            e4_far_r <= e3_far_r;
        end
        if (advance_copy_r[16]) begin
            e5_far_r <= e4_far_r;
        end
        if (advance_copy_r[29]) begin
            e3_base_exp_r <= e2_base_exp_r;
        end
        if (advance_copy_r[30]) e5_c_r[15:0] <= e5_c_next_w[15:0];
        if (advance_copy_r[31]) e5_c_r[31:16] <= e5_c_next_w[31:16];
        if (advance_copy_r[32]) e5_c_r[47:32] <= e5_c_next_w[47:32];
        if (advance_copy_r[33]) e5_c_r[63:48] <= e5_c_next_w[63:48];
        if (advance_copy_r[34]) e5_c_r[76:64] <= e5_c_next_w[76:64];
    end
    reg e2_product_sign_r;
    reg e2_c_sign_r;
    reg e2_product_zero_r;
    reg [2:0] e2_rm_r;
    reg e2_special_r;
    reg [31:0] e2_special_result_r;
    reg [4:0] e2_special_flags_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[16]) begin
            e2_product_sign_r <= e1_product_sign_r;
        end
        if (advance_copy_r[16]) begin
            e2_c_sign_r <= e1_c_sign_r;
        end
        if (advance_copy_r[16]) begin
            e2_product_zero_r <= e1_product_zero_r;
        end
        if (advance_copy_r[23]) begin
            e2_rm_r <= e1_rm_r;
        end
        if (advance_copy_r[16]) begin
            e2_special_r <= e1_special_r;
        end
        if (advance_copy_r[35]) e2_special_result_r[15:0] <= e2_special_result_next_w[15:0];
        if (advance_copy_r[36]) e2_special_result_r[31:16] <= e2_special_result_next_w[31:16];
        if (advance_copy_r[29]) begin
            e2_special_flags_r <= e1_special_flags_r;
        end
    end
    reg e3_product_sign_r;
    reg e3_c_sign_r;
    reg e3_product_zero_r;
    reg [2:0] e3_rm_r;
    reg e3_special_r;
    reg [31:0] e3_special_result_r;
    reg [4:0] e3_special_flags_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[16]) begin
            e3_product_sign_r <= e2_product_sign_r;
        end
        if (advance_copy_r[18]) begin
            e3_c_sign_r <= e2_c_sign_r;
        end
        if (advance_copy_r[28]) begin
            e3_product_zero_r <= e2_product_zero_r;
        end
        if (advance_copy_r[34]) begin
            e3_rm_r <= e2_rm_r;
        end
        if (advance_copy_r[28]) begin
            e3_special_r <= e2_special_r;
        end
        if (advance_copy_r[37]) e3_special_result_r[15:0] <= e3_special_result_next_w[15:0];
        if (advance_copy_r[38]) e3_special_result_r[31:16] <= e3_special_result_next_w[31:16];
        if (advance_copy_r[39]) begin
            e3_special_flags_r <= e2_special_flags_r;
        end
    end
    reg e4_product_sign_r;
    reg e4_c_sign_r;
    reg e4_product_zero_r;
    reg [2:0] e4_rm_r;
    reg e4_special_r;
    reg [31:0] e4_special_result_r;
    reg [4:0] e4_special_flags_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[28]) begin
            e4_product_sign_r <= e3_product_sign_r;
        end
        if (advance_copy_r[29]) begin
            e4_c_sign_r <= e3_c_sign_r;
        end
        if (advance_copy_r[39]) begin
            e4_product_zero_r <= e3_product_zero_r;
        end
        if (advance_copy_r[39]) begin
            e4_rm_r <= e3_rm_r;
        end
        if (advance_copy_r[39]) begin
            e4_special_r <= e3_special_r;
        end
        if (advance_copy_r[40]) e4_special_result_r[15:0] <= e4_special_result_next_w[15:0];
        if (advance_copy_r[41]) e4_special_result_r[31:16] <= e4_special_result_next_w[31:16];
        if (advance_copy_r[39]) begin
            e4_special_flags_r <= e3_special_flags_r;
        end
    end
    reg e5_product_sign_r;
    reg e5_c_sign_r;
    reg e5_product_zero_r;
    reg [2:0] e5_rm_r;
    reg e5_special_r;
    reg [31:0] e5_special_result_r;
    reg [4:0] e5_special_flags_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[39]) begin
            e5_product_sign_r <= e4_product_sign_r;
        end
        if (advance_copy_r[42]) begin
            e5_c_sign_r <= e4_c_sign_r;
        end
        if (advance_copy_r[42]) begin
            e5_product_zero_r <= e4_product_zero_r;
        end
        if (advance_copy_r[42]) begin
            e5_rm_r <= e4_rm_r;
        end
        if (advance_copy_r[42]) begin
            e5_special_r <= e4_special_r;
        end
        if (advance_copy_r[43]) e5_special_result_r[15:0] <= e5_special_result_next_w[15:0];
        if (advance_copy_r[44]) e5_special_result_r[31:16] <= e5_special_result_next_w[31:16];
        if (advance_copy_r[42]) begin
            e5_special_flags_r <= e4_special_flags_r;
        end
    end

    // Insert the min-normal position into both anticipators before their trees.
    // The first hit then clamps the left shift without a count/compare/barrel chain.
    // Very tiny products use an independently prepared right shift instead.
    wire signed [9:0] e3_limit_w;
    wire [6:0] e3_negative_limit_w;
    assign e3_limit_w = e2_base_exp_r + 10'sd154;
    assign e3_negative_limit_w = -e3_limit_w[6:0];
    reg [6:0] e3_limit_r;
    reg e3_tiny_right_r;
    reg [6:0] e3_tiny_shift_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[45]) begin
            e3_limit_r <= e3_limit_w < 10'sd0 ? 7'd0
                : e3_limit_w > 10'sd76 ? 7'd77 : e3_limit_w[6:0];
        end
        if (advance_copy_r[42]) begin
            e3_tiny_right_r <= e3_limit_w < 10'sd0;
        end
        if (advance_copy_r[45]) begin
            e3_tiny_shift_r <= e3_limit_w < -10'sd77 ? 7'd77 : e3_negative_limit_w;
        end
    end
    reg [76:0] e4_marker_r;
    reg [2:0] e4_limit_r;
    reg [76:0] e5_marker_r;
    reg e4_tiny_right_r;
    reg e5_tiny_right_r;
    reg e6_tiny_right_r;
    reg [6:0] e4_tiny_shift_r;
    reg [6:0] e5_tiny_shift_r;
    reg [6:0] e6_tiny_shift_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[46]) e4_marker_r[15:0] <= e4_marker_next_w[15:0];
        if (advance_copy_r[47]) e4_marker_r[31:16] <= e4_marker_next_w[31:16];
        if (advance_copy_r[48]) e4_marker_r[47:32] <= e4_marker_next_w[47:32];
        if (advance_copy_r[49]) e4_marker_r[63:48] <= e4_marker_next_w[63:48];
        if (advance_copy_r[50]) e4_marker_r[76:64] <= e4_marker_next_w[76:64];
        if (advance_copy_r[42]) begin
            e4_limit_r <= e3_limit_r[2:0];
        end
        if (advance_copy_r[51]) e5_marker_r[15:0] <= e5_marker_next_w[15:0];
        if (advance_copy_r[52]) e5_marker_r[31:16] <= e5_marker_next_w[31:16];
        if (advance_copy_r[53]) e5_marker_r[47:32] <= e5_marker_next_w[47:32];
        if (advance_copy_r[54]) e5_marker_r[63:48] <= e5_marker_next_w[63:48];
        if (advance_copy_r[55]) e5_marker_r[76:64] <= e5_marker_next_w[76:64];
        if (advance_copy_r[42]) begin
            e4_tiny_right_r <= e3_tiny_right_r;
        end
        if (advance_copy_r[45]) begin
            e5_tiny_right_r <= e4_tiny_right_r;
        end
        if (advance_copy_r[56]) begin
            e4_tiny_shift_r <= e3_tiny_shift_r;
        end
        if (advance_copy_r[56]) begin
            e5_tiny_shift_r <= e4_tiny_shift_r;
        end
    end
    wire unused_instr_w;
    assign unused_instr_w = ^{instr_w[31:29], instr_w[26:7], reservation_r[0]};
    reg [3:0] product_valid_r;
    reg [3:0] product_mul_r;
    reg [T-1:0] product_tag_r [0:3];
    reg add_valid_r;
    reg [T-1:0] add_tag_r;
    wire add_kill_w;
    wire product_kill_w;
    assign add_kill_w = cancel_valid_i
        && ((add_tag_r - age_head_i) >= cancel_distance_w);
    assign product_kill_w = cancel_valid_i
        && ((product_tag_r[3] - age_head_i) >= cancel_distance_w);
    integer control_idx;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            product_valid_r <= 4'b0;
            add_valid_r <= 1'b0;
        end else begin
            if (advance_copy_r[122]) begin
                product_valid_r[0] <= dispatch_w && (class_kind_r != 2'd0);
                add_valid_r <= dispatch_w && (class_kind_r == 2'd0);
            end else if (add_kill_w) add_valid_r <= 1'b0;
            if (!advance_copy_r[122] && cancel_valid_i
                && ((product_tag_r[0] - age_head_i) >= cancel_distance_w)) begin
                product_valid_r[0] <= 1'b0;
            end
            for (control_idx = 1; control_idx < 4; control_idx = control_idx + 1) begin
                if (advance_copy_r[122]) begin
                    product_valid_r[control_idx] <= product_valid_r[control_idx-1]
                        && !(cancel_valid_i && ((product_tag_r[control_idx-1]
                            - age_head_i) >= cancel_distance_w));
                end else if (cancel_valid_i
                    && ((product_tag_r[control_idx] - age_head_i) >= cancel_distance_w)) begin
                    product_valid_r[control_idx] <= 1'b0;
                end
            end
        end
    end
    integer product_idx;
    always @(posedge clk_i) begin
        if (advance_copy_r[123]) begin
            product_mul_r <= {product_mul_r[2:0], class_kind_r == 2'd1};
            product_tag_r[0] <= class_tag_r;
            add_tag_r <= class_tag_r;
        end
        if (advance_copy_r[124]) begin
            for (product_idx = 1; product_idx < 4; product_idx = product_idx + 1) begin
                product_tag_r[product_idx] <= product_tag_r[product_idx-1];
            end
        end
    end
    // ADD uses raw significands, exponent ordering and three rounding bits.
    // Deep cancellation is exact; large exponent gaps retain the sticky bit.
    reg [23:0] e1_add_big_r;
    reg [23:0] e1_add_small_r;
    reg [7:0] e1_add_delta_r;
    reg signed [9:0] e1_add_base_r;
    reg e1_add_big_sign_r;
    reg e1_add_small_sign_r;
    wire add_a_big_w;
    wire [7:0] add_a_exp_w;
    wire [7:0] add_b_exp_w;
    assign add_a_big_w = a_i[30:0] >= b_i[30:0];
    assign add_a_exp_w = (|a_i[30:23]) ? a_i[30:23] : 8'd1;
    assign add_b_exp_w = (|b_i[30:23]) ? b_i[30:23] : 8'd1;
    always @(posedge clk_i) begin
        if (advance_copy_r[57] && capture_data_w) e1_add_big_r[15:0] <= e1_add_big_next_w[15:0];
        if (advance_copy_r[58] && capture_data_w) e1_add_big_r[23:16] <= e1_add_big_next_w[23:16];
        if (advance_copy_r[59] && capture_data_w) e1_add_small_r[15:0] <= e1_add_small_next_w[15:0];
        if (advance_copy_r[58] && capture_data_w)
            e1_add_small_r[23:16] <= e1_add_small_next_w[23:16];
        if (advance_copy_r[60] && capture_data_w) begin
            e1_add_delta_r <= add_a_big_w ? add_a_exp_w - add_b_exp_w
                : add_b_exp_w - add_a_exp_w;
        end
        if (advance_copy_r[61] && capture_data_w) begin
            e1_add_base_r <= $signed({2'b0, add_a_big_w ? add_a_exp_w : add_b_exp_w})
                - 10'sd154;
        end
        if (advance_copy_r[45] && capture_data_w) begin
            e1_add_big_sign_r <= add_a_big_w ? product_sign_w : c_sign_w;
        end
        if (advance_copy_r[50] && capture_data_w) begin
            e1_add_small_sign_r <= add_a_big_w ? c_sign_w : product_sign_w;
        end
    end
    wire [26:0] add_small_w;
    wire [26:0] add_shifted_w;
    wire add_sticky_w;
    assign add_small_w = {e1_add_small_r, 3'b0};
    assign add_shifted_w = add_small_w >> e1_add_delta_r;
    assign add_sticky_w = |(add_small_w & ~(27'h7ffffff << e1_add_delta_r));
    reg [76:0] e2_add_big_r;
    reg [76:0] e2_add_small_r;
    reg e2_add_big_sign_r;
    reg e2_add_small_sign_r;
    reg [76:0] e2_add_marker_r;
    reg signed [9:0] e2_add_floor_r;
    wire signed [9:0] add_limit_w;
    assign add_limit_w = e1_add_base_r + 10'sd154;
    always @(posedge clk_i) begin
        if (advance_copy_r[62]) e2_add_big_r[15:0] <= e2_add_big_next_w[15:0];
        if (advance_copy_r[63]) e2_add_big_r[31:16] <= e2_add_big_next_w[31:16];
        if (advance_copy_r[64]) e2_add_big_r[47:32] <= e2_add_big_next_w[47:32];
        if (advance_copy_r[65]) e2_add_big_r[63:48] <= e2_add_big_next_w[63:48];
        if (advance_copy_r[66]) e2_add_big_r[76:64] <= e2_add_big_next_w[76:64];
        if (advance_copy_r[67]) e2_add_small_r[15:0] <= e2_add_small_next_w[15:0];
        if (advance_copy_r[68]) e2_add_small_r[31:16] <= e2_add_small_next_w[31:16];
        if (advance_copy_r[69]) e2_add_small_r[47:32] <= e2_add_small_next_w[47:32];
        if (advance_copy_r[70]) e2_add_small_r[63:48] <= e2_add_small_next_w[63:48];
        if (advance_copy_r[71]) e2_add_small_r[76:64] <= e2_add_small_next_w[76:64];
        if (advance_copy_r[50]) begin
            e2_add_big_sign_r <= e1_add_big_sign_r;
        end
        if (advance_copy_r[50]) begin
            e2_add_small_sign_r <= e1_add_small_sign_r;
        end
        if (advance_copy_r[72]) e2_add_marker_r[15:0] <= e2_add_marker_next_w[15:0];
        if (advance_copy_r[73]) e2_add_marker_r[31:16] <= e2_add_marker_next_w[31:16];
        if (advance_copy_r[74]) e2_add_marker_r[47:32] <= e2_add_marker_next_w[47:32];
        if (advance_copy_r[75]) e2_add_marker_r[63:48] <= e2_add_marker_next_w[63:48];
        if (advance_copy_r[76]) e2_add_marker_r[76:64] <= e2_add_marker_next_w[76:64];
        if (advance_copy_r[77]) begin
            e2_add_floor_r <= add_limit_w;
        end
    end
    reg [8:0] e2_add_bias_minus_r;
    reg [8:0] e4_bias_minus_r;
    reg [8:0] e5_bias_minus_r;
    reg [8:0] e6_bias_minus_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[78]) begin
            e2_add_bias_minus_r <= e1_add_base_r[8:0] + 9'd154;
        end
        if (advance_copy_r[79]) begin
            e4_bias_minus_r <= e3_base_exp_r[8:0] + 9'd154;
        end
        if (advance_copy_r[80]) begin
            e5_bias_minus_r <= e4_bias_minus_r;
        end
        if (advance_copy_r[81]) begin
            e6_bias_minus_r <= add_select_r[17] ? e2_add_bias_minus_r : e5_bias_minus_r;
        end
    end
    reg [8:0] e2_add_bias_base_r;
    reg [8:0] e4_bias_base_r;
    reg [8:0] e5_bias_base_r;
    reg [8:0] e6_bias_base_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[82]) begin
            e2_add_bias_base_r <= e1_add_base_r[8:0] + 9'd155;
        end
        if (advance_copy_r[83]) begin
            e4_bias_base_r <= e3_base_exp_r[8:0] + 9'd155;
        end
        if (advance_copy_r[84]) begin
            e5_bias_base_r <= e4_bias_base_r;
        end
        if (advance_copy_r[85]) begin
            e6_bias_base_r <= add_select_r[18] ? e2_add_bias_base_r : e5_bias_base_r;
        end
    end
    reg [8:0] e2_add_bias_plus_r;
    reg [8:0] e4_bias_plus_r;
    reg [8:0] e5_bias_plus_r;
    reg [8:0] e6_bias_plus_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[86]) begin
            e2_add_bias_plus_r <= e1_add_base_r[8:0] + 9'd156;
        end
        if (advance_copy_r[87]) begin
            e4_bias_plus_r <= e3_base_exp_r[8:0] + 9'd156;
        end
        if (advance_copy_r[88]) begin
            e5_bias_plus_r <= e4_bias_plus_r;
        end
        if (advance_copy_r[89]) begin
            e6_bias_plus_r <= add_select_r[19] ? e2_add_bias_plus_r : e5_bias_plus_r;
        end
    end
    reg [8:0] e2_add_bias_plus2_r;
    reg [8:0] e4_bias_plus2_r;
    reg [8:0] e5_bias_plus2_r;
    reg [8:0] e6_bias_plus2_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[90]) begin
            e2_add_bias_plus2_r <= e1_add_base_r[8:0] + 9'd157;
        end
        if (advance_copy_r[91]) begin
            e4_bias_plus2_r <= e3_base_exp_r[8:0] + 9'd157;
        end
        if (advance_copy_r[92]) begin
            e5_bias_plus2_r <= e4_bias_plus2_r;
        end
        if (advance_copy_r[93]) begin
            e6_bias_plus2_r <= add_select_r[20] ? e2_add_bias_plus2_r : e5_bias_plus2_r;
        end
    end
    reg signed [9:0] e4_floor_threshold_r;
    reg signed [9:0] e5_floor_threshold_r;
    reg signed [9:0] e6_floor_threshold_r;
    wire [76:0] e6_product_w;
    wire [76:0] e6_addend_w;
    wire [76:0] e6_marker_w;
    wire e6_product_sign_w;
    wire e6_c_sign_w;
    wire e6_subtract_w;
    wire [77:0] e6_forward_w;
    wire [76:0] e6_reverse_w;
    wire [76:0] e6_forward_predict_w;
    wire [76:0] e6_reverse_predict_w;
    assign e6_product_w[15:0] = add_select_r[0]
        ? e6_product_w_add_w[15:0] : e6_product_w_fma_w[15:0];
    assign e6_product_w[31:16] = add_select_r[1]
        ? e6_product_w_add_w[31:16] : e6_product_w_fma_w[31:16];
    assign e6_product_w[47:32] = add_select_r[2]
        ? e6_product_w_add_w[47:32] : e6_product_w_fma_w[47:32];
    assign e6_product_w[63:48] = add_select_r[3]
        ? e6_product_w_add_w[63:48] : e6_product_w_fma_w[63:48];
    assign e6_product_w[76:64] = add_select_r[4]
        ? e6_product_w_add_w[76:64] : e6_product_w_fma_w[76:64];
    assign e6_addend_w[15:0] = add_select_r[5]
        ? e6_addend_w_add_w[15:0] : e6_addend_w_fma_w[15:0];
    assign e6_addend_w[31:16] = add_select_r[6]
        ? e6_addend_w_add_w[31:16] : e6_addend_w_fma_w[31:16];
    assign e6_addend_w[47:32] = add_select_r[7]
        ? e6_addend_w_add_w[47:32] : e6_addend_w_fma_w[47:32];
    assign e6_addend_w[63:48] = add_select_r[8]
        ? e6_addend_w_add_w[63:48] : e6_addend_w_fma_w[63:48];
    assign e6_addend_w[76:64] = add_select_r[9]
        ? e6_addend_w_add_w[76:64] : e6_addend_w_fma_w[76:64];
    assign e6_marker_w[15:0] = add_select_r[10]
        ? e6_marker_w_add_w[15:0] : e6_marker_w_fma_w[15:0];
    assign e6_marker_w[31:16] = add_select_r[11]
        ? e6_marker_w_add_w[31:16] : e6_marker_w_fma_w[31:16];
    assign e6_marker_w[47:32] = add_select_r[12]
        ? e6_marker_w_add_w[47:32] : e6_marker_w_fma_w[47:32];
    assign e6_marker_w[63:48] = add_select_r[13]
        ? e6_marker_w_add_w[63:48] : e6_marker_w_fma_w[63:48];
    assign e6_marker_w[76:64] = add_select_r[14]
        ? e6_marker_w_add_w[76:64] : e6_marker_w_fma_w[76:64];
    assign e6_product_sign_w = add_select_r[4] ? e2_add_big_sign_r : e5_product_sign_r;
    assign e6_c_sign_w = add_select_r[4] ? e2_add_small_sign_r : e5_c_sign_r;
    assign e6_subtract_w = e6_product_sign_w ^ e6_c_sign_w;
    assign e6_forward_w = {1'b0, e6_product_w}
        + {1'b0, (e6_addend_w ^ {77{e6_subtract_w}})} + {77'b0, e6_subtract_w};
    assign e6_reverse_w = e6_addend_w - e6_product_w;
    assign e6_forward_predict_w = e6_subtract_w
        ? (e6_product_w ^ e6_addend_w)
            & ~{(~e6_product_w[75:0] & e6_addend_w[75:0]), 1'b0}
        : e6_product_w | e6_addend_w;
    assign e6_reverse_predict_w = (e6_addend_w ^ e6_product_w)
        & ~{(~e6_addend_w[75:0] & e6_product_w[75:0]), 1'b0};
    wire [127:0] e6_forward_padded_w;
    wire [127:0] e6_reverse_padded_w;
    assign e6_forward_padded_w = {(e6_forward_predict_w | e6_marker_w), 51'b0};
    assign e6_reverse_padded_w = {(e6_reverse_predict_w | e6_marker_w), 51'b0};
    wire e6_forward_hit0_w;
    wire [4:0] e6_forward_count0_w;
    reg e6_forward_hit0_r;
    reg [4:0] e6_forward_count0_r;
    edrv32_cpu2_fpu_lza32 u_forward_group0 (
        .data_i(e6_forward_padded_w[127:96]),
        .hit_o(e6_forward_hit0_w),
        .count_o(e6_forward_count0_w)
    );
    always @(posedge clk_i) begin
        if (advance_copy_r[55]) begin
            e6_forward_hit0_r <= e6_forward_hit0_w;
        end
        if (advance_copy_r[60]) begin
            e6_forward_count0_r <= e6_forward_count0_w;
        end
    end
    wire e6_forward_hit1_w;
    wire [4:0] e6_forward_count1_w;
    reg e6_forward_hit1_r;
    reg [4:0] e6_forward_count1_r;
    edrv32_cpu2_fpu_lza32 u_forward_group1 (
        .data_i(e6_forward_padded_w[95:64]),
        .hit_o(e6_forward_hit1_w),
        .count_o(e6_forward_count1_w)
    );
    always @(posedge clk_i) begin
        if (advance_copy_r[55]) begin
            e6_forward_hit1_r <= e6_forward_hit1_w;
        end
        if (advance_copy_r[61]) begin
            e6_forward_count1_r <= e6_forward_count1_w;
        end
    end
    wire e6_forward_hit2_w;
    wire [4:0] e6_forward_count2_w;
    reg e6_forward_hit2_r;
    reg [4:0] e6_forward_count2_r;
    edrv32_cpu2_fpu_lza32 u_forward_group2 (
        .data_i(e6_forward_padded_w[63:32]),
        .hit_o(e6_forward_hit2_w),
        .count_o(e6_forward_count2_w)
    );
    always @(posedge clk_i) begin
        if (advance_copy_r[55]) begin
            e6_forward_hit2_r <= e6_forward_hit2_w;
        end
        if (advance_copy_r[77]) begin
            e6_forward_count2_r <= e6_forward_count2_w;
        end
    end
    wire e6_forward_hit3_w;
    wire [4:0] e6_forward_count3_w;
    reg e6_forward_hit3_r;
    reg [4:0] e6_forward_count3_r;
    edrv32_cpu2_fpu_lza32 u_forward_group3 (
        .data_i(e6_forward_padded_w[31:0]),
        .hit_o(e6_forward_hit3_w),
        .count_o(e6_forward_count3_w)
    );
    always @(posedge clk_i) begin
        if (advance_copy_r[56]) begin
            e6_forward_hit3_r <= e6_forward_hit3_w;
        end
        if (advance_copy_r[78]) begin
            e6_forward_count3_r <= e6_forward_count3_w;
        end
    end
    wire [6:0] e7_forward_count_w;
    assign e7_forward_count_w = e6_forward_hit0_r
        ? {2'b00, e6_forward_count0_r}
        : e6_forward_hit1_r ? {2'b01, e6_forward_count1_r}
        : e6_forward_hit2_r ? {2'b10, e6_forward_count2_r}
        : e6_forward_hit3_r ? {2'b11, e6_forward_count3_r} : 7'd77;
    wire e6_reverse_hit0_w;
    wire [4:0] e6_reverse_count0_w;
    reg e6_reverse_hit0_r;
    reg [4:0] e6_reverse_count0_r;
    edrv32_cpu2_fpu_lza32 u_reverse_group0 (
        .data_i(e6_reverse_padded_w[127:96]),
        .hit_o(e6_reverse_hit0_w),
        .count_o(e6_reverse_count0_w)
    );
    always @(posedge clk_i) begin
        if (advance_copy_r[56]) begin
            e6_reverse_hit0_r <= e6_reverse_hit0_w;
        end
        if (advance_copy_r[79]) begin
            e6_reverse_count0_r <= e6_reverse_count0_w;
        end
    end
    wire e6_reverse_hit1_w;
    wire [4:0] e6_reverse_count1_w;
    reg e6_reverse_hit1_r;
    reg [4:0] e6_reverse_count1_r;
    edrv32_cpu2_fpu_lza32 u_reverse_group1 (
        .data_i(e6_reverse_padded_w[95:64]),
        .hit_o(e6_reverse_hit1_w),
        .count_o(e6_reverse_count1_w)
    );
    always @(posedge clk_i) begin
        if (advance_copy_r[60]) begin
            e6_reverse_hit1_r <= e6_reverse_hit1_w;
        end
        if (advance_copy_r[80]) begin
            e6_reverse_count1_r <= e6_reverse_count1_w;
        end
    end
    wire e6_reverse_hit2_w;
    wire [4:0] e6_reverse_count2_w;
    reg e6_reverse_hit2_r;
    reg [4:0] e6_reverse_count2_r;
    edrv32_cpu2_fpu_lza32 u_reverse_group2 (
        .data_i(e6_reverse_padded_w[63:32]),
        .hit_o(e6_reverse_hit2_w),
        .count_o(e6_reverse_count2_w)
    );
    always @(posedge clk_i) begin
        if (advance_copy_r[60]) begin
            e6_reverse_hit2_r <= e6_reverse_hit2_w;
        end
        if (advance_copy_r[81]) begin
            e6_reverse_count2_r <= e6_reverse_count2_w;
        end
    end
    wire e6_reverse_hit3_w;
    wire [4:0] e6_reverse_count3_w;
    reg e6_reverse_hit3_r;
    reg [4:0] e6_reverse_count3_r;
    edrv32_cpu2_fpu_lza32 u_reverse_group3 (
        .data_i(e6_reverse_padded_w[31:0]),
        .hit_o(e6_reverse_hit3_w),
        .count_o(e6_reverse_count3_w)
    );
    always @(posedge clk_i) begin
        if (advance_copy_r[60]) begin
            e6_reverse_hit3_r <= e6_reverse_hit3_w;
        end
        if (advance_copy_r[82]) begin
            e6_reverse_count3_r <= e6_reverse_count3_w;
        end
    end
    wire [6:0] e7_reverse_count_w;
    assign e7_reverse_count_w = e6_reverse_hit0_r
        ? {2'b00, e6_reverse_count0_r}
        : e6_reverse_hit1_r ? {2'b01, e6_reverse_count1_r}
        : e6_reverse_hit2_r ? {2'b10, e6_reverse_count2_r}
        : e6_reverse_hit3_r ? {2'b11, e6_reverse_count3_r} : 7'd77;
    reg [76:0] e6_forward_r;
    reg [76:0] e6_reverse_r;
    reg e6_reverse_select_r;
    reg e6_product_sign_r;
    reg e6_c_sign_r;
    reg [2:0] e6_rm_r;
    reg e6_special_r;
    reg [31:0] e6_special_result_r;
    reg [4:0] e6_special_flags_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[94]) e6_forward_r[15:0] <= e6_forward_next_w[15:0];
        if (advance_copy_r[95]) e6_forward_r[31:16] <= e6_forward_next_w[31:16];
        if (advance_copy_r[96]) e6_forward_r[47:32] <= e6_forward_next_w[47:32];
        if (advance_copy_r[97]) e6_forward_r[63:48] <= e6_forward_next_w[63:48];
        if (advance_copy_r[98]) e6_forward_r[76:64] <= e6_forward_next_w[76:64];
        if (advance_copy_r[99]) e6_reverse_r[15:0] <= e6_reverse_next_w[15:0];
        if (advance_copy_r[100]) e6_reverse_r[31:16] <= e6_reverse_next_w[31:16];
        if (advance_copy_r[101]) e6_reverse_r[47:32] <= e6_reverse_next_w[47:32];
        if (advance_copy_r[102]) e6_reverse_r[63:48] <= e6_reverse_next_w[63:48];
        if (advance_copy_r[103]) e6_reverse_r[76:64] <= e6_reverse_next_w[76:64];
        if (advance_copy_r[61]) begin
            e6_reverse_select_r <= e6_subtract_w && !e6_forward_w[77];
        end
        if (advance_copy_r[66]) begin
            e6_product_sign_r <= e6_product_sign_w;
        end
        if (advance_copy_r[66]) begin
            e6_c_sign_r <= e6_c_sign_w;
        end
        if (advance_copy_r[104]) begin
            e4_floor_threshold_r <= e3_base_exp_r + 10'sd154;
        end
        if (advance_copy_r[105]) begin
            e5_floor_threshold_r <= e4_floor_threshold_r;
        end
        if (advance_copy_r[106]) begin
            e6_floor_threshold_r <= add_select_r[21] ? e2_add_floor_r : e5_floor_threshold_r;
        end
        if (advance_copy_r[66]) begin
            e6_tiny_right_r <= !add_select_r[14] && e5_tiny_right_r;
        end
        if (advance_copy_r[83]) begin
            e6_tiny_shift_r <= e5_tiny_shift_r;
        end
        if (advance_copy_r[71]) begin
            e6_rm_r <= add_select_r[9] ? e2_rm_r : e5_rm_r;
        end
        if (advance_copy_r[76]) begin
            e6_special_r <= add_select_r[4] ? e2_special_r : e5_special_r;
        end
        if (advance_copy_r[107]) e6_special_result_r[15:0] <= e6_special_result_next_w[15:0];
        if (advance_copy_r[108]) e6_special_result_r[31:16] <= e6_special_result_next_w[31:16];
        if (advance_copy_r[84]) begin
            e6_special_flags_r <= add_select_r[17] ? e2_special_flags_r : e5_special_flags_r;
        end
    end
    reg sum_valid_r;
    reg [T-1:0] sum_tag_r;
    reg norm_valid_r;
    reg [T-1:0] norm_tag_r;
    wire mul_tail_w;
    wire mul_select_w;
    wire sum_in_w;
    wire sum_kill_w;
    wire norm_kill_w;
    assign mul_select_w = product_valid_r[3] && product_mul_r[3];
    assign mul_tail_w = mul_select_w && !product_kill_w;
    assign sum_in_w = (add_valid_r && !add_kill_w)
        || (product_valid_r[3] && !product_mul_r[3] && !product_kill_w);
    assign sum_kill_w = cancel_valid_i
        && ((sum_tag_r - age_head_i) >= cancel_distance_w);
    assign norm_kill_w = cancel_valid_i
        && ((norm_tag_r - age_head_i) >= cancel_distance_w);
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            sum_valid_r <= 1'b0;
            norm_valid_r <= 1'b0;
        end else begin
            if (advance_copy_r[125]) begin
                sum_valid_r <= sum_in_w;
                norm_valid_r <= (sum_valid_r && !sum_kill_w) || mul_tail_w;
            end else begin
                if (sum_kill_w) sum_valid_r <= 1'b0;
                if (norm_kill_w) norm_valid_r <= 1'b0;
            end
        end
    end
    always @(posedge clk_i) begin
        if (advance_copy_r[85]) begin
            sum_tag_r <= add_select_r[18] ? add_tag_r : product_tag_r[3];
        end
        if (advance_copy_r[86]) begin
            norm_tag_r <= mul_tail_w ? product_tag_r[3] : sum_tag_r;
        end
    end
    wire [76:0] e7_magnitude_w;
    wire [6:0] e7_sum_count_w;
    wire [6:0] e7_count_w;
    wire e7_right_w;
    wire [6:0] e7_shift_w;
    wire signed [9:0] e7_floor_threshold_w;
    wire [2:0] e7_rm_w;
    wire e7_sign_w;
    wire e7_zero_sign_w;
    wire [6:0] mul_count_w;
    assign mul_count_w = e5_product_w[47] ? 7'd27 : 7'd28;
    assign e7_magnitude_w = mul_select_w ? {27'b0, e5_product_w, 2'b0}
        : (e6_reverse_select_r ? e6_reverse_r : e6_forward_r);
    assign e7_sum_count_w = e6_reverse_select_r ? e7_reverse_count_w : e7_forward_count_w;
    assign e7_count_w = mul_select_w
        ? (e5_floor_threshold_r < $signed({3'b0, mul_count_w})
            ? (e5_floor_threshold_r < 0 ? 7'd0 : e5_floor_threshold_r[6:0]) : mul_count_w)
        : e7_sum_count_w;
    assign e7_right_w = mul_select_w ? e5_tiny_right_r : e6_tiny_right_r;
    assign e7_shift_w = e7_right_w
        ? (mul_select_w ? e5_tiny_shift_r : e6_tiny_shift_r) : e7_count_w;
    assign e7_floor_threshold_w = mul_select_w ? e5_floor_threshold_r : e6_floor_threshold_r;
    assign e7_rm_w = mul_select_w ? e5_rm_r : e6_rm_r;
    assign e7_sign_w = mul_select_w ? e5_product_sign_r
        : e6_reverse_select_r ? e6_c_sign_r : e6_product_sign_r;
    assign e7_zero_sign_w = mul_select_w ? e5_product_sign_r
        : (e6_product_sign_r == e6_c_sign_r) ? e6_product_sign_r : e6_rm_r == 3'b010;
    // Coarse shift has four mux levels. Both directions share the fine
    // normalization and the three fixed rounding-correction lanes below.
    wire [6:0] e7_coarse_shift_w;
    wire [77:0] e7_coarse_left_w;
    wire [77:0] e7_coarse_right_w;
    wire [76:0] e7_discard_mask_w;
    wire [34:0] e7_coarse_w;
    assign e7_coarse_shift_w = {e7_shift_w[6:3], 3'b0};
    assign e7_coarse_left_w = {1'b0, e7_magnitude_w} << e7_coarse_shift_w;
    assign e7_coarse_right_w = {1'b0, e7_magnitude_w} >> e7_coarse_shift_w;
    assign e7_discard_mask_w = ~(77'h1fffffffffffffffffff << e7_coarse_shift_w);
    assign e7_coarse_w = e7_right_w
        ? {e7_coarse_right_w[77:44], (|e7_coarse_right_w[43:0])
            || (|(e7_magnitude_w & e7_discard_mask_w))}
        : {e7_coarse_left_w[77:44], |e7_coarse_left_w[43:0]};
    reg [77:0] e7_magnitude_r;
    reg e7_floor_r;
    reg e7_sign_r;
    reg e7_zero_sign_r;
    reg e7_special_r;
    reg [31:0] e7_special_result_r;
    reg [4:0] e7_special_flags_r;
    reg e7_nearest_even_r;
    reg e7_nearest_max_r;
    reg e7_directed_r;
    reg e7_overflow_inf_r;
    reg [2:0] e7_fine_shift_r;
    reg e7_fine_right_r;
    always @(posedge clk_i) begin
        if (advance_copy_r[109]) e7_magnitude_r[15:0] <= e7_magnitude_next_w[15:0];
        if (advance_copy_r[110]) e7_magnitude_r[31:16] <= e7_magnitude_next_w[31:16];
        if (advance_copy_r[111]) e7_magnitude_r[47:32] <= e7_magnitude_next_w[47:32];
        if (advance_copy_r[112]) e7_magnitude_r[63:48] <= e7_magnitude_next_w[63:48];
        if (advance_copy_r[113]) e7_magnitude_r[77:64] <= e7_magnitude_next_w[77:64];
        if (advance_copy_r[76]) begin
            e7_floor_r <= $signed({3'b0, e7_count_w}) >= e7_floor_threshold_w;
        end
        if (advance_copy_r[76]) begin
            e7_sign_r <= e7_sign_w;
        end
        if (advance_copy_r[77]) begin
            e7_zero_sign_r <= e7_zero_sign_w;
        end
        if (advance_copy_r[78]) begin
            e7_special_r <= mul_select_w ? e5_special_r : e6_special_r;
        end
        if (advance_copy_r[114]) e7_special_result_r[15:0] <= e7_special_result_next_w[15:0];
        if (advance_copy_r[115]) e7_special_result_r[31:16] <= e7_special_result_next_w[31:16];
        if (advance_copy_r[87]) begin
            e7_special_flags_r <= mul_select_w ? e5_special_flags_r : e6_special_flags_r;
        end
        if (advance_copy_r[78]) begin
            e7_nearest_even_r <= e7_rm_w == 3'b000;
        end
        if (advance_copy_r[79]) begin
            e7_nearest_max_r <= e7_rm_w == 3'b100;
        end
        if (advance_copy_r[79]) begin
            e7_directed_r <= ((e7_rm_w == 3'b010) && e7_sign_w)
                || ((e7_rm_w == 3'b011) && !e7_sign_w);
        end
        if (advance_copy_r[80]) begin
            e7_overflow_inf_r <= (e7_rm_w == 3'b000) || (e7_rm_w == 3'b100)
                || ((e7_rm_w == 3'b010) && e7_sign_w)
                || ((e7_rm_w == 3'b011) && !e7_sign_w);
        end
        if (advance_copy_r[85]) begin
            e7_fine_shift_r <= e7_shift_w[2:0];
        end
        if (advance_copy_r[80]) begin
            e7_fine_right_r <= e7_right_w;
        end
    end
    wire [8:0] e7_bias_minus_w;
    reg [7:0] e7_bias_minus_r;
    reg e7_overflow_minus_r;
    assign e7_bias_minus_w = (mul_select_w ? e5_bias_minus_r : e6_bias_minus_r)
        - {2'b0, e7_count_w};
    always @(posedge clk_i) begin
        if (advance_copy_r[116]) begin
            e7_bias_minus_r <= e7_right_w ? 8'd0
                : e7_bias_minus_w[7:0];
        end
        if (advance_copy_r[81]) begin
            e7_overflow_minus_r <= !e7_right_w && (e7_bias_minus_w > 9'd254);
        end
    end
    wire [8:0] e7_bias_base_w;
    reg [7:0] e7_bias_base_r;
    reg e7_overflow_base_r;
    assign e7_bias_base_w = (mul_select_w ? e5_bias_base_r : e6_bias_base_r)
        - {2'b0, e7_count_w};
    always @(posedge clk_i) begin
        if (advance_copy_r[116]) begin
            e7_bias_base_r <= e7_right_w ? 8'd1
                : e7_bias_base_w[7:0];
        end
        if (advance_copy_r[81]) begin
            e7_overflow_base_r <= !e7_right_w && (e7_bias_base_w > 9'd254);
        end
    end
    wire [8:0] e7_bias_plus_w;
    reg [7:0] e7_bias_plus_r;
    reg e7_overflow_plus_r;
    assign e7_bias_plus_w = (mul_select_w ? e5_bias_plus_r : e6_bias_plus_r)
        - {2'b0, e7_count_w};
    always @(posedge clk_i) begin
        if (advance_copy_r[117]) begin
            e7_bias_plus_r <= e7_right_w ? 8'd2
                : e7_bias_plus_w[7:0];
        end
        if (advance_copy_r[82]) begin
            e7_overflow_plus_r <= !e7_right_w && (e7_bias_plus_w > 9'd254);
        end
    end
    wire [8:0] e7_bias_plus2_w;
    reg [7:0] e7_bias_plus2_r;
    reg e7_overflow_plus2_r;
    assign e7_bias_plus2_w = (mul_select_w ? e5_bias_plus2_r : e6_bias_plus2_r)
        - {2'b0, e7_count_w};
    always @(posedge clk_i) begin
        if (advance_copy_r[117]) begin
            e7_bias_plus2_r <= e7_right_w ? 8'd3
                : e7_bias_plus2_w[7:0];
        end
        if (advance_copy_r[82]) begin
            e7_overflow_plus2_r <= !e7_right_w && (e7_bias_plus2_w > 9'd254);
        end
    end
    wire [77:0] shifted_w;
    // Only 35 high bits survive coarse normalization. A three-level fine barrel
    // replaces sixteen replicated rounding lanes; three LZA correction lanes remain.
    assign shifted_w = e7_fine_right_r ? (e7_magnitude_r >> e7_fine_shift_r)
        : (e7_magnitude_r << e7_fine_shift_r);
    wire correct_up_w;
    wire correct_down_w;
    assign correct_up_w = shifted_w[77];
    assign correct_down_w = !shifted_w[76] && !e7_floor_r;
    wire [110:0] e8_candidates_w;
    genvar correction;
    generate
            for (correction = 0; correction < 3;
                correction = correction + 1) begin : g_correction
                wire [76:0] normal_w;
                wire selected_w;
                if (correction == 0) begin : g_up
                    assign normal_w = {shifted_w[77:2], |shifted_w[1:0]};
                    assign selected_w = correct_up_w;
                end else if (correction == 1) begin : g_down
                    assign normal_w = {shifted_w[75:0], 1'b0};
                    assign selected_w = !correct_up_w && correct_down_w;
                end else begin : g_base
                    assign normal_w = shifted_w[76:0];
                    assign selected_w = !correct_up_w && !correct_down_w;
                end
                wire inexact_w;
                wire increment_w;
                wire [22:0] incremented_w;
                wire carry_w;
                wire [22:0] rounded_w;
                wire [7:0] bias_w;
                wire overflow_w;
                wire subnormal_w;
                wire [7:0] exp_field_w;
                wire [22:0] fraction_w;
                wire [31:0] result_w;
                wire [4:0] flags_w;
                assign inexact_w = |normal_w[52:0];
                assign increment_w = (e7_nearest_even_r && normal_w[52]
                        && ((|normal_w[51:0]) || normal_w[53]))
                    || (e7_directed_r && inexact_w)
                    || (e7_nearest_max_r && normal_w[52]);
                assign incremented_w = normal_w[75:53] + 23'd1;
                assign rounded_w = increment_w ? incremented_w : normal_w[75:53];
                // Predict the two exponent transitions independently of the adder.
                assign carry_w = (&normal_w[76:53]) && increment_w;
                assign subnormal_w = !normal_w[76]
                    && !((&normal_w[75:53]) && increment_w);
                if (correction == 0) begin : g_up_exp
                    assign bias_w = carry_w ? e7_bias_plus2_r : e7_bias_plus_r;
                    assign overflow_w = carry_w ? e7_overflow_plus2_r : e7_overflow_plus_r;
                end else if (correction == 1) begin : g_down_exp
                    assign bias_w = carry_w ? e7_bias_base_r : e7_bias_minus_r;
                    assign overflow_w = carry_w ? e7_overflow_base_r : e7_overflow_minus_r;
                end else begin : g_base_exp
                    assign bias_w = carry_w ? e7_bias_plus_r : e7_bias_base_r;
                    assign overflow_w = carry_w ? e7_overflow_plus_r : e7_overflow_base_r;
                end
                assign exp_field_w = subnormal_w ? 8'b0 : bias_w[7:0];
                assign fraction_w = carry_w ? 23'b0 : rounded_w[22:0];
                assign result_w = overflow_w
                    ? {e7_sign_r, e7_overflow_inf_r ? 31'h7f800000 : 31'h7f7fffff}
                    : {!(|normal_w) ? e7_zero_sign_r : e7_sign_r, exp_field_w, fraction_w};
                assign flags_w = {2'b00, overflow_w,
                    inexact_w && !overflow_w && subnormal_w, inexact_w || overflow_w};
                assign e8_candidates_w[correction*37 +: 37]
                    = {37{selected_w}}
                    & {result_w, flags_w};
            end
    endgenerate
    wire [36:0] e8_selected_w;
    assign e8_selected_w = e8_candidates_w[0 +: 37]
        | e8_candidates_w[37 +: 37] | e8_candidates_w[74 +: 37];
    wire enqueue_w;
    wire [T-1:0] enqueue_tag_w;
    wire [31:0] enqueue_data_w;
    wire [4:0] enqueue_flags_w;
    wire enqueue_int_dest_w;
    assign enqueue_w = advance_w && norm_valid_r && !norm_kill_w;
    assign enqueue_tag_w = norm_tag_r;
    assign enqueue_data_w = e7_special_r ? e7_special_result_r : e8_selected_w[36:5];
    assign enqueue_flags_w = e7_special_r ? e7_special_flags_r : e8_selected_w[4:0];
    assign enqueue_int_dest_w = 1'b0;
    reg advance_r;
    assign advance_w = advance_r;
    reg [1:0] skid_valid_r;
    reg [T-1:0] skid_tag_r [0:1];
    reg [31:0] skid_data_r [0:1];
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
    // Same-edge regional clock-enable leaves. Each leaf drives at most 16
    // data FF enables (APM leaves drive 13 macro CE pins). PDS must retain these
    // copies; no extra clock or pipeline latency is introduced.
    (* keep = "true", syn_preserve = 1 *) reg [125:0] advance_copy_r;
    // Region 0: at most 15 enable leaves, each with <=16 sinks.
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity_count0_r;
    wire capacity_keep0_0_w;
    wire capacity_keep1_0_w;
    wire [1:0] capacity_next0_w;
    assign capacity_keep0_0_w = (capacity_count0_r != 2'd0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w));
    assign capacity_keep1_0_w = (capacity_count0_r == 2'd2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w));
    assign capacity_next0_w = {1'b0, capacity_keep0_0_w}
        + {1'b0, capacity_keep1_0_w} + {1'b0, enqueue_w};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            capacity_count0_r <= 2'b0;
        end else begin
            capacity_count0_r <= next_count_w;
        end
    end
    // Region 1: at most 16 enable leaves, each with <=16 sinks.
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity_count1_r;
    wire capacity_keep0_1_w;
    wire capacity_keep1_1_w;
    wire [1:0] capacity_next1_w;
    assign capacity_keep0_1_w = (capacity_count1_r != 2'd0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w));
    assign capacity_keep1_1_w = (capacity_count1_r == 2'd2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w));
    assign capacity_next1_w = {1'b0, capacity_keep0_1_w}
        + {1'b0, capacity_keep1_1_w} + {1'b0, enqueue_w};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            capacity_count1_r <= 2'b0;
        end else begin
            capacity_count1_r <= next_count_w;
        end
    end
    // Region 2: at most 16 enable leaves, each with <=16 sinks.
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity_count2_r;
    wire capacity_keep0_2_w;
    wire capacity_keep1_2_w;
    wire [1:0] capacity_next2_w;
    assign capacity_keep0_2_w = (capacity_count2_r != 2'd0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w));
    assign capacity_keep1_2_w = (capacity_count2_r == 2'd2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w));
    assign capacity_next2_w = {1'b0, capacity_keep0_2_w}
        + {1'b0, capacity_keep1_2_w} + {1'b0, enqueue_w};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            capacity_count2_r <= 2'b0;
        end else begin
            capacity_count2_r <= next_count_w;
        end
    end
    // Region 3: at most 16 enable leaves, each with <=16 sinks.
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity_count3_r;
    wire capacity_keep0_3_w;
    wire capacity_keep1_3_w;
    wire [1:0] capacity_next3_w;
    assign capacity_keep0_3_w = (capacity_count3_r != 2'd0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w));
    assign capacity_keep1_3_w = (capacity_count3_r == 2'd2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w));
    assign capacity_next3_w = {1'b0, capacity_keep0_3_w}
        + {1'b0, capacity_keep1_3_w} + {1'b0, enqueue_w};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            capacity_count3_r <= 2'b0;
        end else begin
            capacity_count3_r <= next_count_w;
        end
    end
    // Region 4: at most 15 enable leaves, each with <=16 sinks.
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity_count4_r;
    wire capacity_keep0_4_w;
    wire capacity_keep1_4_w;
    wire [1:0] capacity_next4_w;
    assign capacity_keep0_4_w = (capacity_count4_r != 2'd0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w));
    assign capacity_keep1_4_w = (capacity_count4_r == 2'd2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w));
    assign capacity_next4_w = {1'b0, capacity_keep0_4_w}
        + {1'b0, capacity_keep1_4_w} + {1'b0, enqueue_w};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            capacity_count4_r <= 2'b0;
        end else begin
            capacity_count4_r <= next_count_w;
        end
    end
    // Region 5: at most 16 enable leaves, each with <=16 sinks.
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity_count5_r;
    wire capacity_keep0_5_w;
    wire capacity_keep1_5_w;
    wire [1:0] capacity_next5_w;
    assign capacity_keep0_5_w = (capacity_count5_r != 2'd0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w));
    assign capacity_keep1_5_w = (capacity_count5_r == 2'd2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w));
    assign capacity_next5_w = {1'b0, capacity_keep0_5_w}
        + {1'b0, capacity_keep1_5_w} + {1'b0, enqueue_w};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            capacity_count5_r <= 2'b0;
        end else begin
            capacity_count5_r <= next_count_w;
        end
    end
    // Region 6: at most 16 enable leaves, each with <=16 sinks.
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity_count6_r;
    wire capacity_keep0_6_w;
    wire capacity_keep1_6_w;
    wire [1:0] capacity_next6_w;
    assign capacity_keep0_6_w = (capacity_count6_r != 2'd0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w));
    assign capacity_keep1_6_w = (capacity_count6_r == 2'd2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w));
    assign capacity_next6_w = {1'b0, capacity_keep0_6_w}
        + {1'b0, capacity_keep1_6_w} + {1'b0, enqueue_w};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            capacity_count6_r <= 2'b0;
        end else begin
            capacity_count6_r <= next_count_w;
        end
    end
    // Region 7: at most 16 enable leaves, each with <=16 sinks.
    (* keep = "true", syn_preserve = 1 *) reg [1:0] capacity_count7_r;
    wire capacity_keep0_7_w;
    wire capacity_keep1_7_w;
    wire [1:0] capacity_next7_w;
    assign capacity_keep0_7_w = (capacity_count7_r != 2'd0) && !unit_resp_ready_i
        && !(cancel_valid_i && ((skid_tag_r[0] - age_head_i) >= cancel_distance_w));
    assign capacity_keep1_7_w = (capacity_count7_r == 2'd2)
        && !(cancel_valid_i && ((skid_tag_r[1] - age_head_i) >= cancel_distance_w));
    assign capacity_next7_w = {1'b0, capacity_keep0_7_w}
        + {1'b0, capacity_keep1_7_w} + {1'b0, enqueue_w};
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            capacity_count7_r <= 2'b0;
        end else begin
            capacity_count7_r <= next_count_w;
        end
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            advance_copy_r <= {126{1'b1}};
        end else begin
            advance_copy_r[14:0] <= {15{capacity_next0_w < 2'd2}};
            advance_copy_r[30:15] <= {16{capacity_next1_w < 2'd2}};
            advance_copy_r[46:31] <= {16{capacity_next2_w < 2'd2}};
            advance_copy_r[62:47] <= {16{capacity_next3_w < 2'd2}};
            advance_copy_r[77:63] <= {15{capacity_next4_w < 2'd2}};
            advance_copy_r[93:78] <= {16{capacity_next5_w < 2'd2}};
            advance_copy_r[109:94] <= {16{capacity_next6_w < 2'd2}};
            advance_copy_r[125:110] <= {16{capacity_next7_w < 2'd2}};
        end
    end
    wire [23:0] e1_a_mantissa_next_w;
    assign e1_a_mantissa_next_w = a_mantissa_w;
    wire [23:0] e1_b_mantissa_next_w;
    assign e1_b_mantissa_next_w = b_mantissa_w;
    wire [23:0] e1_c_mantissa_next_w;
    assign e1_c_mantissa_next_w = c_mantissa_w;
    wire [31:0] e1_special_result_next_w;
    assign e1_special_result_next_w = nan_w ? 32'h7fc00000
                : {product_inf_w ? product_sign_w : c_sign_w, 8'hff, 23'b0};
    wire [23:0] e2_c_next_w;
    assign e2_c_next_w = e2_c_w;
    wire [76:0] e3_c_next_w;
    assign e3_c_next_w = {53'b0, e2_c_r};
    wire [76:0] e4_c_next_w;
    assign e4_c_next_w = e4_shift2_w;
    wire [76:0] e5_c_next_w;
    assign e5_c_next_w = {e5_shift6_w[76:1], e5_shift6_w[0] | e4_sticky_r};
    wire [31:0] e2_special_result_next_w;
    assign e2_special_result_next_w = e1_special_result_r;
    wire [31:0] e3_special_result_next_w;
    assign e3_special_result_next_w = e2_special_result_r;
    wire [31:0] e4_special_result_next_w;
    assign e4_special_result_next_w = e3_special_result_r;
    wire [31:0] e5_special_result_next_w;
    assign e5_special_result_next_w = e4_special_result_r;
    wire [76:0] e4_marker_next_w;
    assign e4_marker_next_w = (77'b1 << 76) >> {e3_limit_r[6:3], 3'b0};
    wire [76:0] e5_marker_next_w;
    assign e5_marker_next_w = e4_marker_r >> e4_limit_r;
    wire [23:0] e1_add_big_next_w;
    assign e1_add_big_next_w = add_a_big_w ? a_mantissa_w : b_mantissa_w;
    wire [23:0] e1_add_small_next_w;
    assign e1_add_small_next_w = add_a_big_w ? b_mantissa_w : a_mantissa_w;
    wire [76:0] e2_add_big_next_w;
    assign e2_add_big_next_w = {1'b0, e1_add_big_r, 3'b0, 49'b0};
    wire [76:0] e2_add_small_next_w;
    assign e2_add_small_next_w = {1'b0, add_shifted_w[26:1],
                add_shifted_w[0] || add_sticky_w, 49'b0};
    wire [76:0] e2_add_marker_next_w;
    assign e2_add_marker_next_w = (77'b1 << 76)
                >> (add_limit_w > 10'sd76 ? 7'd77 : add_limit_w[6:0]);
    wire [76:0] e6_forward_next_w;
    assign e6_forward_next_w = e6_forward_w[76:0];
    wire [76:0] e6_reverse_next_w;
    assign e6_reverse_next_w = e6_reverse_w;
    wire [31:0] e6_special_result_next_w;
    assign e6_special_result_next_w[15:0] = add_select_r[15]
        ? e6_special_result_next_w_add_w[15:0] : e6_special_result_next_w_fma_w[15:0];
    assign e6_special_result_next_w[31:16] = add_select_r[16]
        ? e6_special_result_next_w_add_w[31:16] : e6_special_result_next_w_fma_w[31:16];
    wire [77:0] e7_magnitude_next_w;
    assign e7_magnitude_next_w = {e7_coarse_w, 43'b0};
    wire [31:0] e7_special_result_next_w;
    assign e7_special_result_next_w = mul_select_w ? e5_special_result_r : e6_special_result_r;
    // ADD/FMA join selection is replicated with a 16-data-bit budget per leaf.
    (* keep = "true", syn_preserve = 1 *) reg [21:0] add_select_r;
    // Seven same-edge class roots feed 3/4 ADD-selection leaves apiece.
    (* keep = "true", syn_preserve = 1 *) reg [6:0] add_class_valid_r;
    (* keep = "true", syn_preserve = 1 *) reg [6:0] add_class_kind_r;
    wire [21:0] add_select_next_w;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) add_class_valid_r <= 7'b0;
        else add_class_valid_r <= {7{class_next_w}};
    end
    always @(posedge clk_i) begin
        if (advance_copy_r[119] && capture_data_w) begin
            add_class_kind_r <= {7{kind_w == 2'd0}};
        end
        if (advance_copy_r[118]) add_select_r[15:0] <= add_select_next_w[15:0];
        if (advance_copy_r[119]) add_select_r[21:16] <= add_select_next_w[21:16];
    end
    assign add_select_next_w[0] = add_class_valid_r[0]
        && add_class_kind_r[0] && !reservation_r[2];
    assign add_select_next_w[1] = add_class_valid_r[1]
        && add_class_kind_r[1] && !reservation_r[2];
    assign add_select_next_w[2] = add_class_valid_r[2]
        && add_class_kind_r[2] && !reservation_r[2];
    assign add_select_next_w[3] = add_class_valid_r[3]
        && add_class_kind_r[3] && !reservation_r[2];
    assign add_select_next_w[4] = add_class_valid_r[4]
        && add_class_kind_r[4] && !reservation_r[2];
    assign add_select_next_w[5] = add_class_valid_r[5]
        && add_class_kind_r[5] && !reservation_r[2];
    assign add_select_next_w[6] = add_class_valid_r[6]
        && add_class_kind_r[6] && !reservation_r[2];
    assign add_select_next_w[7] = add_class_valid_r[0]
        && add_class_kind_r[0] && !reservation_r[2];
    assign add_select_next_w[8] = add_class_valid_r[1]
        && add_class_kind_r[1] && !reservation_r[2];
    assign add_select_next_w[9] = add_class_valid_r[2]
        && add_class_kind_r[2] && !reservation_r[2];
    assign add_select_next_w[10] = add_class_valid_r[3]
        && add_class_kind_r[3] && !reservation_r[2];
    assign add_select_next_w[11] = add_class_valid_r[4]
        && add_class_kind_r[4] && !reservation_r[2];
    assign add_select_next_w[12] = add_class_valid_r[5]
        && add_class_kind_r[5] && !reservation_r[2];
    assign add_select_next_w[13] = add_class_valid_r[6]
        && add_class_kind_r[6] && !reservation_r[2];
    assign add_select_next_w[14] = add_class_valid_r[0]
        && add_class_kind_r[0] && !reservation_r[2];
    assign add_select_next_w[15] = add_class_valid_r[1]
        && add_class_kind_r[1] && !reservation_r[2];
    assign add_select_next_w[16] = add_class_valid_r[2]
        && add_class_kind_r[2] && !reservation_r[2];
    assign add_select_next_w[17] = add_class_valid_r[3]
        && add_class_kind_r[3] && !reservation_r[2];
    assign add_select_next_w[18] = add_class_valid_r[4]
        && add_class_kind_r[4] && !reservation_r[2];
    assign add_select_next_w[19] = add_class_valid_r[5]
        && add_class_kind_r[5] && !reservation_r[2];
    assign add_select_next_w[20] = add_class_valid_r[6]
        && add_class_kind_r[6] && !reservation_r[2];
    assign add_select_next_w[21] = add_class_valid_r[0]
        && add_class_kind_r[0] && !reservation_r[2];
    wire [76:0] e6_product_w_add_w;
    wire [76:0] e6_product_w_fma_w;
    assign e6_product_w_add_w = e2_add_big_r;
    assign e6_product_w_fma_w = e5_far_r
        ? {76'b0, !e5_product_zero_r} : {27'b0, e5_product_w, 2'b0};
    wire [76:0] e6_addend_w_add_w;
    wire [76:0] e6_addend_w_fma_w;
    assign e6_addend_w_add_w = e2_add_small_r;
    assign e6_addend_w_fma_w = e5_c_r;
    wire [76:0] e6_marker_w_add_w;
    wire [76:0] e6_marker_w_fma_w;
    assign e6_marker_w_add_w = e2_add_marker_r;
    assign e6_marker_w_fma_w = e5_marker_r;
    wire [31:0] e6_special_result_next_w_add_w;
    wire [31:0] e6_special_result_next_w_fma_w;
    assign e6_special_result_next_w_add_w = e2_special_result_r;
    assign e6_special_result_next_w_fma_w = e5_special_result_r;
endmodule
