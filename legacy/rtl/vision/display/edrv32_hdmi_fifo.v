// ============================================================================
// File        : edrv32_hdmi_fifo.v
// Description : 256-bit asynchronous HDMI FIFO with normalized read semantics.
// Notes       : The Pango FIFO has a synchronous read port. A two-word local
//               queue performs the initial read and one-word look-ahead so the
//               external interface remains a conventional valid/ready stream.
//               Simulation models the same one-cycle raw read latency.
// ============================================================================

`include "edrv32_build_mode.vh"

module edrv32_hdmi_fifo #(
    parameter integer ADDR_W = 9,
    parameter integer ALMOST_EMPTY_WORDS = 64
) (
    input  wire         wr_clk_i,
    input  wire         wr_rst_n_i,
    input  wire [255:0] wr_data_i,
    input  wire         wr_valid_i,
    output wire         wr_ready_o,

    input  wire         rd_clk_i,
    input  wire         rd_rst_n_i,
    output wire [255:0] rd_data_o,
    output wire         rd_valid_o,
    input  wire         rd_ready_i,
    output wire         almost_empty_o,
    output wire [1:0]   local_count_o
);

    wire [255:0] raw_rd_data_w;
    wire raw_empty_w;
    wire raw_almost_empty_w;
    wire raw_read_w;

`ifdef EDRV32_BUILD_MODE_CONFLICT
    edrv32_build_mode_error__define_only_one_of_FPGA_MODE_or_SIM_MODE
        u_build_mode_error ();
`elsif EDRV32_FPGA_MEMORY_MODE
    wire fifo_full_w;
    wire fifo_empty_w;
    wire fifo_almost_empty_w;
    wire unused_almost_full_w;
    wire [9:0] unused_wr_level_w;
    wire [9:0] unused_rd_level_w;

    hdmi_fifo u_hdmi_fifo (
        .wr_clk         (wr_clk_i),
        .wr_rst         (~wr_rst_n_i),
        .wr_en          (wr_valid_i && !fifo_full_w),
        .wr_data        (wr_data_i),
        .wr_full        (fifo_full_w),
        .wr_water_level (unused_wr_level_w),
        .rd_clk         (rd_clk_i),
        .rd_rst         (~rd_rst_n_i),
        .rd_en          (raw_read_w && !fifo_empty_w),
        .rd_data        (raw_rd_data_w),
        .almost_full    (unused_almost_full_w),
        .rd_empty       (fifo_empty_w),
        .rd_water_level (unused_rd_level_w),
        .almost_empty   (fifo_almost_empty_w)
    );

    assign wr_ready_o = !fifo_full_w;
    assign raw_empty_w = fifo_empty_w;
    assign raw_almost_empty_w = fifo_almost_empty_w;

    generate
        if (ADDR_W != 9 || ALMOST_EMPTY_WORDS != 64) begin : gen_bad_ip_geometry
            edrv32_hdmi_fifo_ip_must_be_512x256_threshold_64
                u_static_assert ();
        end
    endgenerate
`else
    reg [255:0] sim_raw_data_r;
    wire sim_rd_valid_w;
    wire [255:0] sim_rd_data_w;

    edrv32_async_fifo #(
        .DATA_W (256),
        .ADDR_W (ADDR_W)
    ) u_sim_fifo (
        .wr_clk_i   (wr_clk_i),
        .wr_rst_n_i (wr_rst_n_i),
        .wr_data_i  (wr_data_i),
        .wr_valid_i (wr_valid_i),
        .wr_ready_o (wr_ready_o),
        .rd_clk_i   (rd_clk_i),
        .rd_rst_n_i (rd_rst_n_i),
        .rd_data_o  (sim_rd_data_w),
        .rd_valid_o (sim_rd_valid_w),
        .rd_ready_i (raw_read_w)
    );

    always @(posedge rd_clk_i or negedge rd_rst_n_i) begin
        if (!rd_rst_n_i)
            sim_raw_data_r <= 256'b0;
        else if (raw_read_w && sim_rd_valid_w)
            sim_raw_data_r <= sim_rd_data_w;
    end

    assign raw_rd_data_w = sim_raw_data_r;
    assign raw_empty_w = !sim_rd_valid_w;
    // The common FIFO intentionally exposes no occupancy count. Empty is a
    // conservative simulation substitute for the generated IP low watermark.
    assign raw_almost_empty_w = !sim_rd_valid_w;
    wire unused_almost_empty_words_w = ALMOST_EMPTY_WORDS != 0;
`endif

    reg [255:0] buffer0_r;
    reg [255:0] buffer1_r;
    reg [1:0] buffer_count_r;
    reg raw_pending_r;

    wire consume_w = rd_ready_i && (buffer_count_r != 0);
    wire [2:0] buffered_after_w =
        {1'b0, buffer_count_r} - consume_w + raw_pending_r;

    // raw_pending_r reserves a local slot for the synchronous read result
    // arriving on this edge. A new raw read may be launched back-to-back when
    // the post-consume/post-return occupancy still leaves a free slot.
    assign raw_read_w = rd_rst_n_i && !raw_empty_w &&
        (buffered_after_w < 3'd2);
    assign rd_data_o = buffer0_r;
    assign rd_valid_o = buffer_count_r != 0;
    assign almost_empty_o = raw_almost_empty_w ||
        (buffer_count_r <= 1);
    assign local_count_o = buffer_count_r;

    always @(posedge rd_clk_i or negedge rd_rst_n_i) begin
        if (!rd_rst_n_i) begin
            buffer0_r <= 256'b0;
            buffer1_r <= 256'b0;
            buffer_count_r <= 2'b0;
            raw_pending_r <= 1'b0;
        end else begin
            raw_pending_r <= raw_read_w;
            case ({consume_w, raw_pending_r})
                2'b01: begin
                    if (buffer_count_r == 0)
                        buffer0_r <= raw_rd_data_w;
                    else
                        buffer1_r <= raw_rd_data_w;
                    buffer_count_r <= buffer_count_r + 1'b1;
                end
                2'b10: begin
                    if (buffer_count_r == 2)
                        buffer0_r <= buffer1_r;
                    buffer_count_r <= buffer_count_r - 1'b1;
                end
                2'b11: begin
                    if (buffer_count_r == 1) begin
                        buffer0_r <= raw_rd_data_w;
                    end else begin
                        buffer0_r <= buffer1_r;
                        buffer1_r <= raw_rd_data_w;
                    end
                end
                default: begin
                end
            endcase
        end
    end

endmodule
