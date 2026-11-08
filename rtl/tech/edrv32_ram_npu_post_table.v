// File: edrv32_ram_npu_post_table.v
// Spec: npu-spec 4.4, 5.2, 5.6; CLAUDE.md 8.
// Description: Fixed 1024x32 true dual port DRM for three heads of 256 entries.
// Both read ports have array and output registers. Load owns port A between descriptors.
// No contents or output reset; users forward read/write collisions outside this wrapper.
// Clock: clk_npu.
`include "edrv32_build_mode.vh"
module edrv32_ram_npu_post_table (
    // Clock.
    input wire clk_i,

    // Port A: loading or the first pixel/serial DFL lookup.
    input wire a_en_i,
    input wire a_write_i,
    input wire [9:0] a_addr_i,
    input wire [31:0] a_data_i,
    output wire [31:0] a_data_o,

    // Port B: second pixel lookup.
    input wire b_en_i,
    input wire [9:0] b_addr_i,
    output wire [31:0] b_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_ram_npu_post_table u_ip (
        .clk_a(clk_i),
        .rst_a(1'b0),
        .clk_en_a(a_en_i),
        .wr_en_a(a_write_i),
        .addr_a(a_addr_i),
        .wr_data_a(a_data_i),
        .rd_data_a(a_data_o),
        .clk_b(clk_i),
        .rst_b(1'b0),
        .clk_en_b(b_en_i),
        .wr_en_b(1'b0),
        .addr_b(b_addr_i),
        .wr_data_b(32'd0),
        .rd_data_b(b_data_o)
    );
`else
    reg [31:0] memory_r [0:1023];
    reg [31:0] a_array_r;
    reg [31:0] b_array_r;
    reg [31:0] a_data_r;
    reg [31:0] b_data_r;
    assign a_data_o = a_data_r;
    assign b_data_o = b_data_r;
    always @(posedge clk_i) begin
        if (a_en_i) begin
            if (a_write_i) memory_r[a_addr_i] <= a_data_i;
            a_array_r <= memory_r[a_addr_i];
        end
        if (b_en_i) b_array_r <= memory_r[b_addr_i];
        a_data_r <= a_array_r;
        b_data_r <= b_array_r;
    end
`endif
endmodule
