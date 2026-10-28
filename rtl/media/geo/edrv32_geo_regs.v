// File: edrv32_geo_regs.v
// Spec: geo-spec 4, 5.3, 6.
// Description: Whole-word APB register file, command pulses, sticky IRQ and performance counters.
// Clock domain: clk_mem.
module edrv32_geo_regs (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,
    // APB control.
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output wire apb_pready_o,
    output reg [31:0] apb_prdata_o,
    output wire apb_pslverr_o,
    // Command and completion events.
    input wire busy_i,
    input wire done_i,
    input wire desc_done_i,
    input wire [15:0] cur_desc_i,
    input wire [1:0] error_i,
    input wire [4:0] pixel_i,
    input wire read_beat_i,
    input wire write_beat_i,
    input wire source_wait_i,
    input wire writer_wait_i,
    output wire start_o,
    output wire abort_o,
    output wire soft_reset_o,
    output reg [31:0] desc_base_o,
    output reg [15:0] desc_count_o,
    // Interrupt.
    output wire irq_o
);
    wire write_w;
    wire unused_w;
    reg enable_r;
    reg [1:0] irq_en_r;
    reg [1:0] irq_stat_r;
    reg [1:0] err_code_r;
    reg [31:0] done_count_r;
    reg [31:0] perf_r [0:5];
    integer counter;
    assign unused_w = &apb_pstrb_i;
    assign write_w = apb_psel_i && apb_penable_i && apb_pwrite_i;
    assign start_o = write_w && apb_paddr_i == 12'h028 && !busy_i;
    assign abort_o = write_w && apb_paddr_i == 12'h004 && apb_pwdata_i[2];
    assign soft_reset_o = write_w && apb_paddr_i == 12'h004 &&
        apb_pwdata_i[3] && !busy_i;
    assign apb_pready_o = 1'b1;
    assign apb_pslverr_o = 1'b0;
    assign irq_o = |(irq_stat_r & irq_en_r);
    always @(*) begin
        apb_prdata_o = 32'd0;
        case (apb_paddr_i)
            12'h000: apb_prdata_o = 32'h00030001;
            12'h004: apb_prdata_o = {31'd0, enable_r};
            12'h008: apb_prdata_o = {29'd0, irq_stat_r[1], !busy_i, busy_i};
            12'h00c: apb_prdata_o = {30'd0, irq_en_r};
            12'h010: apb_prdata_o = {30'd0, irq_stat_r};
            12'h014: apb_prdata_o = {30'd0, err_code_r};
            12'h020: apb_prdata_o = desc_base_o;
            12'h024: apb_prdata_o = {16'd0, desc_count_o};
            12'h02c: apb_prdata_o = done_count_r;
            12'h040: apb_prdata_o = perf_r[0];
            12'h044: apb_prdata_o = perf_r[1];
            12'h048: apb_prdata_o = perf_r[2];
            12'h04c: apb_prdata_o = perf_r[3];
            12'h050: apb_prdata_o = perf_r[4];
            12'h054: apb_prdata_o = perf_r[5];
            12'h100: apb_prdata_o = {16'd0, cur_desc_i};
            default: apb_prdata_o = 32'd0;
        endcase
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            enable_r <= 1'b0;
            irq_en_r <= 2'd0;
            irq_stat_r <= 2'd0;
            err_code_r <= 2'd0;
            done_count_r <= 32'd0;
            desc_base_o <= 32'd0;
            desc_count_o <= 16'd0;
            for (counter = 0; counter < 6; counter = counter + 1)
                perf_r[counter] <= 32'd0;
        end else if (soft_reset_o) begin
            enable_r <= 1'b0;
            irq_en_r <= 2'd0;
            irq_stat_r <= 2'd0;
            err_code_r <= 2'd0;
            done_count_r <= 32'd0;
            desc_base_o <= 32'd0;
            desc_count_o <= 16'd0;
            for (counter = 0; counter < 6; counter = counter + 1)
                perf_r[counter] <= 32'd0;
        end else begin
            if (busy_i)
                perf_r[0] <= perf_r[0] + 32'd1;
            if (pixel_i != 0)
                perf_r[1] <= perf_r[1] + {27'd0, pixel_i};
            if (read_beat_i)
                perf_r[2] <= perf_r[2] + 32'd1;
            if (write_beat_i)
                perf_r[3] <= perf_r[3] + 32'd1;
            if (source_wait_i)
                perf_r[4] <= perf_r[4] + 32'd1;
            if (writer_wait_i)
                perf_r[5] <= perf_r[5] + 32'd1;
            if (write_w) begin
                case (apb_paddr_i)
                    12'h004: enable_r <= apb_pwdata_i[0];
                    12'h00c: irq_en_r <= apb_pwdata_i[1:0];
                    12'h010: begin
                        irq_stat_r <= irq_stat_r & ~apb_pwdata_i[1:0];
                        if (apb_pwdata_i[1])
                            err_code_r <= 2'd0;
                    end
                    12'h020: desc_base_o <= {apb_pwdata_i[31:5], 5'd0};
                    12'h024: desc_count_o <= apb_pwdata_i[15:0];
                    default: begin end
                endcase
            end
            if (desc_done_i)
                done_count_r <= done_count_r + 32'd1;
            if (start_o) begin
                for (counter = 0; counter < 6; counter = counter + 1)
                    perf_r[counter] <= 32'd0;
            end
            // Hardware events win over simultaneous RW1C writes.
            if (done_i || (start_o && desc_count_o == 0))
                irq_stat_r[0] <= 1'b1;
            if (error_i != 0) begin
                irq_stat_r[1] <= 1'b1;
                err_code_r <= error_i;
            end
        end
    end
endmodule
