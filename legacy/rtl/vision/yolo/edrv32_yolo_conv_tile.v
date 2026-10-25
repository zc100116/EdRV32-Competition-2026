// ============================================================================
// File        : edrv32_yolo_conv_tile.v
// Description : One 32-output-channel INT8 convolution tile around 512 MACs.
// Notes       : Preload K weight rows and pair-major activation patches, then
//               start. K is a multiple-of-eight reduction in 1x1 or 3x3
//               convolution order. Only final INT32 sums leave this module.
//               Require activation_base + pair_count * k_count <= 2048 and
//               k_count <= 512. Activation writes may preload a disjoint tile
//               while computation reads the active tile.
// ============================================================================

module edrv32_yolo_conv_tile (
    input  wire          clk_i,
    input  wire          rst_n_i,

    input  wire          weight_valid_i,
    output wire          weight_ready_o,
    input  wire [11:0]   weight_addr_i,
    input  wire [255:0]  weight_data_i,
    input  wire          activation_valid_i,
    output wire          activation_ready_o,
    input  wire [10:0]   activation_addr_i,
    input  wire [127:0]  activation_data_i,

    input  wire          start_i,
    output wire          start_ready_o,
    input  wire [10:0]   activation_base_i,
    input  wire [9:0]    k_count_i,
    input  wire [11:0]   pair_count_i,
    output wire          busy_o,
    output wire          done_o,
    output wire          mac_beat_o,

    output wire          result_valid_o,
    input  wire          result_ready_i,
    output wire          result_last_o,
    output wire [11:0]   result_pair_o,
    output wire [2047:0] result_accum_o
);

    reg busy_r;
    reg done_r;
    reg issuing_r;
    reg [9:0]  k_count_r;
    reg [11:0] pair_count_r;
    reg [8:0]  issue_k_r;
    reg [11:0] issue_pair_r;
    reg [11:0] activation_base_r;
    reg [11:0] result_pair_r;
    reg read_valid_r;
    reg read_first_r;
    reg read_last_r;
    reg mac_input_valid_r;
    reg mac_input_first_r;
    reg mac_input_last_r;
    wire [2047:0] mac_weight_w;
    // Four physically distinct local drivers limit each activation fanout to
    // eight output channels. Preserve the equivalent banks across synthesis.
    (* syn_preserve = 1 *) reg [127:0] activation_group0_r;
    (* syn_preserve = 1 *) reg [127:0] activation_group1_r;
    (* syn_preserve = 1 *) reg [127:0] activation_group2_r;
    (* syn_preserve = 1 *) reg [127:0] activation_group3_r;
    (* syn_keep = 1 *) wire [127:0] activation_group0_w = activation_group0_r;
    (* syn_keep = 1 *) wire [127:0] activation_group1_w = activation_group1_r;
    (* syn_keep = 1 *) wire [127:0] activation_group2_w = activation_group2_r;
    (* syn_keep = 1 *) wire [127:0] activation_group3_w = activation_group3_r;
    wire [511:0] mac_activation_w = {
        activation_group3_w, activation_group2_w,
        activation_group1_w, activation_group0_w};

    wire [11:0] activation_read_addr_w =
        activation_base_r + {3'b000, issue_k_r};
    wire last_k_w = {1'b0, issue_k_r} == k_count_r - 10'd1;
    wire last_issue_pair_w = issue_pair_r == pair_count_r - 12'd1;
    wire last_result_pair_w = result_pair_r == pair_count_r - 12'd1;
    wire read_issue_w;
    wire mac_in_ready_w;
    (* syn_keep = 1 *) wire [31:0] mac_group_ready_w;
    wire mac_out_valid_w;
    wire mac_out_last_w;
    wire result_transfer_w;
    wire [2047:0] weight_row_w;
    wire [127:0] activation_row_w;

    genvar weight_oc;
    generate
        for (weight_oc = 0; weight_oc < 32; weight_oc = weight_oc + 1)
            begin : g_weight_stage
            reg [63:0] weight_r;
            always @(posedge clk_i) begin
                if (mac_group_ready_w[weight_oc])
                    weight_r <= weight_row_w[weight_oc*64 +: 64];
            end
            assign mac_weight_w[weight_oc*64 +: 64] = weight_r;
        end
    endgenerate

    always @(posedge clk_i) begin
        if (mac_group_ready_w[0])
            activation_group0_r <= activation_row_w;
        if (mac_group_ready_w[8])
            activation_group1_r <= activation_row_w;
        if (mac_group_ready_w[16])
            activation_group2_r <= activation_row_w;
        if (mac_group_ready_w[24])
            activation_group3_r <= activation_row_w;
    end

    assign start_ready_o = !busy_r && k_count_i != 10'd0 &&
                           k_count_i <= 10'd512 && pair_count_i != 12'd0;
    assign weight_ready_o     = !busy_r && !start_i;
    assign activation_ready_o = !start_i;
    assign busy_o = busy_r;
    assign done_o = done_r;
    assign mac_beat_o = mac_input_valid_r && mac_in_ready_w;

    assign read_issue_w = issuing_r && mac_in_ready_w;
    assign result_valid_o = mac_out_valid_w && mac_out_last_w;
    assign result_last_o = last_result_pair_w;
    assign result_pair_o = result_pair_r;
    assign result_transfer_w = result_valid_o && result_ready_i;

    edrv32_yolo_tile_store u_tile_store (
        .clk_i                 (clk_i),
        .rst_n_i               (rst_n_i),
        .weight_wr_en_i        (weight_valid_i && weight_ready_o),
        .weight_wr_addr_i      (weight_addr_i),
        .weight_wr_data_i      (weight_data_i),
        .activation_wr_en_i    (activation_valid_i && activation_ready_o),
        .activation_wr_addr_i  (activation_addr_i),
        .activation_wr_data_i  (activation_data_i),
        .rd_en_i               (read_issue_w),
        .weight_rd_addr_i      (issue_k_r),
        .activation_rd_addr_i  (activation_read_addr_w[10:0]),
        .weight_rd_data_o      (weight_row_w),
        .activation_rd_data_o  (activation_row_w)
    );

    edrv32_yolo_mac_array #(
        .ACTIVATION_GROUPS(4),
        .FINAL_ONLY_BACKPRESSURE(1)
    ) u_mac_array (
        .clk_i           (clk_i),
        .rst_n_i         (rst_n_i),
        .in_valid_i      (mac_input_valid_r),
        .in_ready_o      (mac_in_ready_w),
        .in_group_ready_o(mac_group_ready_w),
        .in_first_i      (mac_input_first_r),
        .in_last_i       (mac_input_last_r),
        .in_activation_i (mac_activation_w),
        .in_weight_i     (mac_weight_w),
        .out_valid_o     (mac_out_valid_w),
        .out_ready_i     (result_ready_i),
        .out_last_o      (mac_out_last_w),
        .out_accum_o     (result_accum_o)
    );

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            busy_r            <= 1'b0;
            done_r            <= 1'b0;
            issuing_r         <= 1'b0;
            k_count_r         <= 10'b0;
            pair_count_r      <= 12'b0;
            issue_k_r         <= 9'b0;
            issue_pair_r      <= 12'b0;
            activation_base_r <= 12'b0;
            result_pair_r     <= 12'b0;
            read_valid_r      <= 1'b0;
            read_first_r      <= 1'b0;
            read_last_r       <= 1'b0;
            mac_input_valid_r <= 1'b0;
            mac_input_first_r <= 1'b0;
            mac_input_last_r  <= 1'b0;
        end else begin
            done_r <= 1'b0;
            if (start_i && start_ready_o) begin
                busy_r            <= 1'b1;
                issuing_r         <= 1'b1;
                k_count_r         <= k_count_i;
                pair_count_r      <= pair_count_i;
                issue_k_r         <= 9'b0;
                issue_pair_r      <= 12'b0;
                activation_base_r <= {1'b0, activation_base_i};
                result_pair_r     <= 12'b0;
                read_valid_r      <= 1'b0;
                mac_input_valid_r <= 1'b0;
            end else begin
                if (mac_in_ready_w) begin
                    mac_input_valid_r <= read_valid_r;
                    mac_input_first_r <= read_first_r;
                    mac_input_last_r  <= read_last_r;
                    read_valid_r <= read_issue_w;
                    if (read_issue_w) begin
                        read_first_r <= issue_k_r == 9'd0;
                        read_last_r  <= last_k_w;
                        if (last_k_w) begin
                            issue_k_r <= 9'b0;
                            if (last_issue_pair_w)
                                issuing_r <= 1'b0;
                            else begin
                                issue_pair_r <= issue_pair_r + 12'd1;
                                activation_base_r <=
                                    activation_base_r + {2'b00, k_count_r};
                            end
                        end else begin
                            issue_k_r <= issue_k_r + 9'd1;
                        end
                    end
                end
                if (result_transfer_w) begin
                    if (last_result_pair_w) begin
                        busy_r <= 1'b0;
                        done_r <= 1'b1;
                    end else begin
                        result_pair_r <= result_pair_r + 12'd1;
                    end
                end
            end
        end
    end

endmodule
