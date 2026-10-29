// File: edrv32_ram_rnd_line.v
// Spec: rnd-spec 5.2, 7; CLAUDE.md 8.
// Description: Fixed DRM simple dual-port RAM for one RND line-buffer bank:
// 512 x 256 with 32 byte write enables (one per 8 data bits). Enabled reads
// have one-cycle latency; disabled reads hold. RND never reads and writes the
// same address in one cycle, so collision data is undefined.
// Clock: clk_mem.
`include "edrv32_build_mode.vh"
module edrv32_ram_rnd_line (
    // Clock.
    input wire clk_i,

    // Write port.
    input wire wr_en_i,
    input wire [8:0] wr_addr_i,
    input wire [255:0] wr_data_i,
    input wire [31:0] wr_strb_i,

    // Read port.
    input wire rd_en_i,
    input wire [8:0] rd_addr_i,
    output wire [255:0] rd_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_ram_rnd_line u_ip (
        .wr_clk(clk_i),
        .wr_en(wr_en_i),
        .wr_addr(wr_addr_i),
        .wr_data(wr_data_i),
        .wr_byte_en(wr_strb_i),
        // Generated IP resets are active-high; storage stays unreset.
        .wr_rst(1'b0),
        .rd_clk(clk_i),
        .rd_clk_en(rd_en_i),
        .rd_rst(1'b0),
        .rd_addr(rd_addr_i),
        .rd_data(rd_data_o)
    );
`else
    reg [255:0] memory_r [0:511];
    reg [255:0] rd_data_r;
    integer byte_idx_r;
    assign rd_data_o = rd_data_r;
    always @(posedge clk_i) begin
        if (wr_en_i) begin
            for (byte_idx_r = 0; byte_idx_r < 32; byte_idx_r = byte_idx_r + 1) begin
                if (wr_strb_i[byte_idx_r]) begin
                    memory_r[wr_addr_i][byte_idx_r*8 +: 8] <=
                        wr_data_i[byte_idx_r*8 +: 8];
                end
            end
        end
        if (rd_en_i) begin
            rd_data_r <= memory_r[rd_addr_i];
        end
    end
`endif
endmodule
