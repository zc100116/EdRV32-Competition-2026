// File: edrv32_ram_cpu_direction.v
// Spec: cpu-spec 4.4; CLAUDE.md 8.
// Description: Paired gshare counters, synchronous word write and asynchronous reads.
// Clock domain: clk_sys. Read data follows address and post-edge memory contents.
`include "edrv32_build_mode.vh"
module edrv32_ram_cpu_direction (
    // Clock and write port (no reset).
    input wire clk_i,
    input wire wr_en_i,
    input wire [10:0] wr_addr_i,
    input wire [3:0] wr_data_i,
    // Asynchronous read ports; update reads the write address.
    output wire [3:0] update_data_o,
    input wire [10:0] rd_addr_i,
    output wire [3:0] rd_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    // fpga/ip/ip_lutram_cpu_direction.md: the PDS distributed SDP RAM stops at 10 address
    // bits, so each 2048-word copy is two 1024x4 banks selected by address bit 10.
    // Two copies share every write; one reads the query address, the other the update
    // (write) address.
    wire [1:0] bank_wr_en_w;
    wire [7:0] query_bank_data_w;
    wire [7:0] update_bank_data_w;

    assign bank_wr_en_w = {wr_en_i & wr_addr_i[10], wr_en_i & ~wr_addr_i[10]};

    genvar bank;
    generate
        for (bank = 0; bank < 2; bank = bank + 1) begin : g_bank
            ip_lutram_cpu_direction u_ip_query (
                .wr_clk(clk_i),
                .rd_clk(clk_i),
                .rst(1'b0),
                .wr_en(bank_wr_en_w[bank]),
                .wr_addr(wr_addr_i[9:0]),
                .wr_data(wr_data_i),
                .rd_addr(rd_addr_i[9:0]),
                .rd_data(query_bank_data_w[4*bank +: 4])
            );
            ip_lutram_cpu_direction u_ip_update (
                .wr_clk(clk_i),
                .rd_clk(clk_i),
                .rst(1'b0),
                .wr_en(bank_wr_en_w[bank]),
                .wr_addr(wr_addr_i[9:0]),
                .wr_data(wr_data_i),
                .rd_addr(wr_addr_i[9:0]),
                .rd_data(update_bank_data_w[4*bank +: 4])
            );
        end
    endgenerate

    assign rd_data_o = rd_addr_i[10] ? query_bank_data_w[7:4] : query_bank_data_w[3:0];
    assign update_data_o = wr_addr_i[10] ? update_bank_data_w[7:4] : update_bank_data_w[3:0];
`else
    reg [3:0] memory_r [0:2047];
    integer entry;
    initial begin
        for (entry = 0; entry < 2048; entry = entry + 1)
            memory_r[entry] = 4'b0101;
    end
    assign update_data_o = memory_r[wr_addr_i];
    assign rd_data_o = memory_r[rd_addr_i];
    always @(posedge clk_i) begin
        if (wr_en_i)
            memory_r[wr_addr_i] <= wr_data_i;
    end
`endif
endmodule
