// Simulation-only functional model of the generated Pango 128x128 DRM.
module pango_cache_data_128x128 (
    input  wire [127:0] wr_data,
    input  wire [6:0]   wr_addr,
    input  wire         wr_en,
    input  wire         wr_clk,
    input  wire         wr_rst,
    input  wire [15:0]  wr_byte_en,
    output reg  [127:0] rd_data,
    input  wire [6:0]   rd_addr,
    input  wire         rd_clk,
    input  wire         rd_rst
);
    reg [127:0] memory [0:127];
    integer byte_index;

    always @(posedge wr_clk) begin
        if (!wr_rst && wr_en) begin
            for (byte_index = 0; byte_index < 16; byte_index = byte_index + 1) begin
                if (wr_byte_en[byte_index])
                    memory[wr_addr][byte_index*8 +: 8] <=
                        wr_data[byte_index*8 +: 8];
            end
        end
    end

    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst)
            rd_data <= 128'd0;
        else
            rd_data <= memory[rd_addr];
    end
endmodule
