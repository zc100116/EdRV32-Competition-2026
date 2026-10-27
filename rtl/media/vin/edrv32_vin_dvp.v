// File: edrv32_vin_dvp.v
// Spec: vin 2.1; SoC 5.2 X4.
// Description: Sample high-byte-first DVP and retain the last word until line end.
//              Control items preserve frame boundaries when pixel storage overflows.
// Clock domain: cam pclk producer, clk_mem consumer through the common async FIFO.
module edrv32_vin_dvp (
    // Clocks and resets.
    input wire clk_cam_i,
    input wire rst_cam_n_i,
    input wire clk_mem_i,
    input wire rst_mem_n_i,

    // Sensor input.
    input wire vsync_i,
    input wire href_i,
    input wire [7:0] data_i,

    // Items: [35:34] DATA=0, EOL=1, SOF=2, EOF=3; [33] EOL; [32] lost.
    output wire item_valid_o,
    input wire item_ready_i,
    output wire [35:0] item_data_o
);
    reg vsync_r;
    reg href_r;
    reg active_r;
    reg byte_phase_r;
    reg pixel_phase_r;
    reg [7:0] high_byte_r;
    reg [15:0] left_pixel_r;
    reg [31:0] last_word_r;
    reg last_valid_r;
    reg drop_r;
    reg odd_line_r;
    reg sof_pending_r;
    reg eof_pending_r;
    reg eof_lost_r;
    wire start_w;
    wire end_w;
    wire line_end_w;
    wire word_w;
    wire fifo_ready_w;
    reg fifo_valid_w;
    reg [35:0] fifo_data_w;
    wire pixel_item_w;

    // A retained boundary pair owns its frame until serialized; later raw frames are skipped.
    assign start_w = vsync_r && !vsync_i && !sof_pending_r && !eof_pending_r;
    assign end_w = active_r && !vsync_r && vsync_i;
    assign line_end_w = active_r && href_r && !href_i;
    assign word_w = active_r && href_i && byte_phase_r && pixel_phase_r;
    assign pixel_item_w = !eof_pending_r && !sof_pending_r && !start_w &&
        !drop_r && (line_end_w || (!end_w && word_w && last_valid_r));

    always @(*) begin
        fifo_valid_w = 1'b0;
        fifo_data_w = 36'd0;
        if (sof_pending_r || start_w) begin
            fifo_valid_w = 1'b1;
            fifo_data_w = {2'd2, 34'd0};
        end else if (eof_pending_r) begin
            fifo_valid_w = 1'b1;
            fifo_data_w = {2'd3, 1'b0, eof_lost_r, 32'd0};
        end else if (pixel_item_w) begin
            fifo_valid_w = 1'b1;
            fifo_data_w = {2'd0, line_end_w, 1'b0, last_word_r};
            if (line_end_w && !last_valid_r)
                fifo_data_w = {2'd1, 34'd0};
        end else if (end_w) begin
            fifo_valid_w = 1'b1;
            fifo_data_w = {2'd3, 1'b0, drop_r || odd_line_r, 32'd0};
        end
    end

    edrv32_async_fifo #(
        .WIDTH(36),
        .DEPTH(16)
    ) u_items (
        // Domain boundary, spec SoC X4.
        .clk_write_i(clk_cam_i),
        .rst_write_n_i(rst_cam_n_i),
        .clk_read_i(clk_mem_i),
        .rst_read_n_i(rst_mem_n_i),
        // Item producer and consumer.
        .valid_i(fifo_valid_w),
        .ready_o(fifo_ready_w),
        .data_i(fifo_data_w),
        .valid_o(item_valid_o),
        .ready_i(item_ready_i),
        .data_o(item_data_o)
    );

    always @(posedge clk_cam_i) begin
        if (active_r && href_i) begin
            if (!byte_phase_r)
                high_byte_r <= data_i;
            else if (!pixel_phase_r)
                left_pixel_r <= {high_byte_r, data_i};
            else
                last_word_r <= {high_byte_r, data_i, left_pixel_r};
        end
    end

    always @(posedge clk_cam_i or negedge rst_cam_n_i) begin
        if (!rst_cam_n_i) begin
            vsync_r <= 1'b1;
            href_r <= 1'b0;
            active_r <= 1'b0;
            byte_phase_r <= 1'b0;
            pixel_phase_r <= 1'b0;
            last_valid_r <= 1'b0;
            drop_r <= 1'b0;
            odd_line_r <= 1'b0;
            sof_pending_r <= 1'b0;
            eof_pending_r <= 1'b0;
            eof_lost_r <= 1'b0;
        end else begin
            vsync_r <= vsync_i;
            href_r <= href_i;
            if (fifo_ready_w) begin
                if (sof_pending_r)
                    sof_pending_r <= 1'b0;
                else if (eof_pending_r)
                    eof_pending_r <= 1'b0;
            end
            if (start_w) begin
                active_r <= 1'b1;
                odd_line_r <= 1'b0;
                byte_phase_r <= 1'b0;
                pixel_phase_r <= 1'b0;
                last_valid_r <= 1'b0;
                sof_pending_r <= !fifo_ready_w;
                drop_r <= !fifo_ready_w;
            end else if (end_w) begin
                active_r <= 1'b0;
                last_valid_r <= 1'b0;
                eof_pending_r <= !fifo_ready_w || sof_pending_r || pixel_item_w;
                eof_lost_r <= drop_r || odd_line_r || (line_end_w && pixel_phase_r) ||
                    (pixel_item_w && !fifo_ready_w);
            end else if (active_r) begin
                if (line_end_w && pixel_phase_r)
                    odd_line_r <= 1'b1;
                if (!href_i) begin
                    byte_phase_r <= 1'b0;
                    pixel_phase_r <= 1'b0;
                    last_valid_r <= 1'b0;
                end else begin
                    byte_phase_r <= !byte_phase_r;
                    if (byte_phase_r)
                        pixel_phase_r <= !pixel_phase_r;
                    if (word_w)
                        last_valid_r <= 1'b1;
                end
                if (pixel_item_w && !fifo_ready_w)
                    drop_r <= 1'b1;
            end
        end
    end
endmodule
