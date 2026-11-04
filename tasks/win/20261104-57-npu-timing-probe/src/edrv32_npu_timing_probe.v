// File: edrv32_npu_timing_probe.v
// Spec: card 57; npu-spec 3, 5; CLAUDE.md 10.3.
// Description: Real NPU with serial registered stimulus and registered XOR observation.
// Both domain clocks share the probe pin; this measures internal paths without DDR/CPU.
// Clock: clk_i.
module edrv32_npu_timing_probe (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Serial test access.
    input wire scan_i,
    output wire scan_o
);
    localparam IN_W = 319;
    localparam OUT_W = 403;
    wire rst_n_w;
    reg scan_r;
    reg [IN_W-1:0] in_r;
    reg [OUT_W-1:0] out_r;
    reg [OUT_W-1:0] fold_r;
    wire [11:0] apb_paddr_w;
    wire apb_psel_w;
    wire apb_penable_w;
    wire apb_pwrite_w;
    wire [31:0] apb_pwdata_w;
    wire [3:0] apb_pstrb_w;
    wire axi_awready_w;
    wire axi_wready_w;
    wire axi_bid_w;
    wire [1:0] axi_bresp_w;
    wire axi_bvalid_w;
    wire axi_arready_w;
    wire axi_rid_w;
    wire [255:0] axi_rdata_w;
    wire [1:0] axi_rresp_w;
    wire axi_rlast_w;
    wire axi_rvalid_w;
    wire apb_pready_w;
    wire [31:0] apb_prdata_w;
    wire apb_pslverr_w;
    wire axi_awid_w;
    wire [31:0] axi_awaddr_w;
    wire [3:0] axi_awlen_w;
    wire axi_awvalid_w;
    wire [255:0] axi_wdata_w;
    wire [31:0] axi_wstrb_w;
    wire axi_wlast_w;
    wire axi_wvalid_w;
    wire axi_bready_w;
    wire axi_arid_w;
    wire [31:0] axi_araddr_w;
    wire [3:0] axi_arlen_w;
    wire axi_arvalid_w;
    wire axi_rready_w;
    wire irq_w;

    edrv32_reset_sync u_reset (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .rst_n_o(rst_n_w)
    );
    always @(posedge clk_i) begin
        scan_r <= scan_i;
        in_r <= {in_r[IN_W-2:0], scan_r};
    end
    assign {
        apb_paddr_w,
        apb_psel_w,
        apb_penable_w,
        apb_pwrite_w,
        apb_pwdata_w,
        apb_pstrb_w,
        axi_awready_w,
        axi_wready_w,
        axi_bid_w,
        axi_bresp_w,
        axi_bvalid_w,
        axi_arready_w,
        axi_rid_w,
        axi_rdata_w,
        axi_rresp_w,
        axi_rlast_w,
        axi_rvalid_w
    } = in_r;
    always @(posedge clk_i) begin
        out_r <= {
            apb_pready_w,
            apb_prdata_w,
            apb_pslverr_w,
            axi_awid_w,
            axi_awaddr_w,
            axi_awlen_w,
            axi_awvalid_w,
            axi_wdata_w,
            axi_wstrb_w,
            axi_wlast_w,
            axi_wvalid_w,
            axi_bready_w,
            axi_arid_w,
            axi_araddr_w,
            axi_arlen_w,
            axi_arvalid_w,
            axi_rready_w,
            irq_w
        };
        fold_r <= {fold_r[OUT_W-2:0], 1'b0} ^ out_r;
    end
    assign scan_o = fold_r[OUT_W-1];

    edrv32_npu u_npu (
        .clk_npu_i(clk_i),
        .rst_npu_n_i(rst_n_w),
        .clk_mem_i(clk_i),
        .rst_mem_n_i(rst_n_w),
        .apb_paddr_i(apb_paddr_w),
        .apb_psel_i(apb_psel_w),
        .apb_penable_i(apb_penable_w),
        .apb_pwrite_i(apb_pwrite_w),
        .apb_pwdata_i(apb_pwdata_w),
        .apb_pstrb_i(apb_pstrb_w),
        .apb_pready_o(apb_pready_w),
        .apb_prdata_o(apb_prdata_w),
        .apb_pslverr_o(apb_pslverr_w),
        .axi_awid_o(axi_awid_w),
        .axi_awaddr_o(axi_awaddr_w),
        .axi_awlen_o(axi_awlen_w),
        .axi_awvalid_o(axi_awvalid_w),
        .axi_awready_i(axi_awready_w),
        .axi_wdata_o(axi_wdata_w),
        .axi_wstrb_o(axi_wstrb_w),
        .axi_wlast_o(axi_wlast_w),
        .axi_wvalid_o(axi_wvalid_w),
        .axi_wready_i(axi_wready_w),
        .axi_bid_i(axi_bid_w),
        .axi_bresp_i(axi_bresp_w),
        .axi_bvalid_i(axi_bvalid_w),
        .axi_bready_o(axi_bready_w),
        .axi_arid_o(axi_arid_w),
        .axi_araddr_o(axi_araddr_w),
        .axi_arlen_o(axi_arlen_w),
        .axi_arvalid_o(axi_arvalid_w),
        .axi_arready_i(axi_arready_w),
        .axi_rid_i(axi_rid_w),
        .axi_rdata_i(axi_rdata_w),
        .axi_rresp_i(axi_rresp_w),
        .axi_rlast_i(axi_rlast_w),
        .axi_rvalid_i(axi_rvalid_w),
        .axi_rready_o(axi_rready_w),
        .irq_o(irq_w)
    );
endmodule
