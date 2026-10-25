// File: edrv32_ram_sram.v
// Spec: sys-subsys-spec 2.2, 5.
// Description: Fixed single-port synchronous memory; enabled reads have one-cycle latency.
//              Load +SRAM_HEX in simulation; storage and read data remain unreset.
// Clock domain: clk_sys.
`include "edrv32_build_mode.vh"
module edrv32_ram_sram (
    // Memory clock.
    input wire clk_i,

    // Single memory port.
    input wire en_i,
    input wire [7:0] wr_en_i,
    input wire [63:0] wr_data_i,
    input wire [14:0] addr_i,
    output wire [63:0] rd_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_ram_sram u_ip (
        .clk(clk_i),
        .en(en_i),
        .wr_en(wr_en_i),
        .wr_data(wr_data_i),
        .addr(addr_i),
        .rd_data(rd_data_o)
    );
`else
    reg [63:0] memory_r [0:32767];
    reg [63:0] rd_data_r;
    reg [4095:0] image_path_r;
    integer byte_idx;

    assign rd_data_o = rd_data_r;

    initial begin
        if ($value$plusargs("SRAM_HEX=%s", image_path_r)) begin
            $readmemh(image_path_r, memory_r);
        end
    end

    always @(posedge clk_i) begin
        if (en_i) begin
            for (byte_idx = 0; byte_idx < 8; byte_idx = byte_idx + 1) begin
                if (wr_en_i[byte_idx]) begin
                    memory_r[addr_i][byte_idx*8 +: 8] <= wr_data_i[byte_idx*8 +: 8];
                end
            end
            rd_data_r <= memory_r[addr_i];
        end
    end
`endif
endmodule
