// File: tb.sv
// Spec: sys-subsys-spec 2.1, 3.1, 5, 6, 7; testplan XB-01..06.
// Description: Self-checking transactions, response scoreboards and protocol assertions.
// Clock domain: clk_sys.
module tb;
    // The generated map also declares constants for other SoC clients.
    /* verilator lint_off UNUSEDPARAM */
    `include "edrv32_soc_map.vh"
    /* verilator lint_on UNUSEDPARAM */
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;
    integer cycles = 0;
    integer checks = 0;
    always @(posedge clk) cycles <= cycles + 1;
    initial begin
        #2000000;
        $fatal(1, "FAIL timeout");
    end
    reg [1:0] [3:0] m_awid;
    reg [1:0] [31:0] m_awaddr;
    reg [1:0] [7:0] m_awlen;
    reg [1:0] [2:0] m_awsize;
    reg [1:0] [1:0] m_awburst;
    reg [1:0] m_awvalid;
    wire [1:0] m_awready;
    reg [1:0] [63:0] m_wdata;
    reg [1:0] [7:0] m_wstrb;
    reg [1:0] m_wlast;
    reg [1:0] m_wvalid;
    wire [1:0] m_wready;
    wire [1:0] [3:0] m_bid;
    wire [1:0] [1:0] m_bresp;
    wire [1:0] m_bvalid;
    reg [1:0] m_bready;
    reg [1:0] [3:0] m_arid;
    reg [1:0] [31:0] m_araddr;
    reg [1:0] [7:0] m_arlen;
    reg [1:0] [2:0] m_arsize;
    reg [1:0] [1:0] m_arburst;
    reg [1:0] m_arvalid;
    wire [1:0] m_arready;
    wire [1:0] [3:0] m_rid;
    wire [1:0] [63:0] m_rdata;
    wire [1:0] [1:0] m_rresp;
    wire [1:0] m_rlast;
    wire [1:0] m_rvalid;
    reg [1:0] m_rready;
    wire [6:0] [3:0] s_awid;
    wire [6:0] [31:0] s_awaddr;
    wire [6:0] [7:0] s_awlen;
    wire [6:0] [2:0] s_awsize;
    wire [6:0] [1:0] s_awburst;
    wire [6:0] s_awvalid;
    wire [6:0] s_awready;
    wire [6:0] [63:0] s_wdata;
    wire [6:0] [7:0] s_wstrb;
    wire [6:0] s_wlast;
    wire [6:0] s_wvalid;
    wire [6:0] s_wready;
    wire [6:0] [3:0] s_bid;
    wire [6:0] [1:0] s_bresp;
    wire [6:0] s_bvalid;
    wire [6:0] s_bready;
    wire [6:0] [3:0] s_arid;
    wire [6:0] [31:0] s_araddr;
    wire [6:0] [7:0] s_arlen;
    wire [6:0] [2:0] s_arsize;
    wire [6:0] [1:0] s_arburst;
    wire [6:0] s_arvalid;
    wire [6:0] s_arready;
    wire [6:0] [3:0] s_rid;
    wire [6:0] [63:0] s_rdata;
    wire [6:0] [1:0] s_rresp;
    wire [6:0] s_rlast;
    wire [6:0] s_rvalid;
    wire [6:0] s_rready;
    reg [6:0] ar_gate = 7'h7f;
    reg other_read_done = 0;
    integer forwarded_reads [0:6];
    integer forwarded_writes [0:6];
    integer first_response [0:1];
    integer read_accept_cycle [0:1];
    integer grants [0:6][0:127];
    integer grant_count [0:6];
    reg [63:0] rom_reference [0:2047];
    reg [63:0] sram_reference [0:EDRV32_SRAM_SIZE/8-1];
    edrv32_bus_sys_xbar dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .m0_arid_i(m_arid[0]),
        .m0_araddr_i(m_araddr[0]),
        .m0_arlen_i(m_arlen[0]),
        .m0_arsize_i(m_arsize[0]),
        .m0_arburst_i(m_arburst[0]),
        .m0_arvalid_i(m_arvalid[0]),
        .m0_arready_o(m_arready[0]),
        .m0_rid_o(m_rid[0]),
        .m0_rdata_o(m_rdata[0]),
        .m0_rresp_o(m_rresp[0]),
        .m0_rlast_o(m_rlast[0]),
        .m0_rvalid_o(m_rvalid[0]),
        .m0_rready_i(m_rready[0]),
        .m1_awid_i(m_awid[1]),
        .m1_awaddr_i(m_awaddr[1]),
        .m1_awlen_i(m_awlen[1]),
        .m1_awsize_i(m_awsize[1]),
        .m1_awburst_i(m_awburst[1]),
        .m1_awvalid_i(m_awvalid[1]),
        .m1_awready_o(m_awready[1]),
        .m1_wdata_i(m_wdata[1]),
        .m1_wstrb_i(m_wstrb[1]),
        .m1_wlast_i(m_wlast[1]),
        .m1_wvalid_i(m_wvalid[1]),
        .m1_wready_o(m_wready[1]),
        .m1_bid_o(m_bid[1]),
        .m1_bresp_o(m_bresp[1]),
        .m1_bvalid_o(m_bvalid[1]),
        .m1_bready_i(m_bready[1]),
        .m1_arid_i(m_arid[1]),
        .m1_araddr_i(m_araddr[1]),
        .m1_arlen_i(m_arlen[1]),
        .m1_arsize_i(m_arsize[1]),
        .m1_arburst_i(m_arburst[1]),
        .m1_arvalid_i(m_arvalid[1]),
        .m1_arready_o(m_arready[1]),
        .m1_rid_o(m_rid[1]),
        .m1_rdata_o(m_rdata[1]),
        .m1_rresp_o(m_rresp[1]),
        .m1_rlast_o(m_rlast[1]),
        .m1_rvalid_o(m_rvalid[1]),
        .m1_rready_i(m_rready[1]),
        .s0_awid_o(s_awid[0]),
        .s0_awaddr_o(s_awaddr[0]),
        .s0_awlen_o(s_awlen[0]),
        .s0_awsize_o(s_awsize[0]),
        .s0_awburst_o(s_awburst[0]),
        .s0_awvalid_o(s_awvalid[0]),
        .s0_awready_i(s_awready[0]),
        .s0_wdata_o(s_wdata[0]),
        .s0_wstrb_o(s_wstrb[0]),
        .s0_wlast_o(s_wlast[0]),
        .s0_wvalid_o(s_wvalid[0]),
        .s0_wready_i(s_wready[0]),
        .s0_bid_i(s_bid[0]),
        .s0_bresp_i(s_bresp[0]),
        .s0_bvalid_i(s_bvalid[0]),
        .s0_bready_o(s_bready[0]),
        .s0_arid_o(s_arid[0]),
        .s0_araddr_o(s_araddr[0]),
        .s0_arlen_o(s_arlen[0]),
        .s0_arsize_o(s_arsize[0]),
        .s0_arburst_o(s_arburst[0]),
        .s0_arvalid_o(s_arvalid[0]),
        .s0_arready_i(s_arready[0]),
        .s0_rid_i(s_rid[0]),
        .s0_rdata_i(s_rdata[0]),
        .s0_rresp_i(s_rresp[0]),
        .s0_rlast_i(s_rlast[0]),
        .s0_rvalid_i(s_rvalid[0]),
        .s0_rready_o(s_rready[0]),
        .s1_awid_o(s_awid[1]),
        .s1_awaddr_o(s_awaddr[1]),
        .s1_awlen_o(s_awlen[1]),
        .s1_awsize_o(s_awsize[1]),
        .s1_awburst_o(s_awburst[1]),
        .s1_awvalid_o(s_awvalid[1]),
        .s1_awready_i(s_awready[1]),
        .s1_wdata_o(s_wdata[1]),
        .s1_wstrb_o(s_wstrb[1]),
        .s1_wlast_o(s_wlast[1]),
        .s1_wvalid_o(s_wvalid[1]),
        .s1_wready_i(s_wready[1]),
        .s1_bid_i(s_bid[1]),
        .s1_bresp_i(s_bresp[1]),
        .s1_bvalid_i(s_bvalid[1]),
        .s1_bready_o(s_bready[1]),
        .s1_arid_o(s_arid[1]),
        .s1_araddr_o(s_araddr[1]),
        .s1_arlen_o(s_arlen[1]),
        .s1_arsize_o(s_arsize[1]),
        .s1_arburst_o(s_arburst[1]),
        .s1_arvalid_o(s_arvalid[1]),
        .s1_arready_i(s_arready[1]),
        .s1_rid_i(s_rid[1]),
        .s1_rdata_i(s_rdata[1]),
        .s1_rresp_i(s_rresp[1]),
        .s1_rlast_i(s_rlast[1]),
        .s1_rvalid_i(s_rvalid[1]),
        .s1_rready_o(s_rready[1]),
        .s2_awid_o(s_awid[2]),
        .s2_awaddr_o(s_awaddr[2]),
        .s2_awlen_o(s_awlen[2]),
        .s2_awsize_o(s_awsize[2]),
        .s2_awburst_o(s_awburst[2]),
        .s2_awvalid_o(s_awvalid[2]),
        .s2_awready_i(s_awready[2]),
        .s2_wdata_o(s_wdata[2]),
        .s2_wstrb_o(s_wstrb[2]),
        .s2_wlast_o(s_wlast[2]),
        .s2_wvalid_o(s_wvalid[2]),
        .s2_wready_i(s_wready[2]),
        .s2_bid_i(s_bid[2]),
        .s2_bresp_i(s_bresp[2]),
        .s2_bvalid_i(s_bvalid[2]),
        .s2_bready_o(s_bready[2]),
        .s2_arid_o(s_arid[2]),
        .s2_araddr_o(s_araddr[2]),
        .s2_arlen_o(s_arlen[2]),
        .s2_arsize_o(s_arsize[2]),
        .s2_arburst_o(s_arburst[2]),
        .s2_arvalid_o(s_arvalid[2]),
        .s2_arready_i(s_arready[2]),
        .s2_rid_i(s_rid[2]),
        .s2_rdata_i(s_rdata[2]),
        .s2_rresp_i(s_rresp[2]),
        .s2_rlast_i(s_rlast[2]),
        .s2_rvalid_i(s_rvalid[2]),
        .s2_rready_o(s_rready[2]),
        .s3_awid_o(s_awid[3]),
        .s3_awaddr_o(s_awaddr[3]),
        .s3_awlen_o(s_awlen[3]),
        .s3_awsize_o(s_awsize[3]),
        .s3_awburst_o(s_awburst[3]),
        .s3_awvalid_o(s_awvalid[3]),
        .s3_awready_i(s_awready[3]),
        .s3_wdata_o(s_wdata[3]),
        .s3_wstrb_o(s_wstrb[3]),
        .s3_wlast_o(s_wlast[3]),
        .s3_wvalid_o(s_wvalid[3]),
        .s3_wready_i(s_wready[3]),
        .s3_bid_i(s_bid[3]),
        .s3_bresp_i(s_bresp[3]),
        .s3_bvalid_i(s_bvalid[3]),
        .s3_bready_o(s_bready[3]),
        .s3_arid_o(s_arid[3]),
        .s3_araddr_o(s_araddr[3]),
        .s3_arlen_o(s_arlen[3]),
        .s3_arsize_o(s_arsize[3]),
        .s3_arburst_o(s_arburst[3]),
        .s3_arvalid_o(s_arvalid[3]),
        .s3_arready_i(s_arready[3]),
        .s3_rid_i(s_rid[3]),
        .s3_rdata_i(s_rdata[3]),
        .s3_rresp_i(s_rresp[3]),
        .s3_rlast_i(s_rlast[3]),
        .s3_rvalid_i(s_rvalid[3]),
        .s3_rready_o(s_rready[3]),
        .s4_awid_o(s_awid[4]),
        .s4_awaddr_o(s_awaddr[4]),
        .s4_awlen_o(s_awlen[4]),
        .s4_awsize_o(s_awsize[4]),
        .s4_awburst_o(s_awburst[4]),
        .s4_awvalid_o(s_awvalid[4]),
        .s4_awready_i(s_awready[4]),
        .s4_wdata_o(s_wdata[4]),
        .s4_wstrb_o(s_wstrb[4]),
        .s4_wlast_o(s_wlast[4]),
        .s4_wvalid_o(s_wvalid[4]),
        .s4_wready_i(s_wready[4]),
        .s4_bid_i(s_bid[4]),
        .s4_bresp_i(s_bresp[4]),
        .s4_bvalid_i(s_bvalid[4]),
        .s4_bready_o(s_bready[4]),
        .s4_arid_o(s_arid[4]),
        .s4_araddr_o(s_araddr[4]),
        .s4_arlen_o(s_arlen[4]),
        .s4_arsize_o(s_arsize[4]),
        .s4_arburst_o(s_arburst[4]),
        .s4_arvalid_o(s_arvalid[4]),
        .s4_arready_i(s_arready[4]),
        .s4_rid_i(s_rid[4]),
        .s4_rdata_i(s_rdata[4]),
        .s4_rresp_i(s_rresp[4]),
        .s4_rlast_i(s_rlast[4]),
        .s4_rvalid_i(s_rvalid[4]),
        .s4_rready_o(s_rready[4]),
        .s5_awid_o(s_awid[5]),
        .s5_awaddr_o(s_awaddr[5]),
        .s5_awlen_o(s_awlen[5]),
        .s5_awsize_o(s_awsize[5]),
        .s5_awburst_o(s_awburst[5]),
        .s5_awvalid_o(s_awvalid[5]),
        .s5_awready_i(s_awready[5]),
        .s5_wdata_o(s_wdata[5]),
        .s5_wstrb_o(s_wstrb[5]),
        .s5_wlast_o(s_wlast[5]),
        .s5_wvalid_o(s_wvalid[5]),
        .s5_wready_i(s_wready[5]),
        .s5_bid_i(s_bid[5]),
        .s5_bresp_i(s_bresp[5]),
        .s5_bvalid_i(s_bvalid[5]),
        .s5_bready_o(s_bready[5]),
        .s5_arid_o(s_arid[5]),
        .s5_araddr_o(s_araddr[5]),
        .s5_arlen_o(s_arlen[5]),
        .s5_arsize_o(s_arsize[5]),
        .s5_arburst_o(s_arburst[5]),
        .s5_arvalid_o(s_arvalid[5]),
        .s5_arready_i(s_arready[5]),
        .s5_rid_i(s_rid[5]),
        .s5_rdata_i(s_rdata[5]),
        .s5_rresp_i(s_rresp[5]),
        .s5_rlast_i(s_rlast[5]),
        .s5_rvalid_i(s_rvalid[5]),
        .s5_rready_o(s_rready[5]),
        .s6_awid_o(s_awid[6]),
        .s6_awaddr_o(s_awaddr[6]),
        .s6_awlen_o(s_awlen[6]),
        .s6_awsize_o(s_awsize[6]),
        .s6_awburst_o(s_awburst[6]),
        .s6_awvalid_o(s_awvalid[6]),
        .s6_awready_i(s_awready[6]),
        .s6_wdata_o(s_wdata[6]),
        .s6_wstrb_o(s_wstrb[6]),
        .s6_wlast_o(s_wlast[6]),
        .s6_wvalid_o(s_wvalid[6]),
        .s6_wready_i(s_wready[6]),
        .s6_bid_i(s_bid[6]),
        .s6_bresp_i(s_bresp[6]),
        .s6_bvalid_i(s_bvalid[6]),
        .s6_bready_o(s_bready[6]),
        .s6_arid_o(s_arid[6]),
        .s6_araddr_o(s_araddr[6]),
        .s6_arlen_o(s_arlen[6]),
        .s6_arsize_o(s_arsize[6]),
        .s6_arburst_o(s_arburst[6]),
        .s6_arvalid_o(s_arvalid[6]),
        .s6_arready_i(s_arready[6]),
        .s6_rid_i(s_rid[6]),
        .s6_rdata_i(s_rdata[6]),
        .s6_rresp_i(s_rresp[6]),
        .s6_rlast_i(s_rlast[6]),
        .s6_rvalid_i(s_rvalid[6]),
        .s6_rready_o(s_rready[6])
    );
    genvar g;
    generate
        for (g = 0; g < 7; g = g + 1) begin : slaves
            wire endpoint_arready;
            wire endpoint_rvalid;
            assign s_arready[g] = endpoint_arready && ar_gate[g];
            assign s_rvalid[g] = endpoint_rvalid;
            if (g == 0) begin : g_memory0
                edrv32_bus_rom u_memory (
                    .clk_i(clk),
                    .rst_n_i(rst_n),
                    .axi_awid_i(s_awid[g]),
                    .axi_awaddr_i(s_awaddr[g]),
                    .axi_awlen_i(s_awlen[g]),
                    .axi_awsize_i(s_awsize[g]),
                    .axi_awburst_i(s_awburst[g]),
                    .axi_awvalid_i(s_awvalid[g]),
                    .axi_awready_o(s_awready[g]),
                    .axi_wdata_i(s_wdata[g]),
                    .axi_wstrb_i(s_wstrb[g]),
                    .axi_wlast_i(s_wlast[g]),
                    .axi_wvalid_i(s_wvalid[g]),
                    .axi_wready_o(s_wready[g]),
                    .axi_bid_o(s_bid[g]),
                    .axi_bresp_o(s_bresp[g]),
                    .axi_bvalid_o(s_bvalid[g]),
                    .axi_bready_i(s_bready[g]),
                    .axi_arid_i(s_arid[g]),
                    .axi_araddr_i(s_araddr[g]),
                    .axi_arlen_i(s_arlen[g]),
                    .axi_arsize_i(s_arsize[g]),
                    .axi_arburst_i(s_arburst[g]),
                    .axi_arvalid_i(s_arvalid[g] && ar_gate[g]),
                    .axi_arready_o(endpoint_arready),
                    .axi_rid_o(s_rid[g]),
                    .axi_rdata_o(s_rdata[g]),
                    .axi_rresp_o(s_rresp[g]),
                    .axi_rlast_o(s_rlast[g]),
                    .axi_rvalid_o(endpoint_rvalid),
                    .axi_rready_i(s_rready[g])
                );
            end else if (g == 1) begin : g_memory1
                edrv32_bus_sram u_memory (
                    .clk_i(clk),
                    .rst_n_i(rst_n),
                    .axi_awid_i(s_awid[g]),
                    .axi_awaddr_i(s_awaddr[g]),
                    .axi_awlen_i(s_awlen[g]),
                    .axi_awsize_i(s_awsize[g]),
                    .axi_awburst_i(s_awburst[g]),
                    .axi_awvalid_i(s_awvalid[g]),
                    .axi_awready_o(s_awready[g]),
                    .axi_wdata_i(s_wdata[g]),
                    .axi_wstrb_i(s_wstrb[g]),
                    .axi_wlast_i(s_wlast[g]),
                    .axi_wvalid_i(s_wvalid[g]),
                    .axi_wready_o(s_wready[g]),
                    .axi_bid_o(s_bid[g]),
                    .axi_bresp_o(s_bresp[g]),
                    .axi_bvalid_o(s_bvalid[g]),
                    .axi_bready_i(s_bready[g]),
                    .axi_arid_i(s_arid[g]),
                    .axi_araddr_i(s_araddr[g]),
                    .axi_arlen_i(s_arlen[g]),
                    .axi_arsize_i(s_arsize[g]),
                    .axi_arburst_i(s_arburst[g]),
                    .axi_arvalid_i(s_arvalid[g] && ar_gate[g]),
                    .axi_arready_o(endpoint_arready),
                    .axi_rid_o(s_rid[g]),
                    .axi_rdata_o(s_rdata[g]),
                    .axi_rresp_o(s_rresp[g]),
                    .axi_rlast_o(s_rlast[g]),
                    .axi_rvalid_o(endpoint_rvalid),
                    .axi_rready_i(s_rready[g])
                );
            end else begin : g_model
                reg rd_active = 0;
                reg wr_active = 0;
                reg b_pending = 0;
                reg [7:0] rd_remain;
                reg [7:0] wr_remain;
                reg [3:0] rd_id;
                reg [3:0] wr_id;
                reg [31:0] rd_addr;
                reg [31:0] rd_step;
                assign endpoint_arready = !rd_active;
                assign endpoint_rvalid = rd_active;
                assign s_rid[g] = rd_id;
                assign s_rdata[g] = {rd_addr,32'h90000000 | 32'(g)};
                assign s_rresp[g] = 0;
                assign s_rlast[g] = (rd_remain == 0);
                assign s_awready[g] = !wr_active && !b_pending;
                assign s_wready[g] = wr_active;
                assign s_bid[g] = wr_id;
                assign s_bresp[g] = 0;
                assign s_bvalid[g] = b_pending;
                always @(posedge clk) begin
                    if (!rst_n) begin
                        rd_active <= 0; wr_active <= 0; b_pending <= 0;
                    end else begin
                        if (s_arvalid[g] && s_arready[g]) begin
                            rd_active <= 1; rd_remain <= s_arlen[g];
                            rd_id <= s_arid[g]; rd_addr <= s_araddr[g];
                            rd_step <= 32'd1 << s_arsize[g];
                        end else if (s_rvalid[g] && s_rready[g]) begin
                            if (rd_remain == 0) rd_active <= 0;
                            else begin rd_remain <= rd_remain - 1'b1; rd_addr <= rd_addr+rd_step; end
                        end
                        if (s_awvalid[g] && s_awready[g]) begin
                            wr_active <= 1; wr_remain <= s_awlen[g]; wr_id <= s_awid[g];
                        end else if (s_wvalid[g] && s_wready[g]) begin
                            if (wr_remain == 0) begin wr_active <= 0; b_pending <= 1; end
                            else wr_remain <= wr_remain - 1'b1;
                        end
                        if (s_bvalid[g] && s_bready[g]) b_pending <= 0;
                    end
                end
            end
            reg stalled_ar = 0;
            reg [48:0] saved_ar;
            always @(posedge clk) begin
                if (rst_n && stalled_ar && (!s_arvalid[g] ||
                    {s_arid[g],s_araddr[g],s_arlen[g],s_arsize[g],s_arburst[g]} !== saved_ar))
                    $fatal(1,"FAIL stalled downstream AR changed target=%0d",g);
                stalled_ar <= rst_n && s_arvalid[g] && !s_arready[g];
                saved_ar <= {s_arid[g],s_araddr[g],s_arlen[g],s_arsize[g],s_arburst[g]};
                if (rst_n && s_arvalid[g] && s_arready[g]) begin
                    forwarded_reads[g] = forwarded_reads[g] + 1;
                    grants[g][grant_count[g]] = (s_arid[g] == 4'ha) ? 0 : 1;
                    grant_count[g] = grant_count[g] + 1;
                end
                if (rst_n && s_awvalid[g] && s_awready[g])
                    forwarded_writes[g] = forwarded_writes[g] + 1;
            end
        end
    endgenerate
    genvar m;
    generate
        for (m = 0; m < 2; m = m + 1) begin : master_checks
            reg held = 0;
            reg [70:0] response;
            always @(posedge clk) begin
                if (rst_n && held && (!m_rvalid[m] ||
                    {m_rid[m],m_rdata[m],m_rresp[m],m_rlast[m]} !== response))
                    $fatal(1,"FAIL upstream R changed under backpressure master=%0d",m);
                held <= rst_n && m_rvalid[m] && !m_rready[m];
                response <= {m_rid[m],m_rdata[m],m_rresp[m],m_rlast[m]};
            end
        end
    endgenerate
    reg held_b = 0;
    reg [5:0] saved_b;
    always @(posedge clk) begin
        if (rst_n && held_b && (!m_bvalid[1] || {m_bid[1],m_bresp[1]} !== saved_b))
            $fatal(1,"FAIL xbar B changed under backpressure");
        held_b <= rst_n && m_bvalid[1] && !m_bready[1];
        saved_b <= {m_bid[1],m_bresp[1]};
    end
    task automatic issue_read(input integer master,input [31:0] addr,input integer len,input [2:0] size);
        begin
            @(negedge clk);
            m_araddr[master] = addr; m_arlen[master] = 8'(len); m_arsize[master] = size;
            m_arburst[master] = 1; m_arid[master] = master == 0 ? 4'ha : 4'hb;
            m_arvalid[master] = 1;
            do @(posedge clk); while (!m_arready[master]);
            read_accept_cycle[master] = cycles;
            @(negedge clk); m_arvalid[master] = 0;
        end
    endtask
    task automatic finish_read(input integer master,input [31:0] addr,input integer len,
        input [2:0] size,input integer target,input integer stall,input integer check_latency);
        integer beat;
        integer previous;
        integer idx;
        reg [63:0] expected;
        begin
            m_rready[master] = 0;
            repeat (stall) @(negedge clk);
            m_rready[master] = 1;
            previous = 0;
            for (beat = 0; beat <= len; beat = beat + 1) begin
                do @(posedge clk); while (!m_rvalid[master]);
                if (beat == 0) begin
                    first_response[master] = cycles;
                    if (check_latency != 0 && cycles-read_accept_cycle[master] > 3)
                        $fatal(1,"FAIL XB-06 latency=%0d",cycles-read_accept_cycle[master]);
                end
                expected = 0;
                if (target == 0) begin
                    idx = int'((addr+(32'(beat)<<size)) >> 3);
                    expected = rom_reference[idx];
                end else if (target == 1) begin
                    idx = int'((addr-32'h10000000+(32'(beat)<<size)) >> 3);
                    expected = sram_reference[idx];
                end else if (target != 7) begin
                    expected = {addr+(32'(beat)<<size),32'h90000000 | 32'(target)};
                end
                if (m_rid[master] !== (master == 0 ? 4'ha : 4'hb) ||
                    m_rresp[master] !== (target == 7 ? 2'b11 : 2'b00) ||
                    m_rdata[master] !== expected || m_rlast[master] !== (beat == len))
                    begin
                        $display("DETAIL t=%0t accepted=%0d issued=%b target0=%d target1=%d araddr0=%h araddr1=%h",
                            $time,read_accept_cycle[master],dut.read_issued_r,
                            dut.read_target_r[0],dut.read_target_r[1],dut.read_addr_r[0],dut.read_addr_r[1]);
                        $display("DETAIL SRAM addr=%h data=%h mem0=%h mem1=%h state=%d ref0=%h",
                            slaves[1].g_memory1.u_memory.addr_r,s_rdata[1],
                            slaves[1].g_memory1.u_memory.u_memory.memory_r[0],
                            slaves[1].g_memory1.u_memory.u_memory.memory_r[1],
                            slaves[1].g_memory1.u_memory.state_r,sram_reference[0]);
                        $fatal(1,"FAIL xbar read master=%0d addr=%h beat=%0d exp=%h got=%h resp=%h",
                            master,addr,beat,expected,m_rdata[master],m_rresp[master]);
                    end
                if (len == 3 && target == 1 && stall == 0 && beat > 0 && cycles != previous+1)
                    $fatal(1,"FAIL SRAM burst bubble");
                previous = cycles; checks = checks+1;
                @(negedge clk);
                if (stall != 0 && beat < len) begin
                    m_rready[master] = 0;
                    repeat (stall) @(negedge clk);
                    m_rready[master] = 1;
                end
            end
            m_rready[master] = 0;
        end
    endtask
    task automatic read_check(input integer master,input [31:0] addr,input integer len,
        input [2:0] size,input integer target,input integer stall,input integer latency);
        begin
            issue_read(master,addr,len,size);
            finish_read(master,addr,len,size,target,stall,latency);
        end
    endtask
    task automatic write_check(input [31:0] addr,input integer len,input integer target);
        integer beat;
        reg [1:0] expected_resp;
        begin
            expected_resp = target == 7 ? 2'b11 : (target == 0 ? 2'b10 : 2'b00);
            @(negedge clk);
            m_awaddr[1] = addr; m_awlen[1] = 8'(len); m_awsize[1] = len == 0 ? 2 : 3;
            m_awburst[1] = 1; m_awid[1] = 4'h7; m_awvalid[1] = 1;
            m_wdata[1] = 64'hffeeddccbbaa9988; m_wstrb[1] = 8'hff;
            m_wvalid[1] = 1; m_wlast[1] = (len == 0);
            do @(posedge clk); while (!m_awready[1]);
            @(negedge clk); m_awvalid[1] = 0;
            for (beat = 0; beat <= len; beat = beat + 1) begin
                m_wvalid[1] = 1; m_wlast[1] = (beat == len);
                do @(posedge clk); while (!m_wready[1]);
                if (beat < len && m_bvalid[1]) $fatal(1,"FAIL xbar B before all W");
                if (target == 1) sram_reference[int'((addr-32'h10000000)>>3)+beat] = m_wdata[1];
                @(negedge clk); m_wvalid[1] = 0;
                if (beat < len) repeat (2) @(negedge clk);
            end
            repeat (3) @(negedge clk);
            m_bready[1] = 1;
            do @(posedge clk); while (!m_bvalid[1]);
            if (m_bid[1] !== 7 || m_bresp[1] !== expected_resp)
                $fatal(1,"FAIL xbar write addr=%h exp=%h got=%h",addr,expected_resp,m_bresp[1]);
            checks = checks+1;
            @(negedge clk); m_bready[1] = 0;
        end
    endtask
    reg [31:0] starts [0:7];
    reg [31:0] ends [0:7];
    integer i;
    integer j;
    integer before_reads;
    integer before_writes;
    integer before_grants;
    integer target;
    initial begin
        m_awid[0] = 0; m_awid[1] = 0;
        m_awaddr[0] = 0; m_awaddr[1] = 0;
        m_awlen[0] = 0; m_awlen[1] = 0;
        m_awsize[0] = 0; m_awsize[1] = 0;
        m_awburst[0] = 0; m_awburst[1] = 0;
        m_awvalid[0] = 0; m_awvalid[1] = 0;
        m_wdata[0] = 0; m_wdata[1] = 0;
        m_wstrb[0] = 0; m_wstrb[1] = 0;
        m_wlast[0] = 0; m_wlast[1] = 0;
        m_wvalid[0] = 0; m_wvalid[1] = 0;
        m_bready[0] = 0; m_bready[1] = 0;
        m_arid[0] = 0; m_arid[1] = 0;
        m_araddr[0] = 0; m_araddr[1] = 0;
        m_arlen[0] = 0; m_arlen[1] = 0;
        m_arsize[0] = 0; m_arsize[1] = 0;
        m_arburst[0] = 0; m_arburst[1] = 0;
        m_arvalid[0] = 0; m_arvalid[1] = 0;
        m_rready[0] = 0; m_rready[1] = 0;
        for (i=0;i<7;i=i+1) begin forwarded_reads[i]=0; forwarded_writes[i]=0; grant_count[i]=0; end
        starts[0]=32'h00000000; ends[0]=32'h00003fff;
        starts[1]=32'h10000000; ends[1]=EDRV32_SRAM_BASE + EDRV32_SRAM_SIZE - 1;
        starts[2]=32'h20000000; ends[2]=32'h2000ffff;
        starts[3]=32'h30000000; ends[3]=32'h303fffff;
        starts[4]=32'h40000000; ends[4]=32'h4000ffff;
        starts[5]=32'h41000000; ends[5]=32'h4100ffff;
        starts[6]=32'h80000000; ends[6]=32'hbfffffff;
        starts[7]=32'hc0000000; ends[7]=32'hffffffff;
        $readmemh("verif/unit/bus_rom/init.hex",rom_reference);
        $readmemh("verif/unit/bus_sram/init.hex",sram_reference);
        $readmemh("verif/unit/bus_rom/init.hex",slaves[0].g_memory0.u_memory.u_memory.memory_r);
        $readmemh("verif/unit/bus_sram/init.hex",slaves[1].g_memory1.u_memory.u_memory.memory_r);
        repeat (3) @(negedge clk); rst_n = 1;
        // XB-01/02/06: first/last bytes, every target, both DDR windows and forbidden M0 paths.
        for (i=0;i<8;i=i+1) begin
            for (j=0;j<2;j=j+1) begin
                before_reads = forwarded_reads[i < 7 ? i : 6];
                read_check(j,starts[i],0,0,(j==0 && i>=2 && i<=5) ? 7 : (i<7?i:6),0,(i<2?1:0));
                read_check(j,ends[i],0,0,(j==0 && i>=2 && i<=5) ? 7 : (i<7?i:6),2,0);
                if (forwarded_reads[i<7?i:6]-before_reads != ((j==0&&i>=2&&i<=5)?0:2))
                    $fatal(1,"FAIL forwarding count on target=%0d master=%0d",i,j);
            end
        end
        for (i=2;i<=5;i=i+1) read_check(0,starts[i],3,3,7,2,0);
        for (i=0;i<7;i=i+1) begin
            before_writes=forwarded_writes[i];
            write_check(starts[i],0,i);
            if (forwarded_writes[i]-before_writes != 1) $fatal(1,"FAIL AW route target=%0d",i);
        end
        write_check(32'hc0000000,3,6);
        // XB-03: unmapped boundaries and max LEN; nothing reaches a slave.
        for (i=0;i<7;i=i+1) begin
            if (i<6) begin
                read_check(0,ends[i]+1,3,3,7,1,0);
                write_check(ends[i]+1,3,7);
            end
        end
        read_check(1,32'h70000000,255,0,7,1,0);
        write_check(32'h70000000,255,7);
        read_check(1,32'h10000000,3,3,1,0,1);
        // XB-04: every shared target grants complete bursts alternately to both masters.
        for (j=0;j<3;j=j+1) begin
            target = j == 2 ? 6 : j;
            before_grants=grant_count[target];
            for (i=0;i<6;i=i+1) begin
                fork
                    read_check(0,starts[target],3,3,target,1,0);
                    read_check(1,starts[target],3,3,target,1,0);
                join
            end
            if (grant_count[target] - before_grants != 12)
                $fatal(1,"FAIL arbitration grant count target=%0d",target);
            for (i=1;i<12;i=i+1) begin
                if (grants[target][before_grants+i] == grants[target][before_grants+i-1])
                    $fatal(1,"FAIL round-robin arbitration target=%0d",target);
            end
        end
        // XB-05: a stalled SRAM slave cannot block ROM or a concurrent M1 write elsewhere.
        ar_gate[1]=0;
        fork
            begin
                issue_read(0,32'h10000000,0,2);
                finish_read(0,32'h10000000,0,2,1,0,0);
            end
            begin
                repeat(2) @(negedge clk);
                read_check(1,32'h00000000,0,3,0,0,1);
                write_check(32'h20000000,3,2);
                ar_gate[1]=1;
            end
        join
        // The first contender remains selected while ARREADY is low and a second arrives.
        ar_gate[1]=0;
        fork
            begin
                issue_read(0,32'h10000000,0,2);
                finish_read(0,32'h10000000,0,2,1,0,0);
            end
            begin
                repeat(5) @(negedge clk);
                issue_read(1,32'h10000008,0,2);
                repeat(5) @(negedge clk);
                ar_gate[1]=1;
                finish_read(1,32'h10000008,0,2,1,1,0);
            end
        join
        // Response backpressure on one target leaves the other target available.
        other_read_done = 0;
        fork
            begin
                issue_read(0,32'h10000000,3,3);
                // Keep M0 RREADY low until the other target has finished its entire burst.
                wait (other_read_done);
                finish_read(0,32'h10000000,3,3,1,0,0);
            end
            begin
                read_check(1,32'h00000000,3,3,0,0,1);
                other_read_done = 1;
            end
        join
        // Independent xbar read/write ownership reaches the single-port SRAM arbiter.
        fork
            read_check(0,32'h10000000,3,3,1,2,0);
            write_check(32'h10000000,3,1);
        join
        read_check(1,32'h10000000,3,3,1,0,1);
        // Reset discards an in-flight blocked route, then the same route is reusable.
        ar_gate[1] = 0;
        issue_read(0,32'h10000000,0,2);
        repeat (3) @(negedge clk);
        #1 rst_n = 0;
        #1;
        if (m_rvalid[0] !== 0 || m_rvalid[1] !== 0 || m_bvalid[1] !== 0 || s_arvalid[1] !== 0)
            $fatal(1,"FAIL crossbar asynchronous reset");
        repeat (3) @(negedge clk); rst_n = 1; ar_gate[1] = 1;
        read_check(0,32'h10000000,0,2,1,0,1);
        $display("PASS crossbar checks=%0d",checks);
        $finish;
    end
endmodule
