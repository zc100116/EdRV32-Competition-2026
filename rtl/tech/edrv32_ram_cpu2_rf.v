// File: edrv32_ram_cpu2_rf.v
// Spec: cpu-v2-spec 5.2, 5.4, 5.5, 7.
// Description: Fixed 1R1W memory; asynchronous read.
// Clock domain: clk_sys.
`include "edrv32_build_mode.vh"
module edrv32_ram_cpu2_rf (
    // Clock and write port.
    input wire clk_i,
    input wire wr_en_i,
    input wire [4:0] wr_addr_i,
    input wire [31:0] wr_data_i,
    // Read port.
    input wire [4:0] rd_addr_i,
    output wire [31:0] rd_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_lutram_cpu2_rf u_ip (
        .wr_clk(clk_i),
        .wr_en(wr_en_i),
        .wr_addr(wr_addr_i),
        .wr_data(wr_data_i),
        .rd_clk(clk_i),
        .rst(1'b0),
        .rd_addr(rd_addr_i),
        .rd_data(rd_data_o)
    );
`else
    reg [31:0] memory_r [0:31];
    assign rd_data_o = memory_r[rd_addr_i];
    always @(posedge clk_i) begin
        if (wr_en_i)
            memory_r[wr_addr_i] <= wr_data_i;
    end
`endif
endmodule
