// File: edrv32_cpu2_fpu_convert.v
// Spec: fpu-spec 2.1-2.4, 3.1, 5.3-5.4.
// Description: Single-precision convert unit with local completion and age cancellation.
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
    input wire [31:0] unit_req_src1_i,
    input wire [31:0] unit_req_int_src_i,
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
    always @(posedge clk_i) begin
        if (advance_copy_r[0]) begin
            e1_to_float_r <= to_float_w;
        end
        if (advance_copy_r[0]) begin
            e1_fast_r <= fast_w;
        end
        if (advance_copy_r[1]) e1_move_r[15:0] <= e1_move_next_w[15:0];
        if (advance_copy_r[2]) e1_move_r[31:16] <= e1_move_next_w[31:16];
        if (advance_copy_r[0]) begin
            e1_unsigned_r <= unsigned_w;
        end
        if (advance_copy_r[0]) begin
            e1_sign_r <= sign_w;
        end
        if (advance_copy_r[0]) begin
            e1_rm_r <= unit_req_rm_i;
        end
        if (advance_copy_r[3]) e1_magnitude_r[15:0] <= e1_magnitude_next_w[15:0];
        if (advance_copy_r[4]) e1_magnitude_r[31:16] <= e1_magnitude_next_w[31:16];
        if (advance_copy_r[5]) e1_fraction_r[15:0] <= e1_fraction_next_w[15:0];
        if (advance_copy_r[0]) e1_fraction_r[23:16] <= e1_fraction_next_w[23:16];
        if (advance_copy_r[6]) begin
            e1_exp_r <= unit_req_src1_i[30:23];
        end
        if (advance_copy_r[0]) begin
            e1_nan_r <= (&unit_req_src1_i[30:23]) && (|unit_req_src1_i[22:0]);
        end
        if (advance_copy_r[6]) begin
            e1_int_dest_r <= !to_float_w;
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
    always @(posedge clk_i) begin
        if (advance_copy_r[6]) begin
            e2_to_float_r <= e1_to_float_r;
        end
        if (advance_copy_r[6]) begin
            e2_fast_r <= e1_fast_r;
        end
        if (advance_copy_r[7]) e2_move_r[15:0] <= e2_move_next_w[15:0];
        if (advance_copy_r[8]) e2_move_r[31:16] <= e2_move_next_w[31:16];
        if (advance_copy_r[6]) begin
            e2_unsigned_r <= e1_unsigned_r;
        end
        if (advance_copy_r[6]) begin
            e2_sign_r <= e1_sign_r;
        end
        if (advance_copy_r[6]) begin
            e2_rm_r <= e1_rm_r;
        end
        if (advance_copy_r[9]) e2_integer_r[15:0] <= e2_integer_next_w[15:0];
        if (advance_copy_r[10]) e2_integer_r[31:16] <= e2_integer_next_w[31:16];
        if (advance_copy_r[11]) e2_integer_r[32:32] <= e2_integer_next_w[32:32];
        if (advance_copy_r[12]) e2_fraction_r[15:0] <= e2_fraction_next_w[15:0];
        if (advance_copy_r[11]) e2_fraction_r[22:16] <= e2_fraction_next_w[22:16];
        if (advance_copy_r[11]) begin
            e2_bias_r <= 8'd158 - {3'b0, magnitude_lz_w};
        end
        if (advance_copy_r[13]) begin
            e2_guard_r <= e1_to_float_r ? aligned_w[7]
                : (e1_exp_r < 8'd150 && shifted_right_w[32]);
        end
        if (advance_copy_r[13]) begin
            e2_sticky_r <= e1_to_float_r ? (|aligned_w[6:0])
                : (e1_exp_r < 8'd150 && ((|shifted_right_w[31:0])
                    || ((right_shift_w > 8'd33) && (|e1_fraction_r))));
        end
        if (advance_copy_r[13]) begin
            e2_large_r <= e1_exp_r > 8'd158;
        end
        if (advance_copy_r[13]) begin
            e2_nan_r <= e1_nan_r;
        end
        if (advance_copy_r[13]) begin
            e2_zero_r <= !magnitude_hit_w;
        end
        if (advance_copy_r[13]) begin
            e2_int_dest_r <= e1_int_dest_r;
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
    wire [31:0] enqueue_data_w;
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
        if (advance_copy_r[13]) begin
            tag_r[0] <= unit_req_tag_i;
            for (tag_idx = 1; tag_idx < 2; tag_idx = tag_idx + 1) begin
                tag_r[tag_idx] <= tag_r[tag_idx-1];
            end
        end
    end
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
    assign enqueue_data_w = pending_w ? (e2_fast_r ? e2_move_r : converted_w)
        : (to_float_w ? unit_req_int_src_i : unit_req_src1_i);
    assign enqueue_flags_w = pending_w && !e2_fast_r ? converted_flags_w : 5'b0;
    assign enqueue_int_dest_w = pending_w ? e2_int_dest_r : !to_float_w;
    wire unused_instr_w;
    assign unused_instr_w = ^{unit_req_instr_i[31:30], unit_req_instr_i[27:21],
        unit_req_instr_i[19:0], aligned_w[31]};
    // Same-edge regional clock-enable leaves. Each leaf drives at most 16
    // data FF enables (APM leaves drive 13 macro CE pins). PDS must retain these
    // copies; no extra clock or pipeline latency is introduced.
    (* keep = "true", syn_preserve = 1 *) reg [13:0] advance_copy_r;
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
            capacity_count0_r <= next_count_w;
        end
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            advance_copy_r <= {14{1'b1}};
        end else begin
            advance_copy_r[13:0] <= {14{capacity_next0_w < 2'd2}};
        end
    end
    wire [31:0] e1_move_next_w;
    assign e1_move_next_w = to_float_w ? unit_req_int_src_i : unit_req_src1_i;
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
