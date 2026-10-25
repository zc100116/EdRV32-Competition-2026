// ============================================================================
// File        : tb_ddr_cpu_interconnect.sv
// Description : Synthetic I-cache/D-cache masters through the existing 64-bit
//               System AXI fabric and the 64-to-256 DDR Gateway.
// ============================================================================

`timescale 1ns/1ps
`include "edrv32_axi4.vh"

module tb_ddr_cpu_interconnect;

    localparam integer NUM_M = 2;
    localparam integer NUM_S = 1;
    localparam integer S_ID_W = `AXI_ID_W + 1;

    reg clk_r;
    reg rst_n_r;

    reg [`AXI_ID_W-1:0] m0_arid_r;
    reg [31:0] m0_araddr_r;
    reg [`AXI_LEN_W-1:0] m0_arlen_r;
    reg [2:0] m0_arsize_r;
    reg [1:0] m0_arburst_r;
    reg m0_arvalid_r;
    wire m0_arready_w;
    wire [`AXI_ID_W-1:0] m0_rid_w;
    wire [63:0] m0_rdata_w;
    wire [1:0] m0_rresp_w;
    wire m0_rlast_w;
    wire m0_rvalid_w;
    reg m0_rready_r;

    reg [`AXI_ID_W-1:0] m1_awid_r;
    reg [31:0] m1_awaddr_r;
    reg [`AXI_LEN_W-1:0] m1_awlen_r;
    reg [2:0] m1_awsize_r;
    reg [1:0] m1_awburst_r;
    reg m1_awvalid_r;
    wire m1_awready_w;
    reg [63:0] m1_wdata_r;
    reg [7:0] m1_wstrb_r;
    reg m1_wlast_r;
    reg m1_wvalid_r;
    wire m1_wready_w;
    wire [`AXI_ID_W-1:0] m1_bid_w;
    wire [1:0] m1_bresp_w;
    wire m1_bvalid_w;
    reg m1_bready_r;
    reg [`AXI_ID_W-1:0] m1_arid_r;
    reg [31:0] m1_araddr_r;
    reg [`AXI_LEN_W-1:0] m1_arlen_r;
    reg [2:0] m1_arsize_r;
    reg [1:0] m1_arburst_r;
    reg m1_arvalid_r;
    wire m1_arready_w;
    wire [`AXI_ID_W-1:0] m1_rid_w;
    wire [63:0] m1_rdata_w;
    wire [1:0] m1_rresp_w;
    wire m1_rlast_w;
    wire m1_rvalid_w;
    reg m1_rready_r;

    wire [NUM_M-1:0] m_arready_w;
    wire [NUM_M*`AXI_ID_W-1:0] m_rid_w;
    wire [NUM_M*64-1:0] m_rdata_w;
    wire [NUM_M*2-1:0] m_rresp_w;
    wire [NUM_M-1:0] m_rlast_w;
    wire [NUM_M-1:0] m_rvalid_w;
    wire [NUM_M-1:0] m_awready_w;
    wire [NUM_M-1:0] m_wready_w;
    wire [NUM_M*`AXI_ID_W-1:0] m_bid_w;
    wire [NUM_M*2-1:0] m_bresp_w;
    wire [NUM_M-1:0] m_bvalid_w;

    wire [S_ID_W-1:0] s_awid_w;
    wire [31:0] s_awaddr_w;
    wire [7:0] s_awlen_w;
    wire [2:0] s_awsize_w;
    wire [1:0] s_awburst_w;
    wire s_awvalid_w;
    wire s_awready_w;
    wire [63:0] s_wdata_w;
    wire [7:0] s_wstrb_w;
    wire s_wlast_w;
    wire s_wvalid_w;
    wire s_wready_w;
    wire [S_ID_W-1:0] s_bid_w;
    wire [1:0] s_bresp_w;
    wire s_bvalid_w;
    wire s_bready_w;
    wire [S_ID_W-1:0] s_arid_w;
    wire [31:0] s_araddr_w;
    wire [7:0] s_arlen_w;
    wire [2:0] s_arsize_w;
    wire [1:0] s_arburst_w;
    wire s_arvalid_w;
    wire s_arready_w;
    wire [S_ID_W-1:0] s_rid_w;
    wire [63:0] s_rdata_w;
    wire [1:0] s_rresp_w;
    wire s_rlast_w;
    wire s_rvalid_w;
    wire s_rready_w;

    wire [3:0] d_awid_w;
    wire [31:0] d_awaddr_w;
    wire [7:0] d_awlen_w;
    wire [2:0] d_awsize_w;
    wire [1:0] d_awburst_w;
    wire d_awvalid_w;
    wire d_awready_w;
    wire [255:0] d_wdata_w;
    wire [31:0] d_wstrb_w;
    wire d_wlast_w;
    wire d_wvalid_w;
    wire d_wready_w;
    wire [3:0] d_bid_w;
    wire [1:0] d_bresp_w;
    wire d_bvalid_w;
    wire d_bready_w;
    wire [3:0] d_arid_w;
    wire [31:0] d_araddr_w;
    wire [7:0] d_arlen_w;
    wire [2:0] d_arsize_w;
    wire [1:0] d_arburst_w;
    wire d_arvalid_w;
    wire d_arready_w;
    wire [3:0] d_rid_w;
    wire [255:0] d_rdata_w;
    wire [1:0] d_rresp_w;
    wire d_rlast_w;
    wire d_rvalid_w;
    wire d_rready_w;
    wire gateway_error_w;

    always #5 clk_r = ~clk_r;

    assign m0_arready_w = m_arready_w[0];
    assign m0_rid_w = m_rid_w[0 +: `AXI_ID_W];
    assign m0_rdata_w = m_rdata_w[0 +: 64];
    assign m0_rresp_w = m_rresp_w[0 +: 2];
    assign m0_rlast_w = m_rlast_w[0];
    assign m0_rvalid_w = m_rvalid_w[0];
    assign m1_arready_w = m_arready_w[1];
    assign m1_rid_w = m_rid_w[`AXI_ID_W +: `AXI_ID_W];
    assign m1_rdata_w = m_rdata_w[64 +: 64];
    assign m1_rresp_w = m_rresp_w[2 +: 2];
    assign m1_rlast_w = m_rlast_w[1];
    assign m1_rvalid_w = m_rvalid_w[1];
    assign m1_awready_w = m_awready_w[1];
    assign m1_wready_w = m_wready_w[1];
    assign m1_bid_w = m_bid_w[`AXI_ID_W +: `AXI_ID_W];
    assign m1_bresp_w = m_bresp_w[2 +: 2];
    assign m1_bvalid_w = m_bvalid_w[1];

    axi_interconnect #(
        .NUM_M(NUM_M), .NUM_S(NUM_S), .M_MAX_OUTSTANDING(1),
        .S_MAX_WR(1), .RD_TIMEOUT_CYCLES(32'd1024),
        .WR_TIMEOUT_CYCLES(32'd1024), .AXI_MON_ENABLE(1)
    ) u_system_axi (
        .clk(clk_r), .rst_n(rst_n_r),
        .m_arid_i({m1_arid_r, m0_arid_r}),
        .m_araddr_i({m1_araddr_r, m0_araddr_r}),
        .m_arlen_i({m1_arlen_r, m0_arlen_r}),
        .m_arsize_i({m1_arsize_r, m0_arsize_r}),
        .m_arburst_i({m1_arburst_r, m0_arburst_r}),
        .m_arvalid_i({m1_arvalid_r, m0_arvalid_r}),
        .m_arready_o(m_arready_w), .m_rid_o(m_rid_w),
        .m_rdata_o(m_rdata_w), .m_rresp_o(m_rresp_w),
        .m_rlast_o(m_rlast_w), .m_rvalid_o(m_rvalid_w),
        .m_rready_i({m1_rready_r, m0_rready_r}),
        .m_awid_i({m1_awid_r, {`AXI_ID_W{1'b0}}}),
        .m_awaddr_i({m1_awaddr_r, 32'b0}),
        .m_awlen_i({m1_awlen_r, 8'b0}),
        .m_awsize_i({m1_awsize_r, 3'b0}),
        .m_awburst_i({m1_awburst_r, 2'b0}),
        .m_awvalid_i({m1_awvalid_r, 1'b0}),
        .m_awready_o(m_awready_w),
        .m_wdata_i({m1_wdata_r, 64'b0}),
        .m_wstrb_i({m1_wstrb_r, 8'b0}),
        .m_wlast_i({m1_wlast_r, 1'b0}),
        .m_wvalid_i({m1_wvalid_r, 1'b0}),
        .m_wready_o(m_wready_w), .m_bid_o(m_bid_w),
        .m_bresp_o(m_bresp_w), .m_bvalid_o(m_bvalid_w),
        .m_bready_i({m1_bready_r, 1'b0}),
        .s_base_i(32'h8000_0000), .s_limit_i(32'h0000_0000),
        .m_read_connect_i(2'b11), .m_write_connect_i(2'b10),
        .s_arid_o(s_arid_w), .s_araddr_o(s_araddr_w),
        .s_arlen_o(s_arlen_w), .s_arsize_o(s_arsize_w),
        .s_arburst_o(s_arburst_w), .s_arvalid_o(s_arvalid_w),
        .s_arready_i(s_arready_w), .s_rid_i(s_rid_w),
        .s_rdata_i(s_rdata_w), .s_rresp_i(s_rresp_w),
        .s_rlast_i(s_rlast_w), .s_rvalid_i(s_rvalid_w),
        .s_rready_o(s_rready_w), .s_awid_o(s_awid_w),
        .s_awaddr_o(s_awaddr_w), .s_awlen_o(s_awlen_w),
        .s_awsize_o(s_awsize_w), .s_awburst_o(s_awburst_w),
        .s_awvalid_o(s_awvalid_w), .s_awready_i(s_awready_w),
        .s_wdata_o(s_wdata_w), .s_wstrb_o(s_wstrb_w),
        .s_wlast_o(s_wlast_w), .s_wvalid_o(s_wvalid_w),
        .s_wready_i(s_wready_w), .s_bid_i(s_bid_w),
        .s_bresp_i(s_bresp_w), .s_bvalid_i(s_bvalid_w),
        .s_bready_o(s_bready_w), .fs_rd_fail_o(), .fs_rd_addr_o(),
        .fs_rd_id_o(), .fs_wr_fail_o(), .fs_wr_addr_o(), .fs_wr_id_o(),
        .mon_rd_beats_o(), .mon_rd_bursts_o(), .mon_rd_err_o(),
        .mon_rd_maxwait_o(), .mon_wr_beats_o(), .mon_wr_bursts_o(),
        .mon_wr_err_o(), .mon_wr_maxwait_o()
    );

    edrv32_axi_ddr_gateway #(.S_ID_W(S_ID_W), .M_ID_W(4)) u_gateway (
        .clk_i(clk_r), .rst_n_i(rst_n_r),
        .s_awid_i(s_awid_w), .s_awaddr_i(s_awaddr_w), .s_awlen_i(s_awlen_w),
        .s_awsize_i(s_awsize_w), .s_awburst_i(s_awburst_w),
        .s_awvalid_i(s_awvalid_w), .s_awready_o(s_awready_w),
        .s_wdata_i(s_wdata_w), .s_wstrb_i(s_wstrb_w), .s_wlast_i(s_wlast_w),
        .s_wvalid_i(s_wvalid_w), .s_wready_o(s_wready_w),
        .s_bid_o(s_bid_w), .s_bresp_o(s_bresp_w), .s_bvalid_o(s_bvalid_w),
        .s_bready_i(s_bready_w), .s_arid_i(s_arid_w),
        .s_araddr_i(s_araddr_w), .s_arlen_i(s_arlen_w),
        .s_arsize_i(s_arsize_w), .s_arburst_i(s_arburst_w),
        .s_arvalid_i(s_arvalid_w), .s_arready_o(s_arready_w),
        .s_rid_o(s_rid_w), .s_rdata_o(s_rdata_w), .s_rresp_o(s_rresp_w),
        .s_rlast_o(s_rlast_w), .s_rvalid_o(s_rvalid_w), .s_rready_i(s_rready_w),
        .m_awid_o(d_awid_w), .m_awaddr_o(d_awaddr_w), .m_awlen_o(d_awlen_w),
        .m_awsize_o(d_awsize_w), .m_awburst_o(d_awburst_w), .m_awqos_o(),
        .m_awvalid_o(d_awvalid_w), .m_awready_i(d_awready_w),
        .m_wdata_o(d_wdata_w), .m_wstrb_o(d_wstrb_w), .m_wlast_o(d_wlast_w),
        .m_wvalid_o(d_wvalid_w), .m_wready_i(d_wready_w),
        .m_bid_i(d_bid_w), .m_bresp_i(d_bresp_w), .m_bvalid_i(d_bvalid_w),
        .m_bready_o(d_bready_w), .m_arid_o(d_arid_w),
        .m_araddr_o(d_araddr_w), .m_arlen_o(d_arlen_w),
        .m_arsize_o(d_arsize_w), .m_arburst_o(d_arburst_w), .m_arqos_o(),
        .m_arvalid_o(d_arvalid_w), .m_arready_i(d_arready_w),
        .m_rid_i(d_rid_w), .m_rdata_i(d_rdata_w), .m_rresp_i(d_rresp_w),
        .m_rlast_i(d_rlast_w), .m_rvalid_i(d_rvalid_w),
        .m_rready_o(d_rready_w), .protocol_error_o(gateway_error_w)
    );

    axi256_mem_model #(.ID_W(4), .WORDS(4096)) u_memory (
        .clk_i(clk_r), .rst_n_i(rst_n_r),
        .awid_i(d_awid_w), .awaddr_i(d_awaddr_w), .awlen_i(d_awlen_w),
        .awsize_i(d_awsize_w), .awburst_i(d_awburst_w),
        .awvalid_i(d_awvalid_w), .awready_o(d_awready_w),
        .wdata_i(d_wdata_w), .wstrb_i(d_wstrb_w), .wlast_i(d_wlast_w),
        .wvalid_i(d_wvalid_w), .wready_o(d_wready_w),
        .bid_o(d_bid_w), .bresp_o(d_bresp_w), .bvalid_o(d_bvalid_w),
        .bready_i(d_bready_w), .arid_i(d_arid_w), .araddr_i(d_araddr_w),
        .arlen_i(d_arlen_w), .arsize_i(d_arsize_w),
        .arburst_i(d_arburst_w), .arvalid_i(d_arvalid_w),
        .arready_o(d_arready_w), .rid_o(d_rid_w), .rdata_o(d_rdata_w),
        .rresp_o(d_rresp_w), .rlast_o(d_rlast_w), .rvalid_o(d_rvalid_w),
        .rready_i(d_rready_w)
    );

    function [63:0] beat_data;
        input [31:0] seed;
        input integer index;
        input [2:0] size;
        input [2:0] lane;
        reg [63:0] value;
        begin
            value = {seed + index, seed ^ index};
            if (size == 3'd3)
                beat_data = value;
            else
                beat_data = ({32'b0, value[31:0]} << (lane * 8));
        end
    endfunction

    task write_m1;
        input [31:0] addr;
        input integer beats;
        input [2:0] size;
        input [31:0] seed;
        integer index;
        reg [31:0] beat_addr;
        begin
            @(posedge clk_r);
            m1_awid_r <= 4'h6;
            m1_awaddr_r <= addr;
            m1_awlen_r <= beats - 1;
            m1_awsize_r <= size;
            m1_awburst_r <= 2'b01;
            m1_awvalid_r <= 1'b1;
            do @(posedge clk_r); while (!m1_awready_w);
            m1_awvalid_r <= 1'b0;

            index = 0;
            beat_addr = addr;
            while (index < beats) begin
                m1_wdata_r <= beat_data(seed, index, size, beat_addr[2:0]);
                m1_wstrb_r <= ((8'h01 << (1 << size)) - 1) << beat_addr[2:0];
                m1_wlast_r <= index == beats - 1;
                m1_wvalid_r <= 1'b1;
                do @(posedge clk_r); while (!m1_wready_w);
                index = index + 1;
                beat_addr = beat_addr + (1 << size);
            end
            m1_wvalid_r <= 1'b0;
            m1_wlast_r <= 1'b0;
            while (!m1_bvalid_w)
                @(posedge clk_r);
            if ((m1_bid_w !== 4'h6) || (m1_bresp_w !== 2'b00))
                $fatal(1, "M1 write response id=%h resp=%h", m1_bid_w, m1_bresp_w);
            @(posedge clk_r);
        end
    endtask

    task read_m0;
        input [31:0] addr;
        input integer beats;
        input [2:0] size;
        input [31:0] seed;
        integer index;
        reg [31:0] beat_addr;
        begin
            @(posedge clk_r);
            m0_arid_r <= 4'h2;
            m0_araddr_r <= addr;
            m0_arlen_r <= beats - 1;
            m0_arsize_r <= size;
            m0_arburst_r <= 2'b01;
            m0_arvalid_r <= 1'b1;
            do @(posedge clk_r); while (!m0_arready_w);
            m0_arvalid_r <= 1'b0;
            index = 0;
            beat_addr = addr;
            while (index < beats) begin
                @(posedge clk_r);
                if (m0_rvalid_w) begin
                    if ((m0_rid_w !== 4'h2) || (m0_rresp_w !== 2'b00) ||
                        (m0_rdata_w !== beat_data(seed, index, size,
                                                 beat_addr[2:0])) ||
                        (m0_rlast_w !== (index == beats - 1)))
                        $fatal(1, "M0 read mismatch beat=%0d id=%h resp=%h data=%h",
                               index, m0_rid_w, m0_rresp_w, m0_rdata_w);
                    index = index + 1;
                    beat_addr = beat_addr + (1 << size);
                end
            end
        end
    endtask

    initial begin
        clk_r = 0;
        rst_n_r = 0;
        m0_arid_r = 0; m0_araddr_r = 0; m0_arlen_r = 0;
        m0_arsize_r = 0; m0_arburst_r = 0; m0_arvalid_r = 0;
        m0_rready_r = 1;
        m1_awid_r = 0; m1_awaddr_r = 0; m1_awlen_r = 0;
        m1_awsize_r = 0; m1_awburst_r = 0; m1_awvalid_r = 0;
        m1_wdata_r = 0; m1_wstrb_r = 0; m1_wlast_r = 0; m1_wvalid_r = 0;
        m1_bready_r = 1;
        m1_arid_r = 0; m1_araddr_r = 0; m1_arlen_r = 0;
        m1_arsize_r = 0; m1_arburst_r = 0; m1_arvalid_r = 0;
        m1_rready_r = 1;
        repeat (6) @(posedge clk_r);
        rst_n_r = 1;

        write_m1(32'hc000_0020, 8, 3'd3, 32'h1234_0000);
        read_m0 (32'h8000_0020, 8, 3'd3, 32'h1234_0000);
        write_m1(32'hc000_0104, 4, 3'd2, 32'h5678_0000);
        read_m0 (32'h8000_0104, 4, 3'd2, 32'h5678_0000);
        // Sixty-four 64-bit beats pack into the maximum legal sixteen
        // 256-bit beats on the restricted DDR-facing AXI profile.
        write_m1(32'hc000_1000, 64, 3'd3, 32'h9abc_0000);
        read_m0 (32'h8000_1000, 64, 3'd3, 32'h9abc_0000);

        if (gateway_error_w)
            $fatal(1, "Gateway protocol error");
        $display("DDR_CPU_INTERCONNECT_PASS");
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "DDR CPU interconnect timeout");
    end

endmodule
