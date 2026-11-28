// File: edrv32_cpu2_fpu_convert.v
// Spec: fpu-spec 2.1-2.4, 3.1, 5.3-5.4.
// Description: Single/double-precision convert unit with local completion and age cancellation.
// Clock domain: clk_sys.
module edrv32_cpu2_fpu_convert #(
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
    input wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] unit_req_src1_i,
    input wire [31:0] unit_req_int_src_i,
    input wire [2:0] unit_req_rm_i,

    // Local completion, held through arbitration backpressure.
    output wire unit_resp_valid_o,
    input wire unit_resp_ready_i,
    output wire [(FPU_FORMAT == "FD" ? 4 : 3)-1:0] unit_resp_tag_o,
    output wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] unit_resp_data_o,
    output wire [4:0] unit_resp_flags_o,
    output wire unit_resp_int_dest_o,

    // Head-relative inclusive cancellation.
    input wire [(FPU_FORMAT == "FD" ? 4 : 3)-1:0] age_head_i,
    input wire cancel_valid_i,
    input wire [(FPU_FORMAT == "FD" ? 4 : 3)-1:0] cancel_tag_i
);
    localparam B = FPU_FORMAT == "FD" ? 64 : 32;
    localparam T = FPU_FORMAT == "FD" ? 4 : 3;
    wire to_float_w;
    wire unsigned_w;
    wire fast_w;
    wire sign_w;
    wire [31:0] integer_magnitude_w;
    assign to_float_w = unit_req_instr_i[28];
    assign unsigned_w = unit_req_instr_i[20];
    assign fast_w = unit_req_instr_i[29];
    assign sign_w = to_float_w ? (!unsigned_w && unit_req_int_src_i[31])
        : unit_req_src1_i[31];
    assign integer_magnitude_w = sign_w ? -unit_req_int_src_i : unit_req_int_src_i;
    reg e1_to_float_r;
    reg e1_fast_r;
    reg [31:0] e1_move_r;
    reg e1_unsigned_r;
    reg e1_sign_r;
    reg [2:0] e1_rm_r;
    reg [31:0] e1_magnitude_r;
    reg [23:0] e1_fraction_r;
    reg [7:0] e1_exp_r;
    reg e1_nan_r;
    reg e1_int_dest_r;
        wire [0:0] partition78_w;
    assign partition78_w = to_float_w;
    wire [0:0] partition79_w;
    assign partition79_w = fast_w;
    wire [15:0] partition80_w;
    assign partition80_w = e1_move_next_w[15:0];
    wire [15:0] partition81_w;
    assign partition81_w = e1_move_next_w[31:16];
    wire [0:0] partition82_w;
    assign partition82_w = unsigned_w;
    wire [0:0] partition83_w;
    assign partition83_w = sign_w;
    wire [2:0] partition84_w;
    assign partition84_w = unit_req_rm_i;
    wire [15:0] partition85_w;
    assign partition85_w = e1_magnitude_next_w[15:0];
    wire [15:0] partition86_w;
    assign partition86_w = e1_magnitude_next_w[31:16];
    wire [15:0] partition87_w;
    assign partition87_w = e1_fraction_next_w[15:0];
    wire [7:0] partition88_w;
    assign partition88_w = e1_fraction_next_w[23:16];
    wire [7:0] partition89_w;
    assign partition89_w = unit_req_src1_i[30:23];
    wire [0:0] partition90_w;
    assign partition90_w = (&unit_req_src1_i[30:23]) && (|unit_req_src1_i[22:0]);
    wire [0:0] partition91_w;
    assign partition91_w = !to_float_w && unit_req_instr_i[31:27] != 5'b01000;
    always @(posedge clk_i) begin
        begin
            if (advance_copy_r[78]) e1_to_float_r <= partition78_w[0:0];
        end
        begin
            if (advance_copy_r[79]) e1_fast_r <= partition79_w[0:0];
        end
        if (advance_copy_r[80]) e1_move_r[15:0] <= partition80_w[15:0];
        if (advance_copy_r[81]) e1_move_r[31:16] <= partition81_w[15:0];
        begin
            if (advance_copy_r[82]) e1_unsigned_r <= partition82_w[0:0];
        end
        begin
            if (advance_copy_r[83]) e1_sign_r <= partition83_w[0:0];
        end
        begin
            if (advance_copy_r[84]) e1_rm_r[2:0] <= partition84_w[2:0];
        end
        if (advance_copy_r[85]) e1_magnitude_r[15:0] <= partition85_w[15:0];
        if (advance_copy_r[86]) e1_magnitude_r[31:16] <= partition86_w[15:0];
        if (advance_copy_r[87]) e1_fraction_r[15:0] <= partition87_w[15:0];
        if (advance_copy_r[88]) e1_fraction_r[23:16] <= partition88_w[7:0];
        begin
            if (advance_copy_r[89]) e1_exp_r[7:0] <= partition89_w[7:0];
        end
        begin
            if (advance_copy_r[90]) e1_nan_r <= partition90_w[0:0];
        end
        begin
            if (advance_copy_r[91]) e1_int_dest_r <= partition91_w[0:0];
        end
    end
    wire magnitude_hit_w;
    wire [4:0] magnitude_lz_w;
    wire [31:0] aligned_w;
    edrv32_cpu2_fpu_lza32 u_integer_lz (
        .data_i(e1_magnitude_r),
        .hit_o(magnitude_hit_w),
        .count_o(magnitude_lz_w)
    );
    assign aligned_w = e1_magnitude_r << magnitude_lz_w;
    wire [7:0] right_shift_w;
    wire [7:0] left_shift_w;
    wire [56:0] shifted_right_w;
    wire [32:0] shifted_left_w;
    assign right_shift_w = 8'd150 - e1_exp_r;
    assign left_shift_w = e1_exp_r - 8'd150;
    // Appending 33 zeros gives guard/sticky for every finite integer conversion.
    assign shifted_right_w = {e1_fraction_r, 33'b0} >> right_shift_w;
    assign shifted_left_w = {9'b0, e1_fraction_r} << left_shift_w;
    reg e2_to_float_r;
    reg e2_fast_r;
    reg [31:0] e2_move_r;
    reg e2_unsigned_r;
    reg e2_sign_r;
    reg [2:0] e2_rm_r;
    reg [32:0] e2_integer_r;
    reg [22:0] e2_fraction_r;
    reg [7:0] e2_bias_r;
    reg e2_guard_r;
    reg e2_sticky_r;
    reg e2_large_r;
    reg e2_nan_r;
    reg e2_zero_r;
    reg e2_int_dest_r;
        wire [0:0] partition59_w;
    assign partition59_w = e1_to_float_r;
    wire [0:0] partition60_w;
    assign partition60_w = e1_fast_r;
    wire [15:0] partition61_w;
    assign partition61_w = e2_move_next_w[15:0];
    wire [15:0] partition62_w;
    assign partition62_w = e2_move_next_w[31:16];
    wire [0:0] partition63_w;
    assign partition63_w = e1_unsigned_r;
    wire [0:0] partition64_w;
    assign partition64_w = e1_sign_r;
    wire [2:0] partition65_w;
    assign partition65_w = e1_rm_r;
    wire [15:0] partition66_w;
    assign partition66_w = e2_integer_next_w[15:0];
    wire [15:0] partition67_w;
    assign partition67_w = e2_integer_next_w[31:16];
    wire [0:0] partition68_w;
    assign partition68_w = e2_integer_next_w[32:32];
    wire [15:0] partition69_w;
    assign partition69_w = e2_fraction_next_w[15:0];
    wire [6:0] partition70_w;
    assign partition70_w = e2_fraction_next_w[22:16];
    wire [7:0] partition71_w;
    assign partition71_w = 8'd158 - {3'b0, magnitude_lz_w};
    wire [0:0] partition72_w;
    assign partition72_w = e1_to_float_r ? aligned_w[7]
                : (e1_exp_r < 8'd150 && shifted_right_w[32]);
    wire [0:0] partition73_w;
    assign partition73_w = e1_to_float_r ? (|aligned_w[6:0])
                : (e1_exp_r < 8'd150 && ((|shifted_right_w[31:0])
                    || ((right_shift_w > 8'd33) && (|e1_fraction_r))));
    wire [0:0] partition74_w;
    assign partition74_w = e1_exp_r > 8'd158;
    wire [0:0] partition75_w;
    assign partition75_w = e1_nan_r;
    wire [0:0] partition76_w;
    assign partition76_w = !magnitude_hit_w;
    wire [0:0] partition77_w;
    assign partition77_w = e1_int_dest_r;
    always @(posedge clk_i) begin
        begin
            if (advance_copy_r[59]) e2_to_float_r <= partition59_w[0:0];
        end
        begin
            if (advance_copy_r[60]) e2_fast_r <= partition60_w[0:0];
        end
        if (advance_copy_r[61]) e2_move_r[15:0] <= partition61_w[15:0];
        if (advance_copy_r[62]) e2_move_r[31:16] <= partition62_w[15:0];
        begin
            if (advance_copy_r[63]) e2_unsigned_r <= partition63_w[0:0];
        end
        begin
            if (advance_copy_r[64]) e2_sign_r <= partition64_w[0:0];
        end
        begin
            if (advance_copy_r[65]) e2_rm_r[2:0] <= partition65_w[2:0];
        end
        if (advance_copy_r[66]) e2_integer_r[15:0] <= partition66_w[15:0];
        if (advance_copy_r[67]) e2_integer_r[31:16] <= partition67_w[15:0];
        if (advance_copy_r[68]) e2_integer_r[32:32] <= partition68_w[0:0];
        if (advance_copy_r[69]) e2_fraction_r[15:0] <= partition69_w[15:0];
        if (advance_copy_r[70]) e2_fraction_r[22:16] <= partition70_w[6:0];
        begin
            if (advance_copy_r[71]) e2_bias_r[7:0] <= partition71_w[7:0];
        end
        begin
            if (advance_copy_r[72]) e2_guard_r <= partition72_w[0:0];
        end
        begin
            if (advance_copy_r[73]) e2_sticky_r <= partition73_w[0:0];
        end
        begin
            if (advance_copy_r[74]) e2_large_r <= partition74_w[0:0];
        end
        begin
            if (advance_copy_r[75]) e2_nan_r <= partition75_w[0:0];
        end
        begin
            if (advance_copy_r[76]) e2_zero_r <= partition76_w[0:0];
        end
        begin
            if (advance_copy_r[77]) e2_int_dest_r <= partition77_w[0:0];
        end
    end
    wire inexact_w;
    wire increment_w;
    wire [33:0] integer_rounded_w;
    wire [23:0] float_rounded_w;
    wire invalid_w;
    wire [31:0] saturated_w;
    wire [31:0] converted_w;
    wire [4:0] converted_flags_w;
    assign inexact_w = e2_guard_r || e2_sticky_r;
    assign increment_w = ((e2_rm_r == 3'b000) && e2_guard_r
            && (e2_sticky_r || (e2_to_float_r ? e2_fraction_r[0] : e2_integer_r[0])))
        || ((e2_rm_r == 3'b100) && e2_guard_r)
        || ((e2_rm_r == 3'b010) && e2_sign_r && inexact_w)
        || ((e2_rm_r == 3'b011) && !e2_sign_r && inexact_w);
    assign integer_rounded_w = {1'b0, e2_integer_r} + {33'b0, increment_w};
    assign float_rounded_w = {1'b0, e2_fraction_r} + {23'b0, increment_w};
    assign invalid_w = e2_large_r || (e2_unsigned_r
        ? (integer_rounded_w[33:32] != 2'b0) || (e2_sign_r && (|integer_rounded_w))
        : (integer_rounded_w > (e2_sign_r ? 34'h080000000 : 34'h07fffffff)));
    assign saturated_w = e2_unsigned_r
        ? ((e2_nan_r || !e2_sign_r) ? 32'hffffffff : 32'b0)
        : ((e2_nan_r || !e2_sign_r) ? 32'h7fffffff : 32'h80000000);
    assign converted_w = e2_to_float_r
        ? (e2_zero_r ? 32'b0 : {e2_sign_r,
            (e2_bias_r + {7'b0, float_rounded_w[23]}), float_rounded_w[22:0]})
        : (invalid_w ? saturated_w : (e2_sign_r
            ? -integer_rounded_w[31:0] : integer_rounded_w[31:0]));
    assign converted_flags_w = (!e2_to_float_r && invalid_w)
        ? 5'b10000 : {4'b0, inexact_w};
    wire [63:0] double_data_w;
    wire [4:0] double_flags_w;
    wire [63:0] precision_data_w;
    wire [4:0] precision_flags_w;
    reg e1_double_r;
    reg e2_double_r;
    reg e1_precision_r;
    reg e2_precision_r;
        wire [0:0] partition55_w;
    assign partition55_w = unit_req_instr_i[25];
    wire [0:0] partition56_w;
    assign partition56_w = e1_double_r;
    wire [0:0] partition57_w;
    assign partition57_w = unit_req_instr_i[31:27] == 5'b01000;
    wire [0:0] partition58_w;
    assign partition58_w = e1_precision_r;
    always @(posedge clk_i) begin
        begin
            if (advance_copy_r[55]) e1_double_r <= partition55_w[0:0];
            if (advance_copy_r[56]) e2_double_r <= partition56_w[0:0];
            if (advance_copy_r[57]) e1_precision_r <= partition57_w[0:0];
            if (advance_copy_r[58]) e2_precision_r <= partition58_w[0:0];
        end
    end
    wire [B-1:0] selected_data_w;
    wire [4:0] selected_flags_w;
    generate
        if (FPU_FORMAT == "FD") begin : g_double
            wire [31:0] precision_e2_special_data_chunks_w;
            assign precision_e2_special_data_chunks_w = precision_e1_nan_r ? 32'h7fc00000
                        : {precision_e1_sign_r,8'hff,23'b0};

            wire [23:0] precision_e2_retained_chunks_w;
            assign precision_e2_retained_chunks_w = precision_shifted_w[26:3];

            wire [63:0] precision_e2_exact_chunks_w;
            assign precision_e2_exact_chunks_w = precision_e1_nan_r ? 64'h7ff8000000000000
                        : precision_e1_inf_r ? {precision_e1_sign_r,11'h7ff,52'b0}
                        : !(|precision_normal_w) ? {precision_e1_sign_r,63'b0}
                        : {precision_e1_sign_r,precision_bias_w[10:0],precision_normal_w[51:0]};

            wire [52:0] precision_e1_mantissa_chunks_w;
            assign precision_e1_mantissa_chunks_w = precision_mantissa_w;

            wire [51:0] double_e2_fraction_chunks_w;
            assign double_e2_fraction_chunks_w = double_e2_fraction_next_w;

            wire [52:0] double_e1_fraction_chunks_w;
            assign double_e1_fraction_chunks_w = double_e1_fraction_next_w;

            wire double_to_float_w;
            wire double_unsigned_w;
            wire double_sign_w;
            wire [31:0] double_integer_magnitude_w;
            assign double_to_float_w = unit_req_instr_i[28];
            assign double_unsigned_w = unit_req_instr_i[20];
            assign double_sign_w = double_to_float_w ? (!double_unsigned_w &&
        unit_req_int_src_i[31])
                : unit_req_src1_i[63];
            assign double_integer_magnitude_w = double_sign_w ? -unit_req_int_src_i :
        unit_req_int_src_i;
            reg double_e1_to_float_r;
            reg double_e1_unsigned_r;
            reg double_e1_sign_r;
            reg [2:0] double_e1_rm_r;
            reg [31:0] double_e1_magnitude_r;
            reg [52:0] double_e1_fraction_r;
            reg [10:0] double_e1_exp_r;
            reg double_e1_nan_r;
                wire [0:0] partition43_w;
    assign partition43_w = double_to_float_w;
    wire [0:0] partition44_w;
    assign partition44_w = double_unsigned_w;
    wire [0:0] partition45_w;
    assign partition45_w = double_sign_w;
    wire [2:0] partition46_w;
    assign partition46_w = unit_req_rm_i;
    wire [15:0] partition47_w;
    assign partition47_w = double_e1_magnitude_next_w[15:0];
    wire [15:0] partition48_w;
    assign partition48_w = double_e1_magnitude_next_w[31:16];
    wire [15:0] partition49_w;
    assign partition49_w = double_e1_fraction_chunks_w[15:0];
    wire [15:0] partition50_w;
    assign partition50_w = double_e1_fraction_chunks_w[31:16];
    wire [15:0] partition51_w;
    assign partition51_w = double_e1_fraction_chunks_w[47:32];
    wire [4:0] partition52_w;
    assign partition52_w = double_e1_fraction_chunks_w[52:48];
    wire [10:0] partition53_w;
    assign partition53_w = unit_req_src1_i[62:52];
    wire [0:0] partition54_w;
    assign partition54_w = (&unit_req_src1_i[62:52]) && (|unit_req_src1_i[51:0]);
    always @(posedge clk_i) begin
                begin
                    if (advance_copy_r[43]) double_e1_to_float_r <= partition43_w[0:0];
                end
                begin
                    if (advance_copy_r[44]) double_e1_unsigned_r <= partition44_w[0:0];
                end
                begin
                    if (advance_copy_r[45]) double_e1_sign_r <= partition45_w[0:0];
                end
                begin
                    if (advance_copy_r[46]) double_e1_rm_r[2:0] <= partition46_w[2:0];
                end
                if (advance_copy_r[47]) double_e1_magnitude_r[15:0] <= partition47_w[15:0];
                if (advance_copy_r[48]) double_e1_magnitude_r[31:16] <= partition48_w[15:0];
                if (advance_copy_r[49]) double_e1_fraction_r[15:0] <= partition49_w[15:0];
                if (advance_copy_r[50]) double_e1_fraction_r[31:16] <= partition50_w[15:0];
                if (advance_copy_r[51]) double_e1_fraction_r[47:32] <= partition51_w[15:0];
                if (advance_copy_r[52]) double_e1_fraction_r[52:48] <= partition52_w[4:0];
                begin
                    if (advance_copy_r[53]) double_e1_exp_r[10:0] <= partition53_w[10:0];
                end
                begin
                    if (advance_copy_r[54]) double_e1_nan_r <= partition54_w[0:0];
                end
            end
            wire double_magnitude_hit_w;
            wire [4:0] double_magnitude_lz_w;
            wire [31:0] double_aligned_w;
            edrv32_cpu2_fpu_lza32 u_integer_lz (
                .data_i(double_e1_magnitude_r),
                .hit_o(double_magnitude_hit_w),
                .count_o(double_magnitude_lz_w)
            );
            assign double_aligned_w = double_e1_magnitude_r << double_magnitude_lz_w;
            wire [10:0] double_right_shift_w;
            wire [10:0] double_left_shift_w;
            wire [85:0] double_shifted_right_w;
            wire double_shift_lost_w;
            assign double_shift_lost_w = |({double_e1_fraction_r,33'b0}
                & ~({86{1'b1}} << double_right_shift_w));
            wire [32:0] double_shifted_left_w;
            assign double_right_shift_w = 11'd1075 - double_e1_exp_r;
            assign double_left_shift_w = double_e1_exp_r - 11'd1075;
            // Appending 33 zeros gives guard/sticky for every finite integer conversion.
            assign double_shifted_right_w = {double_e1_fraction_r, 33'b0} >> double_right_shift_w;
            assign double_shifted_left_w = double_e1_fraction_r[32:0] << double_left_shift_w;
            reg double_e2_to_float_r;
            reg double_e2_unsigned_r;
            reg double_e2_sign_r;
            reg [2:0] double_e2_rm_r;
            reg [32:0] double_e2_integer_r;
            reg [51:0] double_e2_fraction_r;
            reg [10:0] double_e2_bias_r;
            reg double_e2_guard_r;
            reg double_e2_sticky_r;
            reg double_e2_large_r;
            reg double_e2_nan_r;
            reg double_e2_zero_r;
                wire [0:0] partition26_w;
    assign partition26_w = double_e1_to_float_r;
    wire [0:0] partition27_w;
    assign partition27_w = double_e1_unsigned_r;
    wire [0:0] partition28_w;
    assign partition28_w = double_e1_sign_r;
    wire [2:0] partition29_w;
    assign partition29_w = double_e1_rm_r;
    wire [15:0] partition30_w;
    assign partition30_w = double_e2_integer_next_w[15:0];
    wire [15:0] partition31_w;
    assign partition31_w = double_e2_integer_next_w[31:16];
    wire [0:0] partition32_w;
    assign partition32_w = double_e2_integer_next_w[32:32];
    wire [15:0] partition33_w;
    assign partition33_w = double_e2_fraction_chunks_w[15:0];
    wire [15:0] partition34_w;
    assign partition34_w = double_e2_fraction_chunks_w[31:16];
    wire [15:0] partition35_w;
    assign partition35_w = double_e2_fraction_chunks_w[47:32];
    wire [3:0] partition36_w;
    assign partition36_w = double_e2_fraction_chunks_w[51:48];
    wire [10:0] partition37_w;
    assign partition37_w = 11'd1054 - {6'b0, double_magnitude_lz_w};
    wire [0:0] partition38_w;
    assign partition38_w = double_e1_to_float_r ? 1'b0
                        : (double_e1_exp_r < 11'd1075 && double_shifted_right_w[32]);
    wire [0:0] partition39_w;
    assign partition39_w = double_e1_to_float_r ? 1'b0
                        : (double_e1_exp_r < 11'd1075 && ((|double_shifted_right_w[31:0])
                            || double_shift_lost_w));
    wire [0:0] partition40_w;
    assign partition40_w = double_e1_exp_r > 11'd1054;
    wire [0:0] partition41_w;
    assign partition41_w = double_e1_nan_r;
    wire [0:0] partition42_w;
    assign partition42_w = !double_magnitude_hit_w;
    always @(posedge clk_i) begin
                begin
                    if (advance_copy_r[26]) double_e2_to_float_r <= partition26_w[0:0];
                end
                begin
                    if (advance_copy_r[27]) double_e2_unsigned_r <= partition27_w[0:0];
                end
                begin
                    if (advance_copy_r[28]) double_e2_sign_r <= partition28_w[0:0];
                end
                begin
                    if (advance_copy_r[29]) double_e2_rm_r[2:0] <= partition29_w[2:0];
                end
                if (advance_copy_r[30]) double_e2_integer_r[15:0] <= partition30_w[15:0];
                if (advance_copy_r[31]) double_e2_integer_r[31:16] <= partition31_w[15:0];
                if (advance_copy_r[32]) double_e2_integer_r[32:32] <= partition32_w[0:0];
                if (advance_copy_r[33]) double_e2_fraction_r[15:0] <= partition33_w[15:0];
                if (advance_copy_r[34]) double_e2_fraction_r[31:16] <= partition34_w[15:0];
                if (advance_copy_r[35]) double_e2_fraction_r[47:32] <= partition35_w[15:0];
                if (advance_copy_r[36]) double_e2_fraction_r[51:48] <= partition36_w[3:0];
                begin
                    if (advance_copy_r[37]) double_e2_bias_r[10:0] <= partition37_w[10:0];
                end
                begin
                    if (advance_copy_r[38]) double_e2_guard_r <= partition38_w[0:0];
                end
                begin
                    if (advance_copy_r[39]) double_e2_sticky_r <= partition39_w[0:0];
                end
                begin
                    if (advance_copy_r[40]) double_e2_large_r <= partition40_w[0:0];
                end
                begin
                    if (advance_copy_r[41]) double_e2_nan_r <= partition41_w[0:0];
                end
                begin
                    if (advance_copy_r[42]) double_e2_zero_r <= partition42_w[0:0];
                end
            end
            wire double_inexact_w;
            wire double_increment_w;
            wire [33:0] double_integer_rounded_w;
            wire [52:0] double_float_rounded_w;
            wire double_invalid_w;
            wire [31:0] double_saturated_w;
            wire [63:0] double_converted_w;
            wire [4:0] double_converted_flags_w;
            assign double_inexact_w = double_e2_guard_r || double_e2_sticky_r;
            assign double_increment_w = ((double_e2_rm_r == 3'b000) && double_e2_guard_r
                    && (double_e2_sticky_r || (double_e2_to_float_r ? double_e2_fraction_r[0] :
        double_e2_integer_r[0])))
                || ((double_e2_rm_r == 3'b100) && double_e2_guard_r)
                || ((double_e2_rm_r == 3'b010) && double_e2_sign_r && double_inexact_w)
                || ((double_e2_rm_r == 3'b011) && !double_e2_sign_r && double_inexact_w);
            assign double_integer_rounded_w = {1'b0, double_e2_integer_r} + {33'b0,
        double_increment_w};
            assign double_float_rounded_w = {1'b0, double_e2_fraction_r} + {52'b0,
        double_increment_w};
            assign double_invalid_w = double_e2_large_r || (double_e2_unsigned_r
                ? (double_integer_rounded_w[33:32] != 2'b0) || (double_e2_sign_r &&
        (|double_integer_rounded_w))
                : (double_integer_rounded_w > (double_e2_sign_r ? 34'h080000000 : 34'h07fffffff)));
            assign double_saturated_w = double_e2_unsigned_r
                ? ((double_e2_nan_r || !double_e2_sign_r) ? 32'hffffffff : 32'b0)
                : ((double_e2_nan_r || !double_e2_sign_r) ? 32'h7fffffff : 32'h80000000);
            assign double_converted_w = double_e2_to_float_r
                ? (double_e2_zero_r ? 64'b0 : {double_e2_sign_r,
                    (double_e2_bias_r + {10'b0, double_float_rounded_w[52]}),
        double_float_rounded_w[51:0]})
                : {32'b0,(double_invalid_w ? double_saturated_w : (double_e2_sign_r
                    ? -double_integer_rounded_w[31:0] : double_integer_rounded_w[31:0]))};
            assign double_converted_flags_w = (!double_e2_to_float_r && double_invalid_w)
                ? 5'b10000 : {4'b0, double_inexact_w};
            wire [31:0] double_e1_magnitude_next_w;
            assign double_e1_magnitude_next_w = double_integer_magnitude_w;
            wire [52:0] double_e1_fraction_next_w;
            assign double_e1_fraction_next_w = {|unit_req_src1_i[62:52], unit_req_src1_i[51:0]};
            wire [32:0] double_e2_integer_next_w;
            assign double_e2_integer_next_w = double_e1_exp_r >= 11'd1075 ? double_shifted_left_w
                        : double_shifted_right_w[65:33];
            wire [51:0] double_e2_fraction_next_w;
            assign double_e2_fraction_next_w = {double_aligned_w[30:0],21'b0};
            assign double_data_w = double_converted_w;
            assign double_flags_w = double_converted_flags_w;
            wire unused_double_w;
            assign unused_double_w = ^{double_aligned_w[31],double_shifted_right_w[85:66],
                precision_shifted_w[55:27],precision_bias_w[12:11]};
            // Precision conversions share the third-edge rounding/completion slot.
            wire precision_to_d_w;
            wire [52:0] precision_mantissa_w;
            wire [5:0] precision_lz_w;
            wire precision_sign_w;
            assign precision_to_d_w = unit_req_instr_i[25];
            assign precision_sign_w = precision_to_d_w ? unit_req_src1_i[31]
                : unit_req_src1_i[63];
            assign precision_mantissa_w = precision_to_d_w
                ? {|unit_req_src1_i[30:23],unit_req_src1_i[22:0],29'b0}
                : {|unit_req_src1_i[62:52],unit_req_src1_i[51:0]};
            edrv32_cpu2_fpu_fma64_lz53 u_precision_lz (
                .data_i(precision_mantissa_w),
                .count_o(precision_lz_w)
            );
            reg precision_e1_to_d_r;
            reg precision_e1_sign_r;
            reg [52:0] precision_e1_mantissa_r;
            reg [5:0] precision_e1_lz_r;
            reg signed [12:0] precision_e1_exp_r;
            reg precision_e1_nan_r;
            reg precision_e1_snan_r;
            reg precision_e1_inf_r;
                wire [0:0] partition15_w;
    assign partition15_w = precision_to_d_w;
    wire [0:0] partition16_w;
    assign partition16_w = precision_sign_w;
    wire [15:0] partition17_w;
    assign partition17_w = precision_e1_mantissa_chunks_w[15:0];
    wire [15:0] partition18_w;
    assign partition18_w = precision_e1_mantissa_chunks_w[31:16];
    wire [15:0] partition19_w;
    assign partition19_w = precision_e1_mantissa_chunks_w[47:32];
    wire [4:0] partition20_w;
    assign partition20_w = precision_e1_mantissa_chunks_w[52:48];
    wire [5:0] partition21_w;
    assign partition21_w = precision_lz_w;
    wire [12:0] partition22_w;
    assign partition22_w = (precision_to_d_w
                        ? ((|unit_req_src1_i[30:23])
                            ? $signed({5'b0,unit_req_src1_i[30:23]}) - 13'sd127
                            : -13'sd126)
                        : ((|unit_req_src1_i[62:52])
                            ? $signed({2'b0,unit_req_src1_i[62:52]}) - 13'sd1023
                            : -13'sd1022)) - $signed({7'b0,precision_lz_w});
    wire [0:0] partition23_w;
    assign partition23_w = precision_to_d_w
                        ? (&unit_req_src1_i[30:23]) && (|unit_req_src1_i[22:0])
                        : (&unit_req_src1_i[62:52]) && (|unit_req_src1_i[51:0]);
    wire [0:0] partition24_w;
    assign partition24_w = precision_to_d_w
                        ? (&unit_req_src1_i[30:23]) && (|unit_req_src1_i[22:0])
                            && !unit_req_src1_i[22]
                        : (&unit_req_src1_i[62:52]) && (|unit_req_src1_i[51:0])
                            && !unit_req_src1_i[51];
    wire [0:0] partition25_w;
    assign partition25_w = precision_to_d_w
                        ? (&unit_req_src1_i[30:23]) && !(|unit_req_src1_i[22:0])
                        : (&unit_req_src1_i[62:52]) && !(|unit_req_src1_i[51:0]);
    always @(posedge clk_i) begin
                begin
                    if (advance_copy_r[15]) precision_e1_to_d_r <= partition15_w[0:0];
                    if (advance_copy_r[16]) precision_e1_sign_r <= partition16_w[0:0];
                if (advance_copy_r[17]) precision_e1_mantissa_r[15:0] <= partition17_w[15:0];
                if (advance_copy_r[18]) precision_e1_mantissa_r[31:16] <= partition18_w[15:0];
                if (advance_copy_r[19]) precision_e1_mantissa_r[47:32] <= partition19_w[15:0];
                if (advance_copy_r[20]) precision_e1_mantissa_r[52:48] <= partition20_w[4:0];
                    if (advance_copy_r[21]) precision_e1_lz_r[5:0] <= partition21_w[5:0];
                    if (advance_copy_r[22]) precision_e1_exp_r[12:0] <= partition22_w[12:0];
                    if (advance_copy_r[23]) precision_e1_nan_r <= partition23_w[0:0];
                    if (advance_copy_r[24]) precision_e1_snan_r <= partition24_w[0:0];
                    if (advance_copy_r[25]) precision_e1_inf_r <= partition25_w[0:0];
                end
            end
            wire [52:0] precision_normal_w;
            wire signed [12:0] precision_tiny_w;
            wire [7:0] precision_shift_w;
            wire [55:0] precision_source_w;
            wire [55:0] precision_shifted_w;
            wire precision_lost_w;
            wire signed [12:0] precision_bias_w;
            assign precision_normal_w = precision_e1_mantissa_r << precision_e1_lz_r;
            assign precision_tiny_w = -13'sd126 - precision_e1_exp_r;
            assign precision_shift_w = precision_tiny_w > 13'sd27 ? 8'd56
                : precision_tiny_w > 0 ? 8'd29 + precision_tiny_w[7:0] : 8'd29;
            assign precision_source_w = {precision_normal_w,3'b0};
            assign precision_shifted_w = precision_source_w >> precision_shift_w;
            assign precision_lost_w = |(precision_source_w
                & ~(56'hffffffffffffff << precision_shift_w));
            assign precision_bias_w = precision_e1_exp_r + 13'sd1023;
            reg [63:0] precision_e2_exact_r;
            reg [23:0] precision_e2_retained_r;
            reg precision_e2_guard_r;
            reg precision_e2_sticky_r;
            reg signed [12:0] precision_e2_bias_r;
            reg precision_e2_sign_r;
            reg precision_e2_to_d_r;
            reg precision_e2_special_r;
            reg [31:0] precision_e2_special_data_r;
            reg [4:0] precision_e2_flags_r;
                wire [15:0] partition0_w;
    assign partition0_w = precision_e2_exact_chunks_w[15:0];
    wire [15:0] partition1_w;
    assign partition1_w = precision_e2_exact_chunks_w[31:16];
    wire [15:0] partition2_w;
    assign partition2_w = precision_e2_exact_chunks_w[47:32];
    wire [15:0] partition3_w;
    assign partition3_w = precision_e2_exact_chunks_w[63:48];
    wire [15:0] partition4_w;
    assign partition4_w = precision_e2_retained_chunks_w[15:0];
    wire [7:0] partition5_w;
    assign partition5_w = precision_e2_retained_chunks_w[23:16];
    wire [0:0] partition6_w;
    assign partition6_w = precision_shifted_w[2];
    wire [0:0] partition7_w;
    assign partition7_w = (|precision_shifted_w[1:0]) || precision_lost_w;
    wire [12:0] partition8_w;
    assign partition8_w = precision_tiny_w > 0 ? 13'sd1
                        : precision_e1_exp_r + 13'sd127;
    wire [0:0] partition9_w;
    assign partition9_w = precision_e1_sign_r;
    wire [0:0] partition10_w;
    assign partition10_w = precision_e1_to_d_r;
    wire [0:0] partition11_w;
    assign partition11_w = precision_e1_nan_r || precision_e1_inf_r;
    wire [15:0] partition12_w;
    assign partition12_w = precision_e2_special_data_chunks_w[15:0];
    wire [15:0] partition13_w;
    assign partition13_w = precision_e2_special_data_chunks_w[31:16];
    wire [4:0] partition14_w;
    assign partition14_w = {precision_e1_snan_r,4'b0};
    always @(posedge clk_i) begin
                begin
                if (advance_copy_r[0]) precision_e2_exact_r[15:0] <= partition0_w[15:0];
                if (advance_copy_r[1]) precision_e2_exact_r[31:16] <= partition1_w[15:0];
                if (advance_copy_r[2]) precision_e2_exact_r[47:32] <= partition2_w[15:0];
                if (advance_copy_r[3]) precision_e2_exact_r[63:48] <= partition3_w[15:0];
                if (advance_copy_r[4]) precision_e2_retained_r[15:0] <= partition4_w[15:0];
                if (advance_copy_r[5]) precision_e2_retained_r[23:16] <= partition5_w[7:0];
                    if (advance_copy_r[6]) precision_e2_guard_r <= partition6_w[0:0];
                    if (advance_copy_r[7]) precision_e2_sticky_r <= partition7_w[0:0];
                    if (advance_copy_r[8]) precision_e2_bias_r[12:0] <= partition8_w[12:0];
                    if (advance_copy_r[9]) precision_e2_sign_r <= partition9_w[0:0];
                    if (advance_copy_r[10]) precision_e2_to_d_r <= partition10_w[0:0];
                    if (advance_copy_r[11]) precision_e2_special_r <= partition11_w[0:0];
                if (advance_copy_r[12]) precision_e2_special_data_r[15:0] <= partition12_w[15:0];
                if (advance_copy_r[13]) precision_e2_special_data_r[31:16] <= partition13_w[15:0];
                    if (advance_copy_r[14]) precision_e2_flags_r[4:0] <= partition14_w[4:0];
                end
            end
            wire precision_inexact_w;
            wire precision_increment_w;
            wire [24:0] precision_rounded_w;
            wire precision_carry_w;
            wire precision_subnormal_w;
            wire precision_overflow_w;
            wire precision_overflow_inf_w;
            wire [7:0] precision_exponent_w;
            wire [31:0] precision_narrow_w;
            assign precision_inexact_w = precision_e2_guard_r || precision_e2_sticky_r;
            assign precision_increment_w = (e2_rm_r == 3'b000 && precision_e2_guard_r
                    && (precision_e2_sticky_r || precision_e2_retained_r[0]))
                || (e2_rm_r == 3'b100 && precision_e2_guard_r)
                || (e2_rm_r == 3'b010 && precision_e2_sign_r && precision_inexact_w)
                || (e2_rm_r == 3'b011 && !precision_e2_sign_r && precision_inexact_w);
            assign precision_rounded_w = {1'b0,precision_e2_retained_r}
                + {24'b0,precision_increment_w};
            assign precision_carry_w = precision_rounded_w[24];
            assign precision_subnormal_w = !precision_rounded_w[24] && !precision_rounded_w[23];
            assign precision_overflow_w = precision_e2_bias_r >= 13'sd255
                || ((precision_e2_bias_r == 13'sd254) && precision_carry_w);
            assign precision_overflow_inf_w = e2_rm_r == 0 || e2_rm_r == 4
                || (e2_rm_r == 2 && precision_e2_sign_r)
                || (e2_rm_r == 3 && !precision_e2_sign_r);
            assign precision_exponent_w = precision_subnormal_w ? 8'b0
                : precision_e2_bias_r[7:0] + {7'b0,precision_carry_w};
            assign precision_narrow_w = precision_e2_special_r ? precision_e2_special_data_r
                : precision_overflow_w ? {precision_e2_sign_r,
                    precision_overflow_inf_w ? 31'h7f800000 : 31'h7f7fffff}
                : {precision_e2_sign_r,precision_exponent_w,
                    precision_carry_w ? 23'b0 : precision_rounded_w[22:0]};
            assign precision_data_w = precision_e2_to_d_r ? precision_e2_exact_r
                : {32'hffffffff,precision_narrow_w};
            assign precision_flags_w = precision_e2_to_d_r || precision_e2_special_r
                ? precision_e2_flags_r
                : {2'b0,precision_overflow_w,
                    precision_subnormal_w && precision_inexact_w && !precision_overflow_w,
                    precision_inexact_w || precision_overflow_w};
            assign selected_data_w = e2_precision_r ? precision_data_w
                : e2_double_r ? double_data_w
                : {e2_int_dest_r ? 32'b0 : 32'hffffffff,converted_w};
            assign selected_flags_w = e2_precision_r ? precision_flags_w
                : e2_double_r ? double_flags_w : converted_flags_w;
        end else begin : g_single
            assign double_data_w = 64'b0;
            assign double_flags_w = 5'b0;
            assign precision_data_w = 64'b0;
            assign precision_flags_w = 5'b0;
            assign selected_data_w = converted_w;
            assign selected_flags_w = converted_flags_w;
        end
    endgenerate
    // One outstanding result per pipeline position; a two-entry completion skid
    // absorbs the final enabled edge before registered backpressure stops APMs.
    reg [1:0] valid_r;
    reg [T-1:0] tag_r [0:1];
    reg advance_r;
    wire accept_w;
    wire [T-1:0] cancel_distance_w;
    wire [T-1:0] req_distance_w;
    wire pending_w;
    wire pending_kill_w;
    wire enqueue_w;
    wire [T-1:0] enqueue_tag_w;
    wire [B-1:0] enqueue_data_w;
    wire [4:0] enqueue_flags_w;
    wire enqueue_int_dest_w;
    assign cancel_distance_w = cancel_tag_i - age_head_i;
    assign req_distance_w = unit_req_tag_i - age_head_i;
    assign pending_w = valid_r[1];
    assign pending_kill_w = cancel_valid_i
        && ((tag_r[1] - age_head_i) >= cancel_distance_w);
    assign unit_req_ready_o = advance_r;
    assign accept_w = unit_req_valid_i && unit_req_ready_o
        && !(cancel_valid_i && (req_distance_w >= cancel_distance_w));
    assign enqueue_w = advance_r && ((pending_w && !pending_kill_w)
        || (accept_w && fast_w && !pending_w));
    assign enqueue_tag_w = pending_w ? tag_r[1] : unit_req_tag_i;
    integer stage_idx;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            valid_r <= 0;
        end else begin
            if (advance_r) begin
                valid_r[0] <= accept_w && (!fast_w || pending_w);
            end else if (cancel_valid_i
                && ((tag_r[0] - age_head_i) >= cancel_distance_w)) begin
                valid_r[0] <= 1'b0;
            end
            for (stage_idx = 1; stage_idx < 2; stage_idx = stage_idx + 1) begin
                if (advance_r) begin
                    valid_r[stage_idx] <= valid_r[stage_idx-1]
                        && !(cancel_valid_i
                            && ((tag_r[stage_idx-1] - age_head_i) >= cancel_distance_w));
                end else if (cancel_valid_i
                    && ((tag_r[stage_idx] - age_head_i) >= cancel_distance_w)) begin
                    valid_r[stage_idx] <= 1'b0;
                end
            end
        end
    end
    integer tag_idx;
    always @(posedge clk_i) begin
        if (advance_copy_r[92]) begin
            tag_r[0] <= unit_req_tag_i;
            for (tag_idx = 1; tag_idx < 2; tag_idx = tag_idx + 1) begin
                tag_r[tag_idx] <= tag_r[tag_idx-1];
            end
        end
    end
    reg [1:0] skid_valid_r;
    reg [T-1:0] skid_tag_r [0:1];
    reg [B-1:0] skid_data_r [0:1];
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
    assign enqueue_data_w = pending_w ? (e2_fast_r ? {{(B-32){!e2_int_dest_r}},e2_move_r} :
        selected_data_w)
        : {{(B-32){to_float_w}},(to_float_w ? unit_req_int_src_i : unit_req_src1_i[31:0])};
    assign enqueue_flags_w = pending_w && !e2_fast_r ? selected_flags_w : 5'b0;
    assign enqueue_int_dest_w = pending_w ? e2_int_dest_r : !to_float_w;
    wire unused_instr_w;
    assign unused_instr_w =
        ^{advance_copy_r,double_data_w,double_flags_w,precision_data_w,precision_flags_w,
        e2_double_r,e2_precision_r,unit_req_instr_i[31:30], unit_req_instr_i[27:21],
        unit_req_instr_i[19:0], aligned_w[31]};
    // Same-edge regional clock-enable leaves. Each leaf drives at most 16
    // data FF enables (APM leaves drive 13 macro CE pins). PDS must retain these
    // copies; no extra clock or pipeline latency is introduced.
    (* keep = "true", syn_preserve = 1 *) reg [92:0] advance_copy_r;
    // Region 0: at most 14 enable leaves, each with <=16 sinks.
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
            capacity_count0_r <= capacity_next0_w;
        end
    end
    // Region 1: at most 14 enable leaves, each with <=16 sinks.
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
            capacity_count1_r <= capacity_next1_w;
        end
    end
    // Region 2: at most 14 enable leaves, each with <=16 sinks.
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
            capacity_count2_r <= capacity_next2_w;
        end
    end
    // Region 3: at most 14 enable leaves, each with <=16 sinks.
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
            capacity_count3_r <= capacity_next3_w;
        end
    end
    // Region 4: at most 14 enable leaves, each with <=16 sinks.
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
            capacity_count4_r <= capacity_next4_w;
        end
    end
    // Region 5: at most 14 enable leaves, each with <=16 sinks.
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
            capacity_count5_r <= capacity_next5_w;
        end
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) advance_copy_r <= {93{1'b1}};
        else begin
            advance_copy_r[15:0] <= {16{capacity_next0_w < 2'd2}};
            advance_copy_r[31:16] <= {16{capacity_next1_w < 2'd2}};
            advance_copy_r[47:32] <= {16{capacity_next2_w < 2'd2}};
            advance_copy_r[63:48] <= {16{capacity_next3_w < 2'd2}};
            advance_copy_r[79:64] <= {16{capacity_next4_w < 2'd2}};
            advance_copy_r[92:80] <= {13{capacity_next5_w < 2'd2}};
        end
    end
    wire [31:0] e1_move_next_w;
    assign e1_move_next_w = to_float_w ? unit_req_int_src_i : unit_req_src1_i[31:0];
    wire [31:0] e1_magnitude_next_w;
    assign e1_magnitude_next_w = integer_magnitude_w;
    wire [23:0] e1_fraction_next_w;
    assign e1_fraction_next_w = {|unit_req_src1_i[30:23], unit_req_src1_i[22:0]};
    wire [31:0] e2_move_next_w;
    assign e2_move_next_w = e1_move_r;
    wire [32:0] e2_integer_next_w;
    assign e2_integer_next_w = e1_exp_r >= 8'd150 ? shifted_left_w
                : {9'b0, shifted_right_w[56:33]};
    wire [22:0] e2_fraction_next_w;
    assign e2_fraction_next_w = aligned_w[30:8];
endmodule
