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
        .a_clk(clk_i),
        .a_rst(1'b0),
        .a_clk_en(a_en_i),
        .a_wr_en(a_write_i),
        .a_addr(a_addr_i),
        .a_wr_data(a_data_i),
        .a_rd_data(a_data_o),
        .b_clk(clk_i),
        .b_rst(1'b0),
        .b_clk_en(b_en_i),
        .b_wr_en(1'b0),
        .b_addr(b_addr_i),
        .b_wr_data(32'd0),
        .b_rd_data(b_data_o)
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
