// File: edrv32_ram_cpu_chooser.v
// Spec: cpu-spec 4.4; CLAUDE.md 8.
// Description: Tournament table with synchronous writes and asynchronous query/update reads.
// Replicated read copies share writes; table contents survive reset.
// Clock domain: clk_sys.
`include "edrv32_build_mode.vh"
module edrv32_ram_cpu_chooser (
    // Clock and write port, without reset.
    input wire clk_i,
    input wire wr_en_i,
    input wire [11:0] wr_addr_i,
    input wire [1:0] wr_data_i,
    output wire [1:0] update_data_o,
    // Independent asynchronous query ports.
    input wire [11:0] rd0_addr_i,
    output wire [1:0] rd0_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    wire [7:0] copy0_data_w;
    wire [7:0] copy1_data_w;
    genvar bank;
    generate
        for (bank = 0; bank < 4; bank = bank + 1) begin : g_bank
            ip_lutram_cpu_tournament u_copy0 (
                .wr_clk(clk_i),
                .rd_clk(clk_i),
                .rst(1'b0),
                .wr_en(wr_en_i && wr_addr_i[11:10] == bank[1:0]),
                .wr_addr(wr_addr_i[9:0]),
                .wr_data(wr_data_i),
                .rd_addr(rd0_addr_i[9:0]),
                .rd_data(copy0_data_w[bank*2 +: 2])
            );
            ip_lutram_cpu_tournament u_copy1 (
                .wr_clk(clk_i),
                .rd_clk(clk_i),
                .rst(1'b0),
                .wr_en(wr_en_i && wr_addr_i[11:10] == bank[1:0]),
                .wr_addr(wr_addr_i[9:0]),
                .wr_data(wr_data_i),
                .rd_addr(wr_addr_i[9:0]),
                .rd_data(copy1_data_w[bank*2 +: 2])
            );
        end
    endgenerate
    assign rd0_data_o = copy0_data_w[rd0_addr_i[11:10]*2 +: 2];
    assign update_data_o = copy1_data_w[wr_addr_i[11:10]*2 +: 2];
`else
    reg [1:0] memory_r [0:4095];
    integer entry;
    initial begin
        for (entry = 0; entry < 4096; entry = entry + 1)
            memory_r[entry] = 2'd1;
    end
    assign update_data_o = memory_r[wr_addr_i];
    assign rd0_data_o = memory_r[rd0_addr_i];
    always @(posedge clk_i) begin
        if (wr_en_i)
            memory_r[wr_addr_i] <= wr_data_i;
    end
`endif
endmodule
