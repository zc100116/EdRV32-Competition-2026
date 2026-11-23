// File: edrv32_ram_gpu_palette_segment.v
// Spec: gpu-spec 2.6; GPU microarchitecture 4.8; CLAUDE.md 8.
// Description: Fixed 1024x20 true dual-port DRM segment, synchronous read with
// output register (two cycles). Loading owns port A; sampling owns both ports.
// Clock: clk_gpu.
`include "edrv32_build_mode.vh"
module edrv32_ram_gpu_palette_segment (
    // Clock, load and two sampling ports.
    input wire clk_i,
    input wire wr_en_i,
    input wire [9:0] wr_addr_i,
    input wire [19:0] wr_data_i,
    input wire rd_a_en_i,
    input wire rd_b_en_i,
    input wire [9:0] rd_a_addr_i,
    input wire [9:0] rd_b_addr_i,
    output wire [19:0] rd_a_data_o,
    output wire [19:0] rd_b_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_ram_gpu_palette_segment u_ip (
        .clk_a(clk_i),
        .rst_a(1'b0),
        .clk_en_a(wr_en_i | rd_a_en_i),
        .wr_en_a(wr_en_i),
        .addr_a(wr_en_i ? wr_addr_i : rd_a_addr_i),
        .wr_data_a(wr_data_i),
        .rd_data_a(rd_a_data_o),
        .clk_b(clk_i),
        .rst_b(1'b0),
        .clk_en_b(rd_b_en_i),
        .wr_en_b(1'b0),
        .addr_b(rd_b_addr_i),
        .wr_data_b(20'b0),
        .rd_data_b(rd_b_data_o)
    );
`else
    reg [19:0] memory_r [0:1023];
    reg [19:0] rd_a_array_r;
    reg [19:0] rd_a_data_r;
    assign rd_a_data_o = rd_a_data_r;
    reg [19:0] rd_b_array_r;
    reg [19:0] rd_b_data_r;
    assign rd_b_data_o = rd_b_data_r;
    always @(posedge clk_i) begin
        if (wr_en_i) begin
            memory_r[wr_addr_i] <= wr_data_i;
        end
        if (rd_a_en_i) begin
            rd_a_array_r <= memory_r[rd_a_addr_i];
        end
        rd_a_data_r <= rd_a_array_r;
        if (rd_b_en_i) begin
            rd_b_array_r <= memory_r[rd_b_addr_i];
        end
        rd_b_data_r <= rd_b_array_r;
    end
`endif
endmodule
