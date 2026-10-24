// ============================================================================
// File        : edrv32_axi_async_bridge.v
// Description : Full AXI channel clock-domain bridge built from five
//               independent asynchronous FIFOs.
// Notes       : AW/W/AR travel from the slave-side clock domain to the master
//               side. B/R return in the opposite direction. Each channel can
//               transfer one payload per local clock while its FIFO is ready.
// ============================================================================

module edrv32_axi_async_bridge #(
    parameter integer ADDR_W = 32,
    parameter integer DATA_W = 256,
    parameter integer ID_W = 4,
    parameter integer LEN_W = 8,
    parameter integer CMD_FIFO_ADDR_W = 2,
    parameter integer DATA_FIFO_ADDR_W = 4
) (
    input  wire                     s_clk_i,
    input  wire                     s_rst_n_i,
    input  wire                     m_clk_i,
    input  wire                     m_rst_n_i,

    input  wire [ID_W-1:0]          s_awid_i,
    input  wire [ADDR_W-1:0]        s_awaddr_i,
    input  wire [LEN_W-1:0]         s_awlen_i,
    input  wire [2:0]               s_awsize_i,
    input  wire [1:0]               s_awburst_i,
    input  wire [3:0]               s_awqos_i,
    input  wire                     s_awvalid_i,
    output wire                     s_awready_o,
    input  wire [DATA_W-1:0]        s_wdata_i,
    input  wire [DATA_W/8-1:0]      s_wstrb_i,
    input  wire                     s_wlast_i,
    input  wire                     s_wvalid_i,
    output wire                     s_wready_o,
    output wire [ID_W-1:0]          s_bid_o,
    output wire [1:0]               s_bresp_o,
    output wire                     s_bvalid_o,
    input  wire                     s_bready_i,

    input  wire [ID_W-1:0]          s_arid_i,
    input  wire [ADDR_W-1:0]        s_araddr_i,
    input  wire [LEN_W-1:0]         s_arlen_i,
    input  wire [2:0]               s_arsize_i,
    input  wire [1:0]               s_arburst_i,
    input  wire [3:0]               s_arqos_i,
    input  wire                     s_arvalid_i,
    output wire                     s_arready_o,
    output wire [ID_W-1:0]          s_rid_o,
    output wire [DATA_W-1:0]        s_rdata_o,
    output wire [1:0]               s_rresp_o,
    output wire                     s_rlast_o,
    output wire                     s_rvalid_o,
    input  wire                     s_rready_i,

    output wire [ID_W-1:0]          m_awid_o,
    output wire [ADDR_W-1:0]        m_awaddr_o,
    output wire [LEN_W-1:0]         m_awlen_o,
    output wire [2:0]               m_awsize_o,
    output wire [1:0]               m_awburst_o,
    output wire [3:0]               m_awqos_o,
    output wire                     m_awvalid_o,
    input  wire                     m_awready_i,
    output wire [DATA_W-1:0]        m_wdata_o,
    output wire [DATA_W/8-1:0]      m_wstrb_o,
    output wire                     m_wlast_o,
    output wire                     m_wvalid_o,
    input  wire                     m_wready_i,
    input  wire [ID_W-1:0]          m_bid_i,
    input  wire [1:0]               m_bresp_i,
    input  wire                     m_bvalid_i,
    output wire                     m_bready_o,

    output wire [ID_W-1:0]          m_arid_o,
    output wire [ADDR_W-1:0]        m_araddr_o,
    output wire [LEN_W-1:0]         m_arlen_o,
    output wire [2:0]               m_arsize_o,
    output wire [1:0]               m_arburst_o,
    output wire [3:0]               m_arqos_o,
    output wire                     m_arvalid_o,
    input  wire                     m_arready_i,
    input  wire [ID_W-1:0]          m_rid_i,
    input  wire [DATA_W-1:0]        m_rdata_i,
    input  wire [1:0]               m_rresp_i,
    input  wire                     m_rlast_i,
    input  wire                     m_rvalid_i,
    output wire                     m_rready_o
);

    localparam integer STRB_W = DATA_W / 8;
    localparam integer AW_W = ID_W + ADDR_W + LEN_W + 3 + 2 + 4;
    localparam integer W_W = DATA_W + STRB_W + 1;
    localparam integer B_W = ID_W + 2;
    localparam integer AR_W = AW_W;
    localparam integer R_W = ID_W + DATA_W + 2 + 1;

    wire [AW_W-1:0] aw_read_data_w;
    wire [W_W-1:0] w_read_data_w;
    wire [B_W-1:0] b_read_data_w;
    wire [AR_W-1:0] ar_read_data_w;
    wire [R_W-1:0] r_read_data_w;

    edrv32_async_fifo #(
        .DATA_W (AW_W),
        .ADDR_W (CMD_FIFO_ADDR_W)
    ) u_aw_fifo (
        .wr_clk_i   (s_clk_i),
        .wr_rst_n_i (s_rst_n_i),
        .wr_data_i  ({s_awid_i, s_awaddr_i, s_awlen_i, s_awsize_i,
                      s_awburst_i, s_awqos_i}),
        .wr_valid_i (s_awvalid_i),
        .wr_ready_o (s_awready_o),
        .rd_clk_i   (m_clk_i),
        .rd_rst_n_i (m_rst_n_i),
        .rd_data_o  (aw_read_data_w),
        .rd_valid_o (m_awvalid_o),
        .rd_ready_i (m_awready_i)
    );

    assign {m_awid_o, m_awaddr_o, m_awlen_o, m_awsize_o,
            m_awburst_o, m_awqos_o} = aw_read_data_w;

    edrv32_async_fifo #(
        .DATA_W (W_W),
        .ADDR_W (DATA_FIFO_ADDR_W)
    ) u_w_fifo (
        .wr_clk_i   (s_clk_i),
        .wr_rst_n_i (s_rst_n_i),
        .wr_data_i  ({s_wdata_i, s_wstrb_i, s_wlast_i}),
        .wr_valid_i (s_wvalid_i),
        .wr_ready_o (s_wready_o),
        .rd_clk_i   (m_clk_i),
        .rd_rst_n_i (m_rst_n_i),
        .rd_data_o  (w_read_data_w),
        .rd_valid_o (m_wvalid_o),
        .rd_ready_i (m_wready_i)
    );

    assign {m_wdata_o, m_wstrb_o, m_wlast_o} = w_read_data_w;

    edrv32_async_fifo #(
        .DATA_W (B_W),
        .ADDR_W (CMD_FIFO_ADDR_W)
    ) u_b_fifo (
        .wr_clk_i   (m_clk_i),
        .wr_rst_n_i (m_rst_n_i),
        .wr_data_i  ({m_bid_i, m_bresp_i}),
        .wr_valid_i (m_bvalid_i),
        .wr_ready_o (m_bready_o),
        .rd_clk_i   (s_clk_i),
        .rd_rst_n_i (s_rst_n_i),
        .rd_data_o  (b_read_data_w),
        .rd_valid_o (s_bvalid_o),
        .rd_ready_i (s_bready_i)
    );

    assign {s_bid_o, s_bresp_o} = b_read_data_w;

    edrv32_async_fifo #(
        .DATA_W (AR_W),
        .ADDR_W (CMD_FIFO_ADDR_W)
    ) u_ar_fifo (
        .wr_clk_i   (s_clk_i),
        .wr_rst_n_i (s_rst_n_i),
        .wr_data_i  ({s_arid_i, s_araddr_i, s_arlen_i, s_arsize_i,
                      s_arburst_i, s_arqos_i}),
        .wr_valid_i (s_arvalid_i),
        .wr_ready_o (s_arready_o),
        .rd_clk_i   (m_clk_i),
        .rd_rst_n_i (m_rst_n_i),
        .rd_data_o  (ar_read_data_w),
        .rd_valid_o (m_arvalid_o),
        .rd_ready_i (m_arready_i)
    );

    assign {m_arid_o, m_araddr_o, m_arlen_o, m_arsize_o,
            m_arburst_o, m_arqos_o} = ar_read_data_w;

    edrv32_async_fifo #(
        .DATA_W (R_W),
        .ADDR_W (DATA_FIFO_ADDR_W)
    ) u_r_fifo (
        .wr_clk_i   (m_clk_i),
        .wr_rst_n_i (m_rst_n_i),
        .wr_data_i  ({m_rid_i, m_rdata_i, m_rresp_i, m_rlast_i}),
        .wr_valid_i (m_rvalid_i),
        .wr_ready_o (m_rready_o),
        .rd_clk_i   (s_clk_i),
        .rd_rst_n_i (s_rst_n_i),
        .rd_data_o  (r_read_data_w),
        .rd_valid_o (s_rvalid_o),
        .rd_ready_i (s_rready_i)
    );

    assign {s_rid_o, s_rdata_o, s_rresp_o, s_rlast_o} = r_read_data_w;

endmodule
