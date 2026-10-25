// ============================================================================
// File        : boot_rom_axi.v
// Author      : Edward ZC
// Description : AXI4 read-only Boot ROM slave (design §6.5.1: 0x0000_0000,
//               16 KiB).  64-bit AXI endpoint: 8-byte beats stream two 32-bit
//               storage words; AxSIZE=4B narrow singles use the addr[2] lane.
//               Writes get a SLVERR (ROM is read-only).  Image initialised via
//               +ROMFILE/ROM_INIT_FILE in SIM_MODE; FPGA_MODE selects the
//               generated, image-initialized Pango ROM.
// Notes       : Verilog-2001. The ROM read is clocked to match the Pango
//               GTP_DRM18K/ipml_rom behavior. Single ID, single outstanding.
//               Out-of-range, unaligned or narrow-burst accesses return SLVERR.
// ============================================================================
`include "edrv32_axi4.vh"
`include "edrv32_build_mode.vh"

// ============================================================================
// boot_rom_axi - AXI4 read-only Boot ROM (64-bit endpoint)
// ============================================================================
module boot_rom_axi #(
    parameter NUM_WORDS = 4096,                // 32-bit words (16 KiB)
    parameter [31:0] BASE_ADDR = 32'h0000_0000,
    parameter ID_W = `AXI_ID_W,                // global ID width from fabric
    parameter ROM_INIT_FILE = ""               // word-per-line hex image
)(
    // --- Clock and reset ---
    input  wire                     clk,
    input  wire                     rst_n,

    // --- AXI4 write channels (rejected: read-only) ---
    input  wire [ID_W-1:0]          awid_i,
    input  wire [31:0]              awaddr_i,
    input  wire [`AXI_LEN_W-1:0]    awlen_i,
    input  wire                     awvalid_i,
    output wire                     awready_o,
    input  wire [`AXI_DATA_W-1:0]   wdata_i,
    input  wire [`AXI_STRB_W-1:0]   wstrb_i,
    input  wire                     wlast_i,
    input  wire                     wvalid_i,
    output wire                     wready_o,
    output wire [ID_W-1:0]          bid_o,
    output wire [`AXI_RESP_W-1:0]   bresp_o,
    output wire                     bvalid_o,
    input  wire                     bready_i,
    // --- AXI4 read address channel ---
    input  wire [ID_W-1:0]          arid_i,
    input  wire [31:0]              araddr_i,
    input  wire [`AXI_LEN_W-1:0]    arlen_i,
    input  wire [`AXI_SIZE_W-1:0]   arsize_i,
    input  wire [`AXI_BURST_W-1:0]  arburst_i,
    input  wire                     arvalid_i,
    output wire                     arready_o,
    // --- AXI4 read data channel ---
    output wire [ID_W-1:0]          rid_o,
    output wire [`AXI_DATA_W-1:0]   rdata_o,
    output wire [`AXI_RESP_W-1:0]   rresp_o,
    output wire                     rlast_o,
    output wire                     rvalid_o,
    input  wire                     rready_i
);

    localparam IDX_W = $clog2(NUM_WORDS);
    localparam PAIR_WORDS = (NUM_WORDS + 1) / 2;
    localparam PAIR_IDX_W = $clog2(PAIR_WORDS);

    reg [ID_W-1:0] rid_r;
    reg rvalid_r;
    reg rlast_r;
    reg r_err_r;
    reg        r_wide_r;
    reg        r_high_lane_r;
    reg [IDX_W-1:0] r_word_r;
    reg [`AXI_LEN_W-1:0] r_beats_left_r;
    reg        rd_busy_r;
    reg        aw_seen_r;
    reg        w_done_r;
    reg        bvalid_r;
    reg [ID_W-1:0] bid_r;

    wire [31:0] END_ADDR_W = BASE_ADDR + NUM_WORDS * 4;
    wire [14:0] rd_blen_w = arsize_i[0] ? ({7'b0, arlen_i} << 3)
                                        : ({7'b0, arlen_i} << 2);
    wire [31:0] rd_last_addr_w = araddr_i + {17'b0, rd_blen_w};
    wire [14:0] rd_end_off_w = {3'b000, araddr_i[11:0]} + rd_blen_w +
                               (arsize_i[0] ? 15'd8 : 15'd4);
    wire rd_size_ok_w = (arsize_i == `AXI_SIZE_8B) ||
                        ((arsize_i == `AXI_SIZE_4B) && (arlen_i == 0));
    wire read_req_err_w = (araddr_i < BASE_ADDR)
                          || (rd_last_addr_w >= END_ADDR_W)
                          || (rd_last_addr_w < araddr_i)
                          || (araddr_i[1:0] != 2'b00)
                          || (araddr_i[2] && (arsize_i == `AXI_SIZE_8B))
                          || !rd_size_ok_w
                          || (arburst_i != `AXI_BURST_INCR)
                          || (rd_end_off_w > 15'd4096);

    wire [IDX_W-1:0] rd_next_word_w = r_word_r +
        (r_wide_r ? {{(IDX_W-2){1'b0}}, 2'b10}
                  : {{(IDX_W-1){1'b0}}, 1'b1});
    wire [IDX_W-1:0] ar_lo_word_w = araddr_i[IDX_W+1:2];
    wire ar_fire_w = arvalid_i && arready_o;
    wire r_fire_w  = rvalid_r && rready_i;
    wire rom_rd_en_w = ar_fire_w || (r_fire_w && !rlast_r);
    wire [PAIR_IDX_W-1:0] rom_rd_addr_w = ar_fire_w
        ? ar_lo_word_w[IDX_W-1:1]
        : rd_next_word_w[IDX_W-1:1];
    wire [63:0] rom_rd_data_w;

`ifdef EDRV32_BUILD_MODE_CONFLICT
    edrv32_build_mode_error__define_only_one_of_FPGA_MODE_or_SIM_MODE
        u_build_mode_error ();
`elsif EDRV32_FPGA_MEMORY_MODE
    pango_boot_rom_storage u_pango_boot_rom_storage (
        .clk       (clk),
        .rst_n     (rst_n),
        .rd_en_i   (rom_rd_en_w),
        .rd_addr_i (rom_rd_addr_w[10:0]),
        .rd_data_o (rom_rd_data_w)
    );

    generate
        if (NUM_WORDS != 4096) begin : gen_bad_pango_rom_geometry
            edrv32_pango_boot_rom_geometry_must_be_4096_words
                u_static_assert ();
        end
    endgenerate
`else
    boot_rom_storage #(
        .NUM_WORDS     (NUM_WORDS),
        .ROM_INIT_FILE (ROM_INIT_FILE)
    ) u_boot_rom_storage (
        .clk       (clk),
        .rst_n     (rst_n),
        .rd_en_i   (rom_rd_en_w),
        .rd_addr_i (rom_rd_addr_w),
        .rd_data_o (rom_rd_data_w)
    );
