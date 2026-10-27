// File: edrv32_npu_regs.v
// Spec: npu-spec 4; edrv32-soc-spec 7.1.
// Description: APB register bank, doorbell, specified interrupts and eight counters.
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
    input wire [7:0] perf_event_i,
    output wire start_o,
    output wire abort_o,
    output wire soft_reset_o,
    output wire [31:0] desc_base_o,
    output wire [31:0] desc_count_o,
    output wire [127:0] bases_o,

    // Level interrupt in clk_npu.
    output wire irq_o
);
    reg enable_r;
    reg [31:0] irq_en_r;
    reg [1:0] irq_stat_r;
    reg [2:0] error_code_r;
    reg [31:0] desc_base_r;
    reg [31:0] desc_count_r;
    reg [31:0] done_count_r;
    reg [31:0] bases_r [0:3];
    reg [31:0] perf_r [0:7];
    wire write_w;
    wire irq_clear_w;
    wire unused_pstrb_w;
    integer counter_idx;
    assign unused_pstrb_w = |apb_pstrb_i;
    assign write_w = apb_psel_i && apb_penable_i && apb_pwrite_i;
    assign irq_clear_w = write_w && (apb_paddr_i == 12'h010);
    assign start_o = write_w && (apb_paddr_i == 12'h028) && !busy_i;
    assign abort_o = write_w && (apb_paddr_i == 12'h004) && apb_pwdata_i[2];
    assign soft_reset_o = write_w && (apb_paddr_i == 12'h004)
        && apb_pwdata_i[3] && !busy_i;
    assign apb_pready_o = 1'b1;
    assign apb_pslverr_o = 1'b0;
    assign irq_o = |(irq_en_r[1:0] & irq_stat_r);
    assign desc_base_o = desc_base_r;
    assign desc_count_o = desc_count_r;
    assign bases_o = {bases_r[3], bases_r[2], bases_r[1], bases_r[0]};

    always @(*) begin
        apb_prdata_o = 32'd0;
        case (apb_paddr_i)
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
            default: begin
                if ((apb_paddr_i >= 12'h040) && (apb_paddr_i < 12'h060)
                    && (apb_paddr_i[1:0] == 2'd0)) begin
                    apb_prdata_o = perf_r[apb_paddr_i[4:2]];
                end
            end
        endcase
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            enable_r <= 1'b0;
            irq_en_r <= 32'd0;
            irq_stat_r <= 2'd0;
            error_code_r <= 3'd0;
            desc_base_r <= 32'd0;
            desc_count_r <= 32'd0;
            done_count_r <= 32'd0;
            for (counter_idx = 0; counter_idx < 4; counter_idx = counter_idx + 1) begin
                bases_r[counter_idx] <= 32'd0;
            end
            for (counter_idx = 0; counter_idx < 8; counter_idx = counter_idx + 1) begin
                perf_r[counter_idx] <= 32'd0;
            end
        end else if (soft_reset_o) begin
            enable_r <= 1'b0;
            irq_en_r <= 32'd0;
            irq_stat_r <= 2'd0;
            error_code_r <= 3'd0;
            desc_base_r <= 32'd0;
            desc_count_r <= 32'd0;
            done_count_r <= 32'd0;
            for (counter_idx = 0; counter_idx < 4; counter_idx = counter_idx + 1) begin
                bases_r[counter_idx] <= 32'd0;
            end
            for (counter_idx = 0; counter_idx < 8; counter_idx = counter_idx + 1) begin
                perf_r[counter_idx] <= 32'd0;
            end
        end else begin
            if (write_w) begin
                case (apb_paddr_i)
                    12'h004: enable_r <= apb_pwdata_i[0];
                    12'h00c: irq_en_r <= apb_pwdata_i;
                    12'h020: desc_base_r <= apb_pwdata_i;
                    12'h024: desc_count_r <= apb_pwdata_i;
                    12'h100: bases_r[0] <= apb_pwdata_i;
                    12'h104: bases_r[1] <= apb_pwdata_i;
                    12'h108: bases_r[2] <= apb_pwdata_i;
                    12'h10c: bases_r[3] <= apb_pwdata_i;
                    default: begin end
                endcase
            end
            if (irq_clear_w) begin
                irq_stat_r <= irq_stat_r & ~apb_pwdata_i[1:0];
                if (apb_pwdata_i[1]) begin
                    error_code_r <= 3'd0;
                end
            end
            if (done_i) begin
                irq_stat_r[0] <= 1'b1;
                done_count_r <= done_count_r + 32'd1;
            end
            if (error_i) begin
                irq_stat_r[1] <= 1'b1;
                error_code_r <= error_code_i;
            end
            for (counter_idx = 0; counter_idx < 8; counter_idx = counter_idx + 1) begin
                if (start_o) begin
                    perf_r[counter_idx] <= 32'd0;
                end else if (perf_event_i[counter_idx]) begin
                    perf_r[counter_idx] <= perf_r[counter_idx] + 32'd1;
                end
            end
        end
    end
endmodule
