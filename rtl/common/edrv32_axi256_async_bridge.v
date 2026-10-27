// File: edrv32_axi256_async_bridge.v
// Spec: edrv32-soc-spec 4.2, 5.2 X9, 5.3; npu-spec 1, 3.
// Description: Fixed AXI256 bridge with one independent async FIFO per channel.
//              Payloads and backpressure cross only through edrv32_async_fifo.
// Clock domain: s_axi in clk_npu; m_axi in clk_mem; reset both ends together.
//
// Depth derivation (edrv32_async_fifo uses two pointer synchronizer registers
// plus a registered full/empty comparison): a write becomes readable within
// four read periods; that read's slot becomes writable within four write
// periods. Thus the slot round trip is at most 4*Tr + 4*Tw, or eight slow-side
// periods. Eight slots sustain one transfer per slow period for 150/125,
// 125/125 and 100/125 MHz, in either direction, including coincident edges.
// At 1:1 with coincident edges, write edge 0 -> read edge 4 -> reuse edge 8;
// depth 4 cannot cover this credit latency. The next legal power of two is 8.
// AW/AR/B also use 8: SoC 4.2 permits single-beat transactions, so each must
// sustain the same transaction rate as W/R; assuming long bursts would allow
// smaller FIFOs but would throttle legal single-beat streams. There are no
// extra registers or transaction tracking in this bridge.
module edrv32_axi256_async_bridge (
    // Source and destination clocks; resets release synchronously in each domain.
    input wire clk_npu_i,
    input wire rst_npu_n_i,
    input wire clk_mem_i,
    input wire rst_mem_n_i,

    // s_axi interface (AXI256).
    input wire [0:0] s_axi_awid_i,
    input wire [31:0] s_axi_awaddr_i,
    input wire [3:0] s_axi_awlen_i,
    input wire s_axi_awvalid_i,
    output wire s_axi_awready_o,
    input wire [255:0] s_axi_wdata_i,
    input wire [31:0] s_axi_wstrb_i,
    input wire s_axi_wlast_i,
    input wire s_axi_wvalid_i,
    output wire s_axi_wready_o,
    output wire [0:0] s_axi_bid_o,
    output wire [1:0] s_axi_bresp_o,
    output wire s_axi_bvalid_o,
    input wire s_axi_bready_i,
    input wire [0:0] s_axi_arid_i,
    input wire [31:0] s_axi_araddr_i,
    input wire [3:0] s_axi_arlen_i,
    input wire s_axi_arvalid_i,
    output wire s_axi_arready_o,
    output wire [0:0] s_axi_rid_o,
    output wire [255:0] s_axi_rdata_o,
    output wire [1:0] s_axi_rresp_o,
    output wire s_axi_rlast_o,
    output wire s_axi_rvalid_o,
    input wire s_axi_rready_i,

    // m_axi interface (AXI256).
    output wire [0:0] m_axi_awid_o,
    output wire [31:0] m_axi_awaddr_o,
    output wire [3:0] m_axi_awlen_o,
    output wire m_axi_awvalid_o,
    input wire m_axi_awready_i,
    output wire [255:0] m_axi_wdata_o,
    output wire [31:0] m_axi_wstrb_o,
    output wire m_axi_wlast_o,
    output wire m_axi_wvalid_o,
    input wire m_axi_wready_i,
    input wire [0:0] m_axi_bid_i,
    input wire [1:0] m_axi_bresp_i,
    input wire m_axi_bvalid_i,
    output wire m_axi_bready_o,
    output wire [0:0] m_axi_arid_o,
    output wire [31:0] m_axi_araddr_o,
    output wire [3:0] m_axi_arlen_o,
    output wire m_axi_arvalid_o,
    input wire m_axi_arready_i,
    input wire [0:0] m_axi_rid_i,
    input wire [255:0] m_axi_rdata_i,
    input wire [1:0] m_axi_rresp_i,
    input wire m_axi_rlast_i,
    input wire m_axi_rvalid_i,
    output wire m_axi_rready_o
);
    edrv32_async_fifo #(
        .WIDTH(37),
        .DEPTH(8)
    ) u_aw_fifo (
        // AW clocks and domain-local resets.
        .clk_write_i(clk_npu_i),
        .rst_write_n_i(rst_npu_n_i),
        .clk_read_i(clk_mem_i),
        .rst_read_n_i(rst_mem_n_i),

        // Producer payload and handshake.
        .valid_i(s_axi_awvalid_i),
        .ready_o(s_axi_awready_o),
        .data_i({s_axi_awid_i, s_axi_awaddr_i, s_axi_awlen_i}),

        // Consumer payload and handshake.
        .valid_o(m_axi_awvalid_o),
        .ready_i(m_axi_awready_i),
        .data_o({m_axi_awid_o, m_axi_awaddr_o, m_axi_awlen_o})
    );
    edrv32_async_fifo #(
        .WIDTH(289),
        .DEPTH(8)
    ) u_w_fifo (
        // W clocks and domain-local resets.
        .clk_write_i(clk_npu_i),
        .rst_write_n_i(rst_npu_n_i),
        .clk_read_i(clk_mem_i),
        .rst_read_n_i(rst_mem_n_i),

        // Producer payload and handshake.
        .valid_i(s_axi_wvalid_i),
        .ready_o(s_axi_wready_o),
        .data_i({s_axi_wdata_i, s_axi_wstrb_i, s_axi_wlast_i}),

        // Consumer payload and handshake.
        .valid_o(m_axi_wvalid_o),
        .ready_i(m_axi_wready_i),
        .data_o({m_axi_wdata_o, m_axi_wstrb_o, m_axi_wlast_o})
    );
    edrv32_async_fifo #(
        .WIDTH(3),
        .DEPTH(8)
    ) u_b_fifo (
        // B clocks and domain-local resets.
        .clk_write_i(clk_mem_i),
        .rst_write_n_i(rst_mem_n_i),
        .clk_read_i(clk_npu_i),
        .rst_read_n_i(rst_npu_n_i),

        // Producer payload and handshake.
        .valid_i(m_axi_bvalid_i),
        .ready_o(m_axi_bready_o),
        .data_i({m_axi_bid_i, m_axi_bresp_i}),

        // Consumer payload and handshake.
        .valid_o(s_axi_bvalid_o),
        .ready_i(s_axi_bready_i),
        .data_o({s_axi_bid_o, s_axi_bresp_o})
    );
    edrv32_async_fifo #(
        .WIDTH(37),
        .DEPTH(8)
    ) u_ar_fifo (
        // AR clocks and domain-local resets.
        .clk_write_i(clk_npu_i),
        .rst_write_n_i(rst_npu_n_i),
        .clk_read_i(clk_mem_i),
        .rst_read_n_i(rst_mem_n_i),

        // Producer payload and handshake.
        .valid_i(s_axi_arvalid_i),
        .ready_o(s_axi_arready_o),
        .data_i({s_axi_arid_i, s_axi_araddr_i, s_axi_arlen_i}),

        // Consumer payload and handshake.
        .valid_o(m_axi_arvalid_o),
        .ready_i(m_axi_arready_i),
        .data_o({m_axi_arid_o, m_axi_araddr_o, m_axi_arlen_o})
    );
    edrv32_async_fifo #(
        .WIDTH(260),
        .DEPTH(8)
    ) u_r_fifo (
        // R clocks and domain-local resets.
        .clk_write_i(clk_mem_i),
        .rst_write_n_i(rst_mem_n_i),
        .clk_read_i(clk_npu_i),
        .rst_read_n_i(rst_npu_n_i),

        // Producer payload and handshake.
        .valid_i(m_axi_rvalid_i),
        .ready_o(m_axi_rready_o),
        .data_i({m_axi_rid_i, m_axi_rdata_i, m_axi_rresp_i, m_axi_rlast_i}),

        // Consumer payload and handshake.
        .valid_o(s_axi_rvalid_o),
        .ready_i(s_axi_rready_i),
        .data_o({s_axi_rid_o, s_axi_rdata_o, s_axi_rresp_o, s_axi_rlast_o})
    );
endmodule
