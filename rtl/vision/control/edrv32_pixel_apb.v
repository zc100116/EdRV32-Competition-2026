// ============================================================================
// File        : edrv32_pixel_apb.v
// Description : APB shadow configuration and status for Pixel Pipeline.
// Notes       : COMMAND.COMMIT starts a toggle handshake. Configuration stays
//               stable until the datapath applies it at an accepted SOF.
// ============================================================================

`include "edrv32_soc_map.vh"

module edrv32_pixel_apb (
    input  wire                clk_i,
    input  wire                rst_n_i,

    input  wire [31:0]         paddr_i,
    input  wire                psel_i,
    input  wire                penable_i,
    input  wire                pwrite_i,
    input  wire [31:0]         pwdata_i,
    input  wire [3:0]          pstrb_i,
    output wire                pready_o,
    output wire [31:0]         prdata_o,
    output wire                pslverr_o,

    input  wire                cfg_ack_toggle_i,
    input  wire [31:0]         frame_count_i,
    input  wire [31:0]         error_count_i,

    output wire                cfg_req_toggle_o,
    output wire                cfg_enable_o,
    output wire                cfg_grayscale_o,
    output wire                cfg_threshold_enable_o,
    output wire                cfg_invert_o,
    output wire signed [8:0]   cfg_brightness_o,
    output wire [8:0]          cfg_contrast_o,
    output wire [7:0]          cfg_threshold_o,
    output wire                cfg_spatial_enable_o,
    output wire [2:0]          cfg_spatial_mode_o,
    output wire [7:0]          cfg_spatial_threshold_o,
    output wire                irq_o
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
        (offset_w == `PIXEL_ID) ||
        (offset_w == `PIXEL_VERSION) ||
        (offset_w == `PIXEL_CAPABILITY) ||
        (offset_w == `PIXEL_CONTROL) ||
        (offset_w == `PIXEL_BRIGHTNESS) ||
        (offset_w == `PIXEL_CONTRAST) ||
        (offset_w == `PIXEL_THRESHOLD) ||
        (offset_w == `PIXEL_COMMAND) ||
        (offset_w == `PIXEL_STATUS) ||
        (offset_w == `PIXEL_FRAME_COUNT) ||
        (offset_w == `PIXEL_ERROR_COUNT) ||
        (offset_w == `PIXEL_IRQ_ENABLE) ||
        (offset_w == `PIXEL_IRQ_STATUS) ||
        (offset_w == `PIXEL_SPATIAL_CONTROL) ||
        (offset_w == `PIXEL_SPATIAL_THRESHOLD);
    wire writable_w =
        (offset_w == `PIXEL_CONTROL) ||
        (offset_w == `PIXEL_BRIGHTNESS) ||
        (offset_w == `PIXEL_CONTRAST) ||
        (offset_w == `PIXEL_THRESHOLD) ||
        (offset_w == `PIXEL_COMMAND) ||
        (offset_w == `PIXEL_IRQ_ENABLE) ||
        (offset_w == `PIXEL_IRQ_STATUS) ||
        (offset_w == `PIXEL_SPATIAL_CONTROL) ||
        (offset_w == `PIXEL_SPATIAL_THRESHOLD);
    wire access_w = psel_i && penable_i;
    wire legal_access_w = aligned_w && local_slot_w && implemented_w &&
        (!pwrite_i || writable_w);
    wire write_w = access_w && pwrite_i && legal_access_w;
    wire [31:0] write_mask_w = {
        {8{pstrb_i[3]}}, {8{pstrb_i[2]}},
        {8{pstrb_i[1]}}, {8{pstrb_i[0]}}
    };

    reg [3:0] control_r;
    reg signed [8:0] brightness_r;
    reg [8:0] contrast_r;
    reg [7:0] threshold_r;
    reg [3:0] spatial_control_r;
    reg [7:0] spatial_threshold_r;
    reg [3:0] transfer_control_r;
    reg signed [8:0] transfer_brightness_r;
    reg [8:0] transfer_contrast_r;
    reg [7:0] transfer_threshold_r;
    reg [3:0] transfer_spatial_control_r;
    reg [7:0] transfer_spatial_threshold_r;
    reg cfg_req_toggle_r;
    reg [2:0] irq_enable_r;
    reg [2:0] irq_status_r;
    reg cfg_ack_meta_r;
    reg cfg_ack_sync_r;
    reg cfg_ack_prev_r;
    reg [31:0] frame_count_prev_r;
    reg [31:0] error_count_prev_r;
    reg [31:0] prdata_r;

    wire [31:0] control_merge_w = apply_strobe(
        {28'b0, control_r}, pwdata_i, pstrb_i);
    wire [31:0] brightness_merge_w = apply_strobe(
        {{23{brightness_r[8]}}, brightness_r}, pwdata_i, pstrb_i);
    wire [31:0] contrast_merge_w = apply_strobe(
        {23'b0, contrast_r}, pwdata_i, pstrb_i);
    wire [31:0] threshold_merge_w = apply_strobe(
        {24'b0, threshold_r}, pwdata_i, pstrb_i);
    wire [31:0] spatial_control_merge_w = apply_strobe(
        {28'b0, spatial_control_r}, pwdata_i, pstrb_i);
    wire [31:0] spatial_threshold_merge_w = apply_strobe(
        {24'b0, spatial_threshold_r}, pwdata_i, pstrb_i);
    wire [31:0] irq_enable_merge_w = apply_strobe(
        {29'b0, irq_enable_r}, pwdata_i, pstrb_i);
    wire commit_write_w = write_w && (offset_w == `PIXEL_COMMAND) &&
        pstrb_i[0] && pwdata_i[`PIXEL_COMMAND_COMMIT] &&
        (cfg_req_toggle_r == cfg_ack_sync_r);
    wire [2:0] irq_clear_w =
        (write_w && (offset_w == `PIXEL_IRQ_STATUS)) ?
        (pwdata_i[2:0] & write_mask_w[2:0]) : 3'b0;
    wire [2:0] irq_event_w = {
        cfg_ack_sync_r != cfg_ack_prev_r,
        error_count_i != error_count_prev_r,
        frame_count_i != frame_count_prev_r
    };
    wire cfg_pending_w = cfg_req_toggle_r != cfg_ack_sync_r;

    assign pready_o = 1'b1;
    assign prdata_o = prdata_r;
    assign pslverr_o = access_w && !legal_access_w;
    assign cfg_req_toggle_o = cfg_req_toggle_r;
    assign cfg_enable_o = transfer_control_r[`PIXEL_CONTROL_ENABLE];
    assign cfg_grayscale_o = transfer_control_r[`PIXEL_CONTROL_GRAYSCALE];
    assign cfg_threshold_enable_o =
        transfer_control_r[`PIXEL_CONTROL_THRESHOLD];
    assign cfg_invert_o = transfer_control_r[`PIXEL_CONTROL_INVERT];
    assign cfg_brightness_o = transfer_brightness_r;
    assign cfg_contrast_o = transfer_contrast_r;
    assign cfg_threshold_o = transfer_threshold_r;
    assign cfg_spatial_enable_o =
        transfer_spatial_control_r[`PIXEL_SPATIAL_ENABLE];
    assign cfg_spatial_mode_o = transfer_spatial_control_r[
        `PIXEL_SPATIAL_MODE_MSB:`PIXEL_SPATIAL_MODE_LSB];
    assign cfg_spatial_threshold_o = transfer_spatial_threshold_r;
    assign irq_o = |(irq_status_r & irq_enable_r);

    always @(*) begin
        prdata_r = 32'b0;
        case (offset_w)
            `PIXEL_ID:          prdata_r = 32'h5049_584c;
            `PIXEL_VERSION:     prdata_r = 32'h0001_0100;
            `PIXEL_CAPABILITY:  prdata_r = 32'h0000_003f;
            `PIXEL_CONTROL:     prdata_r = {28'b0, control_r};
            `PIXEL_BRIGHTNESS:  prdata_r = {
                {23{brightness_r[8]}}, brightness_r
            };
            `PIXEL_CONTRAST:    prdata_r = {23'b0, contrast_r};
            `PIXEL_THRESHOLD:   prdata_r = {24'b0, threshold_r};
            `PIXEL_COMMAND:     prdata_r = 32'b0;
            `PIXEL_STATUS:      prdata_r = {31'b0, cfg_pending_w};
            `PIXEL_FRAME_COUNT: prdata_r = frame_count_i;
            `PIXEL_ERROR_COUNT: prdata_r = error_count_i;
            `PIXEL_IRQ_ENABLE:  prdata_r = {29'b0, irq_enable_r};
            `PIXEL_IRQ_STATUS:  prdata_r = {29'b0, irq_status_r};
            `PIXEL_SPATIAL_CONTROL: prdata_r = {
                28'b0, spatial_control_r
            };
            `PIXEL_SPATIAL_THRESHOLD: prdata_r = {
                24'b0, spatial_threshold_r
            };
            default:            prdata_r = 32'b0;
        endcase
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            control_r <= 4'b0;
            brightness_r <= 9'sd0;
            contrast_r <= 9'd256;
            threshold_r <= 8'd128;
            spatial_control_r <= 4'b0;
            spatial_threshold_r <= 8'd128;
            transfer_control_r <= 4'b0;
            transfer_brightness_r <= 9'sd0;
            transfer_contrast_r <= 9'd256;
            transfer_threshold_r <= 8'd128;
            transfer_spatial_control_r <= 4'b0;
            transfer_spatial_threshold_r <= 8'd128;
            cfg_req_toggle_r <= 1'b0;
            cfg_ack_meta_r <= 1'b0;
            cfg_ack_sync_r <= 1'b0;
            irq_enable_r <= 3'b0;
        end else begin
            cfg_ack_meta_r <= cfg_ack_toggle_i;
            cfg_ack_sync_r <= cfg_ack_meta_r;
            if (commit_write_w) begin
                cfg_req_toggle_r <= !cfg_req_toggle_r;
                transfer_control_r <= control_r;
                transfer_brightness_r <= brightness_r;
                transfer_contrast_r <= contrast_r;
                transfer_threshold_r <= threshold_r;
                transfer_spatial_control_r <= spatial_control_r;
                transfer_spatial_threshold_r <= spatial_threshold_r;
            end
            if (write_w && (offset_w == `PIXEL_CONTROL))
                control_r <= control_merge_w[3:0];
            if (write_w && (offset_w == `PIXEL_BRIGHTNESS))
                brightness_r <= brightness_merge_w[8:0];
            if (write_w && (offset_w == `PIXEL_CONTRAST))
                contrast_r <= contrast_merge_w[8:0];
            if (write_w && (offset_w == `PIXEL_THRESHOLD))
                threshold_r <= threshold_merge_w[7:0];
            if (write_w && (offset_w == `PIXEL_SPATIAL_CONTROL))
                spatial_control_r <= spatial_control_merge_w[3:0];
            if (write_w && (offset_w == `PIXEL_SPATIAL_THRESHOLD))
                spatial_threshold_r <= spatial_threshold_merge_w[7:0];
            if (write_w && (offset_w == `PIXEL_IRQ_ENABLE))
                irq_enable_r <= irq_enable_merge_w[2:0];
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            irq_status_r <= 3'b0;
            cfg_ack_prev_r <= 1'b0;
            frame_count_prev_r <= 32'b0;
            error_count_prev_r <= 32'b0;
        end else begin
            irq_status_r <= (irq_status_r & ~irq_clear_w) | irq_event_w;
            cfg_ack_prev_r <= cfg_ack_sync_r;
            frame_count_prev_r <= frame_count_i;
            error_count_prev_r <= error_count_i;
        end
    end

endmodule
