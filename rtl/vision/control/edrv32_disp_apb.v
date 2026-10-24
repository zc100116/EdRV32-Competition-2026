// ============================================================================
// File        : edrv32_disp_apb.v
// Description : APB control and status block for the HDMI display pipeline.
// Notes       : Buffer bases are read-only until descriptor-driven relocation
//               is implemented. Status inputs must be synchronous to clk_i.
// ============================================================================

`include "edrv32_soc_map.vh"

module edrv32_disp_apb (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire [31:0]  paddr_i,
    input  wire         psel_i,
    input  wire         penable_i,
    input  wire         pwrite_i,
    input  wire [31:0]  pwdata_i,
    input  wire [3:0]   pstrb_i,
    output wire         pready_o,
    output wire [31:0]  prdata_o,
    output wire         pslverr_o,

    input  wire [1:0]   active_buffer_i,
    input  wire         error_i,
    input  wire [31:0]  frame_count_i,
    input  wire [31:0]  underflow_count_i,
    input  wire [31:0]  scanout_frame_count_i,
    input  wire [6:0]   debug_status_i,
    input  wire [31:0]  buffer0_base_i,
    input  wire [31:0]  buffer1_base_i,
    input  wire [31:0]  buffer2_base_i,

    output wire         enable_o,
    output wire         irq_o
);

    function [31:0] apply_strobe;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0] strobe;
        integer byte_index;
        begin
            apply_strobe = old_value;
            for (byte_index = 0; byte_index < 4;
                 byte_index = byte_index + 1) begin
                if (strobe[byte_index])
                    apply_strobe[byte_index*8 +: 8] =
                        new_value[byte_index*8 +: 8];
            end
        end
    endfunction

    wire [7:0] offset_w = paddr_i[7:0];
    wire aligned_w = paddr_i[1:0] == 2'b00;
    wire local_slot_w = paddr_i[31:8] == 0;
    wire implemented_w =
        (offset_w == `DISP_ID) ||
        (offset_w == `DISP_VERSION) ||
        (offset_w == `DISP_CAPABILITY) ||
        (offset_w == `DISP_CONTROL) ||
        (offset_w == `DISP_STATUS) ||
        (offset_w == `DISP_FRAME_COUNT) ||
        (offset_w == `DISP_UNDERFLOW_COUNT) ||
        (offset_w == `DISP_BUFFER0_BASE) ||
        (offset_w == `DISP_BUFFER1_BASE) ||
        (offset_w == `DISP_BUFFER2_BASE) ||
        (offset_w == `DISP_IRQ_ENABLE) ||
        (offset_w == `DISP_IRQ_STATUS) ||
        (offset_w == `DISP_SCANOUT_FRAME_COUNT) ||
        (offset_w == `DISP_DEBUG_STATUS);
    wire writable_w =
        (offset_w == `DISP_CONTROL) ||
        (offset_w == `DISP_IRQ_ENABLE) ||
        (offset_w == `DISP_IRQ_STATUS);
    wire access_w = psel_i && penable_i;
    wire legal_access_w = aligned_w && local_slot_w && implemented_w &&
        (!pwrite_i || writable_w);
    wire write_w = access_w && pwrite_i && legal_access_w;
    wire [31:0] write_mask_w = {
        {8{pstrb_i[3]}}, {8{pstrb_i[2]}},
        {8{pstrb_i[1]}}, {8{pstrb_i[0]}}
    };

    reg enable_r;
    reg [2:0] irq_enable_r;
    reg [2:0] irq_status_r;
    reg [31:0] frame_count_prev_r;
    reg [31:0] underflow_count_prev_r;
    reg error_prev_r;
    reg [31:0] prdata_r;

    wire [31:0] control_merge_w = apply_strobe(
        {31'b0, enable_r}, pwdata_i, pstrb_i);
    wire [31:0] irq_enable_merge_w = apply_strobe(
        {29'b0, irq_enable_r}, pwdata_i, pstrb_i);
    wire [2:0] irq_clear_w =
        (write_w && (offset_w == `DISP_IRQ_STATUS)) ?
        (pwdata_i[2:0] & write_mask_w[2:0]) : 3'b0;
    wire [2:0] irq_event_w = {
        error_i && !error_prev_r,
        underflow_count_i != underflow_count_prev_r,
        frame_count_i != frame_count_prev_r
    };
    wire [31:0] status_w = {
        28'b0, error_i, active_buffer_i, enable_r
    };

    assign pready_o = 1'b1;
    assign prdata_o = prdata_r;
    assign pslverr_o = access_w && !legal_access_w;
    assign enable_o = enable_r;
    assign irq_o = |(irq_status_r & irq_enable_r);

    always @(*) begin
        prdata_r = 32'b0;
        case (offset_w)
            `DISP_ID:              prdata_r = 32'h4449_5350;
            `DISP_VERSION:         prdata_r = 32'h0001_0000;
            `DISP_CAPABILITY:      prdata_r = 32'h0000_0007;
            `DISP_CONTROL:         prdata_r = {31'b0, enable_r};
            `DISP_STATUS:          prdata_r = status_w;
            `DISP_FRAME_COUNT:     prdata_r = frame_count_i;
            `DISP_UNDERFLOW_COUNT: prdata_r = underflow_count_i;
            `DISP_BUFFER0_BASE:    prdata_r = buffer0_base_i;
            `DISP_BUFFER1_BASE:    prdata_r = buffer1_base_i;
            `DISP_BUFFER2_BASE:    prdata_r = buffer2_base_i;
            `DISP_IRQ_ENABLE:      prdata_r = {29'b0, irq_enable_r};
            `DISP_IRQ_STATUS:      prdata_r = {29'b0, irq_status_r};
            `DISP_SCANOUT_FRAME_COUNT: prdata_r = scanout_frame_count_i;
            `DISP_DEBUG_STATUS:    prdata_r = {25'b0, debug_status_i};
            default:               prdata_r = 32'b0;
        endcase
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            enable_r <= 1'b1;
            irq_enable_r <= 3'b0;
        end else begin
            if (write_w && (offset_w == `DISP_CONTROL))
                enable_r <= control_merge_w[0];
            if (write_w && (offset_w == `DISP_IRQ_ENABLE))
                irq_enable_r <= irq_enable_merge_w[2:0];
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            irq_status_r <= 3'b0;
            frame_count_prev_r <= 32'b0;
            underflow_count_prev_r <= 32'b0;
            error_prev_r <= 1'b0;
        end else begin
            irq_status_r <= (irq_status_r & ~irq_clear_w) | irq_event_w;
            frame_count_prev_r <= frame_count_i;
            underflow_count_prev_r <= underflow_count_i;
            error_prev_r <= error_i;
        end
    end

endmodule
