// Pango 64-bit x 1024 simple-dual-port SRAM functional model.
module pango_sram_64x1024 (
    input  wire [63:0] wr_data,
    input  wire [9:0]  wr_addr,
    input  wire        wr_en,
    input  wire        wr_clk,
    input  wire        wr_rst,
    input  wire [7:0]  wr_byte_en,
    output reg  [63:0] rd_data,
    input  wire [9:0]  rd_addr,
    input  wire        rd_clk,
    input  wire        rd_rst
);
    reg [63:0] mem [0:1023];
    integer byte_i;
    integer init_i;

    initial begin
        rd_data = 64'h0;
        for (init_i = 0; init_i < 1024; init_i = init_i + 1)
            mem[init_i] = 64'h0;
    end

    always @(posedge wr_clk) begin
        if (wr_en) begin
            for (byte_i = 0; byte_i < 8; byte_i = byte_i + 1) begin
                if (wr_byte_en[byte_i])
                    mem[wr_addr][byte_i*8 +: 8] <= wr_data[byte_i*8 +: 8];
            end
        end
    end

    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst)
            rd_data <= 64'h0;
        else
            rd_data <= mem[rd_addr];
    end

    wire unused_wr_rst_w = wr_rst;
endmodule
