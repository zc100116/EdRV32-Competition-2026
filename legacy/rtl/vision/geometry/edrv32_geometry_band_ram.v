// ============================================================================
// File        : edrv32_geometry_band_ram.v
// Description : 2048x256 target-band store for raster reordering.
// Notes       : FPGA_MODE uses generated simple dual-port RAM
//               "geometry_band_ram".  A 1280x16 RGB565 band occupies 1280
//               words, leaving capacity for aligned partial-width modes.
// ============================================================================

`include "edrv32_build_mode.vh"

module edrv32_geometry_band_ram (
    input  wire          clk_i,
    input  wire          rst_n_i,
    input  wire          wr_en_i,
    input  wire [10:0]   wr_addr_i,
    input  wire [255:0]  wr_data_i,
    input  wire          rd_en_i,
    input  wire [10:0]   rd_addr_i,
    output wire [255:0]  rd_data_o
);

`ifdef EDRV32_BUILD_MODE_CONFLICT
    edrv32_build_mode_error__define_only_one_of_FPGA_MODE_or_SIM_MODE
        u_build_mode_error ();
`elsif EDRV32_FPGA_MEMORY_MODE
    geometry_band_ram u_band_ram (
        .wr_data    (wr_data_i),
        .wr_addr    (wr_addr_i),
        .wr_en      (wr_en_i),
        .wr_clk     (clk_i),
        .wr_rst     (~rst_n_i),
        .wr_byte_en (32'hffff_ffff),
        .rd_data    (rd_data_o),
        .rd_addr    (rd_addr_i),
        .rd_clk     (clk_i),
        .rd_rst     (~rst_n_i),
        .rd_clk_en  (rd_en_i)
    );
`else
    reg [255:0] memory_r [0:2047];
    reg [255:0] rd_data_r;

    assign rd_data_o = rd_data_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            rd_data_r <= 256'b0;
        end else begin
            if (wr_en_i)
                memory_r[wr_addr_i] <= wr_data_i;
            if (rd_en_i)
                rd_data_r <= memory_r[rd_addr_i];
        end
    end
`endif

endmodule
