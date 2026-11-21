// File: edrv32_ram_npu_quant.v
// Spec: npu-spec 5.2; docs/design/2026-10-27-npu-datapath.md 4.5, 4.9; CLAUDE.md 8.
// Description: Fixed 32x64 distributed RAM simple dual-port storage.
// Enabled reads have two-cycle latency; local read-enable copies gate the second register.
// The wrapper samples the combinational read before the write edge updates memory,
// so same-address reads return old data. Contents and output data are not initialized or reset.
// Clock: clk_npu.
`include "edrv32_build_mode.vh"
module edrv32_ram_npu_quant (
    // Clock.
    input wire clk_i,

    // Write port.
    input wire wr_en_i,
    input wire [4:0] wr_addr_i,
    input wire [63:0] wr_data_i,

    // Read port.
    input wire rd_en_i,
    input wire [4:0] rd_addr_i,
    output wire [63:0] rd_data_o
);
    wire [63:0] memory_data_w;
    reg [63:0] rd_array_r;
    reg [63:0] rd_data_r;
    assign rd_data_o = rd_data_r;

`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_lutram_npu_quant u_ip (
        // Synchronous write port.
        .wr_clk(clk_i),
        .rd_clk(clk_i),
        .rst(1'b0),
        .wr_en(wr_en_i),
        .wr_addr(wr_addr_i),
        .wr_data(wr_data_i),

        // Unregistered combinational read port.
        .rd_addr(rd_addr_i),
        .rd_data(memory_data_w)
    );
`else
    reg [63:0] memory_r [0:31];
    assign memory_data_w = memory_r[rd_addr_i];
    always @(posedge clk_i) begin
        if (wr_en_i) begin
            memory_r[wr_addr_i] <= wr_data_i;
        end
    end
`endif
    // Capture pre-write data unconditionally; move the holding CE to edge two.
    // The common logic below is identical for vendor IP and behavioural storage.
    always @(posedge clk_i) begin
        rd_array_r <= memory_data_w;
    end
    genvar slice;
    generate
        for (slice = 0; slice < 2; slice = slice + 1) begin : g_read_slice
            (* keep = "true", syn_preserve = 1 *) reg rd_en_r;
            always @(posedge clk_i) begin
                rd_en_r <= rd_en_i;
            end
            always @(posedge clk_i) begin
                if (rd_en_r) begin
                    rd_data_r[32*slice +: 32] <= rd_array_r[32*slice +: 32];
                end
            end
        end
    endgenerate
endmodule
