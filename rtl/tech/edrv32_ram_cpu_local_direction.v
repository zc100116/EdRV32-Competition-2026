// File: edrv32_ram_cpu_local_direction.v
// Spec: cpu-spec 4.4; CLAUDE.md 8.
// Description: Tournament table with synchronous writes and asynchronous query/update reads.
// Replicated read copies share writes; table contents survive reset.
// Clock domain: clk_sys.
`include "edrv32_build_mode.vh"
module edrv32_ram_cpu_local_direction (
    // Clock and write port, without reset.
    input wire clk_i,
    input wire wr_en_i,
    input wire [9:0] wr_addr_i,
    input wire [1:0] wr_data_i,
    output wire [1:0] update_data_o,
    // Independent asynchronous query ports.
    input wire [9:0] rd0_addr_i,
    output wire [1:0] rd0_data_o,
    input wire [9:0] rd1_addr_i,
    output wire [1:0] rd1_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    wire [1:0] copy0_data_w;
    wire [1:0] copy1_data_w;
    wire [1:0] copy2_data_w;
    genvar bank;
    generate
        for (bank = 0; bank < 1; bank = bank + 1) begin : g_bank
            ip_lutram_cpu_tournament u_copy0 (
                .wr_clk(clk_i),
                .rd_clk(clk_i),
                .rst(1'b0),
                .wr_en(wr_en_i),
                .wr_addr(wr_addr_i[9:0]),
                .wr_data(wr_data_i),
                .rd_addr(rd0_addr_i[9:0]),
                .rd_data(copy0_data_w[bank*2 +: 2])
            );
            ip_lutram_cpu_tournament u_copy1 (
                .wr_clk(clk_i),
                .rd_clk(clk_i),
                .rst(1'b0),
                .wr_en(wr_en_i),
                .wr_addr(wr_addr_i[9:0]),
                .wr_data(wr_data_i),
                .rd_addr(rd1_addr_i[9:0]),
                .rd_data(copy1_data_w[bank*2 +: 2])
            );
            ip_lutram_cpu_tournament u_copy2 (
                .wr_clk(clk_i),
                .rd_clk(clk_i),
                .rst(1'b0),
                .wr_en(wr_en_i),
                .wr_addr(wr_addr_i[9:0]),
                .wr_data(wr_data_i),
                .rd_addr(wr_addr_i[9:0]),
                .rd_data(copy2_data_w[bank*2 +: 2])
            );
        end
    endgenerate
    assign rd0_data_o = copy0_data_w;
    assign rd1_data_o = copy1_data_w;
    assign update_data_o = copy2_data_w;
`else
    reg [1:0] memory_r [0:1023];
    integer entry;
    initial begin
        for (entry = 0; entry < 1024; entry = entry + 1)
            memory_r[entry] = 2'd1;
    end
    assign update_data_o = memory_r[wr_addr_i];
    assign rd0_data_o = memory_r[rd0_addr_i];
    assign rd1_data_o = memory_r[rd1_addr_i];
    always @(posedge clk_i) begin
        if (wr_en_i)
            memory_r[wr_addr_i] <= wr_data_i;
    end
`endif
endmodule
