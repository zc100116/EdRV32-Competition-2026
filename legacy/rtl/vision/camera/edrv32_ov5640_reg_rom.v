// ============================================================================
// File        : edrv32_ov5640_reg_rom.v
// Description : 512x24 OV5640 register-program ROM backend selector.
// Notes       : FPGA_MODE instantiates generated Pango IP "cam_rom". The IP
//               and simulation model use ov5640_720p.hex as their image.
// ============================================================================

`include "edrv32_build_mode.vh"

module edrv32_ov5640_reg_rom #(
    parameter INIT_FILE = "rtl/vision/camera/ov5640_720p.hex"
) (
    input  wire        clk_i,
    input  wire        rst_n_i,
    input  wire [7:0]  addr_i,
    output wire [23:0] data_o
);

`ifdef EDRV32_BUILD_MODE_CONFLICT
    edrv32_build_mode_error__define_only_one_of_FPGA_MODE_or_SIM_MODE
        u_build_mode_error ();
`elsif EDRV32_FPGA_MEMORY_MODE
    cam_rom u_cam_rom (
        .addr    ({1'b0, addr_i}),
        .clk     (clk_i),
        .rst     (~rst_n_i),
        .rd_data (data_o)
    );
`else
    reg [23:0] mem_r [0:511];
    reg [23:0] data_r;
    integer init_i;

    initial begin
        for (init_i = 0; init_i < 512; init_i = init_i + 1)
            mem_r[init_i] = 24'b0;
        $readmemh(INIT_FILE, mem_r);
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            data_r <= 24'b0;
        else
            data_r <= mem_r[addr_i];
    end

    assign data_o = data_r;
`endif

endmodule
