// File: edrv32_npu_regs.v
// Spec: npu-spec 4; edrv32-soc-spec 7.1.
// Description: APB register bank, doorbell, specified interrupts and two counters.
// IDLE soft reset restores every architectural register (N-C1 coordinator answer).
// Clock: clk_npu.
module edrv32_npu_regs (
    // Clock and domain-local reset.
    input wire clk_i,
    input wire rst_n_i,

    // Local side of the X10 APB bridge; full-word writes, pstrb ignored.
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output wire apb_pready_o,
    output reg [31:0] apb_prdata_o,
    output wire apb_pslverr_o,

    // Execution events and software configuration.
    input wire busy_i,
    input wire done_i,
    input wire error_i,
    input wire [2:0] error_code_i,
    input wire [31:0] cur_desc_i,
    input wire [1:0] perf_event_i,
    output reg start_o,
    output reg abort_o,
    output reg soft_reset_o,
    output wire [31:0] desc_base_o,
    output wire [31:0] desc_count_o,
    output wire [127:0] bases_o,

    // Post configuration and the final write-response publication event (spec 2.4).
    output wire [1:0] post_ctrl_o,
    output wire [31:0] post_base_o,
    output wire [26:0] post_int8_th_o,
    output wire [31:0] post_prob_th_o,
    input wire [12:0] post_count_i,

    // Level interrupt in clk_npu.
    output wire irq_o
);
    reg [11:0] apb_paddr_r;
    reg apb_pwrite_r;
    reg [31:0] apb_pwdata_r;
    reg [3:0] apb_pstrb_r;

    // SoC 4.3: the bridge's setup edge owns the complete local request payload.
    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            apb_paddr_r <= apb_paddr_i;
            apb_pwrite_r <= apb_pwrite_i;
            apb_pwdata_r <= apb_pwdata_i;
            apb_pstrb_r <= apb_pstrb_i;
        end
    end

    reg [1:0] post_ctrl_r;
    reg [31:0] post_base_r;
    reg [8:0] post_int8_th_r [0:2];
    reg [31:0] post_prob_th_r;
    reg [12:0] post_count_r;
    reg post_done_r;
    assign post_ctrl_o = post_ctrl_r;
    assign post_base_o = post_base_r;
    assign post_int8_th_o = {post_int8_th_r[2], post_int8_th_r[1], post_int8_th_r[0]};
    assign post_prob_th_o = post_prob_th_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            post_ctrl_r <= 2'd0;
            post_base_r <= 32'd0;
            post_int8_th_r[0] <= 9'd0;
            post_int8_th_r[1] <= 9'd0;
            post_int8_th_r[2] <= 9'd0;
            post_prob_th_r <= 32'd0;
            post_count_r <= 13'd0;
            post_done_r <= 1'b0;
        end else if (soft_reset_w) begin
            post_ctrl_r <= 2'd0;
            post_base_r <= 32'd0;
            post_int8_th_r[0] <= 9'd0;
            post_int8_th_r[1] <= 9'd0;
            post_int8_th_r[2] <= 9'd0;
            post_prob_th_r <= 32'd0;
            post_count_r <= 13'd0;
            post_done_r <= 1'b0;
        end else begin
            if (write_w && !busy_i) begin
                case (apb_paddr_r)
                    12'h114: post_ctrl_r <= apb_pwdata_r[1:0];
                    12'h118: post_base_r <= apb_pwdata_r;
                    12'h11c: post_int8_th_r[0] <= apb_pwdata_r[8:0];
                    12'h120: post_int8_th_r[1] <= apb_pwdata_r[8:0];
                    12'h124: post_int8_th_r[2] <= apb_pwdata_r[8:0];
                    12'h128: post_prob_th_r <= apb_pwdata_r;
                    default: begin end
                endcase
            end
            if (start_w) begin
                post_count_r <= 13'd0;
                post_done_r <= 1'b0;
            end else if (done_i && post_ctrl_r[0]) begin
                post_count_r <= post_count_i;
                post_done_r <= 1'b1;
            end
        end
    end
    reg enable_r;
    reg [31:0] irq_en_r;
    reg [1:0] irq_stat_r;
    reg [2:0] error_code_r;
    reg [31:0] desc_base_r;
    reg [31:0] desc_count_r;
    reg [31:0] done_count_r;
    reg [31:0] bases_r [0:3];
    reg [31:0] perf_r [0:1];
    reg [1:0] perf_event_r;
    reg [1:0] perf_clear_r /* synthesis syn_preserve=1 */;
    wire start_w;
    wire abort_w;
    wire soft_reset_w;
    wire write_w;
    wire irq_clear_w;
    wire unused_pstrb_w;
    assign unused_pstrb_w = |apb_pstrb_r;
    assign write_w = apb_psel_i && apb_penable_i && apb_pwrite_r;
    assign irq_clear_w = write_w && (apb_paddr_r == 12'h010);
    assign start_w = write_w && (apb_paddr_r == 12'h028) && !busy_i;
    assign abort_w = write_w && (apb_paddr_r == 12'h004) && apb_pwdata_r[2];
    assign soft_reset_w = write_w && (apb_paddr_r == 12'h004)
        && apb_pwdata_r[3] && !busy_i;
    // SoC 7.1: register write side effects before the engine consumes them.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            start_o <= 1'b0;
            abort_o <= 1'b0;
            soft_reset_o <= 1'b0;
        end else begin
            start_o <= start_w;
            abort_o <= abort_w;
            soft_reset_o <= soft_reset_w;
        end
    end
    assign apb_pready_o = 1'b1;
    assign apb_pslverr_o = 1'b0;
    assign irq_o = |(irq_en_r[1:0] & irq_stat_r);
    assign desc_base_o = desc_base_r;
    assign desc_count_o = desc_count_r;
    assign bases_o = {bases_r[3], bases_r[2], bases_r[1], bases_r[0]};

    // SoC 7.1: events and DOORBELL clear take effect together one edge later.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            perf_event_r <= 2'd0;
            perf_clear_r <= 2'd0;
        end else if (soft_reset_w) begin
            perf_event_r <= 2'd0;
            perf_clear_r <= 2'd0;
        end else begin
            perf_event_r <= perf_event_i;
            perf_clear_r <= {2{start_w}};
        end
    end

    always @(*) begin
        apb_prdata_o = 32'd0;
        case (apb_paddr_r)
            12'h000: apb_prdata_o = 32'h00060001;
            12'h004: apb_prdata_o = {31'd0, enable_r};
            12'h008: apb_prdata_o = {29'd0, irq_stat_r[1], !busy_i, busy_i};
            12'h00c: apb_prdata_o = irq_en_r;
            12'h010: apb_prdata_o = {30'd0, irq_stat_r};
            12'h014: apb_prdata_o = {29'd0, error_code_r};
            12'h020: apb_prdata_o = desc_base_r;
            12'h024: apb_prdata_o = desc_count_r;
            12'h02c: apb_prdata_o = done_count_r;
            12'h100: apb_prdata_o = bases_r[0];
            12'h104: apb_prdata_o = bases_r[1];
            12'h108: apb_prdata_o = bases_r[2];
            12'h10c: apb_prdata_o = bases_r[3];
            12'h110: apb_prdata_o = cur_desc_i;
            12'h114: apb_prdata_o = {30'd0, post_ctrl_r};
            12'h118: apb_prdata_o = post_base_r;
            12'h11c: apb_prdata_o = {23'd0, post_int8_th_r[0]};
            12'h120: apb_prdata_o = {23'd0, post_int8_th_r[1]};
            12'h124: apb_prdata_o = {23'd0, post_int8_th_r[2]};
            12'h128: apb_prdata_o = post_prob_th_r;
            12'h12c: apb_prdata_o = {19'd0, post_count_r};
            12'h130: apb_prdata_o = {31'd0, post_done_r};
            default: begin
                if ((apb_paddr_r >= 12'h040) && (apb_paddr_r < 12'h048)
                    && (apb_paddr_r[1:0] == 2'd0)) begin
                    apb_prdata_o = perf_r[apb_paddr_r[2]];
                end
            end
        endcase
    end

    // Small status fields retain their access-edge side effects.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            enable_r <= 1'b0;
            irq_stat_r <= 2'd0;
            error_code_r <= 3'd0;
        end else if (soft_reset_w) begin
            enable_r <= 1'b0;
            irq_stat_r <= 2'd0;
            error_code_r <= 3'd0;
        end else begin
            if (write_w && apb_paddr_r == 12'h004) begin
                enable_r <= apb_pwdata_r[0];
            end
            if (irq_clear_w) begin
                irq_stat_r <= irq_stat_r & ~apb_pwdata_r[1:0];
                if (apb_pwdata_r[1]) begin
                    error_code_r <= 3'd0;
                end
            end
            if (done_i) begin
                irq_stat_r[0] <= 1'b1;
            end
            if (error_i) begin
                irq_stat_r[1] <= 1'b1;
                error_code_r <= error_code_i;
            end
        end
    end
    genvar config_bank;
    generate
        for (config_bank = 0; config_bank < 8; config_bank = config_bank + 1)
            begin : g_config_bank
            localparam [11:0] BANK = config_bank;
            localparam [11:0] ADDR = (config_bank == 0) ? 12'h00c
                : (config_bank == 1) ? 12'h020 : (config_bank == 2) ? 12'h024
                : (config_bank == 3) ? 12'h02c : 12'h0f0 + (BANK << 2);
            (* keep = "true", syn_preserve = 1 *) reg soft_select_r;
            (* keep = "true", syn_preserve = 1 *) reg write_select_r;
            (* keep = "true", syn_keep = 1 *) wire soft_w;
            wire unused_write_bank_w;
            always @(posedge clk_i) begin
                soft_select_r <= apb_paddr_i == 12'h004 && apb_pwdata_i[3];
                write_select_r <= apb_paddr_i == ADDR;
            end
            assign soft_w = write_w && soft_select_r && !busy_i;
            assign unused_write_bank_w = write_w && write_select_r;
            if (config_bank == 0) begin : g_irq
                always @(posedge clk_i or negedge rst_n_i) begin
                    if (!rst_n_i) irq_en_r <= 32'd0;
                    else if (soft_w) irq_en_r <= 32'd0;
                    else if (unused_write_bank_w) irq_en_r <= apb_pwdata_r;
                end
            end else if (config_bank == 1) begin : g_base
                always @(posedge clk_i or negedge rst_n_i) begin
                    if (!rst_n_i) desc_base_r <= 32'd0;
                    else if (soft_w) desc_base_r <= 32'd0;
                    else if (unused_write_bank_w) desc_base_r <= apb_pwdata_r;
                end
            end else if (config_bank == 2) begin : g_count
                always @(posedge clk_i or negedge rst_n_i) begin
                    if (!rst_n_i) desc_count_r <= 32'd0;
                    else if (soft_w) desc_count_r <= 32'd0;
                    else if (unused_write_bank_w) desc_count_r <= apb_pwdata_r;
                end
            end else if (config_bank == 3) begin : g_done
                always @(posedge clk_i or negedge rst_n_i) begin
                    if (!rst_n_i) done_count_r <= 32'd0;
                    else if (soft_w) done_count_r <= 32'd0;
                    else if (done_i) done_count_r <= done_count_r + 32'd1;
                end
            end else begin : g_surface
                always @(posedge clk_i or negedge rst_n_i) begin
                    if (!rst_n_i) bases_r[config_bank-4] <= 32'd0;
                    else if (soft_w) bases_r[config_bank-4] <= 32'd0;
                    else if (unused_write_bank_w) bases_r[config_bank-4] <= apb_pwdata_r;
                end
            end
        end
    endgenerate
    // Capture identical APB payload copies at SETUP for each performance bank.
    genvar perf_bank;
    generate
        for (perf_bank = 0; perf_bank < 2; perf_bank = perf_bank + 1) begin : g_perf_bank
            (* keep = "true", syn_preserve = 1 *) reg [11:0] soft_addr_r;
            (* keep = "true", syn_preserve = 1 *) reg soft_data_r;
            (* keep = "true", syn_keep = 1 *) wire soft_w;
            always @(posedge clk_i) begin
                if (apb_psel_i && !apb_penable_i) begin
                    soft_addr_r <= apb_paddr_i;
                    soft_data_r <= apb_pwdata_i[3];
                end
            end
            assign soft_w = write_w && soft_addr_r == 12'h004 && soft_data_r && !busy_i;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    perf_r[perf_bank] <= 32'd0;
                else if (soft_w || perf_clear_r[perf_bank])
                    perf_r[perf_bank] <= 32'd0;
                else if (perf_event_r[perf_bank])
                    perf_r[perf_bank] <= perf_r[perf_bank] + 32'd1;
            end
        end
    endgenerate
endmodule
