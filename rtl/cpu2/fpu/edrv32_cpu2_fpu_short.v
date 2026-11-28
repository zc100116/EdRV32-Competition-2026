// File: edrv32_cpu2_fpu_short.v
// Spec: fpu-spec 2.1-2.4, 3.1, 5.3-5.4.
// Description: Single/double-precision short unit with local completion and age cancellation.
// Clock domain: clk_sys.
module edrv32_cpu2_fpu_short #(
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
    input wire [(FPU_FORMAT == "FD" ? 64 : 32)-1:0] unit_req_src2_i,

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
    wire [31:0] a_w;
    wire [31:0] b_w;
    wire a_nan_w;
    wire b_nan_w;
    wire a_snan_w;
    wire b_snan_w;
    wire equal_w;
    wire less_w;
    wire both_zero_w;
    wire [6:0] operation_w;
    wire [2:0] function_w;
    wire single_fast_w;
    assign a_w = unit_req_src1_i[31:0];
    assign b_w = unit_req_src2_i[31:0];
    assign a_nan_w = (&a_w[30:23]) && (|a_w[22:0]);
    assign b_nan_w = (&b_w[30:23]) && (|b_w[22:0]);
    assign a_snan_w = a_nan_w && !a_w[22];
    assign b_snan_w = b_nan_w && !b_w[22];
    assign both_zero_w = !(|a_w[30:0]) && !(|b_w[30:0]);
    assign equal_w = (a_w == b_w) || both_zero_w;
    assign less_w = !both_zero_w && ((a_w[31] != b_w[31]) ? a_w[31]
        : (a_w[31] ? (a_w[30:0] > b_w[30:0]) : (a_w[30:0] < b_w[30:0])));
    assign operation_w = unit_req_instr_i[31:25];
    assign function_w = unit_req_instr_i[14:12];
    assign single_fast_w = operation_w == 7'b0010000;
    reg [31:0] single_result_w;
    reg [4:0] single_flags_w;
    reg single_int_dest_w;
    reg [9:0] class_w;
    always @(*) begin
        single_result_w = 32'b0;
        single_flags_w = 5'b0;
        single_int_dest_w = 1'b0;
        class_w = 10'b0;
        case (operation_w)
            7'b0010000: begin
                case (function_w)
                    3'b000: single_result_w = {b_w[31], a_w[30:0]};
                    3'b001: single_result_w = {!b_w[31], a_w[30:0]};
                    3'b010: single_result_w = {a_w[31] ^ b_w[31], a_w[30:0]};
                    default: single_result_w = 32'b0;
                endcase
            end
            7'b0010100: begin
                single_flags_w = {a_snan_w || b_snan_w, 4'b0};
                if (a_nan_w && b_nan_w) single_result_w = 32'h7fc00000;
                else if (a_nan_w) single_result_w = b_w;
                else if (b_nan_w) single_result_w = a_w;
                else if (both_zero_w) begin
                    single_result_w = {function_w[0] ? (a_w[31] && b_w[31])
                        : (a_w[31] || b_w[31]), 31'b0};
                end else single_result_w = (less_w ^ function_w[0]) ? a_w : b_w;
            end
            7'b1010000: begin
                single_int_dest_w = 1'b1;
                single_flags_w = {(function_w == 3'b010) ? (a_snan_w || b_snan_w)
                    : (a_nan_w || b_nan_w), 4'b0};
                if (!(a_nan_w || b_nan_w)) begin
                    case (function_w)
                        3'b010: single_result_w = {31'b0, equal_w};
                        3'b001: single_result_w = {31'b0, less_w};
                        3'b000: single_result_w = {31'b0, less_w || equal_w};
                        default: single_result_w = 32'b0;
                    endcase
                end
            end
            7'b1110000: begin
                single_int_dest_w = 1'b1;
                if (a_nan_w) class_w = a_w[22] ? 10'h200 : 10'h100;
                else if (&a_w[30:23]) class_w = a_w[31] ? 10'h001 : 10'h080;
                else if (!(|a_w[30:23])) begin
                    if (|a_w[22:0]) class_w = a_w[31] ? 10'h004 : 10'h020;
                    else class_w = a_w[31] ? 10'h008 : 10'h010;
                end else class_w = a_w[31] ? 10'h002 : 10'h040;
                single_result_w = {22'b0, class_w};
            end
            default: single_result_w = 32'b0;
        endcase
    end
    wire [63:0] double_data_w;
    wire [4:0] double_flag_w;
    wire double_dest_w;
    wire double_fast_o_w;
    wire [B-1:0] result_w;
    wire [4:0] flags_w;
    wire int_dest_w;
    wire fast_w;
    generate
        if (FPU_FORMAT == "FD") begin : g_double
            wire [63:0] double_a_w;
            wire [63:0] double_b_w;
            wire double_a_nan_w;
            wire double_b_nan_w;
            wire double_a_snan_w;
            wire double_b_snan_w;
            wire double_equal_w;
            wire double_less_w;
            wire double_both_zero_w;
            wire [6:0] double_operation_w;
            wire [2:0] double_function_w;
            wire double_fast_w;
            assign double_a_w = unit_req_src1_i;
            assign double_b_w = unit_req_src2_i;
            assign double_a_nan_w = (&double_a_w[62:52]) && (|double_a_w[51:0]);
            assign double_b_nan_w = (&double_b_w[62:52]) && (|double_b_w[51:0]);
            assign double_a_snan_w = double_a_nan_w && !double_a_w[51];
            assign double_b_snan_w = double_b_nan_w && !double_b_w[51];
            assign double_both_zero_w = !(|double_a_w[62:0]) && !(|double_b_w[62:0]);
            assign double_equal_w = (double_a_w == double_b_w) || double_both_zero_w;
            assign double_less_w = !double_both_zero_w && ((double_a_w[63] != double_b_w[63]) ?
        double_a_w[63]
                : (double_a_w[63] ? (double_a_w[62:0] > double_b_w[62:0]) : (double_a_w[62:0] <
        double_b_w[62:0])));
            assign double_operation_w = {unit_req_instr_i[31:26],1'b0};
            assign double_function_w = unit_req_instr_i[14:12];
            assign double_fast_w = double_operation_w == 7'b0010000;
            reg [63:0] double_result_w;
            reg [4:0] double_flags_w;
            reg double_int_dest_w;
            reg [9:0] double_class_w;
            always @(*) begin
                double_result_w = 64'b0;
                double_flags_w = 5'b0;
                double_int_dest_w = 1'b0;
                double_class_w = 10'b0;
                case (double_operation_w)
                    7'b0010000: begin
                        case (double_function_w)
                            3'b000: double_result_w = {double_b_w[63], double_a_w[62:0]};
                            3'b001: double_result_w = {!double_b_w[63], double_a_w[62:0]};
                            3'b010: double_result_w = {double_a_w[63] ^ double_b_w[63],
        double_a_w[62:0]};
                            default: double_result_w = 64'b0;
                        endcase
                    end
                    7'b0010100: begin
                        double_flags_w = {double_a_snan_w || double_b_snan_w, 4'b0};
                        if (double_a_nan_w && double_b_nan_w) double_result_w =
        64'h7ff8000000000000;
                        else if (double_a_nan_w) double_result_w = double_b_w;
                        else if (double_b_nan_w) double_result_w = double_a_w;
                        else if (double_both_zero_w) begin
                            double_result_w = {double_function_w[0] ? (double_a_w[63] &&
        double_b_w[63])
                                : (double_a_w[63] || double_b_w[63]), 63'b0};
                        end else double_result_w = (double_less_w ^ double_function_w[0]) ?
        double_a_w : double_b_w;
                    end
                    7'b1010000: begin
                        double_int_dest_w = 1'b1;
                        double_flags_w = {(double_function_w == 3'b010) ? (double_a_snan_w ||
        double_b_snan_w)
                            : (double_a_nan_w || double_b_nan_w), 4'b0};
                        if (!(double_a_nan_w || double_b_nan_w)) begin
                            case (double_function_w)
                                3'b010: double_result_w = {63'b0, double_equal_w};
                                3'b001: double_result_w = {63'b0, double_less_w};
                                3'b000: double_result_w = {63'b0, double_less_w || double_equal_w};
                                default: double_result_w = 64'b0;
                            endcase
                        end
                    end
                    7'b1110000: begin
                        double_int_dest_w = 1'b1;
                        if (double_a_nan_w) double_class_w = double_a_w[51] ? 10'h200 : 10'h100;
                        else if (&double_a_w[62:52]) double_class_w = double_a_w[63] ? 10'h001 :
        10'h080;
                        else if (!(|double_a_w[62:52])) begin
                            if (|double_a_w[51:0]) double_class_w = double_a_w[63] ? 10'h004 :
        10'h020;
                            else double_class_w = double_a_w[63] ? 10'h008 : 10'h010;
                        end else double_class_w = double_a_w[63] ? 10'h002 : 10'h040;
                        double_result_w = {54'b0, double_class_w};
                    end
                    default: double_result_w = 64'b0;
                endcase
            end
            assign double_data_w = double_result_w;
            assign double_flag_w = double_flags_w;
            assign double_dest_w = double_int_dest_w;
            assign double_fast_o_w = double_fast_w;
            assign result_w = unit_req_instr_i[25] ? double_data_w
                : {single_int_dest_w ? 32'b0 : 32'hffffffff,single_result_w};
        end else begin : g_single
            assign double_data_w = 64'b0;
            assign double_flag_w = 5'b0;
            assign double_dest_w = 1'b0;
            assign double_fast_o_w = 1'b0;
            assign result_w = single_result_w;
        end
    endgenerate
    assign flags_w = (FPU_FORMAT == "FD" && unit_req_instr_i[25])
        ? double_flag_w : single_flags_w;
    assign int_dest_w = (FPU_FORMAT == "FD" && unit_req_instr_i[25])
        ? double_dest_w : single_int_dest_w;
    assign fast_w = (FPU_FORMAT == "FD" && unit_req_instr_i[25])
        ? double_fast_o_w : single_fast_w;
    reg [B-1:0] e1_result_r;
    reg [4:0] e1_flags_r;
    reg e1_int_dest_r;
    integer result_idx;
    always @(posedge clk_i) begin
        for (result_idx = 0; result_idx < B/16; result_idx = result_idx + 1) begin
            if (advance_copy_r[result_idx])
                e1_result_r[result_idx*16 +: 16] <= e1_result_next_w[result_idx*16 +: 16];
        end
        if (advance_copy_r[4]) begin
            e1_flags_r <= flags_w;
        end
        if (advance_copy_r[4]) begin
            e1_int_dest_r <= int_dest_w;
        end
    end
    // One outstanding result per pipeline position; a two-entry completion skid
    // absorbs the final enabled edge before registered backpressure stops APMs.
    reg [0:0] valid_r;
    reg [T-1:0] tag_r [0:0];
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
    assign pending_w = valid_r[0];
    assign pending_kill_w = cancel_valid_i
        && ((tag_r[0] - age_head_i) >= cancel_distance_w);
    assign unit_req_ready_o = advance_r;
    assign accept_w = unit_req_valid_i && unit_req_ready_o
        && !(cancel_valid_i && (req_distance_w >= cancel_distance_w));
    assign enqueue_w = advance_r && ((pending_w && !pending_kill_w)
        || (accept_w && fast_w && !pending_w));
    assign enqueue_tag_w = pending_w ? tag_r[0] : unit_req_tag_i;
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
        end
    end
    always @(posedge clk_i) begin
        if (advance_copy_r[4]) begin
            tag_r[0] <= unit_req_tag_i;
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
    assign enqueue_data_w = pending_w ? e1_result_r : result_w;
    assign enqueue_flags_w = pending_w ? e1_flags_r : flags_w;
    assign enqueue_int_dest_w = pending_w ? e1_int_dest_r : int_dest_w;
    wire unused_instr_w;
    assign unused_instr_w = ^{double_data_w,unit_req_instr_i[24:15], unit_req_instr_i[11:0]};
    // Same-edge regional clock-enable leaves. Each leaf drives at most 16
    // data FF enables (APM leaves drive 13 macro CE pins). PDS must retain these
    // copies; no extra clock or pipeline latency is introduced.
    (* keep = "true", syn_preserve = 1 *) reg [4:0] advance_copy_r;
    // Region 0: at most 3 enable leaves, each with <=16 sinks.
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
            advance_copy_r <= {5{1'b1}};
        end else begin
            advance_copy_r[4:0] <= {5{capacity_next0_w < 2'd2}};
        end
    end
    wire [B-1:0] e1_result_next_w;
    assign e1_result_next_w = result_w;
endmodule
