// File: edrv32_npu_result_quant.v
// Spec: npu-spec 2.3, 5.4; datapath design 4.2, 4.3, 4.6.2.
// Description: Four always-advancing quantization lanes, sixteen/eight groups per pair.
// Parameters are requested at R4; payload and tags follow Q0 through Q12.
// Clock: clk_npu.
module edrv32_npu_result_quant (
    // Clock and local control.
    input wire clk_i,
    input wire rst_n_i,
    input wire cancel_i,

    // R4 preparation and ACC final vector.
    input wire quant_prepare_valid_i,
    input wire [48:0] quant_prepare_tag_i,
    input wire accum_valid_i,
    input wire [48:0] accum_tag_i,
    input wire [2047:0] accum_data_i,

    // Two-edge parameter and activation reads.
    output wire param_rd_en_o,
    output wire [2:0] param_rd_block_o,
    output wire [1:0] param_rd_phase_o,
    input wire [511:0] param_rd_data_i,
    output wire lut_rd_en_o,
    output wire [2:0] lut_rd_block_o,
    output wire [31:0] lut_rd_addr_o,
    input wire [31:0] lut_rd_data_i,

    // Q10 residual prefetch and Q12 complete pair.
    output wire residual_rd_en_o,
    output wire [4:0] residual_rd_addr_o,
    output wire quant_valid_o,
    output wire [48:0] quant_tag_o,
    output wire [511:0] quant_data_o,

    // Local pipeline occupancy.
    output wire idle_o
);
    reg request_active_r;
    reg [3:0] request_phase_r;
    reg [2:0] request_block_r;
    reg request_half_r;
    reg [1:0] prepare_valid_r;
    reg [3:0] prepare_phase_r [0:1];
    reg [48:0] hold_tag_r;
    reg [12:0] q_valid_r;
    reg [48:0] q_tag_r [0:12];
    reg [3:0] q_phase_r [0:12];
    wire [511:0] pair_data_w;
    reg residual_high_valid_r;
    reg [4:0] residual_high_addr_r;
    wire residual_low_w;
    wire q9_last_w;
    wire [44:0] unused_prepare_tag_w;
    integer stage;

    assign unused_prepare_tag_w = {quant_prepare_tag_i[48:27],
        quant_prepare_tag_i[25:15], quant_prepare_tag_i[11:0]};
    assign param_rd_en_o = (quant_prepare_valid_i || request_active_r) && !cancel_i;
    assign param_rd_block_o = quant_prepare_valid_i
        ? quant_prepare_tag_i[14:12] : request_block_r;
    assign param_rd_phase_o = quant_prepare_valid_i ? 2'd0 : request_phase_r[3:2];
    assign lut_rd_en_o = q_valid_r[9] && q_tag_r[9][27] && !cancel_i;
    assign lut_rd_block_o = q_tag_r[9][14:12];
    assign q9_last_w = q_phase_r[9] == (q_tag_r[9][26] ? 4'd7 : 4'd15);
    assign residual_low_w = q_valid_r[9] && q9_last_w && q_tag_r[9][28];
    assign residual_rd_en_o = (residual_low_w || residual_high_valid_r) && !cancel_i;
    assign residual_rd_addr_o = residual_low_w ? q_tag_r[9][47:43] : residual_high_addr_r;
    assign quant_valid_o = q_valid_r[12] && !cancel_i;
    assign quant_tag_o = q_tag_r[12];
    assign quant_data_o = pair_data_w;
    assign idle_o = !(request_active_r || (|prepare_valid_r) || (|q_valid_r)
        || residual_high_valid_r);

    // The prepare pulse itself is phase0: no register before the RAM request.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            request_active_r <= 1'b0;
            prepare_valid_r <= 2'd0;
            q_valid_r <= 13'd0;
            residual_high_valid_r <= 1'b0;
        end else if (cancel_i) begin
            request_active_r <= 1'b0;
            prepare_valid_r <= 2'd0;
            q_valid_r <= 13'd0;
            residual_high_valid_r <= 1'b0;
        end else begin
            if (quant_prepare_valid_i) begin
                request_active_r <= 1'b1;
            end else if (request_active_r
                && request_phase_r == (request_half_r ? 4'd7 : 4'd15)) begin
                request_active_r <= 1'b0;
            end
            prepare_valid_r <= {prepare_valid_r[0], param_rd_en_o};
            q_valid_r[0] <= prepare_valid_r[1];
            q_valid_r[11:1] <= q_valid_r[10:0];
            q_valid_r[12] <= q_valid_r[11]
                && q_phase_r[11] == (q_tag_r[11][26] ? 4'd7 : 4'd15);
            residual_high_valid_r <= residual_low_w && !q_tag_r[9][26];
        end
    end

    always @(posedge clk_i) begin
        if (quant_prepare_valid_i) begin
            request_block_r <= quant_prepare_tag_i[14:12];
            request_half_r <= quant_prepare_tag_i[26];
            request_phase_r <= 4'd1;
        end else if (request_active_r) begin
            request_phase_r <= request_phase_r + 4'd1;
        end
        prepare_phase_r[0] <= quant_prepare_valid_i ? 4'd0 : request_phase_r;
        prepare_phase_r[1] <= prepare_phase_r[0];
        if (accum_valid_i) begin
            hold_tag_r <= accum_tag_i;
        end
        // ACC and the first parameter group are visible before the Q0 edge.
        q_tag_r[0] <= (prepare_phase_r[1] == 4'd0) ? accum_tag_i : hold_tag_r;
        q_phase_r[0] <= prepare_phase_r[1];
        for (stage = 1; stage <= 12; stage = stage + 1) begin
            q_tag_r[stage] <= q_tag_r[stage-1];
            q_phase_r[stage] <= q_phase_r[stage-1];
        end
        if (residual_low_w) begin
            residual_high_addr_r <= q_tag_r[9][47:43] + 5'd1;
        end
    end

    genvar index;
    genvar group;
    genvar hold_bank;
    generate
        for (index = 0; index < 4; index = index + 1) begin : g_lane
            // Local Q0 controls also capture this lane's sixteen value groups.
            (* keep = "true", syn_preserve = 1 *) reg [3:0] q0_phase_r;
            reg [31:0] hold_acc_r [0:15];
            (* keep = "true", syn_preserve = 1 *) reg [7:0] q_zp_r [0:7];
            (* keep = "true", syn_preserve = 1 *) reg [3:0] q11_phase_r;
            (* keep = "true", syn_preserve = 1 *) reg q11_half_r;
            (* keep = "true", syn_preserve = 1 *) reg q11_lut_r;
            reg [127:0] pair_data_r;
            integer zp_stage;

            reg signed [31:0] q0_acc_r;
            reg signed [31:0] q0_bias_r;
            reg [15:0] q0_mult_r;
            reg [15:0] q1_mult_r;
            reg [5:0] q_shift_r [0:6];
            reg signed [32:0] q1_bias_sum_r;
            wire [33:0] q3_low_product_w;
            wire [31:0] q3_high_product_w;
            reg signed [48:0] q4_product_r;
            reg signed [48:0] q5_round_r;
            reg signed [48:0] q6_q_shift_r;
            reg signed [48:0] q7_q_shift_r;
            reg signed [49:0] q8_zero_point_r;
            reg [7:0] q9_clamp_r;
            reg [7:0] q10_bypass_r;
            reg [7:0] q11_bypass_r;
            wire [9:0] unused_param_reserved_w;
            integer shift_stage;

            // Each capture control drives only four INT32 hold entries, as in T-NPU1.
            for (hold_bank = 0; hold_bank < 4; hold_bank = hold_bank + 1) begin : g_hold
                (* keep = "true", syn_preserve = 1 *) reg capture_r;
                integer group_idx;

                (* keep = "true" *)
                always @(posedge clk_i or negedge rst_n_i) begin
                    if (!rst_n_i) begin
                        capture_r <= 1'b0;
                    end else if (cancel_i) begin
                        capture_r <= 1'b0;
                    end else begin
                        capture_r <= prepare_valid_r[0] && prepare_phase_r[0] == 4'd0;
                    end
                end

                always @(posedge clk_i) begin
                    if (capture_r) begin
                        for (group_idx = 4*hold_bank; group_idx < 4*hold_bank+4;
                            group_idx = group_idx + 1) begin
                            hold_acc_r[group_idx] <= accum_data_i[32*(32*((group_idx/2)%2)
                                + 8*(group_idx/4) + 4*(group_idx%2) + index) +: 32];
                        end
                    end
                end
            end

            for (group = 0; group < 16; group = group + 1) begin : g_output
                // phase={channel[4:3],pixel,channel[2]}; result={plane,pixel,c16}.
                assign pair_data_w[8*(32*(group/8) + 16*((group/2)%2)
                    + 8*((group/4)%2) + 4*(group%2) + index) +: 8]
                    = pair_data_r[8*group +: 8];
            end

            edrv32_mul_npu_quant_low u_low (
                .clk_i(clk_i),
                .operand_a_i({1'b0, q1_bias_sum_r[16:0]}),
                .operand_b_i(q1_mult_r),
                .product_o(q3_low_product_w)
            );
            edrv32_mul_npu_quant_high u_high (
                .clk_i(clk_i),
                .operand_a_i(q1_bias_sum_r[32:17]),
                .operand_b_i(q1_mult_r),
                .product_o(q3_high_product_w)
            );
            assign unused_param_reserved_w = param_rd_data_i[64*(4*q0_phase_r[0]+index)+54 +: 10];
            assign lut_rd_addr_o[8*index +: 8] = q9_clamp_r;

            // Preserve independent final-edge controls rather than a shared wide CE.
            (* keep = "true" *)
            always @(posedge clk_i) begin
                q0_phase_r <= prepare_phase_r[0];
                q_zp_r[0] <= (q0_phase_r == 4'd0)
                    ? accum_tag_i[36:29] : hold_tag_r[36:29];
                for (zp_stage = 1; zp_stage < 8; zp_stage = zp_stage + 1) begin
                    q_zp_r[zp_stage] <= q_zp_r[zp_stage-1];
                end
                q11_phase_r <= q_phase_r[10];
                q11_half_r <= q_tag_r[10][26];
                q11_lut_r <= q_tag_r[10][27];
            end

            always @(posedge clk_i) begin
                if (q0_phase_r == 4'd0) begin
                    q0_acc_r <= accum_data_i[32*index +: 32];
                end else begin
                    q0_acc_r <= hold_acc_r[q0_phase_r];
                end
                // Assembly advances freely; only the Q12 valid exposes the complete pair.
                if (q11_half_r && q11_phase_r == 4'd0) begin
                    pair_data_r[127:64] <= 64'd0;
                end
                pair_data_r[8*q11_phase_r +: 8]
                    <= q11_lut_r ? lut_rd_data_i[8*index +: 8] : q11_bypass_r;
                q0_bias_r <= param_rd_data_i[64*(4*q0_phase_r[0]+index) +: 32];
                q0_mult_r <= param_rd_data_i[64*(4*q0_phase_r[0]+index)+32 +: 16];
                q_shift_r[0] <= param_rd_data_i[64*(4*q0_phase_r[0]+index)+48 +: 6];
                for (shift_stage = 1; shift_stage < 7; shift_stage = shift_stage + 1) begin
                    q_shift_r[shift_stage] <= q_shift_r[shift_stage-1];
                end
                q1_bias_sum_r <= {q0_acc_r[31], q0_acc_r} + {q0_bias_r[31], q0_bias_r};
                q1_mult_r <= q0_mult_r;
                // Design 4.6.2: low17 is unsigned; high16 carries the sign.
                q4_product_r <= $signed({q3_high_product_w, 17'd0})
                    + $signed({{15{q3_low_product_w[33]}}, q3_low_product_w});
                q5_round_r <= q4_product_r + ((q_shift_r[4] == 6'd0) ? 49'd0
                    : (49'd1 << (q_shift_r[4] - 6'd1)));
                q6_q_shift_r <= q5_round_r >>> q_shift_r[5][2:0];
                q7_q_shift_r <= q6_q_shift_r >>> {q_shift_r[6][5:3], 3'd0};
                q8_zero_point_r <= $signed({q7_q_shift_r[48], q7_q_shift_r})
                    + $signed({{42{q_zp_r[7][7]}}, q_zp_r[7]});
                if (q8_zero_point_r > 50'sd127) begin
                    q9_clamp_r <= 8'h7f;
                end else if (q8_zero_point_r < -50'sd128) begin
                    q9_clamp_r <= 8'h80;
                end else begin
                    q9_clamp_r <= q8_zero_point_r[7:0];
                end
                q10_bypass_r <= q9_clamp_r;
                q11_bypass_r <= q10_bypass_r;
            end
        end
    endgenerate
endmodule
