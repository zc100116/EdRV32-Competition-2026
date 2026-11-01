// File: edrv32_vin_ch.v
// Spec: vin 2.4--2.7, 2.9, 4.3, 5, 6; SoC 7.3 R2/R5/R6.
// Description: Admit a frame, select its software-owned surface slot, and pack writes.
//              One pending descriptor permits reception while the preceding DMA retires.
// Clock domain: clk_mem.
module edrv32_vin_ch (
    // Clock and reset.
    input wire clk_i,
    input wire [2:0] rst_n_i,

    // Selected source before PIX (or the CH1 bypass).
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

    // Pipeline send; CH0 goes to PIX, CH1 loops back locally.
    output wire pipe_valid_o,
    input wire pipe_ready_i,
    output wire [31:0] pipe_data_o,
    output wire pipe_sof_o,
    output wire pipe_eol_o,
    output wire pipe_eof_o,

    // Pipeline return, packed into the write FIFO.
    input wire result_valid_i,
    output wire result_ready_o,
    input wire [31:0] result_data_i,
    input wire result_eol_i,
    input wire result_eof_i,

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
    output wire urgent_o,
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
    reg [10:0] pending_width_r;
    reg [11:0] pending_height_r;
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
    reg pack_valid_r;
    reg [31:0] pack_data_r;
    reg [2:0] pack_word_r;
    reg fifo_push_r;
    reg [255:0] pack_r;
    reg [9:0] fifo_write_r;
    reg [9:0] fifo_fetch_r;
    reg [1:0] fifo_output_count_r;
    reg [3:0] fifo_read_slot_r /* synthesis syn_preserve=1 */;
    reg fifo_fetch_slot_r;
    reg fifo_pending_r;
    reg fifo_capture0_r;
    reg fifo_capture1_r;
    reg [287:0] fifo_head0_r;
    reg [287:0] fifo_head1_r;
    wire fifo_read_w;
    wire [2:0] fifo_reserved_w;
    reg [2:0] word_r;
    reg [9:0] count_r;
    reg [255:0] packed_data_w;
    reg [31:0] packed_strb_w;
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
    wire flush_w;
    wire fifo_ready_w;
    wire ram_wr_en_w;
    wire [8:0] ram_wr_addr_w;
    wire [287:0] ram_wr_data_w;
    wire ram_rd_en_w;
    wire [8:0] ram_rd_addr_w;
    wire [287:0] ram_rd_data_w;
    wire fifo_valid_w;
    wire fifo_push_w;
    wire pack_accept_w;
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

    assign source_select_o = route_r ? receive_src_r : src_i;
    assign qualified_w = enable_i && en_i && !receiving_r && !pending_r &&
        !dropping_r && !stopping_r && !abort_i;
    assign boundary_w = source_valid_i && source_sof_i;
    assign cfg_errors_o = !qualified_w ? 2'd0 : (src_i == 2'd3 ?
        ({1'b0, frame_boundary_i[0]} + {1'b0, frame_boundary_i[1]} +
            {1'b0, frame_boundary_i[2]}) :
        {1'b0, (boundary_w && (ring_i < 3'd2 || ring_i > 3'd4))});
    assign cfg_error_o = |cfg_errors_o;
    assign skip_o = qualified_w && boundary_w && src_i != 2'd3 &&
        ring_i >= 3'd2 && ring_i <= 3'd4 && !found_w;
    assign can_admit_w = qualified_w && source_sof_i && src_i != 2'd3 &&
        ring_i >= 3'd2 && ring_i <= 3'd4 && found_w;
    assign admit_w = can_admit_w && source_valid_i;
    assign passing_w = (route_r || can_admit_w) && !abort_i &&
        (!stopping_r || dropping_r);
    assign pipe_valid_o = source_valid_i && passing_w;
    assign pipe_data_o = source_data_i;
    assign pipe_sof_o = source_sof_i;
    assign pipe_eol_o = source_eol_i;
    assign pipe_eof_o = source_eof_i;
    assign source_ready_o = !passing_w || pipe_ready_i;
    assign source_fire_w = source_valid_i && source_ready_o;
    assign result_ready_o = (receiving_r ? receive_src_r : src_i) != 2'd2 ||
        fifo_ready_w ||
        dropping_r || stopping_r || abort_i;
    assign result_fire_w = result_valid_i && result_ready_o && (receiving_r || admit_w);
    assign overflow_o = result_valid_i && (receiving_r || admit_w) &&
        (receiving_r ? receive_src_r : src_i) != 2'd2 && !fifo_ready_w &&
        !dropping_r && !stopping_r && !abort_i;
    assign flush_w = word_r == 3'd7 || result_eol_i;
    assign pack_accept_w = result_fire_w && flush_w && !dropping_r && !stopping_r
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
    assign urgent_o = receiving_r && receive_src_r != 2'd2 && count_r >= 10'd256;
    assign wr_stat_o = {write_slot_r, write_meta_r};
    assign descriptor_w = pending_r && dma_ready_w && !dma_abort_o;
    assign done_o = dma_done_w && !dropping_write_w && !stopping_r && !abort_i;
    assign bus_error_o = done_o && dma_error_w;

    always @(*) begin
        packed_data_w = pack_r;
        packed_data_w[pack_word_r * 32 +: 32] = pack_data_r;
        packed_strb_w = 32'hffff_ffff >> ((7 - {29'd0, pack_word_r}) * 4);
    end

    // Reserve an output slot when issuing a DRM read. Its capture enable is
    // registered one clock before the RAM data arrives, so no READY/abort logic
    // drives the 288-bit head registers' enables (vin 2.6).
    // Reserve the entry when accepting its final word. The registered write
    // owns that entry even if the next frame overflows or ABORT arrives later.
    assign fifo_ready_w = count_r < 10'd512;
    assign ram_wr_en_w = fifo_push_w;
    assign ram_wr_addr_w = fifo_write_r[8:0];
    assign ram_wr_data_w = {packed_strb_w, packed_data_w};
    assign fifo_valid_w = fifo_output_count_r != 0;
    assign fifo_data_w[287:256] = fifo_read_slot_r[3] ?
        fifo_head1_r[287:256] : fifo_head0_r[287:256];
    genvar read_slice;
    generate
        for (read_slice = 0; read_slice < 4; read_slice = read_slice + 1) begin : g_read_slice
            assign fifo_data_w[read_slice*64 +: 64] = fifo_read_slot_r[read_slice] ?
                fifo_head1_r[read_slice*64 +: 64] : fifo_head0_r[read_slice*64 +: 64];
        end
    endgenerate
    assign fifo_read_w = fifo_pop_w && fifo_valid_w;
    assign fifo_reserved_w = {1'b0, fifo_output_count_r} + {2'd0, fifo_pending_r}
        - {2'd0, fifo_read_w};
    assign ram_rd_en_w = fifo_fetch_r != fifo_write_r && fifo_reserved_w < 3'd2;
    assign ram_rd_addr_w = fifo_fetch_r[8:0];
    always @(posedge clk_i or negedge rst_n_i[0]) begin
        if (!rst_n_i[0]) begin
            fifo_write_r <= 10'd0;
            fifo_fetch_r <= 10'd0;
            fifo_output_count_r <= 2'd0;
            fifo_read_slot_r <= 4'b0;
            fifo_fetch_slot_r <= 1'b0;
            fifo_pending_r <= 1'b0;
            fifo_capture0_r <= 1'b0;
            fifo_capture1_r <= 1'b0;
            pack_valid_r <= 1'b0;
            fifo_push_r <= 1'b0;
        end else begin
            fifo_push_r <= pack_accept_w;
            pack_valid_r <= result_fire_w && !dropping_r && !stopping_r && !abort_i
                && !overflow_o;
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
                fifo_read_slot_r <= ~fifo_read_slot_r;
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
        if (result_fire_w) begin
            pack_data_r <= result_data_i;
            pack_word_r <= word_r;
        end
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
        .rst_n_i(rst_n_i[2]),
        .desc_valid_i(pending_r && !dma_abort_o),
        .desc_ready_o(dma_ready_w),
        .desc_base_i(pending_base_r),
        .desc_stride_i({16'd0, pending_stride_r}),
        .desc_width_bytes_i({4'd0, pending_width_r, 1'b0}),
        .desc_height_i(pending_height_r),
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
            pending_width_r <= source_width_i;
            pending_height_r <= source_height_i;
        end
        if (descriptor_w)
            write_id_r <= pending_id_r;
        if (pack_valid_r)
            pack_r[pack_word_r * 32 +: 32] <= pack_data_r;
    end

    always @(posedge clk_i or negedge rst_n_i[1]) begin
        if (!rst_n_i[1]) begin
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
            word_r <= 3'd0;
            count_r <= 10'd0;
            done_info_o <= 6'd0;
            done_frame_id_o <= 32'd0;
        end else begin
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
                word_r <= 3'd0;
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
                word_r <= flush_w ? 3'd0 : word_r + 3'd1;
                if (result_eof_i)
                    receiving_r <= 1'b0;
                if (result_eof_i && write_meta_r && !source_eof_i)
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
                word_r <= 3'd0;
            end
            case ({pack_accept_w, fifo_pop_w && fifo_valid_w})
                2'b10: count_r <= count_r + 10'd1;
                2'b01: count_r <= count_r - 10'd1;
                default: count_r <= count_r;
            endcase
        end
    end
endmodule