`endif

    // ------------------------------------------------------------------
    // Read channel
    // ------------------------------------------------------------------
    assign arready_o = !rd_busy_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_busy_r      <= 1'b0;
            rvalid_r       <= 1'b0;
            rlast_r        <= 1'b0;
            r_err_r        <= 1'b0;
            rid_r          <= {ID_W{1'b0}};
            r_wide_r       <= 1'b0;
            r_high_lane_r  <= 1'b0;
            r_word_r       <= {IDX_W{1'b0}};
            r_beats_left_r <= {`AXI_LEN_W{1'b0}};
        end else if (ar_fire_w) begin
            rd_busy_r      <= 1'b1;
            rid_r          <= arid_i;
            r_wide_r       <= (arsize_i == `AXI_SIZE_8B);
            r_high_lane_r  <= araddr_i[2];
            r_word_r       <= ar_lo_word_w;
            r_beats_left_r <= arlen_i;
            r_err_r        <= read_req_err_w;
            rvalid_r       <= 1'b1;
            rlast_r        <= (arlen_i == 0);
        end else if (r_fire_w) begin
            if (rlast_r) begin
                rvalid_r  <= 1'b0;
                rd_busy_r <= 1'b0;
            end else begin
                r_beats_left_r <= r_beats_left_r - 1'b1;
                r_word_r       <= rd_next_word_w;
                rlast_r        <= (r_beats_left_r == 1);
            end
        end
    end

    assign rvalid_o = rvalid_r;
    assign rdata_o  = r_err_r ? {`AXI_DATA_W{1'b0}}
                    : r_wide_r ? rom_rd_data_w
                    : r_high_lane_r ? {rom_rd_data_w[63:32], 32'h0000_0000}
                    : {32'h0000_0000, rom_rd_data_w[31:0]};
    assign rresp_o  = r_err_r ? `AXI_RESP_SLVERR : `AXI_RESP_OKAY;
    assign rlast_o  = rlast_r;
    assign rid_o    = rid_r;

    // ------------------------------------------------------------------
    // Write channel: error response (read-only ROM). AW and W are independent;
    // discard every W beat through WLAST, then return one retained SLVERR.
    // ------------------------------------------------------------------
    assign awready_o = !aw_seen_r && !bvalid_r;
    assign wready_o  = !w_done_r && !bvalid_r;
    wire aw_fire_w = awvalid_i && awready_o;
    wire w_fire_w  = wvalid_i && wready_o;
    wire write_done_w = (aw_seen_r || aw_fire_w) &&
                        (w_done_r || (w_fire_w && wlast_i));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_seen_r <= 1'b0;
            w_done_r  <= 1'b0;
            bvalid_r  <= 1'b0;
            bid_r     <= {ID_W{1'b0}};
        end else begin
            if (aw_fire_w) begin
                aw_seen_r <= 1'b1;
                bid_r <= awid_i;
            end
            if (w_fire_w && wlast_i)
                w_done_r <= 1'b1;
            if (write_done_w) begin
                bvalid_r <= 1'b1;
                aw_seen_r <= 1'b0;
                w_done_r <= 1'b0;
            end
            if (bvalid_r && bready_i) begin
                bvalid_r <= 1'b0;
            end
        end
    end

    assign bvalid_o = bvalid_r;
    assign bid_o    = bid_r;
    assign bresp_o  = `AXI_RESP_SLVERR;

    wire unused_write_payload_w = ^{awaddr_i, awlen_i, wdata_i, wstrb_i};

endmodule
