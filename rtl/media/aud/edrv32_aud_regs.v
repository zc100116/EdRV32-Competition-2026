// File: edrv32_aud_regs.v
// Spec: aud-spec 4, 6; edrv32-soc-spec 4.3, 7.1.
// Description: Setup-latched APB registers, low-water IRQ and saturating underruns.
//              Abort disables playback; soft reset waits for outstanding DMA.
// Clock domain: clk_mem.
module edrv32_aud_regs (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Media APB slave.
    input wire [11:0] s_apb_paddr_i,
    input wire s_apb_psel_i,
    input wire s_apb_penable_i,
    input wire s_apb_pwrite_i,
    input wire [31:0] s_apb_pwdata_i,
    input wire [3:0] s_apb_pstrb_i,
    output wire s_apb_pready_o,
    output reg [31:0] s_apb_prdata_o,
    output wire s_apb_pslverr_o,

    // DMA configuration and status.
    output reg enable_o,
    output wire restart_o,
    output wire clear_error_o,
    output reg [31:0] ring_base_o,
    output reg [23:0] ring_size_o,
    output reg [23:0] wr_ptr_o,
    input wire [23:0] rd_ptr_i,
    input wire [23:0] avail_i,
    input wire busy_i,
    input wire error_i,
    input wire underrun_i,

    // Interrupt.
    output wire irq_o
);
    // The shared generated header also defines fields unused by this engine.
    /* verilator lint_off UNUSEDPARAM */
    `include "regs/edrv32_aud_regs.vh"
    /* verilator lint_on UNUSEDPARAM */
    reg [11:0] addr_r;
    reg write_r;
    reg [31:0] data_r;
    reg [3:0] strb_r;
    reg [31:0] irq_en_r;
    reg [31:0] irq_stat_r;
    reg [23:0] low_level_r;
    reg [31:0] underrun_cnt_r;
    reg error_r;
    reg soft_reset_r;
    reg [23:0] previous_avail_r;
    reg underrun_r;
    wire write_w;
    wire ctrl_write_w;
    wire reset_w;
    wire low_w;
    wire [31:0] mask_w;
    wire [31:0] merged_w;
    wire [31:0] irq_clear_w;

    assign s_apb_pready_o = 1'b1;
    assign s_apb_pslverr_o = 1'b0;
    assign write_w = s_apb_psel_i && s_apb_penable_i && write_r;
    assign ctrl_write_w = write_w && ({20'd0, addr_r} == EDRV32_AUD_CTRL_OFFSET) &&
        strb_r[0];
    assign reset_w = soft_reset_r && !busy_i;
    assign restart_o = (ctrl_write_w && data_r[0] && !enable_o && !data_r[2] &&
        !data_r[3]) || reset_w;
    assign irq_clear_w = write_w && ({20'd0, addr_r} == EDRV32_AUD_IRQ_STAT_OFFSET) ?
        data_r & mask_w : 32'd0;
    assign clear_error_o = irq_clear_w[1] || reset_w;
    assign low_w = (previous_avail_r >= low_level_r) && (avail_i < low_level_r);
    assign irq_o = |(irq_stat_r & irq_en_r);
    assign mask_w = {{8{strb_r[3]}}, {8{strb_r[2]}}, {8{strb_r[1]}}, {8{strb_r[0]}}};
    assign merged_w = (s_apb_prdata_o & ~mask_w) | (data_r & mask_w);

    always @(posedge clk_i) begin
        if (s_apb_psel_i && !s_apb_penable_i) begin
            addr_r <= s_apb_paddr_i;
            write_r <= s_apb_pwrite_i;
            data_r <= s_apb_pwdata_i;
            strb_r <= s_apb_pstrb_i;
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            enable_o <= 1'b0;
            ring_base_o <= 32'd0;
            ring_size_o <= 24'd0;
            wr_ptr_o <= 24'd0;
            irq_en_r <= 32'd0;
            irq_stat_r <= 32'd0;
            low_level_r <= 24'd0;
            underrun_cnt_r <= 32'd0;
            error_r <= 1'b0;
            soft_reset_r <= 1'b0;
            previous_avail_r <= 24'd0;
            underrun_r <= 1'b0;
        end else if (reset_w) begin
            enable_o <= 1'b0;
            ring_base_o <= 32'd0;
            ring_size_o <= 24'd0;
            wr_ptr_o <= 24'd0;
            irq_en_r <= 32'd0;
            irq_stat_r <= 32'd0;
            low_level_r <= 24'd0;
            underrun_cnt_r <= 32'd0;
            error_r <= 1'b0;
            soft_reset_r <= 1'b0;
            previous_avail_r <= 24'd0;
            underrun_r <= 1'b0;
        end else begin
            previous_avail_r <= avail_i;
            underrun_r <= underrun_i;
            irq_stat_r <= (irq_stat_r & ~irq_clear_w) |
                (error_i ? 32'h2 : 32'd0) | (low_w ? 32'h100 : 32'd0);
            if (clear_error_o) begin
                error_r <= 1'b0;
            end
            if (error_i) begin
                error_r <= 1'b1;
            end
            if (underrun_r && (underrun_cnt_r != 32'hffffffff)) begin
                underrun_cnt_r <= underrun_cnt_r + 1'b1;
            end
            if (ctrl_write_w) begin
                enable_o <= data_r[0] && !data_r[2] && !data_r[3];
                if (data_r[3]) begin
                    soft_reset_r <= 1'b1;
                end
            end
            if (write_w) begin
                case ({20'd0, addr_r})
                    EDRV32_AUD_IRQ_EN_OFFSET: irq_en_r <= merged_w & 32'h102;
                    EDRV32_AUD_RING_BASE_OFFSET: begin
                        if (!enable_o) begin
                            ring_base_o <= merged_w & EDRV32_AUD_RING_BASE_ADDR_MASK;
                        end
                    end
                    EDRV32_AUD_RING_SIZE_OFFSET: begin
                        if (!enable_o) begin
                            ring_size_o <= merged_w[23:0] & 24'hfffe00;
                        end
                    end
                    EDRV32_AUD_WR_PTR_OFFSET: wr_ptr_o <= merged_w[23:0] & 24'hffffe0;
                    EDRV32_AUD_LOW_LEVEL_OFFSET: low_level_r <= merged_w[23:0];
                    default: begin end
                endcase
            end
        end
    end

    always @(*) begin
        s_apb_prdata_o = 32'd0;
        case ({20'd0, addr_r})
            EDRV32_AUD_ID_OFFSET: s_apb_prdata_o = 32'h00010001;
            EDRV32_AUD_CTRL_OFFSET: s_apb_prdata_o = {31'd0, enable_o};
            EDRV32_AUD_STATUS_OFFSET:
                s_apb_prdata_o = {29'd0, error_r, !busy_i, busy_i};
            EDRV32_AUD_IRQ_EN_OFFSET: s_apb_prdata_o = irq_en_r;
            EDRV32_AUD_IRQ_STAT_OFFSET: s_apb_prdata_o = irq_stat_r;
            EDRV32_AUD_ERR_CODE_OFFSET: s_apb_prdata_o = {31'd0, error_r};
            EDRV32_AUD_RING_BASE_OFFSET: s_apb_prdata_o = ring_base_o;
            EDRV32_AUD_RING_SIZE_OFFSET: s_apb_prdata_o = {8'd0, ring_size_o};
            EDRV32_AUD_WR_PTR_OFFSET: s_apb_prdata_o = {8'd0, wr_ptr_o};
            EDRV32_AUD_RD_PTR_OFFSET: s_apb_prdata_o = {8'd0, rd_ptr_i};
            EDRV32_AUD_LOW_LEVEL_OFFSET: s_apb_prdata_o = {8'd0, low_level_r};
            EDRV32_AUD_UNDERRUN_CNT_OFFSET: s_apb_prdata_o = underrun_cnt_r;
            default: begin end
        endcase
    end
endmodule
