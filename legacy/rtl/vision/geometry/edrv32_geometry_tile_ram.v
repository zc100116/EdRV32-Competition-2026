// ============================================================================
// File        : edrv32_geometry_tile_ram.v
// Description : Replicated 64x256 physical RAM with two row read ports.
// Notes       : FPGA_MODE uses two copies of generated SDP RAM
//               "geometry_tile_ram".  The full six-bit address is exposed so
//               the same IP can hold either one 16-row tile or one 64-row
//               source-patch column.
// ============================================================================

`include "edrv32_build_mode.vh"

module edrv32_geometry_tile_ram (
    input  wire         clk_i,
    input  wire         rst_n_i,
    input  wire         wr_en_i,
    input  wire [5:0]   wr_addr_i,
    input  wire [255:0] wr_data_i,
    input  wire         rd_en_i,
    input  wire [5:0]   rd_addr0_i,
    output wire [255:0] rd_data0_o,
    input  wire [5:0]   rd_addr1_i,
    output wire [255:0] rd_data1_o
);

`ifdef EDRV32_BUILD_MODE_CONFLICT
    edrv32_build_mode_error__define_only_one_of_FPGA_MODE_or_SIM_MODE
        u_build_mode_error ();
`elsif EDRV32_FPGA_MEMORY_MODE
    geometry_tile_ram u_bank0 (
        .wr_data    (wr_data_i),
        .wr_addr    (wr_addr_i),
        .wr_en      (wr_en_i),
        .wr_clk     (clk_i),
        .wr_rst     (~rst_n_i),
        .wr_byte_en (32'hffff_ffff),
        .rd_data    (rd_data0_o),
        .rd_addr    (rd_addr0_i),
        .rd_clk     (clk_i),
        .rd_rst     (~rst_n_i),
        .rd_clk_en  (rd_en_i)
    );

    geometry_tile_ram u_bank1 (
        .wr_data    (wr_data_i),
        .wr_addr    (wr_addr_i),
        .wr_en      (wr_en_i),
        .wr_clk     (clk_i),
        .wr_rst     (~rst_n_i),
        .wr_byte_en (32'hffff_ffff),
        .rd_data    (rd_data1_o),
        .rd_addr    (rd_addr1_i),
        .rd_clk     (clk_i),
        .rd_rst     (~rst_n_i),
        .rd_clk_en  (rd_en_i)
    );
`else
    reg [255:0] memory_r [0:63];
    reg [255:0] rd_data0_r;
    reg [255:0] rd_data1_r;

    assign rd_data0_o = rd_data0_r;
    assign rd_data1_o = rd_data1_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            rd_data0_r <= 256'b0;
            rd_data1_r <= 256'b0;
        end else begin
            if (wr_en_i)
                memory_r[wr_addr_i] <= wr_data_i;
            if (rd_en_i) begin
                rd_data0_r <= memory_r[rd_addr0_i];
                rd_data1_r <= memory_r[rd_addr1_i];
            end
        end
    end
`endif

endmodule
