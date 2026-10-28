// File: edrv32_pix_regs.v
// Spec: pix-spec 4, 5.1, 5.2; edrv32-soc-spec 4.3, 7.1.
// Description: PIX shadow configuration, frame IRQ and performance registers.
// Soft reset remains pending until the frame controller is idle; Gamma is retained.
// Clock: clk_mem.
module edrv32_pix_regs (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // APB slave, whole-word writes (PSTRB intentionally ignored).
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output wire apb_pready_o,
    output reg [31:0] apb_prdata_o,
    output wire apb_pslverr_o,

    // Shadow configuration and Gamma writes.
    output reg enable_o,
    output reg [31:0] cfg_o,
    output reg [31:0] bc_o,
    output reg [7:0] thresh_o,
    output wire gamma_wr_o,
    output wire [8:0] gamma_addr_o,
    output wire [7:0] gamma_data_o,

    // Frame events and reset request.
    input wire busy_i,
    input wire frame_done_i,
    input wire input_stall_i,
    input wire output_stall_i,
    input wire discard_i,
    output wire soft_pending_o,
    output wire soft_reset_o,

    // Interrupt.
    output wire irq_o
);
    wire write_w;
    wire soft_request_w;
    wire unused_pstrb_w;
    reg soft_pending_r;
    reg irq_en_r;
    reg irq_stat_r;
    reg [31:0] done_count_r;
    reg [31:0] input_stalls_r;
    reg [31:0] output_stalls_r;
    reg [31:0] discarded_r;

    assign unused_pstrb_w = &apb_pstrb_i;
    assign write_w = apb_psel_i && apb_penable_i && apb_pwrite_i;
    assign soft_request_w = write_w && apb_paddr_i == 12'h004 && apb_pwdata_i[3];
    assign soft_pending_o = soft_pending_r || soft_request_w;
    assign soft_reset_o = soft_pending_o && !busy_i;
    assign gamma_wr_o = write_w && apb_paddr_i == 12'h10c;
    assign gamma_addr_o = apb_pwdata_i[8:0];
    assign gamma_data_o = apb_pwdata_i[23:16];
    assign apb_pready_o = 1'b1;
    assign apb_pslverr_o = 1'b0;
    assign irq_o = irq_en_r && irq_stat_r;

    always @(*) begin
        apb_prdata_o = 32'd0;
        case (apb_paddr_i)
            12'h000: apb_prdata_o = 32'h00020001;
            12'h004: apb_prdata_o = {31'd0, enable_o};
            12'h008: apb_prdata_o = {30'd0, !busy_i, busy_i};
            12'h00c: apb_prdata_o = {29'd0, irq_en_r, 2'd0};
            12'h010: apb_prdata_o = {29'd0, irq_stat_r, 2'd0};
            12'h02c, 12'h040: apb_prdata_o = done_count_r;
            12'h044: apb_prdata_o = input_stalls_r;
            12'h048: apb_prdata_o = output_stalls_r;
            12'h04c: apb_prdata_o = discarded_r;
            12'h100: apb_prdata_o = cfg_o;
            12'h104: apb_prdata_o = bc_o;
            12'h108: apb_prdata_o = {24'd0, thresh_o};
            default: apb_prdata_o = 32'd0;
        endcase
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            enable_o <= 1'b0;
            cfg_o <= 32'd0;
            bc_o <= 32'h00000100;
            thresh_o <= 8'd128;
            soft_pending_r <= 1'b0;
            irq_en_r <= 1'b0;
            irq_stat_r <= 1'b0;
            done_count_r <= 32'd0;
            input_stalls_r <= 32'd0;
            output_stalls_r <= 32'd0;
            discarded_r <= 32'd0;
        end else if (soft_reset_o) begin
            enable_o <= 1'b0;
            cfg_o <= 32'd0;
            bc_o <= 32'h00000100;
            thresh_o <= 8'd128;
            soft_pending_r <= 1'b0;
            irq_en_r <= 1'b0;
            irq_stat_r <= 1'b0;
            done_count_r <= 32'd0;
            input_stalls_r <= 32'd0;
            output_stalls_r <= 32'd0;
            discarded_r <= 32'd0;
        end else begin
            if (soft_request_w) begin
                soft_pending_r <= 1'b1;
            end
            if (input_stall_i) begin
                input_stalls_r <= input_stalls_r + 32'd1;
            end
            if (output_stall_i) begin
                output_stalls_r <= output_stalls_r + 32'd1;
            end
            if (discard_i) begin
                discarded_r <= discarded_r + 32'd1;
            end
            if (write_w) begin
                case (apb_paddr_i)
                    12'h004: enable_o <= apb_pwdata_i[0];
                    12'h00c: irq_en_r <= apb_pwdata_i[2];
                    12'h010: irq_stat_r <= irq_stat_r && !apb_pwdata_i[2];
                    12'h100: cfg_o <= apb_pwdata_i & 32'h00070777;
                    12'h104: bc_o <= apb_pwdata_i & 32'h01ff01ff;
                    12'h108: thresh_o <= apb_pwdata_i[7:0];
                    default: begin end
                endcase
            end
            // A simultaneous completion wins over software's RW1C clear.
            if (frame_done_i) begin
                irq_stat_r <= 1'b1;
                done_count_r <= done_count_r + 32'd1;
            end
        end
    end
endmodule
