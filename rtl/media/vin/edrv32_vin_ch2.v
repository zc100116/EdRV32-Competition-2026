// File: edrv32_vin_ch2.v
// Spec: vin 2.4--2.9, 4.3, 5, 6; SoC 7.3 R2/R5/R6.
// Description: Admit CH2 frames, adapt RGB565 to INT8_C4, and queue surface writes.
//              One pending descriptor permits reception while the preceding DMA retires.
// Clock domain: clk_mem.
module edrv32_vin_ch2 (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Selected RGB565 source, before PIX.
    input wire source_valid_i,
    output wire source_ready_o,
    input wire [31:0] source_data_i,
    input wire source_sof_i,
    input wire source_eol_i,
    input wire source_eof_i,
    input wire [31:0] source_frame_id_i,
    input wire [10:0] source_width_i,
    input wire [11:0] source_height_i,
    input wire source_incomplete_i,
    input wire [2:0] frame_boundary_i,

    // DMA write master, routed through the common VIN arbiter.
    output wire [31:0] axi_awaddr_o,
    output wire [3:0] axi_awlen_o,
    output wire axi_awvalid_o,
    input wire axi_awready_i,
    output wire [255:0] axi_wdata_o,
    output wire [31:0] axi_wstrb_o,
    output wire axi_wlast_o,
    output wire axi_wvalid_o,
    input wire axi_wready_i,
    input wire [1:0] axi_bresp_i,
    input wire axi_bvalid_i,
    output wire axi_bready_o,

    // Configuration, source selection, and status.
    input wire enable_i,
    input wire en_i,
    input wire [1:0] src_i,
    input wire [2:0] ring_i,
    input wire [15:0] stride_i,
    input wire [127:0] bases_i,
    input wire [3:0] slot_busy_i,
    input wire abort_i,
    output wire [1:0] source_select_o,
    output wire busy_o,
    output wire [9:0] count_o,
    output wire dma_abort_o,
    output wire [2:0] wr_stat_o,
    output reg [5:0] done_info_o,
    output reg [31:0] done_frame_id_o,
    output wire done_o,
    output wire bus_error_o,
    output wire overflow_o,
    output wire skip_o,
    output wire cfg_error_o,
    output wire [1:0] cfg_errors_o
);
    reg route_r;
    reg receiving_r;
    reg dropping_r;
    reg stopping_r;
    reg [1:0] receive_src_r;
    reg [31:0] receive_id_r;
    reg receive_incomplete_r;
    reg [2:0] last_slot_r;
    reg [2:0] receive_previous_r;
    reg pending_r;
    reg [31:0] pending_base_r;
    reg [15:0] pending_stride_r;
    reg [1:0] pending_slot_r;
    reg [1:0] pending_src_r;
    reg [31:0] pending_id_r;
    reg pending_incomplete_r;
    reg [2:0] pending_previous_r;
    reg write_meta_r;
    reg [1:0] write_slot_r;
    reg [1:0] write_src_r;
    reg [31:0] write_id_r;
    reg write_incomplete_r;
    reg [2:0] write_previous_r;
    reg fifo_push_r;
    reg [9:0] fifo_write_r;
    reg [9:0] fifo_fetch_r;
    reg [1:0] fifo_output_count_r;
    reg fifo_read_slot_r;
    reg fifo_fetch_slot_r;
    reg fifo_pending_r;
    reg fifo_capture0_r;
    reg fifo_capture1_r;
    reg [287:0] fifo_head0_r;
    reg [287:0] fifo_head1_r;
    wire fifo_read_w;
    wire [2:0] fifo_reserved_w;
    reg [9:0] count_r;
    reg [2:0] candidate_w;
    reg found_w;
    reg [1:0] slot_w;
    integer scan_w;
    wire qualified_w;
    wire boundary_w;
    wire admit_w;
    wire can_admit_w;
    wire dropping_write_w;
    wire passing_w;
    wire source_fire_w;
    wire result_fire_w;
    wire fifo_ready_w;
    wire ram_wr_en_w;
    wire [8:0] ram_wr_addr_w;
    wire [287:0] ram_wr_data_w;
    wire ram_rd_en_w;
    wire [8:0] ram_rd_addr_w;
    wire [287:0] ram_rd_data_w;
    wire fifo_valid_w;
    wire fifo_push_w;
    wire beat_accept_w;
    wire fifo_pop_w;
    wire fifo_discard_w;
    wire [287:0] fifo_data_w;
    wire dma_ready_w;
    wire dma_idle_w;
    wire dma_done_w;
    wire dma_error_w;
    wire dma_data_ready_w;
    wire descriptor_w;
    wire short_tail_w;
    wire unused_awid_w;
    wire result_valid_w;
    wire [255:0] result_data_w;
    wire result_eof_w;
    wire result_blocked_w;
    wire top_pending_w;
    reg source_capacity_r;
    wire size_valid_w;
    reg [255:0] fifo_data_r;

    // spec 2.6: start after the previous allocation, wrapping in the configured ring.
    always @(*) begin
        found_w = 1'b0;
        slot_w = 2'd0;
        candidate_w = last_slot_r + 3'd1;
        if (last_slot_r == 3'd7 || candidate_w >= ring_i)
            candidate_w = 3'd0;
        for (scan_w = 0; scan_w < 4; scan_w = scan_w + 1) begin
            if (!found_w && scan_w < {29'd0, ring_i} && !slot_busy_i[candidate_w[1:0]]) begin
                found_w = 1'b1;
                slot_w = candidate_w[1:0];
            end
            candidate_w = candidate_w + 3'd1;
            if (candidate_w >= ring_i)
                candidate_w = 3'd0;
        end
    end

    assign size_valid_w = source_width_i == 11'd1280 && source_height_i == 12'd720;
    assign source_select_o = route_r ? receive_src_r : src_i;
    assign qualified_w = enable_i && en_i && !receiving_r && !pending_r &&
        !dropping_r && !stopping_r && !abort_i;
    assign boundary_w = source_valid_i && source_sof_i;
    assign cfg_errors_o = !qualified_w ? 2'd0 : (src_i == 2'd3 ?
        ({1'b0, frame_boundary_i[0]} + {1'b0, frame_boundary_i[1]} +
            {1'b0, frame_boundary_i[2]}) :
        {1'b0, (boundary_w && (ring_i < 3'd2 || ring_i > 3'd4 || !size_valid_w))});
    assign cfg_error_o = |cfg_errors_o;
    assign skip_o = qualified_w && boundary_w && src_i != 2'd3 &&
        ring_i >= 3'd2 && ring_i <= 3'd4 && size_valid_w && !found_w;
    assign can_admit_w = qualified_w && source_sof_i && src_i != 2'd3 &&
        ring_i >= 3'd2 && ring_i <= 3'd4 && size_valid_w && found_w;
    assign admit_w = can_admit_w && source_valid_i;
    assign passing_w = (route_r || can_admit_w) && !abort_i &&
        (!stopping_r || dropping_r);
    // vin 2.5/2.8: cameras never stall; memory waits for padding and FIFO capacity.
    // Once count reaches 430, the registered capacity can admit one more word.
    // Horizontal/read/pixel plus that word contribute at most four pixels: with
    // seven packed pixels, at most one beat, plus one registered result beat.
    // EOF may independently flush 640 pixels = 80 beats. Thus 430 + 2 + 80 = 512.
    // Top padding is serialized before memory input; bottom padding is paced
    // separately with one slot reserved for valid_o (count < 511).
    assign source_ready_o = source_select_o != 2'd2 || !passing_w ||
        (source_capacity_r && !top_pending_w);
    assign source_fire_w = source_valid_i && source_ready_o;
    assign result_fire_w = result_valid_w && receiving_r;
    assign overflow_o = result_fire_w && (!fifo_ready_w || result_blocked_w) &&
        !dropping_r && !stopping_r && !abort_i;
    assign beat_accept_w = result_fire_w && !dropping_r && !stopping_r
        && !abort_i && !overflow_o;
    assign fifo_push_w = fifo_push_r;
    assign fifo_discard_w = stopping_r && dma_idle_w;
    assign fifo_pop_w = fifo_discard_w || dma_data_ready_w;
    assign count_o = count_r;
    assign short_tail_w = axi_awvalid_o &&
        count_r < {6'd0, axi_awlen_o} + 10'd1;
    assign dropping_write_w = dropping_r && write_meta_r &&
        write_id_r == receive_id_r && write_src_r == receive_src_r;
    assign dma_abort_o = abort_i || stopping_r;
    assign busy_o = receiving_r || pending_r || !dma_idle_w || stopping_r || dropping_r;
    assign wr_stat_o = {write_slot_r, write_meta_r};
    assign descriptor_w = pending_r && dma_ready_w && !dma_abort_o;
    assign done_o = dma_done_w && !dropping_write_w && !stopping_r && !abort_i;
    assign bus_error_o = done_o && dma_error_w;

    edrv32_vin_ch2_data u_data (
        // An admitted frame owns the pipeline through its bottom padding.
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .valid_i(source_fire_w && passing_w),
        .data_i(source_data_i),
        .sof_i(source_sof_i),
        .eol_i(source_eol_i),
        .eof_i(source_eof_i),
        .abort_i(abort_i),

        // Only padding waits; effective camera beats retain the overflow path.
        .padding_ready_i(count_r < 10'd511),
        .top_pending_o(top_pending_w),
        .valid_o(result_valid_w),
        .data_o(result_data_w),
        .eof_o(result_eof_w),
        .blocked_o(result_blocked_w)
    );

    // Reserve an output slot when issuing a DRM read. Its capture enable is
    // registered one clock before the RAM data arrives, so no READY/abort logic
    // drives the 288-bit head registers' enables (vin 2.6).
    // Reserve the entry when accepting a whole beat. The registered write
    // owns that entry even if the next frame overflows or ABORT arrives later.
    assign fifo_ready_w = count_r < 10'd512;
    assign ram_wr_en_w = fifo_push_w;
    assign ram_wr_addr_w = fifo_write_r[8:0];
    assign ram_wr_data_w = {32'hffff_ffff, fifo_data_r};
    assign fifo_valid_w = fifo_output_count_r != 0;
    assign fifo_data_w = fifo_read_slot_r ? fifo_head1_r : fifo_head0_r;
    assign fifo_read_w = fifo_pop_w && fifo_valid_w;
    assign fifo_reserved_w = {1'b0, fifo_output_count_r} + {2'd0, fifo_pending_r}
        - {2'd0, fifo_read_w};
    assign ram_rd_en_w = fifo_fetch_r != fifo_write_r && fifo_reserved_w < 3'd2;
    assign ram_rd_addr_w = fifo_fetch_r[8:0];
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            fifo_write_r <= 10'd0;
            fifo_fetch_r <= 10'd0;
            fifo_output_count_r <= 2'd0;
            fifo_read_slot_r <= 1'b0;
            fifo_fetch_slot_r <= 1'b0;
            fifo_pending_r <= 1'b0;
            fifo_capture0_r <= 1'b0;
            fifo_capture1_r <= 1'b0;
            fifo_push_r <= 1'b0;
        end else begin
            fifo_push_r <= beat_accept_w;
            if (ram_wr_en_w)
                fifo_write_r <= fifo_write_r + 10'd1;
            if (ram_rd_en_w) begin
                fifo_fetch_r <= fifo_fetch_r + 10'd1;
                fifo_fetch_slot_r <= !fifo_fetch_slot_r;
            end
            fifo_pending_r <= ram_rd_en_w;
            fifo_capture0_r <= ram_rd_en_w && !fifo_fetch_slot_r;
            fifo_capture1_r <= ram_rd_en_w && fifo_fetch_slot_r;
            if (fifo_read_w)
                fifo_read_slot_r <= !fifo_read_slot_r;
            case ({fifo_pending_r, fifo_read_w})
                2'b10: fifo_output_count_r <= fifo_output_count_r + 2'd1;
                2'b01: fifo_output_count_r <= fifo_output_count_r - 2'd1;
                default: begin end
            endcase
        end
    end
    always @(posedge clk_i) begin
        if (fifo_capture0_r)
            fifo_head0_r <= ram_rd_data_w;
        if (fifo_capture1_r)
            fifo_head1_r <= ram_rd_data_w;
        fifo_data_r <= result_data_w;
    end

    edrv32_ram_vin_wfifo u_fifo_ram (
        // Storage clocks and enabled ports.
        .clk_i(clk_i),
        .wr_en_i(ram_wr_en_w),
        .wr_addr_i(ram_wr_addr_w),
        .wr_data_i(ram_wr_data_w),
        .rd_en_i(ram_rd_en_w),
        .rd_addr_i(ram_rd_addr_w),
        .rd_data_o(ram_rd_data_w)
    );

    edrv32_dma2d_wr #(
        .OUTSTANDING(4)
    ) u_write (
        // Descriptor and buffered beats.
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .desc_valid_i(pending_r && !dma_abort_o),
        .desc_ready_o(dma_ready_w),
        .desc_base_i(pending_base_r),
        .desc_stride_i({16'd0, pending_stride_r}),
        .desc_width_bytes_i(16'd2560),
        .desc_height_i(12'd384),
        .data_valid_i(fifo_valid_w && !fifo_discard_w),
        .data_ready_o(dma_data_ready_w),
        .data_i(fifo_data_w[255:0]),
        .data_strb_i(fifo_data_w[287:256]),
        // Write bus.
        .axi_awid_o(unused_awid_w),
        .axi_awaddr_o(axi_awaddr_o),
        .axi_awlen_o(axi_awlen_o),
        .axi_awvalid_o(axi_awvalid_o),
        .axi_awready_i(axi_awready_i),
        .axi_wdata_o(axi_wdata_o),
        .axi_wstrb_o(axi_wstrb_o),
        .axi_wlast_o(axi_wlast_o),
        .axi_wvalid_o(axi_wvalid_o),
        .axi_wready_i(axi_wready_i),
        .axi_bid_i(1'b0),
        .axi_bresp_i(axi_bresp_i),
        .axi_bvalid_i(axi_bvalid_i),
        .axi_bready_o(axi_bready_o),
        // ABORT drains every committed burst, including held AW/W.
        .abort_i(dma_abort_o),
        .idle_o(dma_idle_w),
        .done_o(dma_done_w),
        .err_o(dma_error_w)
    );

    always @(posedge clk_i) begin
        if (admit_w && source_ready_o) begin
            receive_id_r <= source_frame_id_i;
            pending_id_r <= source_frame_id_i;
            pending_base_r <= bases_i[slot_w * 32 +: 32];
            pending_stride_r <= stride_i;
        end
        if (descriptor_w)
            write_id_r <= pending_id_r;
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            route_r <= 1'b0;
            receiving_r <= 1'b0;
            dropping_r <= 1'b0;
            stopping_r <= 1'b0;
            receive_src_r <= 2'd0;
            receive_incomplete_r <= 1'b0;
            last_slot_r <= 3'd7;
            receive_previous_r <= 3'd7;
            pending_r <= 1'b0;
            pending_slot_r <= 2'd0;
            pending_src_r <= 2'd0;
            pending_incomplete_r <= 1'b0;
            pending_previous_r <= 3'd7;
            write_meta_r <= 1'b0;
            write_slot_r <= 2'd0;
            write_src_r <= 2'd0;
            write_incomplete_r <= 1'b0;
            write_previous_r <= 3'd7;
            count_r <= 10'd0;
            source_capacity_r <= 1'b1;
            done_info_o <= 6'd0;
            done_frame_id_o <= 32'd0;
        end else begin
            source_capacity_r <= count_r < 10'd430;
            if (descriptor_w) begin
                pending_r <= 1'b0;
                write_meta_r <= 1'b1;
                write_slot_r <= pending_slot_r;
                write_src_r <= pending_src_r;
                write_incomplete_r <= (source_fire_w && source_eof_i &&
                    pending_id_r == receive_id_r && pending_src_r == receive_src_r) ?
                    source_incomplete_i : pending_incomplete_r;
                write_previous_r <= pending_previous_r;
            end
            if (done_o) begin
                done_info_o <= {dma_error_w, write_incomplete_r, write_src_r, write_slot_r};
                done_frame_id_o <= write_id_r;
                write_meta_r <= descriptor_w;
            end
            if (admit_w && source_ready_o) begin
                route_r <= !source_eof_i;
                receiving_r <= 1'b1;
                receive_src_r <= src_i;
                receive_incomplete_r <= source_incomplete_i;
                receive_previous_r <= last_slot_r;
                last_slot_r <= {1'b0, slot_w};
                pending_r <= 1'b1;
                pending_slot_r <= slot_w;
                pending_src_r <= src_i;
                pending_incomplete_r <= source_incomplete_i;
                pending_previous_r <= last_slot_r;
            end
            if (source_fire_w && route_r && source_eof_i) begin
                route_r <= 1'b0;
                receive_incomplete_r <= source_incomplete_i;
                if (pending_r && pending_id_r == receive_id_r && pending_src_r == receive_src_r)
                    pending_incomplete_r <= source_incomplete_i;
                if (write_meta_r && write_id_r == receive_id_r && write_src_r == receive_src_r)
                    write_incomplete_r <= source_incomplete_i;
            end
            if (result_fire_w) begin
                if (result_eof_w)
                    receiving_r <= 1'b0;
                if (result_eof_w && write_meta_r && !source_eof_i)
                    write_incomplete_r <= receive_incomplete_r;
            end
            if (overflow_o) begin
                dropping_r <= 1'b1;
                last_slot_r <= admit_w && source_ready_o ? last_slot_r : receive_previous_r;
            end
            if (dropping_write_w && (short_tail_w || count_r == 0))
                stopping_r <= 1'b1;
            if (abort_i) begin
                route_r <= 1'b0;
                receiving_r <= 1'b0;
                pending_r <= 1'b0;
                stopping_r <= 1'b1;
                if (write_meta_r)
                    last_slot_r <= write_previous_r;
                else if (receiving_r || pending_r)
                    last_slot_r <= receive_previous_r;
            end
            // Count includes the registered write and entries awaiting RAM prefetch.
            if (stopping_r && dma_idle_w && count_r == 10'd0 && !receiving_r) begin
                stopping_r <= 1'b0;
                dropping_r <= 1'b0;
                receiving_r <= 1'b0;
                write_meta_r <= 1'b0;
                pending_r <= 1'b0;
            end
            case ({beat_accept_w, fifo_pop_w && fifo_valid_w})
                2'b10: count_r <= count_r + 10'd1;
                2'b01: count_r <= count_r - 10'd1;
                default: count_r <= count_r;
            endcase
        end
    end
endmodule
