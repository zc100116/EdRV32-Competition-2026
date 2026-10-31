// File: edrv32_rnd_regs.v
// Spec: rnd-spec 3, 4, 5.1, 5.3, 6; SoC 4.3, 7.1.
// Description: Always-ready APB registers, command/list accounting and performance counters.
//              ENABLE is readable state; DOORBELL is gated only by BUSY.
// Clock domain: clk_mem (clk_i).
module edrv32_rnd_regs (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Media APB slave.
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output wire apb_pready_o,
    output reg [31:0] apb_prdata_o,
    output wire apb_pslverr_o,

    // Execution events and the programming interface.
    input wire busy_i,
    input wire command_done_i,
    input wire list_done_i,
    input wire [1:0] error_i,
    input wire [4:0] pixel_count_i,
    input wire read_beat_i,
    input wire write_beat_i,
    input wire read_wait_i,
    input wire write_wait_i,
    output wire start_o,
    output wire abort_o,
    output wire soft_reset_o,
    output wire [31:0] desc_base_o,
    output wire [15:0] desc_count_o,
    output wire [31:0] cur_desc_o,

    // Interrupt.
    output wire irq_o
);
    // SoC 4.3: the shared APB payload only drives setup registers.
    reg [11:0] apb_paddr_r;
    reg apb_pwrite_r;
    reg [31:0] apb_pwdata_r;
    reg [3:0] apb_pstrb_r;
    reg start_r;
    reg abort_r;
    reg soft_reset_r;
    reg busy_r;
    reg [4:0] pixel_count_r;
    reg read_beat_r;
    reg write_beat_r;
    reg read_wait_r;
    reg write_wait_r;
    reg enable_r;
    reg [1:0] irq_en_r;
    reg [1:0] irq_stat_r;
    reg [1:0] err_code_r;
    reg [31:0] desc_base_r;
    reg [15:0] desc_count_r;
    reg [31:0] cur_desc_r;
    reg [31:0] done_count_r;
    reg [31:0] perf_r [0:5];
    wire [5:0] pixel_sum_w;
    // A five-bit increment carries at most once into the high counter segment.
    assign pixel_sum_w = {1'b0, perf_r[1][4:0]} + {1'b0, pixel_count_r};
    wire write_w;
    wire start_w;
    wire abort_w;
    wire soft_reset_w;
    wire unused_pstrb_w;
    integer count;
    assign write_w = apb_psel_i && apb_penable_i && apb_pwrite_r;
    assign start_w = write_w && apb_paddr_r == 12'h028 && !busy_i;
    assign abort_w = write_w && apb_paddr_r == 12'h004 && apb_pwdata_r[2];
    assign soft_reset_w = write_w && apb_paddr_r == 12'h004 &&
        apb_pwdata_r[3] && !busy_i;
    assign start_o = start_r;
    assign abort_o = abort_r;
    assign soft_reset_o = soft_reset_r;
    assign apb_pready_o = 1'b1;
    assign apb_pslverr_o = 1'b0;
    assign desc_base_o = desc_base_r;
    assign desc_count_o = desc_count_r;
    assign cur_desc_o = cur_desc_r;
    assign irq_o = |(irq_stat_r & irq_en_r);
    assign unused_pstrb_w = ^apb_pstrb_r;

    always @(posedge clk_i) begin
        if (apb_psel_i && !apb_penable_i) begin
            apb_paddr_r <= apb_paddr_i;
            apb_pwrite_r <= apb_pwrite_i;
            apb_pwdata_r <= apb_pwdata_i;
            apb_pstrb_r <= apb_pstrb_i;
        end
    end
    // SoC 7.1: events and clear commands reach PERF one cycle later together.
    // Register writes and functional accounting retain their access-edge timing.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            start_r <= 1'b0;
            abort_r <= 1'b0;
            soft_reset_r <= 1'b0;
            busy_r <= 1'b0;
            pixel_count_r <= 5'd0;
            read_beat_r <= 1'b0;
            write_beat_r <= 1'b0;
            read_wait_r <= 1'b0;
            write_wait_r <= 1'b0;
        end else begin
            start_r <= start_w;
            abort_r <= abort_w;
            soft_reset_r <= soft_reset_w;
            busy_r <= busy_i;
            pixel_count_r <= pixel_count_i;
            read_beat_r <= read_beat_i;
            write_beat_r <= write_beat_i;
            read_wait_r <= read_wait_i;
            write_wait_r <= write_wait_i;
        end
    end
    always @(*) begin
        apb_prdata_o = 32'd0;
        case (apb_paddr_r)
            12'h000: apb_prdata_o = 32'h0004_0001;
            12'h004: apb_prdata_o = {31'd0, enable_r};
            12'h008: apb_prdata_o = {29'd0, irq_stat_r[1], !busy_i, busy_i};
            12'h00c: apb_prdata_o = {30'd0, irq_en_r};
            12'h010: apb_prdata_o = {30'd0, irq_stat_r};
            12'h014: apb_prdata_o = {30'd0, err_code_r};
            12'h020: apb_prdata_o = desc_base_r;
            12'h024: apb_prdata_o = {16'd0, desc_count_r};
            12'h02c: apb_prdata_o = done_count_r;
            12'h040: apb_prdata_o = perf_r[0];
            12'h044: apb_prdata_o = perf_r[1];
            12'h048: apb_prdata_o = perf_r[2];
            12'h04c: apb_prdata_o = perf_r[3];
            12'h050: apb_prdata_o = perf_r[4];
            12'h054: apb_prdata_o = perf_r[5];
            12'h100: apb_prdata_o = cur_desc_r;
            default: apb_prdata_o = 32'd0;
        endcase
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            enable_r <= 1'b0;
            irq_en_r <= 2'd0;
            irq_stat_r <= 2'd0;
            err_code_r <= 2'd0;
            desc_base_r <= 32'd0;
            desc_count_r <= 16'd0;
            cur_desc_r <= 32'd0;
            done_count_r <= 32'd0;
        end else if (soft_reset_w) begin
            enable_r <= 1'b0;
            irq_en_r <= 2'd0;
            irq_stat_r <= 2'd0;
            err_code_r <= 2'd0;
            desc_base_r <= 32'd0;
            desc_count_r <= 16'd0;
            cur_desc_r <= 32'd0;
            done_count_r <= 32'd0;
        end else begin
            if (write_w) begin
                case (apb_paddr_r)
                    12'h004: enable_r <= apb_pwdata_r[0];
                    12'h00c: irq_en_r <= apb_pwdata_r[1:0];
                    12'h010: begin
                        irq_stat_r <= irq_stat_r & ~apb_pwdata_r[1:0];
                        if (apb_pwdata_r[1])
                            err_code_r <= 2'd0;
                    end
                    12'h020: desc_base_r <= {apb_pwdata_r[31:6], 6'd0};
                    12'h024: desc_count_r <= apb_pwdata_r[15:0];
                    default: enable_r <= enable_r;
                endcase
            end
            if (start_w)
                cur_desc_r <= 32'd0;
            if (command_done_i) begin
                cur_desc_r <= cur_desc_r + 32'd1;
                done_count_r <= done_count_r + 32'd1;
            end
            if (list_done_i)
                irq_stat_r[0] <= 1'b1;
            if (error_i != 0) begin
                irq_stat_r[1] <= 1'b1;
                err_code_r <= error_i;
            end
        end
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            for (count = 0; count < 6; count = count + 1)
                perf_r[count] <= 32'd0;
        end else if (soft_reset_o || start_o) begin
            for (count = 0; count < 6; count = count + 1)
                perf_r[count] <= 32'd0;
        end else begin
            if (busy_r)
                perf_r[0] <= perf_r[0] + 32'd1;
            perf_r[1][4:0] <= pixel_sum_w[4:0];
            if (pixel_sum_w[5])
                perf_r[1][31:5] <= perf_r[1][31:5] + 27'd1;
            perf_r[2] <= perf_r[2] + {31'd0, read_beat_r};
            perf_r[3] <= perf_r[3] + {31'd0, write_beat_r};
            perf_r[4] <= perf_r[4] + {31'd0, read_wait_r};
            perf_r[5] <= perf_r[5] + {31'd0, write_wait_r};
        end
    end
endmodule
