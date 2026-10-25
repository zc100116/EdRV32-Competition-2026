// ============================================================================
// File        : gpio.v
// Author      : Edward ZC
// Description : One 32-bit SOC3 GPIO bank with APB control and interrupt logic.
// Notes       : Inputs use two synchronizer stages. Interrupt pending is raw
//               sticky state; INT_EN masks only the combined IRQ output.
// ============================================================================

// ============================================================================
// gpio - 32-bit APB GPIO bank
// ============================================================================
module gpio (
    // --- Clock and reset ---
    input  wire         clk,
    input  wire         rst_n,

    // --- APB slave port ---
    input  wire [31:0]  paddr_i,
    input  wire         psel_i,
    input  wire         penable_i,
    input  wire         pwrite_i,
    input  wire [31:0]  pwdata_i,
    input  wire [3:0]   pstrb_i,
    output wire         pready_o,
    output reg  [31:0]  prdata_o,
    output wire         pslverr_o,

    // --- GPIO pins and interrupt ---
    input  wire [31:0]  pin_in_i,
    output wire [31:0]  pin_out_o,
    output wire [31:0]  pin_oe_o,
    output wire         irq_o
);

    localparam [11:0] OFF_DIR         = 12'h000;
    localparam [11:0] OFF_OUT         = 12'h004;
    localparam [11:0] OFF_IN          = 12'h008;
    localparam [11:0] OFF_OUT_SET     = 12'h00C;
    localparam [11:0] OFF_OUT_CLR     = 12'h010;
    localparam [11:0] OFF_INT_EN      = 12'h014;
    localparam [11:0] OFF_INT_TYPE    = 12'h018;
    localparam [11:0] OFF_INT_POL     = 12'h01C;
    localparam [11:0] OFF_INT_BOTH    = 12'h020;
    localparam [11:0] OFF_INT_PENDING = 12'h024;
    localparam [11:0] OFF_INT_STATUS  = 12'h028;

    wire [11:0] offset_w = paddr_i[11:0];
    wire aligned_w = paddr_i[1:0] == 2'b00;
    wire implemented_w =
        offset_w == OFF_DIR ||
        offset_w == OFF_OUT ||
        offset_w == OFF_IN ||
        offset_w == OFF_OUT_SET ||
        offset_w == OFF_OUT_CLR ||
        offset_w == OFF_INT_EN ||
        offset_w == OFF_INT_TYPE ||
        offset_w == OFF_INT_POL ||
        offset_w == OFF_INT_BOTH ||
        offset_w == OFF_INT_PENDING ||
        offset_w == OFF_INT_STATUS;
    wire access_w = psel_i && penable_i;
    wire write_w =
        access_w && pwrite_i && aligned_w && implemented_w;
    wire [31:0] write_mask_w = {
        {8{pstrb_i[3]}}, {8{pstrb_i[2]}},
        {8{pstrb_i[1]}}, {8{pstrb_i[0]}}
    };
    wire [19:0] unused_paddr_upper_w = paddr_i[31:12];

    assign pready_o = 1'b1;
    assign pslverr_o = access_w && (!aligned_w || !implemented_w);

    reg [31:0] dir_r;
    reg [31:0] out_r;
    reg [31:0] sync_meta_r;
    reg [31:0] sync_r;
    reg [31:0] sync_prev_r;
    reg [31:0] int_en_r;
    reg [31:0] int_type_r;
    reg [31:0] int_pol_r;
    reg [31:0] int_both_r;
    reg [31:0] pending_r;

    wire [31:0] rising_w = sync_r & ~sync_prev_r;
    wire [31:0] falling_w = ~sync_r & sync_prev_r;
    wire [31:0] edge_status_w =
        (int_both_r & (rising_w | falling_w)) |
        (~int_both_r & int_pol_r & rising_w) |
        (~int_both_r & ~int_pol_r & falling_w);
    wire [31:0] level_status_w =
        (int_pol_r & sync_r) | (~int_pol_r & ~sync_r);
    wire [31:0] int_status_w =
        (int_type_r & edge_status_w) |
        (~int_type_r & level_status_w);
    wire [31:0] pending_clear_w =
        write_w && offset_w == OFF_INT_PENDING ?
        (pwdata_i & write_mask_w) : 32'b0;

    assign pin_out_o = out_r;
    assign pin_oe_o = dir_r;
    assign irq_o = |(pending_r & int_en_r);

    // ------------------------------------------------------------------------
    // APB read response is combinational and therefore valid before the
    // transfer-completion edge. WO aliases read zero.
    // ------------------------------------------------------------------------
    always @* begin
        prdata_o = 32'b0;
        case (offset_w)
            OFF_DIR:         prdata_o = dir_r;
            OFF_OUT:         prdata_o = out_r;
            OFF_IN:          prdata_o = sync_r;
            OFF_OUT_SET:     prdata_o = 32'b0;
            OFF_OUT_CLR:     prdata_o = 32'b0;
            OFF_INT_EN:      prdata_o = int_en_r;
            OFF_INT_TYPE:    prdata_o = int_type_r;
            OFF_INT_POL:     prdata_o = int_pol_r;
            OFF_INT_BOTH:    prdata_o = int_both_r;
            OFF_INT_PENDING: prdata_o = pending_r;
            OFF_INT_STATUS:  prdata_o = int_status_w;
            default:         prdata_o = 32'b0;
        endcase
    end

    // ------------------------------------------------------------------------
    // Two-stage asynchronous input synchronization and delayed sample for
    // edge detection.
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_meta_r <= 32'b0;
            sync_r <= 32'b0;
            sync_prev_r <= 32'b0;
        end else begin
            sync_meta_r <= pin_in_i;
            sync_r <= sync_meta_r;
            sync_prev_r <= sync_r;
        end
    end

    // ------------------------------------------------------------------------
    // Direction and output state. CLR is applied after SET in the next-state
    // expression, freezing CLR priority if both commands are ever asserted.
    // ------------------------------------------------------------------------
    reg [31:0] out_next_r;
    always @* begin
        out_next_r = out_r;
        if (write_w && offset_w == OFF_OUT)
            out_next_r =
                (out_r & ~write_mask_w) | (pwdata_i & write_mask_w);
        if (write_w && offset_w == OFF_OUT_SET)
            out_next_r = out_next_r | (pwdata_i & write_mask_w);
        if (write_w && offset_w == OFF_OUT_CLR)
            out_next_r = out_next_r & ~(pwdata_i & write_mask_w);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dir_r <= 32'b0;
        end else if (write_w && offset_w == OFF_DIR) begin
            dir_r <=
                (dir_r & ~write_mask_w) | (pwdata_i & write_mask_w);
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            out_r <= 32'b0;
        else
            out_r <= out_next_r;
    end

    // ------------------------------------------------------------------------
    // Interrupt configuration. Configuration writes do not clear pending.
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            int_en_r <= 32'b0;
            int_type_r <= 32'b0;
            int_pol_r <= 32'b0;
            int_both_r <= 32'b0;
        end else begin
            if (write_w && offset_w == OFF_INT_EN)
                int_en_r <=
                    (int_en_r & ~write_mask_w) |
                    (pwdata_i & write_mask_w);
            if (write_w && offset_w == OFF_INT_TYPE)
                int_type_r <=
                    (int_type_r & ~write_mask_w) |
                    (pwdata_i & write_mask_w);
            if (write_w && offset_w == OFF_INT_POL)
                int_pol_r <=
                    (int_pol_r & ~write_mask_w) |
                    (pwdata_i & write_mask_w);
            if (write_w && offset_w == OFF_INT_BOTH)
                int_both_r <=
                    (int_both_r & ~write_mask_w) |
                    (pwdata_i & write_mask_w);
        end
    end

    // Hardware status is ORed after software clear, so a same-cycle event wins.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pending_r <= 32'b0;
        else
            pending_r <= (pending_r & ~pending_clear_w) | int_status_w;
    end

endmodule
