// File: edrv32_cpu_l1_timing_probe.v
// Spec: card 56 (tasks/win/20261104-56-cpu-l1-timing-probe/task.md); CLAUDE.md 10.3.
// Description: Timing-only top for edrv32_cpu_subsys (CPU + I$ + D$) without the SoC.
//              Every subsystem input comes from a serial shift chain and every
//              output is folded into a serial XOR chain, so no logic is constant
//              and every subsystem port has one register at the probe boundary.
// Clock domain: clk_i only.
module edrv32_cpu_l1_timing_probe (
    // Clock and asynchronous reset.
    input wire clk_i,
    input wire rst_n_i,

    // Serial stimulus in, folded observation out.
    input wire scan_i,
    output wire scan_o
);

    localparam IN_W = 273;
    localparam OUT_W = 262;

    wire rst_n_w;

    reg scan_r;
    reg [IN_W-1:0] in_r;
    reg [OUT_W-1:0] out_r;
    reg [OUT_W-1:0] fold_r;

    // Subsystem inputs, all driven by in_r.
    wire iaxi_arready_w;
    wire [3:0] iaxi_rid_w;
    wire [63:0] iaxi_rdata_w;
    wire [1:0] iaxi_rresp_w;
    wire iaxi_rlast_w;
    wire iaxi_rvalid_w;
    wire daxi_awready_w;
    wire daxi_wready_w;
    wire [3:0] daxi_bid_w;
    wire [1:0] daxi_bresp_w;
    wire daxi_bvalid_w;
    wire daxi_arready_w;
    wire [3:0] daxi_rid_w;
    wire [63:0] daxi_rdata_w;
    wire [1:0] daxi_rresp_w;
    wire daxi_rlast_w;
    wire daxi_rvalid_w;
    wire [11:0] apb_paddr_w;
    wire apb_psel_w;
    wire apb_penable_w;
    wire apb_pwrite_w;
    wire [31:0] apb_pwdata_w;
    wire [3:0] apb_pstrb_w;
    wire irq_meip_w;
    wire irq_msip_w;
    wire irq_mtip_w;
    wire [63:0] mtime_w;

    // Subsystem outputs, all captured in out_r. debug_o stays open as on the board top.
    wire [3:0] iaxi_arid_w;
    wire [31:0] iaxi_araddr_w;
    wire [7:0] iaxi_arlen_w;
    wire [2:0] iaxi_arsize_w;
    wire [1:0] iaxi_arburst_w;
    wire iaxi_arvalid_w;
    wire iaxi_rready_w;
    wire [3:0] daxi_awid_w;
    wire [31:0] daxi_awaddr_w;
    wire [7:0] daxi_awlen_w;
    wire [2:0] daxi_awsize_w;
    wire [1:0] daxi_awburst_w;
    wire daxi_awvalid_w;
    wire [63:0] daxi_wdata_w;
    wire [7:0] daxi_wstrb_w;
    wire daxi_wlast_w;
    wire daxi_wvalid_w;
    wire daxi_bready_w;
    wire [3:0] daxi_arid_w;
    wire [31:0] daxi_araddr_w;
    wire [7:0] daxi_arlen_w;
    wire [2:0] daxi_arsize_w;
    wire [1:0] daxi_arburst_w;
    wire daxi_arvalid_w;
    wire daxi_rready_w;
    wire apb_pready_w;
    wire [31:0] apb_prdata_w;
    wire apb_pslverr_w;
    wire irq_w;
    wire [63:0] unused_debug_w;

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
        iaxi_arready_w, iaxi_rid_w, iaxi_rdata_w, iaxi_rresp_w, iaxi_rlast_w,
        iaxi_rvalid_w, daxi_awready_w, daxi_wready_w, daxi_bid_w, daxi_bresp_w,
        daxi_bvalid_w, daxi_arready_w, daxi_rid_w, daxi_rdata_w, daxi_rresp_w,
        daxi_rlast_w, daxi_rvalid_w, apb_paddr_w, apb_psel_w, apb_penable_w,
        apb_pwrite_w, apb_pwdata_w, apb_pstrb_w, irq_meip_w, irq_msip_w,
        irq_mtip_w, mtime_w
    } = in_r;

    // Each fold bit is one LUT2 from its neighbour, so the observation chain stays shallow.
    always @(posedge clk_i) begin
        out_r <= {
            iaxi_arid_w, iaxi_araddr_w, iaxi_arlen_w, iaxi_arsize_w, iaxi_arburst_w,
            iaxi_arvalid_w, iaxi_rready_w, daxi_awid_w, daxi_awaddr_w, daxi_awlen_w,
            daxi_awsize_w, daxi_awburst_w, daxi_awvalid_w, daxi_wdata_w,
            daxi_wstrb_w, daxi_wlast_w, daxi_wvalid_w, daxi_bready_w, daxi_arid_w,
            daxi_araddr_w, daxi_arlen_w, daxi_arsize_w, daxi_arburst_w,
            daxi_arvalid_w, daxi_rready_w, apb_pready_w, apb_prdata_w,
            apb_pslverr_w, irq_w
        };
        fold_r <= {fold_r[OUT_W-2:0], 1'b0} ^ out_r;
    end

    assign scan_o = fold_r[OUT_W-1];

    edrv32_cpu_subsys u_cpu (
        // Clock and reset.
        .clk_i(clk_i),
        .rst_n_i(rst_n_w),

        // Instruction AXI64 master.
        .iaxi_arid_o(iaxi_arid_w),
        .iaxi_araddr_o(iaxi_araddr_w),
        .iaxi_arlen_o(iaxi_arlen_w),
        .iaxi_arsize_o(iaxi_arsize_w),
        .iaxi_arburst_o(iaxi_arburst_w),
        .iaxi_arvalid_o(iaxi_arvalid_w),
        .iaxi_arready_i(iaxi_arready_w),
        .iaxi_rid_i(iaxi_rid_w),
        .iaxi_rdata_i(iaxi_rdata_w),
        .iaxi_rresp_i(iaxi_rresp_w),
        .iaxi_rlast_i(iaxi_rlast_w),
        .iaxi_rvalid_i(iaxi_rvalid_w),
        .iaxi_rready_o(iaxi_rready_w),

        // Data AXI64 master.
        .daxi_awid_o(daxi_awid_w),
        .daxi_awaddr_o(daxi_awaddr_w),
        .daxi_awlen_o(daxi_awlen_w),
        .daxi_awsize_o(daxi_awsize_w),
        .daxi_awburst_o(daxi_awburst_w),
        .daxi_awvalid_o(daxi_awvalid_w),
        .daxi_awready_i(daxi_awready_w),
        .daxi_wdata_o(daxi_wdata_w),
        .daxi_wstrb_o(daxi_wstrb_w),
        .daxi_wlast_o(daxi_wlast_w),
        .daxi_wvalid_o(daxi_wvalid_w),
        .daxi_wready_i(daxi_wready_w),
        .daxi_bid_i(daxi_bid_w),
        .daxi_bresp_i(daxi_bresp_w),
        .daxi_bvalid_i(daxi_bvalid_w),
        .daxi_bready_o(daxi_bready_w),
        .daxi_arid_o(daxi_arid_w),
        .daxi_araddr_o(daxi_araddr_w),
        .daxi_arlen_o(daxi_arlen_w),
        .daxi_arsize_o(daxi_arsize_w),
        .daxi_arburst_o(daxi_arburst_w),
        .daxi_arvalid_o(daxi_arvalid_w),
        .daxi_arready_i(daxi_arready_w),
        .daxi_rid_i(daxi_rid_w),
        .daxi_rdata_i(daxi_rdata_w),
        .daxi_rresp_i(daxi_rresp_w),
        .daxi_rlast_i(daxi_rlast_w),
        .daxi_rvalid_i(daxi_rvalid_w),
        .daxi_rready_o(daxi_rready_w),

        // Cache-control APB slave.
        .apb_paddr_i(apb_paddr_w),
        .apb_psel_i(apb_psel_w),
        .apb_penable_i(apb_penable_w),
        .apb_pwrite_i(apb_pwrite_w),
        .apb_pwdata_i(apb_pwdata_w),
        .apb_pstrb_i(apb_pstrb_w),
        .apb_pready_o(apb_pready_w),
        .apb_prdata_o(apb_prdata_w),
        .apb_pslverr_o(apb_pslverr_w),

        // Interrupts, time and debug.
        .irq_meip_i(irq_meip_w),
        .irq_msip_i(irq_msip_w),
        .irq_mtip_i(irq_mtip_w),
        .mtime_i(mtime_w),
        .debug_o(unused_debug_w),
        .irq_o(irq_w)
    );

endmodule
