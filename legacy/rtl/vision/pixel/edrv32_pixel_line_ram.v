// ============================================================================
// File        : edrv32_pixel_line_ram.v
// Description : FPGA-IP-backed RGB565 pair line store for spatial filters.
// Notes       : FPGA_MODE instantiates pixel_line_ram (1024x32 SDP RAM).
//               SIM_MODE provides the same synchronous one-cycle read model.
// ============================================================================

`include "edrv32_build_mode.vh"

module edrv32_pixel_line_ram #(
    parameter integer ADDR_W = 10
) (
    input  wire                 clk_i,
    input  wire                 rst_n_i,
    input  wire                 rd_en_i,
    input  wire [ADDR_W-1:0]    rd_addr_i,
    output wire [31:0]          rd_data_o,
    input  wire                 wr_en_i,
    input  wire [ADDR_W-1:0]    wr_addr_i,
    input  wire [31:0]          wr_data_i
);

`ifdef EDRV32_BUILD_MODE_CONFLICT
    edrv32_build_mode_error__define_only_one_of_FPGA_MODE_or_SIM_MODE
        u_build_mode_error ();
`elsif EDRV32_FPGA_MEMORY_MODE
    pixel_line_ram u_pixel_line_ram (
        .wr_data    (wr_data_i),
        .wr_addr    (wr_addr_i),
        .wr_en      (wr_en_i),
        .wr_clk     (clk_i),
        .wr_rst     (~rst_n_i),
        .wr_byte_en (4'hf),
        .rd_data    (rd_data_o),
        .rd_addr    (rd_addr_i),
        .rd_clk     (clk_i),
        .rd_rst     (~rst_n_i),
        .rd_clk_en  (rd_en_i)
    );

    generate
        if (ADDR_W != 10) begin : gen_bad_ip_geometry
            edrv32_pixel_line_ram_ip_must_be_1024x32
                u_static_assert ();
        end
    endgenerate
`else
    reg [31:0] memory_r [0:(1<<ADDR_W)-1];
    reg [31:0] rd_data_r;

    assign rd_data_o = rd_data_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            rd_data_r <= 32'b0;
        end else begin
            if (rd_en_i)
                rd_data_r <= memory_r[rd_addr_i];
            if (wr_en_i)
                memory_r[wr_addr_i] <= wr_data_i;
        end
    end
`endif

endmodule
