// File: edrv32_ram_cpu2_completion.v
// Spec: cpu-v2-spec 5.1, 5.6; fpu-spec F05; interface freeze 2026-11-28 technology wrappers.
// Description: Fixed 8x32 1R1W memory; asynchronous read. One completion-queue bank copy
// (data low/high word or PC); F uses addresses 0..3, FD uses 0..7. Shares the RF LUTRAM IP.
// Clock domain: clk_sys.
`include "edrv32_build_mode.vh"
module edrv32_ram_cpu2_completion (
    // Clock and write port.
    input wire clk_i,
    input wire wr_en_i,
    input wire [2:0] wr_addr_i,
    input wire [31:0] wr_data_i,
    // Read port.
    input wire [2:0] rd_addr_i,
    output wire [31:0] rd_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_lutram_cpu2_rf u_ip (
        .wr_clk(clk_i),
        .wr_en(wr_en_i),
        .wr_addr({2'b00, wr_addr_i}),
        .wr_data(wr_data_i),
        .rd_clk(clk_i),
        .rst(1'b0),
        .rd_addr({2'b00, rd_addr_i}),
        .rd_data(rd_data_o)
    );
`else
    reg [31:0] memory_r [0:7];
    assign rd_data_o = memory_r[rd_addr_i];
    always @(posedge clk_i) begin
        if (wr_en_i)
            memory_r[wr_addr_i] <= wr_data_i;
    end
`endif
endmodule
