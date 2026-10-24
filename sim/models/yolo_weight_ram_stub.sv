`timescale 1ns/1ps

// Functional stand-in for the generated 512 x 256 synchronous-read RAM IP.
module yolo_weight_ram (
    input  wire [255:0] wr_data,
    input  wire [8:0]   wr_addr,
    input  wire         wr_en,
    input  wire         wr_clk,
    input  wire         wr_rst,
    input  wire [31:0]  wr_byte_en,
    output wire [255:0] rd_data,
    input  wire [8:0]   rd_addr,
    input  wire         rd_clk,
    input  wire         rd_rst,
    input  wire         rd_clk_en
);
    reg [255:0] mem_r [0:511];
    reg [255:0] read_r;
    integer byte_index;
    always @(posedge wr_clk) begin
        if (wr_en)
            for (byte_index = 0; byte_index < 32; byte_index = byte_index + 1)
                if (wr_byte_en[byte_index])
                    mem_r[wr_addr][byte_index*8 +: 8] <=
                        wr_data[byte_index*8 +: 8];
    end
    always @(posedge rd_clk) begin
        if (rd_clk_en)
            read_r <= mem_r[rd_addr];
    end
    assign rd_data = read_r;
endmodule
