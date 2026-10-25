// ============================================================================
// File        : edrv32_camera_fifo.v
// Description : Backend selector for the 258-bit DVP-to-DDR asynchronous FIFO.
// Notes       : FPGA_MODE uses generated Pango IP "cam_fifo". SIM_MODE uses
//               the common asynchronous FIFO model.
// ============================================================================

`include "edrv32_build_mode.vh"

module edrv32_camera_fifo #(
    parameter integer ADDR_W = 10
) (
    input  wire         wr_clk_i,
    input  wire         wr_rst_n_i,
    input  wire [257:0] wr_data_i,
    input  wire         wr_valid_i,
    output wire         wr_ready_o,
    output wire         almost_full_o,

    input  wire         rd_clk_i,
    input  wire         rd_rst_n_i,
    output wire [257:0] rd_data_o,
    output wire         rd_valid_o,
    input  wire         rd_ready_i
);

`ifdef EDRV32_BUILD_MODE_CONFLICT
    edrv32_build_mode_error__define_only_one_of_FPGA_MODE_or_SIM_MODE
        u_build_mode_error ();
`elsif EDRV32_FPGA_MEMORY_MODE
    wire fifo_full_w;
    wire fifo_empty_w;
    wire unused_almost_empty_w;

    cam_fifo u_cam_fifo (
        .wr_clk       (wr_clk_i),
        .wr_rst       (~wr_rst_n_i),
        .wr_en        (wr_valid_i && !fifo_full_w),
        .wr_data      (wr_data_i),
        .wr_full      (fifo_full_w),
        .almost_full  (almost_full_o),
        .rd_clk       (rd_clk_i),
        .rd_rst       (~rd_rst_n_i),
        .rd_en        (rd_ready_i && !fifo_empty_w),
        .rd_data      (rd_data_o),
        .rd_empty     (fifo_empty_w),
        .almost_empty (unused_almost_empty_w)
    );

    assign wr_ready_o = !fifo_full_w;
    assign rd_valid_o = !fifo_empty_w;

    generate
        if (ADDR_W != 10) begin : gen_bad_ip_geometry
            edrv32_camera_fifo_ip_must_be_1024x258
                u_static_assert ();
        end
    endgenerate
`else
    wire sim_ready_w;

    edrv32_async_fifo #(
        .DATA_W (258),
        .ADDR_W (ADDR_W)
    ) u_sim_fifo (
        .wr_clk_i   (wr_clk_i),
        .wr_rst_n_i (wr_rst_n_i),
        .wr_data_i  (wr_data_i),
        .wr_valid_i (wr_valid_i),
        .wr_ready_o (sim_ready_w),
        .rd_clk_i   (rd_clk_i),
        .rd_rst_n_i (rd_rst_n_i),
        .rd_data_o  (rd_data_o),
        .rd_valid_o (rd_valid_o),
        .rd_ready_i (rd_ready_i)
    );

    assign wr_ready_o = sim_ready_w;
    assign almost_full_o = !sim_ready_w;
`endif

endmodule
