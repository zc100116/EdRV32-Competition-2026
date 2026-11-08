// File: edrv32_npu_post_dfl.v
// Spec: npu-spec 4.4, 5.6.
// Description: One serial DFL chain with full-width sums and rounded integer division.
// Twelve quotient bits use two 13-bit subtraction segments and a registered select.
// Clock: clk_npu.
module edrv32_npu_post_dfl (
    // Clock and lifetime.
    input wire clk_i,
    input wire rst_n_i,
    input wire cancel_i,

    // One gathered side; peak-minus-bin is independent of box zero point.
    input wire start_i,
    input wire [127:0] bins_i,
    output wire done_o,
    output wire [11:0] distance_o,

    // Two-cycle exp RAM read; caller selects the head.
    output wire exp_en_o,
    output wire [7:0] exp_addr_o,
    input wire [31:0] exp_data_i
);
    localparam [3:0] S_IDLE = 4'd0;
    localparam [3:0] S_PEAK = 4'd1;
    localparam [3:0] S_EXP = 4'd2;
    localparam [3:0] S_SUM = 4'd3;
    localparam [3:0] S_ROUND = 4'd4;
    localparam [3:0] S_DIV_INIT = 4'd5;
    localparam [3:0] S_DIV_LOW = 4'd6;
    localparam [3:0] S_DIV_HIGH = 4'd7;
    localparam [3:0] S_DONE = 4'd8;
    localparam [3:0] S_PEAK_UPDATE = 4'd9;
    localparam [3:0] S_DIV_SELECT = 4'd10;
    reg [3:0] state_r;
    reg peak_greater_r;
    reg [7:0] peak_bin_r;
    reg [127:0] bins_r;
    reg signed [7:0] peak_r;
    reg [3:0] index_r;
    reg [3:0] valid_r;
    reg [3:0] bin_r [0:3];
    reg [7:0] difference_r;
    reg [24:0] product_r;
    reg [20:0] product_weight_r;
    reg [24:0] den_r;
    reg [27:0] num_r;
    reg [35:0] rounded_r;
    reg [24:0] remainder_r;
    reg [11:0] quotient_r;
    reg [3:0] division_r;
    reg [13:0] sub_low_r;
    reg [12:0] shifted_high_r;
    reg [24:0] shifted_r;
    wire [25:0] shift_w;
    wire [13:0] sub_high_w;
    wire subtract_w;
    wire unused_exp_w;
    assign unused_exp_w = |exp_data_i[31:21];
    assign shift_w = {remainder_r, quotient_r[11]};
    assign sub_high_w = {1'b0, shifted_high_r} - {2'b0, den_r[24:13]}
        - {13'd0, sub_low_r[13]};
    assign subtract_w = !sub_high_w[13];
    assign exp_en_o = valid_r[0];
    assign exp_addr_o = difference_r;
    assign distance_o = quotient_r;
    assign done_o = state_r == S_DONE;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            index_r <= 4'd0;
            valid_r <= 4'd0;
            division_r <= 4'd0;
        end else if (cancel_i) begin
            state_r <= S_IDLE;
            valid_r <= 4'd0;
        end else begin
            valid_r <= {valid_r[2:0], state_r == S_EXP};
            case (state_r)
                S_IDLE: begin
                    if (start_i) begin
                        state_r <= S_PEAK;
                        index_r <= 4'd0;
                    end
                end
                S_PEAK: state_r <= S_PEAK_UPDATE;
                S_PEAK_UPDATE: begin
                    index_r <= index_r + 4'd1;
                    state_r <= index_r == 4'd15 ? S_EXP : S_PEAK;
                end
                S_EXP: begin
                    index_r <= index_r + 4'd1;
                    if (index_r == 4'd15) state_r <= S_SUM;
                end
                S_SUM: begin
                    if (valid_r[3] && bin_r[3] == 4'd15) state_r <= S_ROUND;
                end
                S_ROUND: state_r <= S_DIV_INIT;
                S_DIV_INIT: begin
                    state_r <= S_DIV_LOW;
                    division_r <= 4'd11;
                end
                S_DIV_LOW: state_r <= S_DIV_HIGH;
                S_DIV_HIGH: state_r <= S_DIV_SELECT;
                S_DIV_SELECT: begin
                    division_r <= division_r - 4'd1;
                    state_r <= (division_r == 4'd0) ? S_DONE : S_DIV_LOW;
                end
                S_DONE: state_r <= S_IDLE;
                default: begin end
            endcase
        end
    end
    (* keep = "true", syn_preserve = 1 *) reg [2:0] initialize_copy_r;
    genvar initialize_region;
    generate
        for (initialize_region = 0; initialize_region < 3;
            initialize_region = initialize_region + 1) begin : g_initialize_region
            always @(posedge clk_i) begin
                initialize_copy_r[initialize_region] <= cancel_i || state_r == S_DONE
                    || (state_r == S_IDLE && !start_i);
            end
        end
    endgenerate
    wire [127:0] rotate_w;
    assign rotate_w = {bins_r[7:0], bins_r[127:8]};
    genvar region;
    generate
        for (region = 0; region < 4; region = region + 1) begin : g_bins_region
            (* keep = "true", syn_preserve = 1 *) reg input_copy_r;
            (* keep = "true", syn_preserve = 1 *) reg rotate_copy_r;
            always @(posedge clk_i) begin
                input_copy_r <= cancel_i || state_r == S_DONE
                    || (state_r == S_IDLE && !start_i);
                rotate_copy_r <= (state_r == S_IDLE && start_i)
                    || state_r == S_PEAK_UPDATE || (state_r == S_EXP && index_r != 4'd15);
                if (input_copy_r) bins_r[32*region+:32] <= bins_i[32*region+:32];
                if (rotate_copy_r) bins_r[32*region+:32] <= rotate_w[32*region+:32];
            end
        end
    endgenerate
    integer stage;
    always @(posedge clk_i) begin
        if (state_r == S_PEAK) begin
            peak_greater_r <= $signed(bins_r[7:0]) > peak_r;
            peak_bin_r <= bins_r[7:0];
        end
        if (initialize_copy_r[0]) peak_r <= -8'sd128;
        else if (state_r == S_PEAK_UPDATE && peak_greater_r) peak_r <= peak_bin_r;
        difference_r <= peak_r - $signed(bins_r[7:0]);
        bin_r[0] <= index_r;
        for (stage = 1; stage < 4; stage = stage + 1) bin_r[stage] <= bin_r[stage-1];
        // RAM output is sampled directly into the APM input/product register.
        product_r <= {21'd0, bin_r[2]} * {4'd0, exp_data_i[20:0]};
        product_weight_r <= exp_data_i[20:0];
        if (initialize_copy_r[1]) den_r <= 25'd0;
        else if (accumulate_copy_r[0]) den_r <= den_r + {4'd0, product_weight_r};
        if (initialize_copy_r[2]) num_r <= 28'd0;
        else if (accumulate_copy_r[1]) num_r <= num_r + {3'd0, product_r};

    end
    (* keep = "true", syn_preserve = 1 *) reg [2:0] init_copy_r;
    (* keep = "true", syn_preserve = 1 *) reg [2:0] low_copy_r;
    (* keep = "true", syn_preserve = 1 *) reg [2:0] select_copy_r;
    (* keep = "true", syn_preserve = 1 *) reg [1:0] subtract_copy_r;
    genvar divide_region;
    generate
        for (divide_region = 0; divide_region < 3;
            divide_region = divide_region + 1) begin : g_divide_region
            always @(posedge clk_i) begin
                init_copy_r[divide_region] <= state_r == S_ROUND;
                low_copy_r[divide_region] <= state_r == S_DIV_INIT
                    || (state_r == S_DIV_SELECT && division_r != 4'd0);
                select_copy_r[divide_region] <= state_r == S_DIV_HIGH;
            end
            if (divide_region < 2) begin : g_subtract
                always @(posedge clk_i) begin
                    if (state_r == S_DIV_HIGH) subtract_copy_r[divide_region] <= subtract_w;
                end
            end
        end
    endgenerate
    always @(posedge clk_i) begin
        if (init_copy_r[0]) remainder_r[12:0] <= rounded_r[24:12];
        else if (select_copy_r[0]) remainder_r[12:0] <= subtract_copy_r[0]
            ? sub_low_r[12:0] : shifted_r[12:0];
        if (init_copy_r[1]) remainder_r[24:13] <= {1'b0, rounded_r[35:25]};
        else if (select_copy_r[1]) remainder_r[24:13] <= subtract_copy_r[1]
            ? sub_high_w[11:0] : shifted_r[24:13];
        if (init_copy_r[2]) quotient_r <= rounded_r[11:0];
        else if (select_copy_r[2]) quotient_r <= {quotient_r[10:0], subtract_copy_r[0]};
        if (low_copy_r[0])
            sub_low_r <= {1'b0, shift_w[12:0]} - {1'b0, den_r[12:0]};
        if (low_copy_r[1]) shifted_high_r <= shift_w[25:13];
        if (low_copy_r[2]) shifted_r <= shift_w[24:0];
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] accumulate_copy_r;
    genvar accumulate_region;
    generate
        for (accumulate_region = 0; accumulate_region < 2;
            accumulate_region = accumulate_region + 1) begin : g_accumulate_region
            always @(posedge clk_i) accumulate_copy_r[accumulate_region] <= valid_r[2];
        end
    endgenerate
    wire [35:0] round_value_w;
    assign round_value_w = {num_r, 8'd0} + {12'd0, den_r[24:1]};
    (* keep = "true", syn_preserve = 1 *) reg [1:0] round_copy_r;
    genvar round_region;
    generate
        for (round_region = 0; round_region < 2; round_region = round_region + 1)
            begin : g_round_region
            always @(posedge clk_i) begin
                round_copy_r[round_region] <= state_r == S_SUM && valid_r[3]
                    && bin_r[3] == 4'd15;
                if (round_copy_r[round_region])
                    rounded_r[18*round_region+:18] <= round_value_w[18*round_region+:18];
            end
        end
    endgenerate
    wire unused_high_w;
    assign unused_high_w = sub_high_w[12];
endmodule
