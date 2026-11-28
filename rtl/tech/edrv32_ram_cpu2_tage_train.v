// File: edrv32_ram_cpu2_tage_train.v
// Spec: cpu-v2-spec 5.2, 5.4, 5.5, 7.
// Description: Fixed 1R1W memory; one-cycle old-data read.
// Clock domain: clk_sys.
`include "edrv32_build_mode.vh"
module edrv32_ram_cpu2_tage_train (
    // Clock and write port.
    input wire clk_i,
    input wire wr_en_i,
    input wire [8:0] wr_addr_i,
    input wire [15:0] wr_data_i,
    // Read port.
    input wire rd_en_i,
    input wire [8:0] rd_addr_i,
    output wire [15:0] rd_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_ram_cpu2_tage_train u_ip (
        .wr_clk(clk_i),
        .wr_en(wr_en_i),
        .wr_addr(wr_addr_i),
        .wr_data(wr_data_i),
        .rd_clk(clk_i),
        .wr_rst(1'b0),
        .rd_rst(1'b0),
        .rd_clk_en(rd_en_i),
        .rd_addr(rd_addr_i),
        .rd_data(rd_data_o)
    );
`else
    reg [15:0] memory_r [0:511];
    integer entry;
    initial begin
        for (entry = 0; entry < 512; entry = entry + 1)
            memory_r[entry] = 16'd0;
    end
    reg [15:0] rd_data_r;
    assign rd_data_o = rd_data_r;
    always @(posedge clk_i) begin
        if (wr_en_i)
            memory_r[wr_addr_i] <= wr_data_i;
        if (rd_en_i)
            rd_data_r <= memory_r[rd_addr_i];
    end
`endif
endmodule
