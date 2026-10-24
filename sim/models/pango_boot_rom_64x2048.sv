// Pango 64-bit x 2048 ROM functional model for board-level simulation.
module pango_boot_rom_64x2048 (
    input  wire [10:0] addr,
    output reg  [63:0] rd_data,
    input  wire        clk,
    input  wire        rst
);
    reg [63:0] mem [0:2047];
    reg [4095:0] rom_file;
    integer init_i;

    initial begin
        rd_data = 64'h0;
        for (init_i = 0; init_i < 2048; init_i = init_i + 1)
            mem[init_i] = 64'h0;
        if ($value$plusargs("ROMHEX=%s", rom_file))
            $readmemh(rom_file, mem);
    end

    always @(posedge clk or posedge rst) begin
        if (rst)
            rd_data <= 64'h0;
        else
            rd_data <= mem[addr];
    end
endmodule
