// ============================================================================
// File        : boot_rom_storage.v
// Author      : Edward ZC
// Description : Generic 32-bit-image Boot ROM with a synchronous 64-bit port.
// Notes       : Simulation and non-Pango backend. Storage is not writable.
// ============================================================================
module boot_rom_storage #(
    parameter integer NUM_WORDS = 4096,
    parameter ROM_INIT_FILE = ""
)(
    // --- Clock and reset ---
    input  wire         clk,
    input  wire         rst_n,

    // --- Synchronous paired-word read port ---
    input  wire         rd_en_i,
    input  wire [$clog2((NUM_WORDS+1)/2)-1:0] rd_addr_i,
    output wire [63:0]  rd_data_o
);
    localparam integer PAIR_WORDS = (NUM_WORDS + 1) / 2;
    localparam integer PAIR_IDX_W = $clog2(PAIR_WORDS);

    reg [31:0] mem [0:NUM_WORDS-1];
    reg [63:0] rd_data_r;
    reg [1023:0] romfile;
    integer init_word_i;

    wire [PAIR_IDX_W:0] rd_lo_word_w = {rd_addr_i, 1'b0};
    wire [PAIR_IDX_W:0] rd_hi_word_w = rd_lo_word_w + 1'b1;
    wire [31:0] rd_hi_data_w = (rd_hi_word_w < NUM_WORDS)
        ? mem[rd_hi_word_w] : 32'h0000_0000;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rd_data_r <= 64'h0000_0000_0000_0000;
        else if (rd_en_i)
            rd_data_r <= {rd_hi_data_w, mem[rd_lo_word_w]};
    end

    assign rd_data_o = rd_data_r;

    initial begin
        for (init_word_i = 0; init_word_i < NUM_WORDS;
             init_word_i = init_word_i + 1)
            mem[init_word_i] = 32'h0000_0000;
        if (ROM_INIT_FILE != "")
            $readmemh(ROM_INIT_FILE, mem);
        // synthesis translate_off
        if ($value$plusargs("ROMFILE=%s", romfile))
            $readmemh(romfile, mem);
        // synthesis translate_on
    end
endmodule
