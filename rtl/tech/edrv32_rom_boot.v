// File: edrv32_rom_boot.v
// Spec: sys-subsys-spec 2.2, 5.
// Description: Fixed single-port synchronous memory; enabled reads have one-cycle latency.
//              Load +ROM_HEX in simulation; storage and read data remain unreset.
// Clock domain: clk_sys.
`include "edrv32_build_mode.vh"
module edrv32_rom_boot (
    // Memory clock.
    input wire clk_i,

    // Single memory port.
    input wire en_i,
    input wire [10:0] addr_i,
    output wire [63:0] rd_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_rom_boot u_ip (
        .clk(clk_i),
        .en(en_i),
        .addr(addr_i),
        .rd_data(rd_data_o)
    );
`else
    reg [63:0] memory_r [0:2047];
    reg [63:0] rd_data_r;
    reg [4095:0] image_path_r;

    assign rd_data_o = rd_data_r;

    initial begin
        if ($value$plusargs("ROM_HEX=%s", image_path_r)) begin
            $readmemh(image_path_r, memory_r);
        end
    end

    always @(posedge clk_i) begin
        if (en_i) begin
            rd_data_r <= memory_r[addr_i];
        end
    end
`endif
endmodule
