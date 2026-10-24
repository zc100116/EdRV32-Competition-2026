// ============================================================================
// File        : sram_storage.v
// Author      : Edward ZC
// Description : Generic synchronous 64-bit SRAM storage backend.
// Notes       : Board builds select a dedicated Pango IP backend.
// ============================================================================
module sram_storage #(
    parameter ADDR_W = 15,
    parameter DEPTH  = 32768,
    parameter INIT_FILE = ""
)(
    input  wire                 clk,
    input  wire [ADDR_W-1:0]    rd_addr_i,
    output wire [63:0]          rd_data_o,
    input  wire [ADDR_W-1:0]    wr_addr_i,
    input  wire [63:0]          wr_data_i,
    input  wire [7:0]           wr_strb_i,
    input  wire                 wr_en_i
);
    reg [63:0] mem [0:DEPTH-1];
    reg [63:0] rd_data_r;
    integer byte_i;

    assign rd_data_o = rd_data_r;

    always @(posedge clk)
        rd_data_r <= mem[rd_addr_i];

    always @(posedge clk) begin
        if (wr_en_i) begin
            for (byte_i = 0; byte_i < 8; byte_i = byte_i + 1) begin
                if (wr_strb_i[byte_i])
                    mem[wr_addr_i][byte_i*8 +: 8] <= wr_data_i[byte_i*8 +: 8];
            end
        end
    end

    // synthesis translate_off
    reg [1023:0] memfile_r;
    reg [31:0] mem_init_r [0:DEPTH*2-1];
    integer init_i;
    initial begin
        rd_data_r = 64'h0;
        for (init_i = 0; init_i < DEPTH; init_i = init_i + 1)
            mem[init_i] = 64'h0;
        for (init_i = 0; init_i < DEPTH*2; init_i = init_i + 1)
            mem_init_r[init_i] = 32'h0;
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem_init_r);
            for (init_i = 0; init_i < DEPTH; init_i = init_i + 1)
                mem[init_i] = {mem_init_r[init_i*2+1],
                               mem_init_r[init_i*2]};
        end
        if ($value$plusargs("SRAMFILE=%s", memfile_r)) begin
            $readmemh(memfile_r, mem_init_r);
            for (init_i = 0; init_i < DEPTH; init_i = init_i + 1)
                mem[init_i] = {mem_init_r[init_i*2+1],
                               mem_init_r[init_i*2]};
        end
    end
    // synthesis translate_on
endmodule
