// ============================================================================
// File        : edrv32_yolo_result_quant.v
// Description : Buffered, 16-lane INT8 requantizer for CONV tile results.
// Notes       : Five arithmetic stages and one configurable activation lookup
//               accept one 16-value group per clock.
//               Four groups form one two-pixel result. Output backpressure
//               freezes the pipeline only when the two-entry output queue
//               cannot accept a completed result. Valid shifts are 0..47.
// ============================================================================

module edrv32_yolo_result_quant (
    input  wire          clk_i,
    input  wire          rst_n_i,

    input  wire          in_valid_i,
    output wire          in_ready_o,
    input  wire          in_last_i,
    input  wire [11:0]   in_pair_i,
    input  wire [2047:0] in_accum_i,

    output wire          out_valid_o,
    input  wire          out_ready_i,
    output wire          out_last_o,
    output wire [11:0]   out_pair_o,
    output wire [511:0]  out_data_o,

    input  wire          cfg_valid_i,
    output wire          cfg_ready_o,
    input  wire [4:0]    cfg_channel_i,
    input  wire [31:0]   cfg_bias_i,
    input  wire [15:0]   cfg_multiplier_i,
    input  wire [5:0]    cfg_shift_i,
    input  wire [7:0]    cfg_zero_point_i,
    input  wire          lut_enable_i,
    input  wire          lut_cfg_valid_i,
    output wire          lut_cfg_ready_o,
    input  wire [7:0]    lut_cfg_addr_i,
    input  wire [7:0]    lut_cfg_data_i
);

    reg signed [31:0] bias_r [0:31];
    reg signed [15:0] multiplier_r [0:31];
    reg [5:0] shift_r [0:31];
    reg signed [7:0] zero_point_r;

    reg [2047:0] in_fifo_data_r [0:1];
    reg [11:0] in_fifo_pair_r [0:1];
    reg in_fifo_last_r [0:1];
    reg in_read_ptr_r;
    reg in_write_ptr_r;
    reg [1:0] in_count_r;
    reg working_r;
    reg [1:0] phase_r;

    reg s0_valid_r;
    reg s1_valid_r;
    reg s2_valid_r;
    reg s3_valid_r;
    reg s4_valid_r;
    reg s5_valid_r;
    reg [1:0] s0_phase_r;
    reg [1:0] s1_phase_r;
    reg [1:0] s2_phase_r;
    reg [1:0] s3_phase_r;
    reg [1:0] s4_phase_r;
    reg [1:0] s5_phase_r;
    reg [11:0] s0_pair_r;
    reg [11:0] s1_pair_r;
    reg [11:0] s2_pair_r;
    reg [11:0] s3_pair_r;
    reg [11:0] s4_pair_r;
    reg [11:0] s5_pair_r;
    reg s0_last_r;
    reg s1_last_r;
    reg s2_last_r;
    reg s3_last_r;
    reg s4_last_r;
    reg s5_last_r;
    reg signed [7:0] s0_zero_r;
    reg signed [7:0] s1_zero_r;
    reg signed [7:0] s2_zero_r;
    reg signed [7:0] s3_zero_r;

    reg signed [31:0] s0_accum_r [0:15];
    reg signed [31:0] s0_bias_r [0:15];
    reg signed [15:0] s0_multiplier_r [0:15];
    reg [5:0] s0_shift_r [0:15];
    reg signed [32:0] s1_biased_r [0:15];
    reg signed [15:0] s1_multiplier_r [0:15];
    reg [5:0] s1_shift_r [0:15];
    reg signed [48:0] s2_product_r [0:15];
    reg [5:0] s2_shift_r [0:15];
    reg signed [48:0] s3_shifted_r [0:15];
    reg [127:0] s4_group_r;
    reg [127:0] s5_group_r;

    reg [511:0] assembly_r;
    reg [511:0] assembled_w;
    reg [511:0] out_fifo_data_r [0:1];
    reg [11:0] out_fifo_pair_r [0:1];
    reg out_fifo_last_r [0:1];
    reg out_read_ptr_r;
    reg out_write_ptr_r;
    reg [1:0] out_count_r;

    wire out_pop_w = out_valid_o && out_ready_i;
    wire out_push_pending_w = s5_valid_r && s5_phase_r == 2'd3;
    // A full output FIFO pauses the local pipeline until the next clock.
    // Writer ready must not feed the wide quantizer CE through same-cycle pop.
    wire advance_w = !out_push_pending_w || out_count_r != 2'd2;
    wire issue_w = advance_w && (working_r || in_count_r != 2'd0);
    wire [1:0] issue_phase_w = working_r ? phase_r : 2'd0;
    wire in_pop_w = issue_w && issue_phase_w == 2'd3;
    wire in_push_w = in_valid_i && in_ready_o;
    wire out_push_w = advance_w && out_push_pending_w;
    wire [2047:0] selected_accum_w = in_fifo_data_r[in_read_ptr_r];

    assign in_ready_o = in_count_r != 2'd2;
    wire quiescent_w = in_count_r == 2'd0 && !working_r &&
                         !s0_valid_r && !s1_valid_r && !s2_valid_r &&
                         !s3_valid_r && !s4_valid_r && !s5_valid_r &&
                         out_count_r == 2'd0;
    assign cfg_ready_o = quiescent_w && cfg_shift_i <= 6'd47;
    assign lut_cfg_ready_o = quiescent_w;
    assign out_valid_o = out_count_r != 2'd0;
    assign out_last_o = out_fifo_last_r[out_read_ptr_r];
    assign out_pair_o = out_fifo_pair_r[out_read_ptr_r];
    assign out_data_o = out_fifo_data_r[out_read_ptr_r];

    wire signed [48:0] shifted_w [0:15];
    wire [7:0] quant_byte_w [0:15];
    wire [127:0] mapped_group_w;
    genvar lane;
    generate
        for (lane = 0; lane < 16; lane = lane + 1) begin : g_quant_lane
            reg [7:0] activation_lut_r [0:255];
            wire [7:0] mapped_byte_w =
                activation_lut_r[s4_group_r[lane*8 +: 8]];
            assign mapped_group_w[lane*8 +: 8] = mapped_byte_w;
            always @(posedge clk_i) begin
                if (lut_cfg_valid_i && lut_cfg_ready_o)
                    activation_lut_r[lut_cfg_addr_i] <= lut_cfg_data_i;
            end
            wire signed [48:0] round_w =
                s2_shift_r[lane] == 6'd0 ? 49'sd0 :
                (49'sd1 <<< (s2_shift_r[lane] - 6'd1));
            assign shifted_w[lane] =
                (s2_product_r[lane] + round_w) >>> s2_shift_r[lane];
            wire signed [49:0] zero_added_w =
                $signed({s3_shifted_r[lane][48], s3_shifted_r[lane]}) +
                $signed({{42{s3_zero_r[7]}}, s3_zero_r});
            assign quant_byte_w[lane] =
                zero_added_w > 50'sd127 ? 8'h7f :
                zero_added_w < -50'sd128 ? 8'h80 :
                zero_added_w[7:0];
        end
    endgenerate

    always @(*) begin
        assembled_w = assembly_r;
        case (s5_phase_r)
            2'd0: begin
                assembled_w[0 +: 64]   = s5_group_r[0 +: 64];
                assembled_w[256 +: 64] = s5_group_r[64 +: 64];
            end
            2'd1: begin
                assembled_w[64 +: 64]  = s5_group_r[0 +: 64];
                assembled_w[320 +: 64] = s5_group_r[64 +: 64];
            end
            2'd2: begin
                assembled_w[128 +: 64] = s5_group_r[0 +: 64];
                assembled_w[384 +: 64] = s5_group_r[64 +: 64];
            end
            2'd3: begin
                assembled_w[192 +: 64] = s5_group_r[0 +: 64];
                assembled_w[448 +: 64] = s5_group_r[64 +: 64];
            end
        endcase
    end

    integer j;
    integer channel;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            in_read_ptr_r   <= 1'b0;
            in_write_ptr_r  <= 1'b0;
            in_count_r      <= 2'd0;
            working_r       <= 1'b0;
            phase_r         <= 2'd0;
            s0_valid_r      <= 1'b0;
            s1_valid_r      <= 1'b0;
            s2_valid_r      <= 1'b0;
            s3_valid_r      <= 1'b0;
            s4_valid_r      <= 1'b0;
            s5_valid_r      <= 1'b0;
            out_read_ptr_r  <= 1'b0;
            out_write_ptr_r <= 1'b0;
            out_count_r     <= 2'd0;
            zero_point_r    <= 8'sd0;
        end else begin
            if (cfg_valid_i && cfg_ready_o) begin
                bias_r[cfg_channel_i]       <= cfg_bias_i;
                multiplier_r[cfg_channel_i] <= cfg_multiplier_i;
                shift_r[cfg_channel_i]      <= cfg_shift_i;
                zero_point_r                <= cfg_zero_point_i;
            end

            if (in_push_w) begin
                in_fifo_data_r[in_write_ptr_r] <= in_accum_i;
                in_fifo_pair_r[in_write_ptr_r] <= in_pair_i;
                in_fifo_last_r[in_write_ptr_r] <= in_last_i;
                in_write_ptr_r                 <= !in_write_ptr_r;
            end
            if (in_pop_w)
                in_read_ptr_r <= !in_read_ptr_r;
            case ({in_push_w, in_pop_w})
                2'b10: in_count_r <= in_count_r + 2'd1;
                2'b01: in_count_r <= in_count_r - 2'd1;
                default: in_count_r <= in_count_r;
            endcase

            if (out_pop_w)
                out_read_ptr_r <= !out_read_ptr_r;
            if (out_push_w) begin
                out_fifo_data_r[out_write_ptr_r] <= assembled_w;
                out_fifo_pair_r[out_write_ptr_r] <= s5_pair_r;
                out_fifo_last_r[out_write_ptr_r] <= s5_last_r;
                out_write_ptr_r                  <= !out_write_ptr_r;
            end
            case ({out_push_w, out_pop_w})
                2'b10: out_count_r <= out_count_r + 2'd1;
                2'b01: out_count_r <= out_count_r - 2'd1;
                default: out_count_r <= out_count_r;
            endcase

            if (advance_w) begin
                s0_valid_r <= issue_w;
                s1_valid_r <= s0_valid_r;
                s2_valid_r <= s1_valid_r;
                s3_valid_r <= s2_valid_r;
                s4_valid_r <= s3_valid_r;
                s5_valid_r <= s4_valid_r;

                if (issue_w) begin
                    s0_phase_r <= issue_phase_w;
                    s0_pair_r  <= in_fifo_pair_r[in_read_ptr_r];
                    s0_last_r  <= in_fifo_last_r[in_read_ptr_r];
                    s0_zero_r  <= zero_point_r;
                    for (j = 0; j < 16; j = j + 1) begin
                        channel = issue_phase_w * 8 + j % 8;
                        s0_accum_r[j] <= $signed(
                            selected_accum_w[((j/8)*32+channel)*32 +: 32]);
                        s0_bias_r[j]       <= bias_r[channel];
                        s0_multiplier_r[j] <= multiplier_r[channel];
                        s0_shift_r[j]      <= shift_r[channel];
                    end
                    if (issue_phase_w == 2'd3) begin
                        working_r <= 1'b0;
                        phase_r   <= 2'd0;
                    end else begin
                        working_r <= 1'b1;
                        phase_r   <= issue_phase_w + 2'd1;
                    end
                end

                if (s0_valid_r) begin
                    s1_phase_r <= s0_phase_r;
                    s1_pair_r  <= s0_pair_r;
                    s1_last_r  <= s0_last_r;
                    s1_zero_r  <= s0_zero_r;
                    for (j = 0; j < 16; j = j + 1) begin
                        s1_biased_r[j] <=
                            $signed({s0_accum_r[j][31], s0_accum_r[j]}) +
                            $signed({s0_bias_r[j][31], s0_bias_r[j]});
                        s1_multiplier_r[j] <= s0_multiplier_r[j];
                        s1_shift_r[j]      <= s0_shift_r[j];
                    end
                end
                if (s1_valid_r) begin
                    s2_phase_r <= s1_phase_r;
                    s2_pair_r  <= s1_pair_r;
                    s2_last_r  <= s1_last_r;
                    s2_zero_r  <= s1_zero_r;
                    for (j = 0; j < 16; j = j + 1) begin
                        s2_product_r[j] <= s1_biased_r[j] *
                                           s1_multiplier_r[j];
                        s2_shift_r[j]   <= s1_shift_r[j];
                    end
                end
                if (s2_valid_r) begin
                    s3_phase_r <= s2_phase_r;
                    s3_pair_r  <= s2_pair_r;
                    s3_last_r  <= s2_last_r;
                    s3_zero_r  <= s2_zero_r;
                    for (j = 0; j < 16; j = j + 1)
                        s3_shifted_r[j] <= shifted_w[j];
                end
                if (s3_valid_r) begin
                    s4_phase_r <= s3_phase_r;
                    s4_pair_r  <= s3_pair_r;
                    s4_last_r  <= s3_last_r;
                    for (j = 0; j < 16; j = j + 1)
                        s4_group_r[j*8 +: 8] <= quant_byte_w[j];
                end
                if (s4_valid_r) begin
                    s5_phase_r <= s4_phase_r;
                    s5_pair_r <= s4_pair_r;
                    s5_last_r <= s4_last_r;
                    s5_group_r <= lut_enable_i ? mapped_group_w : s4_group_r;
                end
                if (s5_valid_r)
                    assembly_r <= assembled_w;
            end
        end
    end

endmodule
