// File: edrv32_axi_async_bridge.v
// Spec: mem-subsys-spec 1, 2.1; edrv32-soc-spec 4.1, 5.2 X2, 5.3.
// Description: Five independent AXI64 channels cross through common asynchronous FIFOs.
//              DEPTH=2 on every channel is the primitive minimum; W/R stream with
//              backpressure, so one outstanding transaction does not require a whole-line FIFO.
// Clock domain: s_axi in clk_sys, m_axi in clk_mem; both ends reset together.
module edrv32_axi_async_bridge (
    // Source and destination clocks; resets release synchronously in each domain.
    input wire clk_sys_i,
    input wire rst_sys_n_i,
    input wire clk_mem_i,
    input wire rst_mem_n_i,

    // s_axi interface (AXI64).
    input wire [3:0] s_axi_awid_i,
    input wire [31:0] s_axi_awaddr_i,
    input wire [7:0] s_axi_awlen_i,
    input wire [2:0] s_axi_awsize_i,
    input wire [1:0] s_axi_awburst_i,
    input wire s_axi_awvalid_i,
    output wire s_axi_awready_o,
    input wire [63:0] s_axi_wdata_i,
    input wire [7:0] s_axi_wstrb_i,
    input wire s_axi_wlast_i,
    input wire s_axi_wvalid_i,
    output wire s_axi_wready_o,
    output wire [3:0] s_axi_bid_o,
    output wire [1:0] s_axi_bresp_o,
    output wire s_axi_bvalid_o,
    input wire s_axi_bready_i,
    input wire [3:0] s_axi_arid_i,
    input wire [31:0] s_axi_araddr_i,
    input wire [7:0] s_axi_arlen_i,
    input wire [2:0] s_axi_arsize_i,
    input wire [1:0] s_axi_arburst_i,
    input wire s_axi_arvalid_i,
    output wire s_axi_arready_o,
    output wire [3:0] s_axi_rid_o,
    output wire [63:0] s_axi_rdata_o,
    output wire [1:0] s_axi_rresp_o,
    output wire s_axi_rlast_o,
    output wire s_axi_rvalid_o,
    input wire s_axi_rready_i,

    // m_axi interface (AXI64).
    output wire [3:0] m_axi_awid_o,
    output wire [31:0] m_axi_awaddr_o,
    output wire [7:0] m_axi_awlen_o,
    output wire [2:0] m_axi_awsize_o,
    output wire [1:0] m_axi_awburst_o,
    output wire m_axi_awvalid_o,
    input wire m_axi_awready_i,
    output wire [63:0] m_axi_wdata_o,
    output wire [7:0] m_axi_wstrb_o,
    output wire m_axi_wlast_o,
    output wire m_axi_wvalid_o,
    input wire m_axi_wready_i,
    input wire [3:0] m_axi_bid_i,
    input wire [1:0] m_axi_bresp_i,
    input wire m_axi_bvalid_i,
    output wire m_axi_bready_o,
    output wire [3:0] m_axi_arid_o,
    output wire [31:0] m_axi_araddr_o,
    output wire [7:0] m_axi_arlen_o,
    output wire [2:0] m_axi_arsize_o,
    output wire [1:0] m_axi_arburst_o,
    output wire m_axi_arvalid_o,
    input wire m_axi_arready_i,
    input wire [3:0] m_axi_rid_i,
    input wire [63:0] m_axi_rdata_i,
    input wire [1:0] m_axi_rresp_i,
    input wire m_axi_rlast_i,
    input wire m_axi_rvalid_i,
    output wire m_axi_rready_o
);
    edrv32_async_fifo #(
        .WIDTH(49),
        .DEPTH(2)
    ) u_aw_fifo (
        // AW payload and handshake travel in the same FIFO.
        .clk_write_i(clk_sys_i),
        .rst_write_n_i(rst_sys_n_i),
        .clk_read_i(clk_mem_i),
        .rst_read_n_i(rst_mem_n_i),
        .valid_i(s_axi_awvalid_i),
        .ready_o(s_axi_awready_o),
        .data_i({s_axi_awid_i, s_axi_awaddr_i, s_axi_awlen_i, s_axi_awsize_i, s_axi_awburst_i}),
        .valid_o(m_axi_awvalid_o),
        .ready_i(m_axi_awready_i),
        .data_o({m_axi_awid_o, m_axi_awaddr_o, m_axi_awlen_o, m_axi_awsize_o, m_axi_awburst_o})
    );
    edrv32_async_fifo #(
        .WIDTH(73),
        .DEPTH(2)
    ) u_w_fifo (
        // W payload and handshake travel in the same FIFO.
        .clk_write_i(clk_sys_i),
        .rst_write_n_i(rst_sys_n_i),
        .clk_read_i(clk_mem_i),
        .rst_read_n_i(rst_mem_n_i),
        .valid_i(s_axi_wvalid_i),
        .ready_o(s_axi_wready_o),
        .data_i({s_axi_wdata_i, s_axi_wstrb_i, s_axi_wlast_i}),
        .valid_o(m_axi_wvalid_o),
        .ready_i(m_axi_wready_i),
        .data_o({m_axi_wdata_o, m_axi_wstrb_o, m_axi_wlast_o})
    );
    edrv32_async_fifo #(
        .WIDTH(6),
        .DEPTH(2)
    ) u_b_fifo (
        // B payload and handshake travel in the same FIFO.
        .clk_write_i(clk_mem_i),
        .rst_write_n_i(rst_mem_n_i),
        .clk_read_i(clk_sys_i),
        .rst_read_n_i(rst_sys_n_i),
        .valid_i(m_axi_bvalid_i),
        .ready_o(m_axi_bready_o),
        .data_i({m_axi_bid_i, m_axi_bresp_i}),
        .valid_o(s_axi_bvalid_o),
        .ready_i(s_axi_bready_i),
        .data_o({s_axi_bid_o, s_axi_bresp_o})
    );
    edrv32_async_fifo #(
        .WIDTH(49),
        .DEPTH(2)
    ) u_ar_fifo (
        // AR payload and handshake travel in the same FIFO.
        .clk_write_i(clk_sys_i),
        .rst_write_n_i(rst_sys_n_i),
        .clk_read_i(clk_mem_i),
        .rst_read_n_i(rst_mem_n_i),
        .valid_i(s_axi_arvalid_i),
        .ready_o(s_axi_arready_o),
        .data_i({s_axi_arid_i, s_axi_araddr_i, s_axi_arlen_i, s_axi_arsize_i, s_axi_arburst_i}),
        .valid_o(m_axi_arvalid_o),
        .ready_i(m_axi_arready_i),
        .data_o({m_axi_arid_o, m_axi_araddr_o, m_axi_arlen_o, m_axi_arsize_o, m_axi_arburst_o})
    );
    edrv32_async_fifo #(
        .WIDTH(71),
        .DEPTH(2)
    ) u_r_fifo (
        // R payload and handshake travel in the same FIFO.
        .clk_write_i(clk_mem_i),
        .rst_write_n_i(rst_mem_n_i),
        .clk_read_i(clk_sys_i),
        .rst_read_n_i(rst_sys_n_i),
        .valid_i(m_axi_rvalid_i),
        .ready_o(m_axi_rready_o),
        .data_i({m_axi_rid_i, m_axi_rdata_i, m_axi_rresp_i, m_axi_rlast_i}),
        .valid_o(s_axi_rvalid_o),
        .ready_i(s_axi_rready_i),
        .data_o({s_axi_rid_o, s_axi_rdata_o, s_axi_rresp_o, s_axi_rlast_o})
    );
endmodule
