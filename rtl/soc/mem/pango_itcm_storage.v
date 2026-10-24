// ============================================================================
// File        : pango_itcm_storage.v
// Description : MES50HP ITCM backend using a generated 64-bit Pango RAM IP.
// Notes       : The unused write port is retained so a future boot loader can
//               populate the same physical RAM without changing its geometry.
// ============================================================================
module pango_itcm_storage (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        rd_en_i,
    input  wire [13:0] rd_addr_i,
    output wire [31:0] rd_data_o
);
    reg         word_select_r;
    wire [63:0] pair_data_w;

    assign rd_data_o = word_select_r ? pair_data_w[63:32] :
                                         pair_data_w[31:0];

    always @(posedge clk_i) begin
        if (rd_en_i)
            word_select_r <= rd_addr_i[0];
    end

`ifdef EDRV32_SOC_100MHZ
    pango_itcm_64x8192_100m u_pango_itcm_64x8192 (
`else
    pango_itcm_64x8192 u_pango_itcm_64x8192 (
`endif
        .wr_data    (64'd0),
        .wr_addr    (13'd0),
        .wr_en      (1'b0),
        .wr_clk     (clk_i),
        .wr_rst     (rst_i),
        .wr_byte_en (8'd0),
        .rd_data    (pair_data_w),
        .rd_addr    (rd_addr_i[13:1]),
        .rd_clk     (clk_i),
        .rd_rst     (rst_i)
    );

endmodule
