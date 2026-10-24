// ============================================================================
// File        : axi_interconnect.v
// Author      : Edward ZC
// Description : Parameterised NUM_M x NUM_S AXI4 Full interconnect (design
//               §6.3).  Thin top wrapping the independent read and write
//               crossbars.  Read and write arbitrate independently per slave;
//               address ranges are [base, limit); unmapped, disconnected or
//               overlapping matches return DECERR from inline responders.
// Notes       : Verilog-2001 packed ports.  Master-side IDs are local; the
//               fabric forms global IDs {master_index, local_id} towards
//               slaves (GID_W) and strips the prefix on return.  AR/AW
//               admission grants end at the address handshake; each master
//               may keep up to M_MAX_OUTSTANDING read and write transactions
//               in flight.  Optional per-master read/write timeout watchdogs
//               latch the first failure and place that direction in fail-stop.
// ============================================================================
`include "edrv32_axi4.vh"

module axi_interconnect #(
    parameter NUM_M   = 2,
    parameter NUM_S   = 5,
    parameter ADDR_W  = `AXI_ADDR_W,
    parameter DATA_W  = `AXI_DATA_W,
    parameter STRB_W  = `AXI_STRB_W,
    parameter ID_W    = `AXI_ID_W,
    parameter LEN_W   = `AXI_LEN_W,
    parameter SIZE_W  = `AXI_SIZE_W,
    parameter BURST_W = `AXI_BURST_W,
    parameter RESP_W  = `AXI_RESP_W,
    parameter GID_W   = ID_W + ((NUM_M <= 1) ? 1 : $clog2(NUM_M)),
    parameter M_MAX_OUTSTANDING = 4,
    parameter S_MAX_WR = 8,
    parameter RD_TIMEOUT_CYCLES = 0,
    parameter WR_TIMEOUT_CYCLES = 0,
    parameter AXI_MON_ENABLE = 0
)(
    // --- Clock and reset ---
    input  wire                         clk,
    input  wire                         rst_n,

    // --- Master-side read address channels (local ID) ---
    input  wire [NUM_M*ID_W-1:0]        m_arid_i,
    input  wire [NUM_M*ADDR_W-1:0]      m_araddr_i,
    input  wire [NUM_M*LEN_W-1:0]       m_arlen_i,
    input  wire [NUM_M*SIZE_W-1:0]      m_arsize_i,
    input  wire [NUM_M*BURST_W-1:0]     m_arburst_i,
    input  wire [NUM_M-1:0]             m_arvalid_i,
    output wire [NUM_M-1:0]             m_arready_o,

    // --- Master-side read data channels (local ID) ---
    output wire [NUM_M*ID_W-1:0]        m_rid_o,
    output wire [NUM_M*DATA_W-1:0]      m_rdata_o,
    output wire [NUM_M*RESP_W-1:0]      m_rresp_o,
    output wire [NUM_M-1:0]             m_rlast_o,
    output wire [NUM_M-1:0]             m_rvalid_o,
    input  wire [NUM_M-1:0]             m_rready_i,

    // --- Master-side write address channels (local ID) ---
    input  wire [NUM_M*ID_W-1:0]        m_awid_i,
    input  wire [NUM_M*ADDR_W-1:0]      m_awaddr_i,
    input  wire [NUM_M*LEN_W-1:0]       m_awlen_i,
    input  wire [NUM_M*SIZE_W-1:0]      m_awsize_i,
    input  wire [NUM_M*BURST_W-1:0]     m_awburst_i,
    input  wire [NUM_M-1:0]             m_awvalid_i,
    output wire [NUM_M-1:0]             m_awready_o,

    // --- Master-side write data channels ---
    input  wire [NUM_M*DATA_W-1:0]      m_wdata_i,
    input  wire [NUM_M*STRB_W-1:0]      m_wstrb_i,
    input  wire [NUM_M-1:0]             m_wlast_i,
    input  wire [NUM_M-1:0]             m_wvalid_i,
    output wire [NUM_M-1:0]             m_wready_o,

    // --- Master-side write response channels (local ID) ---
    output wire [NUM_M*ID_W-1:0]        m_bid_o,
    output wire [NUM_M*RESP_W-1:0]      m_bresp_o,
    output wire [NUM_M-1:0]             m_bvalid_o,
    input  wire [NUM_M-1:0]             m_bready_i,

    // --- Address map and master/slave connectivity ---
    input  wire [NUM_S*ADDR_W-1:0]      s_base_i,
    input  wire [NUM_S*ADDR_W-1:0]      s_limit_i,
    input  wire [NUM_M*NUM_S-1:0]       m_read_connect_i,
    input  wire [NUM_M*NUM_S-1:0]       m_write_connect_i,

    // --- Slave-side read address channels (global ID) ---
    output wire [NUM_S*GID_W-1:0]       s_arid_o,
    output wire [NUM_S*ADDR_W-1:0]      s_araddr_o,
    output wire [NUM_S*LEN_W-1:0]       s_arlen_o,
    output wire [NUM_S*SIZE_W-1:0]      s_arsize_o,
    output wire [NUM_S*BURST_W-1:0]     s_arburst_o,
    output wire [NUM_S-1:0]             s_arvalid_o,
    input  wire [NUM_S-1:0]             s_arready_i,

    // --- Slave-side read data channels (global ID) ---
    input  wire [NUM_S*GID_W-1:0]       s_rid_i,
    input  wire [NUM_S*DATA_W-1:0]      s_rdata_i,
    input  wire [NUM_S*RESP_W-1:0]      s_rresp_i,
    input  wire [NUM_S-1:0]             s_rlast_i,
    input  wire [NUM_S-1:0]             s_rvalid_i,
    output wire [NUM_S-1:0]             s_rready_o,

    // --- Slave-side write address channels (global ID) ---
    output wire [NUM_S*GID_W-1:0]       s_awid_o,
    output wire [NUM_S*ADDR_W-1:0]      s_awaddr_o,
    output wire [NUM_S*LEN_W-1:0]       s_awlen_o,
    output wire [NUM_S*SIZE_W-1:0]      s_awsize_o,
    output wire [NUM_S*BURST_W-1:0]     s_awburst_o,
    output wire [NUM_S-1:0]             s_awvalid_o,
    input  wire [NUM_S-1:0]             s_awready_i,

    // --- Slave-side write data channels ---
    output wire [NUM_S*DATA_W-1:0]      s_wdata_o,
    output wire [NUM_S*STRB_W-1:0]      s_wstrb_o,
    output wire [NUM_S-1:0]             s_wlast_o,
    output wire [NUM_S-1:0]             s_wvalid_o,
    input  wire [NUM_S-1:0]             s_wready_i,

    // --- Slave-side write response channels (global ID) ---
    input  wire [NUM_S*GID_W-1:0]       s_bid_i,
    input  wire [NUM_S*RESP_W-1:0]      s_bresp_i,
    input  wire [NUM_S-1:0]             s_bvalid_i,
    output wire [NUM_S-1:0]             s_bready_o,

    // --- Fail-stop timeout status (per master, read/write) ---
    output wire [NUM_M-1:0]             fs_rd_fail_o,
    output wire [NUM_M*ADDR_W-1:0]      fs_rd_addr_o,
    output wire [NUM_M*ID_W-1:0]        fs_rd_id_o,
    output wire [NUM_M-1:0]             fs_wr_fail_o,
    output wire [NUM_M*ADDR_W-1:0]      fs_wr_addr_o,
    output wire [NUM_M*ID_W-1:0]        fs_wr_id_o,

    // --- AXI monitor (per master) ---
    output wire [NUM_M*32-1:0]          mon_rd_beats_o,
    output wire [NUM_M*32-1:0]          mon_rd_bursts_o,
    output wire [NUM_M*32-1:0]          mon_rd_err_o,
    output wire [NUM_M*32-1:0]          mon_rd_maxwait_o,
    output wire [NUM_M*32-1:0]          mon_wr_beats_o,
    output wire [NUM_M*32-1:0]          mon_wr_bursts_o,
    output wire [NUM_M*32-1:0]          mon_wr_err_o,
    output wire [NUM_M*32-1:0]          mon_wr_maxwait_o
);

    axi_rd_fabric #(
        .NUM_M   (NUM_M),
        .NUM_S   (NUM_S),
        .ADDR_W  (ADDR_W),
        .DATA_W  (DATA_W),
        .ID_W    (ID_W),
        .LEN_W   (LEN_W),
        .SIZE_W  (SIZE_W),
        .BURST_W (BURST_W),
        .RESP_W  (RESP_W),
        .GID_W   (GID_W),
        .M_MAX_OUTSTANDING (M_MAX_OUTSTANDING),
        .RD_TIMEOUT_CYCLES (RD_TIMEOUT_CYCLES),
        .AXI_MON_ENABLE    (AXI_MON_ENABLE)
    ) u_axi_rd_fabric (
        // --- Clock and reset ---
        .clk                (clk),
        .rst_n              (rst_n),
        // --- Master-side read channels ---
        .m_arid_i           (m_arid_i),
        .m_araddr_i         (m_araddr_i),
        .m_arlen_i          (m_arlen_i),
        .m_arsize_i         (m_arsize_i),
        .m_arburst_i        (m_arburst_i),
        .m_arvalid_i        (m_arvalid_i),
        .m_arready_o        (m_arready_o),
        .m_rid_o            (m_rid_o),
        .m_rdata_o          (m_rdata_o),
        .m_rresp_o          (m_rresp_o),
        .m_rlast_o          (m_rlast_o),
        .m_rvalid_o         (m_rvalid_o),
        .m_rready_i         (m_rready_i),
        // --- Address map and connectivity ---
        .s_base_i           (s_base_i),
        .s_limit_i          (s_limit_i),
        .m_read_connect_i   (m_read_connect_i),
        // --- Slave-side read channels ---
        .s_arid_o           (s_arid_o),
        .s_araddr_o         (s_araddr_o),
        .s_arlen_o          (s_arlen_o),
        .s_arsize_o         (s_arsize_o),
        .s_arburst_o        (s_arburst_o),
        .s_arvalid_o        (s_arvalid_o),
        .s_arready_i        (s_arready_i),
        .s_rid_i            (s_rid_i),
        .s_rdata_i          (s_rdata_i),
        .s_rresp_i          (s_rresp_i),
        .s_rlast_i          (s_rlast_i),
        .s_rvalid_i         (s_rvalid_i),
        .s_rready_o         (s_rready_o),
        .fs_rd_fail_o       (fs_rd_fail_o),
        .fs_rd_addr_o       (fs_rd_addr_o),
        .fs_rd_id_o         (fs_rd_id_o),
        .mon_rd_beats_o     (mon_rd_beats_o),
        .mon_rd_bursts_o    (mon_rd_bursts_o),
        .mon_rd_err_o       (mon_rd_err_o),
        .mon_rd_maxwait_o   (mon_rd_maxwait_o)
    );

    axi_wr_fabric #(
        .NUM_M   (NUM_M),
        .NUM_S   (NUM_S),
        .ADDR_W  (ADDR_W),
        .DATA_W  (DATA_W),
        .STRB_W  (STRB_W),
        .ID_W    (ID_W),
        .LEN_W   (LEN_W),
        .SIZE_W  (SIZE_W),
        .BURST_W (BURST_W),
        .RESP_W  (RESP_W),
        .GID_W   (GID_W),
        .M_MAX_OUTSTANDING (M_MAX_OUTSTANDING),
        .S_MAX_WR (S_MAX_WR),
        .WR_TIMEOUT_CYCLES (WR_TIMEOUT_CYCLES),
        .AXI_MON_ENABLE    (AXI_MON_ENABLE)
    ) u_axi_wr_fabric (
        // --- Clock and reset ---
        .clk                (clk),
        .rst_n              (rst_n),
        // --- Master-side write channels ---
        .m_awid_i           (m_awid_i),
        .m_awaddr_i         (m_awaddr_i),
        .m_awlen_i          (m_awlen_i),
        .m_awsize_i         (m_awsize_i),
        .m_awburst_i        (m_awburst_i),
        .m_awvalid_i        (m_awvalid_i),
        .m_awready_o        (m_awready_o),
        .m_wdata_i          (m_wdata_i),
        .m_wstrb_i          (m_wstrb_i),
        .m_wlast_i          (m_wlast_i),
        .m_wvalid_i         (m_wvalid_i),
        .m_wready_o         (m_wready_o),
        .m_bid_o            (m_bid_o),
        .m_bresp_o          (m_bresp_o),
        .m_bvalid_o         (m_bvalid_o),
        .m_bready_i         (m_bready_i),
        // --- Address map and connectivity ---
        .s_base_i           (s_base_i),
        .s_limit_i          (s_limit_i),
        .m_write_connect_i  (m_write_connect_i),
        // --- Slave-side write channels ---
        .s_awid_o           (s_awid_o),
        .s_awaddr_o         (s_awaddr_o),
        .s_awlen_o          (s_awlen_o),
        .s_awsize_o         (s_awsize_o),
        .s_awburst_o        (s_awburst_o),
        .s_awvalid_o        (s_awvalid_o),
        .s_awready_i        (s_awready_i),
        .s_wdata_o          (s_wdata_o),
        .s_wstrb_o          (s_wstrb_o),
        .s_wlast_o          (s_wlast_o),
        .s_wvalid_o         (s_wvalid_o),
        .s_wready_i         (s_wready_i),
        .s_bid_i            (s_bid_i),
        .s_bresp_i          (s_bresp_i),
        .s_bvalid_i         (s_bvalid_i),
        .s_bready_o         (s_bready_o),
        .fs_wr_fail_o       (fs_wr_fail_o),
        .fs_wr_addr_o       (fs_wr_addr_o),
        .fs_wr_id_o         (fs_wr_id_o),
        .mon_wr_beats_o     (mon_wr_beats_o),
        .mon_wr_bursts_o    (mon_wr_bursts_o),
        .mon_wr_err_o       (mon_wr_err_o),
        .mon_wr_maxwait_o   (mon_wr_maxwait_o)
    );

endmodule
