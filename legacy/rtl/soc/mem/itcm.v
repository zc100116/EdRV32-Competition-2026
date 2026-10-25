// ============================================================================
// File        : itcm.v
// Description : 64-KiB CPU-private instruction TCM storage.
// Notes       : FPGA builds use an image-initialized Pango RAM IP. Simulation
//               uses a synchronous RTL model with the same one-cycle read.
// ============================================================================
`include "edrv32_build_mode.vh"

module itcm #(
    parameter [31:0] SIZE_BYTES = 32'd65536,
    parameter        INIT_FILE  = ""
) (
    input  wire        clk_i,
    input  wire        read_en_i,
    input  wire [31:0] local_addr_i,
    output wire [31:0] local_rdata_o
);

`ifdef EDRV32_BUILD_MODE_CONFLICT
    edrv32_build_mode_error__define_only_one_of_FPGA_MODE_or_SIM_MODE
        u_build_mode_error ();
`elsif EDRV32_FPGA_MEMORY_MODE
    pango_itcm_storage u_pango_itcm_storage (
        .clk_i     (clk_i),
        .rst_i     (1'b0),
        .rd_en_i   (read_en_i),
        .rd_addr_i (local_addr_i[15:2]),
        .rd_data_o (local_rdata_o)
    );
`else
    localparam integer WORDS = SIZE_BYTES >> 2;
    localparam integer IDX_W = $clog2(WORDS);

    reg [31:0] itcm_mem [0:WORDS-1];
    reg [31:0] local_rdata_r;
    reg [1023:0] itcm_file_r;
    integer init_word_i;

    wire [IDX_W-1:0] local_idx_w = local_addr_i[IDX_W+1:2];

    assign local_rdata_o = local_rdata_r;

    always @(posedge clk_i) begin
        if (read_en_i)
            local_rdata_r <= itcm_mem[local_idx_w];
    end

    initial begin
        local_rdata_r = 32'd0;
        for (init_word_i = 0; init_word_i < WORDS;
             init_word_i = init_word_i + 1)
            itcm_mem[init_word_i] = 32'd0;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, itcm_mem);
        // synthesis translate_off
        if ($value$plusargs("ITCMFILE=%s", itcm_file_r))
            $readmemh(itcm_file_r, itcm_mem);
        // synthesis translate_on
    end
`endif

endmodule
