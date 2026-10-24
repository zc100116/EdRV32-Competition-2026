// ============================================================================
// File        : edrv32_cam_apb.v
// Description : APB control, status and runtime SCCB command block.
// Notes       : Camera status inputs are synchronous to clk_i. cfg_ack_toggle_i
//               is asynchronous and synchronized locally. The command payload
//               remains stable until the remote domain acknowledges it.
// ============================================================================

`include "edrv32_soc_map.vh"

module edrv32_cam_apb (
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

    input  wire         cam0_init_done_i,
    input  wire         cam1_init_done_i,
    input  wire         error_i,
    input  wire [31:0]  cam0_frame_count_i,
    input  wire [31:0]  cam1_frame_count_i,
    input  wire         cfg_ack_toggle_i,
    input  wire         cfg_response_error_i,
    input  wire [7:0]   cfg_response_data_i,

    output wire         cam0_enable_o,
    output wire         cam1_enable_o,
    output wire         cfg_req_toggle_o,
    output wire         cfg_camera_o,
    output wire         cfg_read_o,
    output wire [15:0]  cfg_reg_addr_o,
    output wire [7:0]   cfg_write_data_o,
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
        (offset_w == `CAM_ID) ||
        (offset_w == `CAM_VERSION) ||
        (offset_w == `CAM_CAPABILITY) ||
        (offset_w == `CAM_CONTROL) ||
        (offset_w == `CAM_STATUS) ||
        (offset_w == `CAM_FRAME_COUNT0) ||
        (offset_w == `CAM_FRAME_COUNT1) ||
        (offset_w == `CAM_IRQ_ENABLE) ||
        (offset_w == `CAM_IRQ_STATUS) ||
        (offset_w == `CAM_SCCB_TARGET) ||
        (offset_w == `CAM_SCCB_REG_ADDR) ||
        (offset_w == `CAM_SCCB_WRITE_DATA) ||
        (offset_w == `CAM_SCCB_COMMAND) ||
        (offset_w == `CAM_SCCB_STATUS) ||
        (offset_w == `CAM_SCCB_READ_DATA);
    wire writable_w =
        (offset_w == `CAM_CONTROL) ||
        (offset_w == `CAM_IRQ_ENABLE) ||
        (offset_w == `CAM_IRQ_STATUS) ||
        (offset_w == `CAM_SCCB_TARGET) ||
        (offset_w == `CAM_SCCB_REG_ADDR) ||
        (offset_w == `CAM_SCCB_WRITE_DATA) ||
        (offset_w == `CAM_SCCB_COMMAND);
    wire access_w = psel_i && penable_i;
    wire legal_access_w = aligned_w && local_slot_w && implemented_w &&
        (!pwrite_i || writable_w);
    wire write_w = access_w && pwrite_i && legal_access_w;
    wire [31:0] write_mask_w = {
        {8{pstrb_i[3]}}, {8{pstrb_i[2]}},
        {8{pstrb_i[1]}}, {8{pstrb_i[0]}}
    };

    reg [1:0] control_r;
    reg [4:0] irq_enable_r;
    reg [4:0] irq_status_r;
    reg [31:0] cam0_frame_prev_r;
    reg [31:0] cam1_frame_prev_r;
    reg error_prev_r;
    reg cfg_target_r;
    reg [15:0] cfg_reg_addr_r;
    reg [7:0] cfg_write_data_r;
    reg cfg_req_toggle_r;
    reg cfg_camera_r;
    reg cfg_read_r;
    reg [15:0] cfg_payload_addr_r;
    reg [7:0] cfg_payload_data_r;
    reg [7:0] cfg_read_data_r;
    reg cfg_ack_meta_r;
    reg cfg_ack_sync_r;
    reg cfg_ack_prev_r;
    reg [31:0] prdata_r;

    wire [31:0] control_merge_w = apply_strobe(
        {30'b0, control_r}, pwdata_i, pstrb_i);
    wire [31:0] irq_enable_merge_w = apply_strobe(
        {27'b0, irq_enable_r}, pwdata_i, pstrb_i);
    wire [31:0] cfg_target_merge_w = apply_strobe(
        {31'b0, cfg_target_r}, pwdata_i, pstrb_i);
    wire [31:0] cfg_addr_merge_w = apply_strobe(
        {16'b0, cfg_reg_addr_r}, pwdata_i, pstrb_i);
    wire [31:0] cfg_data_merge_w = apply_strobe(
        {24'b0, cfg_write_data_r}, pwdata_i, pstrb_i);
    wire [4:0] irq_clear_w =
        (write_w && (offset_w == `CAM_IRQ_STATUS)) ?
        (pwdata_i[4:0] & write_mask_w[4:0]) : 5'b0;
    wire cfg_busy_w = cfg_req_toggle_r != cfg_ack_sync_r;
    wire cfg_ready_w = cam0_init_done_i && cam1_init_done_i && !cfg_busy_w;
    wire cfg_command_write_w = write_w &&
        (offset_w == `CAM_SCCB_COMMAND);
    wire cfg_submit_w = cfg_command_write_w &&
        pwdata_i[`CAM_SCCB_COMMAND_SUBMIT] && pstrb_i[0];
    wire cfg_accept_w = cfg_submit_w && cfg_ready_w;
    wire cfg_reject_w = cfg_submit_w && !cfg_ready_w;
    wire cfg_done_event_w = cfg_ack_sync_r != cfg_ack_prev_r;
    wire [4:0] irq_event_w = {
        cfg_reject_w || (cfg_done_event_w && cfg_response_error_i),
        cfg_done_event_w,
        error_i && !error_prev_r,
        cam1_frame_count_i != cam1_frame_prev_r,
        cam0_frame_count_i != cam0_frame_prev_r
    };
    wire [31:0] status_w = {
        22'b0, control_r[1], control_r[0],
        5'b0, error_i, cam1_init_done_i, cam0_init_done_i
    };

    assign pready_o = 1'b1;
    assign prdata_o = prdata_r;
    assign pslverr_o = access_w && !legal_access_w;
    assign cam0_enable_o = control_r[0];
    assign cam1_enable_o = control_r[1];
    assign cfg_req_toggle_o = cfg_req_toggle_r;
    assign cfg_camera_o = cfg_camera_r;
    assign cfg_read_o = cfg_read_r;
    assign cfg_reg_addr_o = cfg_payload_addr_r;
    assign cfg_write_data_o = cfg_payload_data_r;
    assign irq_o = |(irq_status_r & irq_enable_r);

    always @(*) begin
        prdata_r = 32'b0;
        case (offset_w)
            `CAM_ID:           prdata_r = 32'h4341_4d30;
            `CAM_VERSION:      prdata_r = 32'h0003_0000;
            `CAM_CAPABILITY:   prdata_r = 32'h0000_000f;
            `CAM_CONTROL:      prdata_r = {30'b0, control_r};
            `CAM_STATUS:       prdata_r = status_w;
            `CAM_FRAME_COUNT0: prdata_r = cam0_frame_count_i;
            `CAM_FRAME_COUNT1: prdata_r = cam1_frame_count_i;
            `CAM_IRQ_ENABLE:   prdata_r = {27'b0, irq_enable_r};
            `CAM_IRQ_STATUS:   prdata_r = {27'b0, irq_status_r};
            `CAM_SCCB_TARGET:  prdata_r = {31'b0, cfg_target_r};
            `CAM_SCCB_REG_ADDR: prdata_r = {16'b0, cfg_reg_addr_r};
            `CAM_SCCB_WRITE_DATA: prdata_r = {24'b0, cfg_write_data_r};
            `CAM_SCCB_COMMAND: prdata_r = 32'b0;
            `CAM_SCCB_STATUS: prdata_r = {
                28'b0, cfg_ready_w, irq_status_r[4], irq_status_r[3],
                cfg_busy_w
            };
            `CAM_SCCB_READ_DATA: prdata_r = {24'b0, cfg_read_data_r};
            default:           prdata_r = 32'b0;
        endcase
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            control_r <= 2'b11;
            irq_enable_r <= 5'b0;
            cfg_target_r <= 1'b0;
            cfg_reg_addr_r <= 16'b0;
            cfg_write_data_r <= 8'b0;
            cfg_req_toggle_r <= 1'b0;
            cfg_camera_r <= 1'b0;
            cfg_read_r <= 1'b0;
            cfg_payload_addr_r <= 16'b0;
            cfg_payload_data_r <= 8'b0;
        end else begin
            if (write_w && (offset_w == `CAM_CONTROL))
                control_r <= control_merge_w[1:0];
            if (write_w && (offset_w == `CAM_IRQ_ENABLE))
                irq_enable_r <= irq_enable_merge_w[4:0];
            if (write_w && (offset_w == `CAM_SCCB_TARGET))
                cfg_target_r <= cfg_target_merge_w[0];
            if (write_w && (offset_w == `CAM_SCCB_REG_ADDR))
                cfg_reg_addr_r <= cfg_addr_merge_w[15:0];
            if (write_w && (offset_w == `CAM_SCCB_WRITE_DATA))
                cfg_write_data_r <= cfg_data_merge_w[7:0];
            if (cfg_accept_w) begin
                cfg_camera_r <= cfg_target_r;
                cfg_read_r <= pwdata_i[`CAM_SCCB_COMMAND_READ];
                cfg_payload_addr_r <= cfg_reg_addr_r;
                cfg_payload_data_r <= cfg_write_data_r;
                cfg_req_toggle_r <= ~cfg_req_toggle_r;
            end
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            irq_status_r <= 5'b0;
            cam0_frame_prev_r <= 32'b0;
            cam1_frame_prev_r <= 32'b0;
            error_prev_r <= 1'b0;
            cfg_ack_meta_r <= 1'b0;
            cfg_ack_sync_r <= 1'b0;
            cfg_ack_prev_r <= 1'b0;
            cfg_read_data_r <= 8'b0;
        end else begin
            irq_status_r <= (irq_status_r & ~irq_clear_w) | irq_event_w;
            cam0_frame_prev_r <= cam0_frame_count_i;
            cam1_frame_prev_r <= cam1_frame_count_i;
            error_prev_r <= error_i;
            cfg_ack_meta_r <= cfg_ack_toggle_i;
            cfg_ack_sync_r <= cfg_ack_meta_r;
            cfg_ack_prev_r <= cfg_ack_sync_r;
            if (cfg_done_event_w)
                cfg_read_data_r <= cfg_response_data_i;
        end
    end

endmodule
