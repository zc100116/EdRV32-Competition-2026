// File: edrv32_vin_msrc.v
// Spec: vin 2.3, 2.5, 5.3, 6.
// Description: Reserve a complete row before issuing its single-row DMA descriptor.
//              A two-line-or-larger buffer decouples unthrottled R from pixel backpressure.
// Clock domain: clk_mem.
module edrv32_vin_msrc (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Pixel output.
    output wire valid_o,
    input wire ready_i,
    output wire [31:0] data_o,
    output wire sof_o,
    output wire eol_o,
    output wire eof_o,
    output wire [31:0] frame_id_o,
    output wire [10:0] width_o,
    output wire [11:0] height_o,

    // P1 read master.
    output wire p1_arid_o,
    output wire [31:0] p1_araddr_o,
    output wire [3:0] p1_arlen_o,
    output wire p1_arvalid_o,
    input wire p1_arready_i,
    input wire p1_rid_i,
    input wire [255:0] p1_rdata_i,
    input wire [1:0] p1_rresp_i,
    input wire p1_rlast_i,
    input wire p1_rvalid_i,
    output wire p1_rready_o,

    // Software configuration.
    input wire start_i,
    input wire abort_i,
    input wire [31:0] base_i,
    input wire [15:0] stride_i,
    input wire [10:0] width_i,
    input wire [11:0] height_i,

    // Status and events.
    output wire busy_o,
    output reg done_o,
    output wire error_o,
    output reg cfg_error_o,
    output wire frame_o
);
    reg busy_r;
    reg stopping_r;
    reg output_done_r;
    reg read_done_r;
    reg [10:0] width_r;
    reg [11:0] height_r;
    reg [15:0] stride_r;
    reg [31:0] row_addr_r;
    reg [11:0] rows_left_r;
    reg [9:0] x_r;
    reg [11:0] y_r;
    reg [2:0] word_r;
    reg [8:0] count_r;
    reg [31:0] frame_count_r;
    reg [31:0] frame_id_r;
    wire desc_valid_w;
    wire desc_ready_w;
    wire dma_valid_w;
    wire [255:0] dma_data_w;
    wire dma_idle_w;
    wire dma_done_w;
    wire dma_error_w;
    wire fifo_ready_w;
    wire fifo_valid_w;
    wire fifo_pop_w;
    wire [255:0] fifo_data_w;
    wire [7:0] row_beats_w;
    wire transfer_w;
    wire launch_w;
    wire unused_w;
    wire unused_sol_w;
    wire unused_eol_w;
    wire unused_eof_w;

    assign row_beats_w = {1'b0, width_r[10:4]} + {7'd0, (|width_r[3:0])};
    assign desc_valid_w = busy_r && !stopping_r && !abort_i && rows_left_r != 0 &&
        (9'd256 - count_r >= {1'b0, row_beats_w});
    assign launch_w = start_i && !busy_r && !abort_i &&
        width_i != 0 && width_i <= 11'd1280 && height_i != 0;
    assign busy_o = busy_r;
    assign error_o = dma_error_w && !stopping_r;
    assign valid_o = busy_r && !stopping_r && !abort_i && !output_done_r && fifo_valid_w;
    assign data_o = fifo_data_w[word_r * 32 +: 32];
    assign sof_o = x_r == 0 && y_r == 0;
    assign eol_o = x_r == width_r[10:1] - 10'd1;
    assign eof_o = eol_o && y_r == height_r - 12'd1;
    assign frame_id_o = frame_id_r;
    assign width_o = width_r;
    assign height_o = height_r;
    assign transfer_w = valid_o && ready_i;
    assign frame_o = transfer_w && sof_o;
    assign fifo_pop_w = stopping_r || (transfer_w && (word_r == 3'd7 || eol_o));
    assign unused_w = fifo_ready_w;

    edrv32_sync_fifo #(
        .WIDTH(256),
        .DEPTH(256)
    ) u_buffer (
        // Reserved rows fit regardless of downstream pauses.
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .valid_i(dma_valid_w),
        .ready_o(fifo_ready_w),
        .data_i(dma_data_w),
        .valid_o(fifo_valid_w),
        .ready_i(fifo_pop_w),
        .data_o(fifo_data_w)
    );

    edrv32_dma2d_rd #(
        .OUTSTANDING(2)
    ) u_read (
        // DMA and descriptor.
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .desc_valid_i(desc_valid_w),
        .desc_ready_o(desc_ready_w),
        .desc_base_i(row_addr_r),
        .desc_stride_i({16'd0, stride_r}),
        .desc_width_bytes_i({4'd0, width_r, 1'b0}),
        .desc_height_i(12'd1),
        .data_valid_o(dma_valid_w),
        .data_ready_i(1'b1),
        .data_o(dma_data_w),
        .data_sol_o(unused_sol_w),
        .data_eol_o(unused_eol_w),
        .data_eof_o(unused_eof_w),
        // Read master.
        .axi_arid_o(p1_arid_o),
        .axi_araddr_o(p1_araddr_o),
        .axi_arlen_o(p1_arlen_o),
        .axi_arvalid_o(p1_arvalid_o),
        .axi_arready_i(p1_arready_i),
        .axi_rid_i(p1_rid_i),
        .axi_rdata_i(p1_rdata_i),
        .axi_rresp_i(p1_rresp_i),
        .axi_rlast_i(p1_rlast_i),
        .axi_rvalid_i(p1_rvalid_i),
        .axi_rready_o(p1_rready_o),
        // Control and status.
        .abort_i(abort_i),
        .idle_o(dma_idle_w),
        .done_o(dma_done_w),
        .err_o(dma_error_w)
    );

    always @(posedge clk_i) begin
        if (launch_w) begin
            frame_id_r <= frame_count_r;
            width_r <= width_i;
            height_r <= height_i;
            stride_r <= stride_i;
            row_addr_r <= base_i;
        end else if (desc_valid_w && desc_ready_w) begin
            row_addr_r <= row_addr_r + {16'd0, stride_r};
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            busy_r <= 1'b0;
            stopping_r <= 1'b0;
            output_done_r <= 1'b0;
            read_done_r <= 1'b0;
            rows_left_r <= 12'd0;
            x_r <= 10'd0;
            y_r <= 12'd0;
            word_r <= 3'd0;
            count_r <= 9'd0;
            frame_count_r <= 32'd0;
            done_o <= 1'b0;
            cfg_error_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            cfg_error_o <= start_i && !busy_r &&
                (width_i == 0 || width_i > 11'd1280 || height_i == 0);
            if (launch_w) begin
                busy_r <= 1'b1;
                stopping_r <= 1'b0;
                output_done_r <= 1'b0;
                read_done_r <= 1'b0;
                rows_left_r <= height_i;
                x_r <= 10'd0;
                y_r <= 12'd0;
                word_r <= 3'd0;
            end
            if (desc_valid_w && desc_ready_w)
                rows_left_r <= rows_left_r - 12'd1;
            if (dma_done_w && rows_left_r == 0 && !stopping_r && !abort_i) begin
                read_done_r <= 1'b1;
                done_o <= 1'b1;
            end
            if (transfer_w) begin
                if (sof_o)
                    frame_count_r <= frame_count_r + 32'd1;
                if (eol_o) begin
                    x_r <= 10'd0;
                    y_r <= y_r + 12'd1;
                    word_r <= 3'd0;
                end else begin
                    x_r <= x_r + 10'd1;
                    word_r <= word_r + 3'd1;
                end
                if (eof_o)
                    output_done_r <= 1'b1;
            end
            if (busy_r && output_done_r && read_done_r)
                busy_r <= 1'b0;
            if (abort_i && busy_r)
                stopping_r <= 1'b1;
            if (stopping_r && dma_idle_w && !fifo_valid_w) begin
                busy_r <= 1'b0;
                stopping_r <= 1'b0;
            end
            case ({dma_valid_w, fifo_pop_w && fifo_valid_w})
                2'b10: count_r <= count_r + 9'd1;
                2'b01: count_r <= count_r - 9'd1;
                default: count_r <= count_r;
            endcase
        end
    end
endmodule
