// File: edrv32_fpga_probe_gpu2_banks_lutram_top.v
// Spec: gpu-v2-spec 2.4/2.6; G-P03/G-P04.
// Description: C12 memories and 72 independent scratch banks.
//              Local stimulus and observation registers preserve measured boundaries.
// Clock domain: clk_gpu, 220 MHz probe constraint.
module edrv32_fpga_probe_gpu2_banks_lutram_top (
    input wire clk_i,
    input wire rst_n_i,
    input wire stim_i,
    output wire obs_o
);
    // Registered input tree: one root has eight loads, leaves have nine bank loads.
    (* keep = "true", syn_preserve = 1 *) reg [7:0] stimulus_root_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) stimulus_root_r <= 8'b0;
        else stimulus_root_r <= {8{stim_i}};
    end
    wire [71:0] bank_observation_w;
    wire [71:0] setup_wr_en_w;
    wire [287:0] setup_wr_addr_w;
    wire [6623:0] setup_wr_data_w;
    wire [71:0] setup_rd_en_w;
    wire [287:0] setup_rd_addr_w;
    wire [6623:0] setup_rd_data_w;
    genvar bank;
    generate
        for (bank = 0; bank < 72; bank = bank+1) begin : g_bank
            (* keep = "true", syn_preserve = 1 *) reg [101:0] stimulus_r;
            reg observation_r;
            always @(posedge clk_i) begin
                stimulus_r <= {stimulus_r[100:0], stimulus_r[101] ^
                    stimulus_r[97] ^ stimulus_root_r[bank/9]};
                observation_r <= ^setup_rd_data_w[bank*92 +: 92];
            end
            assign setup_wr_en_w[bank] = stimulus_r[0];
            assign setup_rd_en_w[bank] = stimulus_r[1];
            assign setup_wr_addr_w[bank*4 +: 4] = stimulus_r[5:2];
            assign setup_rd_addr_w[bank*4 +: 4] = stimulus_r[9:6];
            assign setup_wr_data_w[bank*92 +: 92] = stimulus_r[101:10];
            assign bank_observation_w[bank] = observation_r;
        end
    endgenerate
    wire [7:0] group_observation_w;
    genvar group_idx;
    generate
        for (group_idx = 0; group_idx < 8; group_idx = group_idx+1) begin : g_group
            reg observation_r;
            always @(posedge clk_i) begin
                observation_r <= ^bank_observation_w[group_idx*9 +: 9];
            end
            assign group_observation_w[group_idx] = observation_r;
        end
    endgenerate
    (* keep = "true", syn_preserve = 1 *) reg [0:0] rf_wr_en_r;
    always @(posedge clk_i) begin
        rf_wr_en_r <=
            stimulus_root_r[1];
    end
    (* keep = "true", syn_preserve = 1 *) reg [8:0] rf_wr_addr_r;
    always @(posedge clk_i) begin
        rf_wr_addr_r <=
            {rf_wr_addr_r[7:0], rf_wr_addr_r[8] ^ stimulus_root_r[2]};
    end
    (* keep = "true", syn_preserve = 1 *) reg [127:0] rf_wr_data_r;
    always @(posedge clk_i) begin
        rf_wr_data_r <=
            {rf_wr_data_r[126:0], rf_wr_data_r[127] ^ stimulus_root_r[3]};
    end
    (* keep = "true", syn_preserve = 1 *) reg [2:0] rf_rd_en_r;
    always @(posedge clk_i) begin
        rf_rd_en_r <=
            {rf_rd_en_r[1:0], rf_rd_en_r[2] ^ stimulus_root_r[4]};
    end
    (* keep = "true", syn_preserve = 1 *) reg [26:0] rf_rd_addr_r;
    always @(posedge clk_i) begin
        rf_rd_addr_r <=
            {rf_rd_addr_r[25:0], rf_rd_addr_r[26] ^ stimulus_root_r[5]};
    end
    wire [383:0] rf_rd_data_w;
    reg rf_rd_data_observed_r;
    always @(posedge clk_i) begin
        rf_rd_data_observed_r <= ^rf_rd_data_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [0:0] const_wr_en_r;
    always @(posedge clk_i) begin
        const_wr_en_r <=
            stimulus_root_r[7];
    end
    (* keep = "true", syn_preserve = 1 *) reg [6:0] const_wr_addr_r;
    always @(posedge clk_i) begin
        const_wr_addr_r <=
            {const_wr_addr_r[5:0], const_wr_addr_r[6] ^ stimulus_root_r[0]};
    end
    (* keep = "true", syn_preserve = 1 *) reg [127:0] const_wr_data_r;
    always @(posedge clk_i) begin
        const_wr_data_r <=
            {const_wr_data_r[126:0], const_wr_data_r[127] ^ stimulus_root_r[1]};
    end
    (* keep = "true", syn_preserve = 1 *) reg [1:0] const_rd_en_r;
    always @(posedge clk_i) begin
        const_rd_en_r <=
            {const_rd_en_r[0:0], const_rd_en_r[1] ^ stimulus_root_r[2]};
    end
    (* keep = "true", syn_preserve = 1 *) reg [13:0] const_rd_addr_r;
    always @(posedge clk_i) begin
        const_rd_addr_r <=
            {const_rd_addr_r[12:0], const_rd_addr_r[13] ^ stimulus_root_r[3]};
    end
    wire [255:0] const_rd_data_w;
    reg const_rd_data_observed_r;
    always @(posedge clk_i) begin
        const_rd_data_observed_r <= ^const_rd_data_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [0:0] program_wr_en_r;
    always @(posedge clk_i) begin
        program_wr_en_r <=
            stimulus_root_r[5];
    end
    (* keep = "true", syn_preserve = 1 *) reg [9:0] program_wr_addr_r;
    always @(posedge clk_i) begin
        program_wr_addr_r <=
            {program_wr_addr_r[8:0], program_wr_addr_r[9] ^ stimulus_root_r[6]};
    end
    (* keep = "true", syn_preserve = 1 *) reg [159:0] program_wr_data_r;
    always @(posedge clk_i) begin
        program_wr_data_r <=
            {program_wr_data_r[158:0], program_wr_data_r[159] ^ stimulus_root_r[7]};
    end
    (* keep = "true", syn_preserve = 1 *) reg [0:0] program_rd_en_r;
    always @(posedge clk_i) begin
        program_rd_en_r <=
            stimulus_root_r[0];
    end
    (* keep = "true", syn_preserve = 1 *) reg [9:0] program_rd_addr_r;
    always @(posedge clk_i) begin
        program_rd_addr_r <=
            {program_rd_addr_r[8:0], program_rd_addr_r[9] ^ stimulus_root_r[1]};
    end
    wire [159:0] program_rd_data_w;
    reg program_rd_data_observed_r;
    always @(posedge clk_i) begin
        program_rd_data_observed_r <= ^program_rd_data_w;
    end
    edrv32_gpu2_banks_lutram u_probe (
        .clk_i(clk_i),
        .rf_wr_en_i(rf_wr_en_r),
        .rf_wr_addr_i(rf_wr_addr_r),
        .rf_wr_data_i(rf_wr_data_r),
        .rf_rd_en_i(rf_rd_en_r),
        .rf_rd_addr_i(rf_rd_addr_r),
        .rf_rd_data_o(rf_rd_data_w),
        .const_wr_en_i(const_wr_en_r),
        .const_wr_addr_i(const_wr_addr_r),
        .const_wr_data_i(const_wr_data_r),
        .const_rd_en_i(const_rd_en_r),
        .const_rd_addr_i(const_rd_addr_r),
        .const_rd_data_o(const_rd_data_w),
        .program_wr_en_i(program_wr_en_r),
        .program_wr_addr_i(program_wr_addr_r),
        .program_wr_data_i(program_wr_data_r),
        .program_rd_en_i(program_rd_en_r),
        .program_rd_addr_i(program_rd_addr_r),
        .program_rd_data_o(program_rd_data_w),
        .setup_wr_en_i(setup_wr_en_w),
        .setup_wr_addr_i(setup_wr_addr_w),
        .setup_wr_data_i(setup_wr_data_w),
        .setup_rd_en_i(setup_rd_en_w),
        .setup_rd_addr_i(setup_rd_addr_w),
        .setup_rd_data_o(setup_rd_data_w)
    );
    reg observation_r;
    always @(posedge clk_i) begin
        observation_r <= ^group_observation_w ^
            rf_rd_data_observed_r ^
            const_rd_data_observed_r ^
            program_rd_data_observed_r;
    end
    assign obs_o = observation_r;
endmodule
