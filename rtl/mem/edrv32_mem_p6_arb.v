// File: edrv32_mem_p6_arb.v
// Spec: mem-subsys-spec 2.4; edrv32-soc-spec 4.2
// Description: Independent transaction round robin for ETH and PERF_MON.
//              The accepted AW owns W until its last transfer.
// Clock: clk_i (clk_mem).
module edrv32_mem_p6_arb (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Upstream PERF_MON AXI256 master.
    input wire pmon_awid_i,
    input wire [31:0] pmon_awaddr_i,
    input wire [3:0] pmon_awlen_i,
    input wire pmon_awvalid_i,
    output wire pmon_awready_o,
    input wire [255:0] pmon_wdata_i,
    input wire [31:0] pmon_wstrb_i,
    input wire pmon_wlast_i,
    input wire pmon_wvalid_i,
    output wire pmon_wready_o,
    output wire pmon_bid_o,
    output wire [1:0] pmon_bresp_o,
    output wire pmon_bvalid_o,
    input wire pmon_bready_i,
    input wire pmon_arid_i,
    input wire [31:0] pmon_araddr_i,
    input wire [3:0] pmon_arlen_i,
    input wire pmon_arvalid_i,
    output wire pmon_arready_o,
    output wire pmon_rid_o,
    output wire [255:0] pmon_rdata_o,
    output wire [1:0] pmon_rresp_o,
    output wire pmon_rlast_o,
    output wire pmon_rvalid_o,
    input wire pmon_rready_i,

    // Upstream ETH AXI256 master.
    input wire eth_awid_i,
    input wire [31:0] eth_awaddr_i,
    input wire [3:0] eth_awlen_i,
    input wire eth_awvalid_i,
    output wire eth_awready_o,
    input wire [255:0] eth_wdata_i,
    input wire [31:0] eth_wstrb_i,
    input wire eth_wlast_i,
    input wire eth_wvalid_i,
    output wire eth_wready_o,
    output wire eth_bid_o,
    output wire [1:0] eth_bresp_o,
    output wire eth_bvalid_o,
    input wire eth_bready_i,
    input wire eth_arid_i,
    input wire [31:0] eth_araddr_i,
    input wire [3:0] eth_arlen_i,
    input wire eth_arvalid_i,
    output wire eth_arready_o,
    output wire eth_rid_o,
    output wire [255:0] eth_rdata_o,
    output wire [1:0] eth_rresp_o,
    output wire eth_rlast_o,
    output wire eth_rvalid_o,
    input wire eth_rready_i,

    // Downstream shared P6 AXI256 port.
    output wire p6_awid_o,
    output wire [31:0] p6_awaddr_o,
    output wire [3:0] p6_awlen_o,
    output wire p6_awvalid_o,
    input wire p6_awready_i,
    output wire [255:0] p6_wdata_o,
    output wire [31:0] p6_wstrb_o,
    output wire p6_wlast_o,
    output wire p6_wvalid_o,
    input wire p6_wready_i,
    input wire p6_bid_i,
    input wire [1:0] p6_bresp_i,
    input wire p6_bvalid_i,
    output wire p6_bready_o,
    output wire p6_arid_o,
    output wire [31:0] p6_araddr_o,
    output wire [3:0] p6_arlen_o,
    output wire p6_arvalid_o,
    input wire p6_arready_i,
    input wire p6_rid_i,
    input wire [255:0] p6_rdata_i,
    input wire [1:0] p6_rresp_i,
    input wire p6_rlast_i,
    input wire p6_rvalid_i,
    output wire p6_rready_o
);
    reg ar_turn_r;
    reg ar_locked_r;
    reg ar_owner_r;
    reg aw_turn_r;
    reg aw_locked_r;
    reg aw_owner_r;
    reg w_busy_r;
    reg w_owner_r;
    wire ar_owner_w;
    wire aw_owner_w;
    wire ar_fire_w;
    wire aw_fire_w;
    wire w_last_w;
    wire unused_w;

    assign unused_w = ^{pmon_awid_i, pmon_arid_i, eth_awid_i, eth_arid_i};
    assign ar_owner_w = ar_locked_r ? ar_owner_r :
        (eth_arvalid_i && (!pmon_arvalid_i || ar_turn_r));
    assign aw_owner_w = aw_locked_r ? aw_owner_r :
        (eth_awvalid_i && (!pmon_awvalid_i || aw_turn_r));
    assign ar_fire_w = p6_arvalid_o && p6_arready_i;
    assign aw_fire_w = p6_awvalid_o && p6_awready_i;
    assign w_last_w = p6_wvalid_o && p6_wready_i && p6_wlast_o;
    assign p6_arvalid_o = rst_n_i &&
        (ar_owner_w ? eth_arvalid_i : pmon_arvalid_i);
    assign p6_arid_o = ar_owner_w;
    assign p6_araddr_o = ar_owner_w ? eth_araddr_i : pmon_araddr_i;
    assign p6_arlen_o = ar_owner_w ? eth_arlen_i : pmon_arlen_i;
    assign eth_arready_o = rst_n_i && ar_owner_w && p6_arready_i;
    assign pmon_arready_o = rst_n_i && !ar_owner_w && p6_arready_i;
    assign p6_awvalid_o = rst_n_i && !w_busy_r &&
        (aw_owner_w ? eth_awvalid_i : pmon_awvalid_i);
    assign p6_awid_o = aw_owner_w;
    assign p6_awaddr_o = aw_owner_w ? eth_awaddr_i : pmon_awaddr_i;
    assign p6_awlen_o = aw_owner_w ? eth_awlen_i : pmon_awlen_i;
    assign eth_awready_o = rst_n_i && !w_busy_r && aw_owner_w && p6_awready_i;
    assign pmon_awready_o = rst_n_i && !w_busy_r && !aw_owner_w && p6_awready_i;
    assign p6_wdata_o = w_owner_r ? eth_wdata_i : pmon_wdata_i;
    assign p6_wstrb_o = w_owner_r ? eth_wstrb_i : pmon_wstrb_i;
    assign p6_wlast_o = w_owner_r ? eth_wlast_i : pmon_wlast_i;
    assign p6_wvalid_o = rst_n_i && w_busy_r &&
        (w_owner_r ? eth_wvalid_i : pmon_wvalid_i);
    assign eth_wready_o = rst_n_i && w_busy_r && w_owner_r && p6_wready_i;
    assign pmon_wready_o = rst_n_i && w_busy_r && !w_owner_r && p6_wready_i;
    assign p6_bready_o = p6_bid_i ? eth_bready_i : pmon_bready_i;
    assign eth_bid_o = p6_bid_i;
    assign eth_bresp_o = p6_bresp_i;
    assign eth_bvalid_o = rst_n_i && p6_bvalid_i && p6_bid_i;
    assign pmon_bid_o = p6_bid_i;
    assign pmon_bresp_o = p6_bresp_i;
    assign pmon_bvalid_o = rst_n_i && p6_bvalid_i && !p6_bid_i;
    assign p6_rready_o = p6_rid_i ? eth_rready_i : pmon_rready_i;
    assign eth_rid_o = p6_rid_i;
    assign eth_rdata_o = p6_rdata_i;
    assign eth_rresp_o = p6_rresp_i;
    assign eth_rlast_o = p6_rlast_i;
    assign eth_rvalid_o = rst_n_i && p6_rvalid_i && p6_rid_i;
    assign pmon_rid_o = p6_rid_i;
    assign pmon_rdata_o = p6_rdata_i;
    assign pmon_rresp_o = p6_rresp_i;
    assign pmon_rlast_o = p6_rlast_i;
    assign pmon_rvalid_o = rst_n_i && p6_rvalid_i && !p6_rid_i;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            ar_turn_r <= 1'b0;
            ar_locked_r <= 1'b0;
            ar_owner_r <= 1'b0;
            aw_turn_r <= 1'b0;
            aw_locked_r <= 1'b0;
            aw_owner_r <= 1'b0;
            w_busy_r <= 1'b0;
            w_owner_r <= 1'b0;
        end else begin
            if (p6_arvalid_o) begin
                ar_locked_r <= !p6_arready_i;
                ar_owner_r <= ar_owner_w;
            end
            if (ar_fire_w)
                ar_turn_r <= !ar_owner_w;
            if (p6_awvalid_o) begin
                aw_locked_r <= !p6_awready_i;
                aw_owner_r <= aw_owner_w;
            end
            if (aw_fire_w) begin
                aw_turn_r <= !aw_owner_w;
                w_busy_r <= 1'b1;
                w_owner_r <= aw_owner_w;
            end
            if (w_last_w)
                w_busy_r <= 1'b0;
        end
    end
endmodule
