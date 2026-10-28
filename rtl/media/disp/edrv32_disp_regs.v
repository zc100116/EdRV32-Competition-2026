// File: edrv32_disp_regs.v
// Spec: disp-spec 4-6; edrv32-soc-spec 7.1.
// Description: APB frame handoff registers, sticky interrupts and performance counts.
//              Local software reset drains requested frames before clearing state.
// Clock domain: clk_mem (clk_i).
module edrv32_disp_regs (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Media APB slave; pstrb is ignored per spec 4.
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output wire apb_pready_o,
    output reg [31:0] apb_prdata_o,
    output wire apb_pslverr_o,

    // Reader controls and completion events.
    output wire enable_o,
    output wire [31:0] next_base_o,
    output wire [31:0] stride_o,
    output reg soft_clear_o,
    input wire busy_i,
    input wire frame_start_i,
    input wire underflow_i,
    input wire dma_err_i,
    input wire urgent_i,
    input wire delayed_req_i,

    // Synchronized scan counts; raw counts survive a local SOFT_RST.
    input wire [31:0] perf0_i,
    input wire [31:0] perf1_i,
    input wire [31:0] perf2_i,
    output wire [31:0] scan_cnt_o,

    // Interrupt output.
    output wire irq_o
);
    localparam [31:0] IRQ_MASK = 32'h0000_0106;
    reg enable_r;
    reg soft_pending_r;
    reg [31:0] irq_en_r;
    reg [31:0] irq_stat_r;
    reg [1:0] err_code_r;
    reg [31:0] next_base_r;
    reg [31:0] stride_r;
    reg [31:0] cur_base_r;
    reg [31:0] rel_base_r;
    reg [31:0] frame_cnt_r;
    reg [31:0] perf0_r;
    reg [31:0] perf1_r;
    reg [31:0] perf2_r;
    reg urgent_r;
    reg delayed_req_r;
    reg [31:0] perf0_base_r;
    reg [31:0] perf1_base_r;
    reg [31:0] perf2_base_r;
    reg [31:0] perf3_r;
    reg [31:0] perf4_r;
    wire write_w;
    wire ctrl_write_w;
    wire switch_w;
    wire [31:0] irq_set_w;
    wire [31:0] irq_clear_w;
    wire [3:0] unused_pstrb_w;

    assign unused_pstrb_w = apb_pstrb_i;
    assign apb_pready_o = 1'b1;
    assign apb_pslverr_o = 1'b0;
    assign write_w = apb_psel_i && apb_penable_i && apb_pwrite_i;
    assign ctrl_write_w = write_w && apb_paddr_i == 12'h004;
    assign enable_o = enable_r;
    assign next_base_o = next_base_r;
    assign stride_o = stride_r;
    // The stop handshake makes IDLE stable before the registered clear pulse.
    // Capture the CDC gray-to-binary outputs before subtraction and stop logic.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            soft_clear_o <= 1'b0;
            perf0_r <= 32'd0;
            perf1_r <= 32'd0;
            perf2_r <= 32'd0;
            urgent_r <= 1'b0;
            delayed_req_r <= 1'b0;
        end else begin
            soft_clear_o <= soft_pending_r && !busy_i && !soft_clear_o;
            perf0_r <= perf0_i;
            perf1_r <= perf1_i;
            perf2_r <= perf2_i;
            urgent_r <= urgent_i && !soft_clear_o;
            delayed_req_r <= delayed_req_i && !soft_clear_o;
        end
    end
    assign scan_cnt_o = perf0_r - perf0_base_r;
    assign switch_w = frame_start_i && next_base_r != cur_base_r;
    assign irq_set_w = {23'd0, switch_w, 5'd0, frame_start_i,
                        (underflow_i || dma_err_i), 1'b0};
    assign irq_clear_w = write_w && apb_paddr_i == 12'h010 ? apb_pwdata_i : 32'd0;
    assign irq_o = |(irq_en_r & irq_stat_r);

    always @(*) begin
        apb_prdata_o = 32'd0;
        case (apb_paddr_i)
            12'h000: apb_prdata_o = 32'h0005_0001;
            12'h004: apb_prdata_o = {31'd0, enable_r};
            12'h008: apb_prdata_o = {29'd0, irq_stat_r[1], !busy_i, busy_i};
            12'h00c: apb_prdata_o = irq_en_r;
            12'h010: apb_prdata_o = irq_stat_r;
            12'h014: apb_prdata_o = {30'd0, err_code_r};
            12'h02c: apb_prdata_o = frame_cnt_r;
            12'h040: apb_prdata_o = scan_cnt_o;
            12'h044: apb_prdata_o = perf1_r - perf1_base_r;
            12'h048: apb_prdata_o = perf2_r - perf2_base_r;
            12'h04c: apb_prdata_o = perf3_r;
            12'h050: apb_prdata_o = perf4_r;
            12'h100: apb_prdata_o = next_base_r;
            12'h104: apb_prdata_o = stride_r;
            12'h108: apb_prdata_o = cur_base_r;
            12'h10c: apb_prdata_o = rel_base_r;
            12'h110: apb_prdata_o = frame_cnt_r;
            default: begin end
        endcase
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            enable_r <= 1'b0;
            soft_pending_r <= 1'b0;
            irq_en_r <= 32'd0;
            irq_stat_r <= 32'd0;
            err_code_r <= 2'd0;
            next_base_r <= 32'd0;
            stride_r <= 32'h0000_0a00;
            cur_base_r <= 32'd0;
            rel_base_r <= 32'd0;
            frame_cnt_r <= 32'd0;
            perf0_base_r <= 32'd0;
            perf1_base_r <= 32'd0;
            perf2_base_r <= 32'd0;
            perf3_r <= 32'd0;
            perf4_r <= 32'd0;
        end else if (soft_clear_o) begin
            enable_r <= 1'b0;
            soft_pending_r <= 1'b0;
            irq_en_r <= 32'd0;
            irq_stat_r <= 32'd0;
            err_code_r <= 2'd0;
            next_base_r <= 32'd0;
            stride_r <= 32'h0000_0a00;
            cur_base_r <= 32'd0;
            rel_base_r <= 32'd0;
            frame_cnt_r <= 32'd0;
            perf0_base_r <= perf0_r;
            perf1_base_r <= perf1_r;
            perf2_base_r <= perf2_r;
            perf3_r <= 32'd0;
            perf4_r <= 32'd0;
        end else begin
            if (ctrl_write_w) begin
                enable_r <= apb_pwdata_i[0] && !apb_pwdata_i[2] && !apb_pwdata_i[3];
                if (apb_pwdata_i[3]) begin
                    soft_pending_r <= 1'b1;
                end
            end
            if (soft_pending_r) begin
                enable_r <= 1'b0;
            end
            if (write_w && apb_paddr_i == 12'h00c) begin
                irq_en_r <= apb_pwdata_i & IRQ_MASK;
            end
            irq_stat_r <= (irq_stat_r & ~irq_clear_w) | irq_set_w;
            if (irq_clear_w[1]) begin
                err_code_r <= 2'd0;
            end
            if (underflow_i) begin
                err_code_r <= 2'd1;
            end
            if (dma_err_i) begin
                err_code_r <= 2'd2;
            end
            if (write_w && apb_paddr_i == 12'h100) begin
                next_base_r <= {apb_pwdata_i[31:12], 12'd0};
            end
            if (write_w && apb_paddr_i == 12'h104) begin
                stride_r <= {16'd0, apb_pwdata_i[15:5], 5'd0};
            end
            if (frame_start_i) begin
                cur_base_r <= next_base_r;
                frame_cnt_r <= frame_cnt_r + 32'd1;
            end
            if (switch_w) begin
                rel_base_r <= cur_base_r;
            end
            if (urgent_r) begin
                perf3_r <= perf3_r + 32'd1;
            end
            if (delayed_req_r) begin
                perf4_r <= perf4_r + 32'd1;
            end
        end
    end
endmodule
