// File: edrv32_disp_control.v
// Spec: disp-spec 2.4, 4.1, 5.2; coordinator X5/X6 reset-drain clarification.
// Description: Acknowledge frame requests before allowing a memory-domain reset.
//              Each disable is explicitly acknowledged after prior frame requests drain.
// Clock domain: clk_mem and clk_pix.
module edrv32_disp_control (
    // Clock domains and resets.
    input wire clk_mem_i,
    input wire rst_mem_n_i,
    input wire clk_pix_i,
    input wire rst_pix_n_i,

    // Memory-domain control and pixel-domain request.
    input wire enable_i,
    input wire frame_req_i,

    // Pixel enable, memory request and drain status.
    output wire enable_o,
    output wire frame_req_o,
    output wire scan_live_o
);
    wire frame_req_ready_w;
    wire scan_live_w;
    wire unused_frame_req_data_w;
    wire scan_live_mem_w;
    wire stop_ready_mem_w;
    wire stop_ready_pix_w;
    wire stop_valid_w;
    wire stop_fire_w;
    wire stop_needed_w;
    wire unused_stop_valid_w;
    wire unused_stop_data_w;
    reg enable_previous_r;
    reg stop_pending_r;
    reg stop_sent_r;

    assign scan_live_w = enable_o || !frame_req_ready_w;
    assign stop_needed_w = enable_previous_r && !enable_i;
    assign stop_valid_w = stop_needed_w || (stop_pending_r && !stop_sent_r);
    assign stop_fire_w = stop_valid_w && stop_ready_mem_w;
    assign stop_ready_pix_w = !enable_o && frame_req_ready_w;
    assign scan_live_o = scan_live_mem_w || stop_pending_r || stop_needed_w;

    // A falling ENABLE cannot complete from a stale returned scan-live level.
    always @(posedge clk_mem_i or negedge rst_mem_n_i) begin
        if (!rst_mem_n_i) begin
            enable_previous_r <= 1'b0;
            stop_pending_r <= 1'b0;
            stop_sent_r <= 1'b0;
        end else begin
            enable_previous_r <= enable_i;
            if (stop_needed_w) begin
                stop_pending_r <= 1'b1;
                stop_sent_r <= stop_fire_w;
            end else if (stop_fire_w) begin
                stop_sent_r <= 1'b1;
            end else if (stop_pending_r && stop_sent_r && stop_ready_mem_w) begin
                stop_pending_r <= 1'b0;
                stop_sent_r <= 1'b0;
            end
        end
    end

    edrv32_cdc_sync_bit u_enable (
        // Pixel destination clock and reset.
        .clk_i(clk_pix_i),
        .rst_n_i(rst_pix_n_i),

        // Scan enable level.
        .bit_i(enable_i),
        .bit_o(enable_o)
    );

    // The destination acknowledges on the same edge that reader counts the request.
    edrv32_cdc_handshake #(
        .WIDTH(1)
    ) u_frame_req (
        // Clock domains and resets.
        .clk_src_i(clk_pix_i),
        .rst_src_n_i(rst_pix_n_i),
        .clk_dst_i(clk_mem_i),
        .rst_dst_n_i(rst_mem_n_i),

        // Frame event with completion acknowledgement.
        .valid_i(frame_req_i),
        .ready_o(frame_req_ready_w),
        .data_i(1'b0),
        .valid_o(frame_req_o),
        .ready_i(1'b1),
        .data_o(unused_frame_req_data_w)
    );

    edrv32_cdc_sync_bit u_scan_live (
        // Memory destination clock and reset.
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),

        // Drain acknowledgement includes the frame-request handshake.
        .bit_i(scan_live_w),
        .bit_o(scan_live_mem_w)
    );

    // The pixel destination accepts a stop only after disable and the frame ACK.
    edrv32_cdc_handshake #(
        .WIDTH(1)
    ) u_stop (
        // Clock domains and resets.
        .clk_src_i(clk_mem_i),
        .rst_src_n_i(rst_mem_n_i),
        .clk_dst_i(clk_pix_i),
        .rst_dst_n_i(rst_pix_n_i),

        // Stop request and explicit round-trip completion.
        .valid_i(stop_valid_w),
        .ready_o(stop_ready_mem_w),
        .data_i(1'b0),
        .valid_o(unused_stop_valid_w),
        .ready_i(stop_ready_pix_w),
        .data_o(unused_stop_data_w)
    );
endmodule
