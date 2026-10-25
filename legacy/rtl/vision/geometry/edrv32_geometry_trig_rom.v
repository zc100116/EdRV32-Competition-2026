// ============================================================================
// File        : edrv32_geometry_trig_rom.v
// Description : 512x36 sine/cosine ROM backend selector for Geometry.
// Notes       : Each word is {signed Q2.16 cosine, signed Q2.16 sine}.
//               FPGA_MODE instantiates generated Pango IP "trig_rom".
// ============================================================================

`include "edrv32_build_mode.vh"

module edrv32_geometry_trig_rom #(
    parameter INIT_FILE = "rtl/vision/geometry/trig_q2_16.hex"
) (
    input  wire         clk_i,
    input  wire         rst_n_i,
    input  wire [8:0]   addr_i,
    output wire [35:0]  data_o
);

`ifdef EDRV32_BUILD_MODE_CONFLICT
    edrv32_build_mode_error__define_only_one_of_FPGA_MODE_or_SIM_MODE
        u_build_mode_error ();
`elsif EDRV32_FPGA_MEMORY_MODE
    trig_rom u_trig_rom (
        .addr    (addr_i),
        .clk     (clk_i),
        .rst     (~rst_n_i),
        .rd_data (data_o)
    );
`else
    reg [35:0] memory_r [0:511];
    reg [35:0] data_r;
    integer init_i;

    initial begin
        for (init_i = 0; init_i < 512; init_i = init_i + 1)
            memory_r[init_i] = 36'b0;
        $readmemh(INIT_FILE, memory_r);
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            data_r <= 36'b0;
        else
            data_r <= memory_r[addr_i];
    end

    assign data_o = data_r;
`endif

endmodule
