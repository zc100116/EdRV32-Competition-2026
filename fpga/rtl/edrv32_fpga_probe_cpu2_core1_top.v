// File: edrv32_fpga_probe_cpu2_core1_top.v
// Spec: cpu-v2-spec 2.2, 3, 7; P-CORE probe task.
// Description: Fixed ISSUE_WIDTH=1, FPU_FORMAT=NONE integer core timing probe.
//              Registered stimuli and captures expose core paths with four pins.
// Clock domain: clk_sys.
module edrv32_fpga_probe_cpu2_core1_top (
    // Clock and asynchronous board reset.
    input wire clk_i,
    input wire rst_n_i,

    // Serial stimulus and folded observation.
    input wire stim_i,
    output wire obs_o
);
    wire rst_core_n_w;
    edrv32_reset_sync u_reset_sync (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .rst_n_o(rst_core_n_w)
    );

    // The seed and serial input keep every stimulus stage live.
    reg [255:0] stimulus_r;
    always @(posedge clk_i or negedge rst_core_n_w) begin
        if (!rst_core_n_w)
            stimulus_r <= 256'h1;
        else
            stimulus_r <= {stimulus_r[254:0], stimulus_r[255] ^ stimulus_r[253] ^
                stimulus_r[250] ^ stimulus_r[245] ^ stim_i};
    end

    // Per-port registers preserve the core boundary before observation folding.
    wire [3:0] ic_axi_arid_w;
    (* keep = "true", syn_preserve = 1 *) reg [3:0] ic_axi_arid_r;
    always @(posedge clk_i) begin
        ic_axi_arid_r <= ic_axi_arid_w;
    end

    wire [31:0] ic_axi_araddr_w;
    (* keep = "true", syn_preserve = 1 *) reg [31:0] ic_axi_araddr_r;
    always @(posedge clk_i) begin
        ic_axi_araddr_r <= ic_axi_araddr_w;
    end

    wire [7:0] ic_axi_arlen_w;
    (* keep = "true", syn_preserve = 1 *) reg [7:0] ic_axi_arlen_r;
    always @(posedge clk_i) begin
        ic_axi_arlen_r <= ic_axi_arlen_w;
    end

    wire [2:0] ic_axi_arsize_w;
    (* keep = "true", syn_preserve = 1 *) reg [2:0] ic_axi_arsize_r;
    always @(posedge clk_i) begin
        ic_axi_arsize_r <= ic_axi_arsize_w;
    end

    wire [1:0] ic_axi_arburst_w;
    (* keep = "true", syn_preserve = 1 *) reg [1:0] ic_axi_arburst_r;
    always @(posedge clk_i) begin
        ic_axi_arburst_r <= ic_axi_arburst_w;
    end

    wire ic_axi_arvalid_w;
    (* keep = "true", syn_preserve = 1 *) reg ic_axi_arvalid_r;
    always @(posedge clk_i) begin
        ic_axi_arvalid_r <= ic_axi_arvalid_w;
    end

    (* keep = "true", syn_preserve = 1 *) reg ic_axi_arready_r;
    always @(posedge clk_i) begin
        ic_axi_arready_r <= stimulus_r[152 +: 1];
    end

    (* keep = "true", syn_preserve = 1 *) reg [3:0] ic_axi_rid_r;
    always @(posedge clk_i) begin
        ic_axi_rid_r <= stimulus_r[171 +: 4];
    end

    (* keep = "true", syn_preserve = 1 *) reg [63:0] ic_axi_rdata_r;
    always @(posedge clk_i) begin
        ic_axi_rdata_r <= stimulus_r[190 +: 64];
    end

    (* keep = "true", syn_preserve = 1 *) reg [1:0] ic_axi_rresp_r;
    always @(posedge clk_i) begin
        ic_axi_rresp_r <= stimulus_r[209 +: 2];
    end

    (* keep = "true", syn_preserve = 1 *) reg ic_axi_rlast_r;
    always @(posedge clk_i) begin
        ic_axi_rlast_r <= stimulus_r[228 +: 1];
    end

    (* keep = "true", syn_preserve = 1 *) reg ic_axi_rvalid_r;
    always @(posedge clk_i) begin
        ic_axi_rvalid_r <= stimulus_r[247 +: 1];
    end

    wire ic_axi_rready_w;
    (* keep = "true", syn_preserve = 1 *) reg ic_axi_rready_r;
    always @(posedge clk_i) begin
        ic_axi_rready_r <= ic_axi_rready_w;
    end

    wire [3:0] dc_axi_arid_w;
    (* keep = "true", syn_preserve = 1 *) reg [3:0] dc_axi_arid_r;
    always @(posedge clk_i) begin
        dc_axi_arid_r <= dc_axi_arid_w;
    end

    wire [31:0] dc_axi_araddr_w;
    (* keep = "true", syn_preserve = 1 *) reg [31:0] dc_axi_araddr_r;
    always @(posedge clk_i) begin
        dc_axi_araddr_r <= dc_axi_araddr_w;
    end

    wire [7:0] dc_axi_arlen_w;
    (* keep = "true", syn_preserve = 1 *) reg [7:0] dc_axi_arlen_r;
    always @(posedge clk_i) begin
        dc_axi_arlen_r <= dc_axi_arlen_w;
    end

    wire [2:0] dc_axi_arsize_w;
    (* keep = "true", syn_preserve = 1 *) reg [2:0] dc_axi_arsize_r;
    always @(posedge clk_i) begin
        dc_axi_arsize_r <= dc_axi_arsize_w;
    end

    wire [1:0] dc_axi_arburst_w;
    (* keep = "true", syn_preserve = 1 *) reg [1:0] dc_axi_arburst_r;
    always @(posedge clk_i) begin
        dc_axi_arburst_r <= dc_axi_arburst_w;
    end

    wire dc_axi_arvalid_w;
    (* keep = "true", syn_preserve = 1 *) reg dc_axi_arvalid_r;
    always @(posedge clk_i) begin
        dc_axi_arvalid_r <= dc_axi_arvalid_w;
    end

    (* keep = "true", syn_preserve = 1 *) reg dc_axi_arready_r;
    always @(posedge clk_i) begin
        dc_axi_arready_r <= stimulus_r[143 +: 1];
    end

    (* keep = "true", syn_preserve = 1 *) reg [3:0] dc_axi_rid_r;
    always @(posedge clk_i) begin
        dc_axi_rid_r <= stimulus_r[165 +: 4];
    end

    (* keep = "true", syn_preserve = 1 *) reg [63:0] dc_axi_rdata_r;
    always @(posedge clk_i) begin
        dc_axi_rdata_r <= stimulus_r[51 +: 64];
    end

    (* keep = "true", syn_preserve = 1 *) reg [1:0] dc_axi_rresp_r;
    always @(posedge clk_i) begin
        dc_axi_rresp_r <= stimulus_r[201 +: 2];
    end

    (* keep = "true", syn_preserve = 1 *) reg dc_axi_rlast_r;
    always @(posedge clk_i) begin
        dc_axi_rlast_r <= stimulus_r[219 +: 1];
    end

    (* keep = "true", syn_preserve = 1 *) reg dc_axi_rvalid_r;
    always @(posedge clk_i) begin
        dc_axi_rvalid_r <= stimulus_r[238 +: 1];
    end

    wire dc_axi_rready_w;
    (* keep = "true", syn_preserve = 1 *) reg dc_axi_rready_r;
    always @(posedge clk_i) begin
        dc_axi_rready_r <= dc_axi_rready_w;
    end

    wire [3:0] dc_axi_awid_w;
    (* keep = "true", syn_preserve = 1 *) reg [3:0] dc_axi_awid_r;
    always @(posedge clk_i) begin
        dc_axi_awid_r <= dc_axi_awid_w;
    end

    wire [31:0] dc_axi_awaddr_w;
    (* keep = "true", syn_preserve = 1 *) reg [31:0] dc_axi_awaddr_r;
    always @(posedge clk_i) begin
        dc_axi_awaddr_r <= dc_axi_awaddr_w;
    end

    wire [7:0] dc_axi_awlen_w;
    (* keep = "true", syn_preserve = 1 *) reg [7:0] dc_axi_awlen_r;
    always @(posedge clk_i) begin
        dc_axi_awlen_r <= dc_axi_awlen_w;
    end

    wire [2:0] dc_axi_awsize_w;
    (* keep = "true", syn_preserve = 1 *) reg [2:0] dc_axi_awsize_r;
    always @(posedge clk_i) begin
        dc_axi_awsize_r <= dc_axi_awsize_w;
    end

    wire [1:0] dc_axi_awburst_w;
    (* keep = "true", syn_preserve = 1 *) reg [1:0] dc_axi_awburst_r;
    always @(posedge clk_i) begin
        dc_axi_awburst_r <= dc_axi_awburst_w;
    end

    wire dc_axi_awvalid_w;
    (* keep = "true", syn_preserve = 1 *) reg dc_axi_awvalid_r;
    always @(posedge clk_i) begin
        dc_axi_awvalid_r <= dc_axi_awvalid_w;
    end

    (* keep = "true", syn_preserve = 1 *) reg dc_axi_awready_r;
    always @(posedge clk_i) begin
        dc_axi_awready_r <= stimulus_r[134 +: 1];
    end

    wire [63:0] dc_axi_wdata_w;
    (* keep = "true", syn_preserve = 1 *) reg [63:0] dc_axi_wdata_r;
    always @(posedge clk_i) begin
        dc_axi_wdata_r <= dc_axi_wdata_w;
    end

    wire [7:0] dc_axi_wstrb_w;
    (* keep = "true", syn_preserve = 1 *) reg [7:0] dc_axi_wstrb_r;
    always @(posedge clk_i) begin
        dc_axi_wstrb_r <= dc_axi_wstrb_w;
    end

    wire dc_axi_wlast_w;
    (* keep = "true", syn_preserve = 1 *) reg dc_axi_wlast_r;
    always @(posedge clk_i) begin
        dc_axi_wlast_r <= dc_axi_wlast_w;
    end

    wire dc_axi_wvalid_w;
    (* keep = "true", syn_preserve = 1 *) reg dc_axi_wvalid_r;
    always @(posedge clk_i) begin
        dc_axi_wvalid_r <= dc_axi_wvalid_w;
    end

    (* keep = "true", syn_preserve = 1 *) reg dc_axi_wready_r;
    always @(posedge clk_i) begin
        dc_axi_wready_r <= stimulus_r[229 +: 1];
    end

    (* keep = "true", syn_preserve = 1 *) reg [3:0] dc_axi_bid_r;
    always @(posedge clk_i) begin
        dc_axi_bid_r <= stimulus_r[1 +: 4];
    end

    (* keep = "true", syn_preserve = 1 *) reg [1:0] dc_axi_bresp_r;
    always @(posedge clk_i) begin
        dc_axi_bresp_r <= stimulus_r[14 +: 2];
    end

    (* keep = "true", syn_preserve = 1 *) reg dc_axi_bvalid_r;
    always @(posedge clk_i) begin
        dc_axi_bvalid_r <= stimulus_r[30 +: 1];
    end

    wire dc_axi_bready_w;
    (* keep = "true", syn_preserve = 1 *) reg dc_axi_bready_r;
    always @(posedge clk_i) begin
        dc_axi_bready_r <= dc_axi_bready_w;
    end

    (* keep = "true", syn_preserve = 1 *) reg [11:0] apb_paddr_r;
    always @(posedge clk_i) begin
        apb_paddr_r <= stimulus_r[101 +: 12];
    end

    (* keep = "true", syn_preserve = 1 *) reg apb_psel_r;
    always @(posedge clk_i) begin
        apb_psel_r <= stimulus_r[87 +: 1];
    end

    (* keep = "true", syn_preserve = 1 *) reg apb_penable_r;
    always @(posedge clk_i) begin
        apb_penable_r <= stimulus_r[106 +: 1];
    end

    (* keep = "true", syn_preserve = 1 *) reg apb_pwrite_r;
    always @(posedge clk_i) begin
        apb_pwrite_r <= stimulus_r[125 +: 1];
    end

    (* keep = "true", syn_preserve = 1 *) reg [31:0] apb_pwdata_r;
    always @(posedge clk_i) begin
        apb_pwdata_r <= stimulus_r[12 +: 32];
    end

    (* keep = "true", syn_preserve = 1 *) reg [3:0] apb_pstrb_r;
    always @(posedge clk_i) begin
        apb_pstrb_r <= stimulus_r[172 +: 4];
    end

    wire apb_pready_w;
    (* keep = "true", syn_preserve = 1 *) reg apb_pready_r;
    always @(posedge clk_i) begin
        apb_pready_r <= apb_pready_w;
    end

    wire [31:0] apb_prdata_w;
    (* keep = "true", syn_preserve = 1 *) reg [31:0] apb_prdata_r;
    always @(posedge clk_i) begin
        apb_prdata_r <= apb_prdata_w;
    end

    wire apb_pslverr_w;
    (* keep = "true", syn_preserve = 1 *) reg apb_pslverr_r;
    always @(posedge clk_i) begin
        apb_pslverr_r <= apb_pslverr_w;
    end

    wire cache_irq_w;
    (* keep = "true", syn_preserve = 1 *) reg cache_irq_r;
    always @(posedge clk_i) begin
        cache_irq_r <= cache_irq_w;
    end

    (* keep = "true", syn_preserve = 1 *) reg irq_meip_r;
    always @(posedge clk_i) begin
        irq_meip_r <= stimulus_r[2 +: 1];
    end

    (* keep = "true", syn_preserve = 1 *) reg irq_msip_r;
    always @(posedge clk_i) begin
        irq_msip_r <= stimulus_r[21 +: 1];
    end

    (* keep = "true", syn_preserve = 1 *) reg irq_mtip_r;
    always @(posedge clk_i) begin
        irq_mtip_r <= stimulus_r[40 +: 1];
    end

    (* keep = "true", syn_preserve = 1 *) reg [63:0] mtime_r;
    always @(posedge clk_i) begin
        mtime_r <= stimulus_r[118 +: 64];
    end

    wire [63:0] debug_w;
    (* keep = "true", syn_preserve = 1 *) reg [63:0] debug_r;
    always @(posedge clk_i) begin
        debug_r <= debug_w;
    end

    // Fixed spec configurations; no probe configuration parameters.
    edrv32_cpu2_top #(
        .ISSUE_WIDTH(1),
        .FPU_FORMAT("NONE")
    ) u_core (
        // Clock and reset.
        .clk_i(clk_i),
        .rst_n_i(rst_core_n_w),

        // Instruction AXI read channel.
        .ic_axi_arid_o(ic_axi_arid_w),
        .ic_axi_araddr_o(ic_axi_araddr_w),
        .ic_axi_arlen_o(ic_axi_arlen_w),
        .ic_axi_arsize_o(ic_axi_arsize_w),
        .ic_axi_arburst_o(ic_axi_arburst_w),
        .ic_axi_arvalid_o(ic_axi_arvalid_w),
        .ic_axi_arready_i(ic_axi_arready_r),
        .ic_axi_rid_i(ic_axi_rid_r),
        .ic_axi_rdata_i(ic_axi_rdata_r),
        .ic_axi_rresp_i(ic_axi_rresp_r),
        .ic_axi_rlast_i(ic_axi_rlast_r),
        .ic_axi_rvalid_i(ic_axi_rvalid_r),
        .ic_axi_rready_o(ic_axi_rready_w),

        // Data AXI channel.
        .dc_axi_arid_o(dc_axi_arid_w),
        .dc_axi_araddr_o(dc_axi_araddr_w),
        .dc_axi_arlen_o(dc_axi_arlen_w),
        .dc_axi_arsize_o(dc_axi_arsize_w),
        .dc_axi_arburst_o(dc_axi_arburst_w),
        .dc_axi_arvalid_o(dc_axi_arvalid_w),
        .dc_axi_arready_i(dc_axi_arready_r),
        .dc_axi_rid_i(dc_axi_rid_r),
        .dc_axi_rdata_i(dc_axi_rdata_r),
        .dc_axi_rresp_i(dc_axi_rresp_r),
        .dc_axi_rlast_i(dc_axi_rlast_r),
        .dc_axi_rvalid_i(dc_axi_rvalid_r),
        .dc_axi_rready_o(dc_axi_rready_w),

        // Data AXI channel.
        .dc_axi_awid_o(dc_axi_awid_w),
        .dc_axi_awaddr_o(dc_axi_awaddr_w),
        .dc_axi_awlen_o(dc_axi_awlen_w),
        .dc_axi_awsize_o(dc_axi_awsize_w),
        .dc_axi_awburst_o(dc_axi_awburst_w),
        .dc_axi_awvalid_o(dc_axi_awvalid_w),
        .dc_axi_awready_i(dc_axi_awready_r),

        // Data AXI channel.
        .dc_axi_wdata_o(dc_axi_wdata_w),
        .dc_axi_wstrb_o(dc_axi_wstrb_w),
        .dc_axi_wlast_o(dc_axi_wlast_w),
        .dc_axi_wvalid_o(dc_axi_wvalid_w),
        .dc_axi_wready_i(dc_axi_wready_r),

        // Data AXI channel.
        .dc_axi_bid_i(dc_axi_bid_r),
        .dc_axi_bresp_i(dc_axi_bresp_r),
        .dc_axi_bvalid_i(dc_axi_bvalid_r),
        .dc_axi_bready_o(dc_axi_bready_w),

        // Cache control APB.
        .apb_paddr_i(apb_paddr_r),
        .apb_psel_i(apb_psel_r),
        .apb_penable_i(apb_penable_r),
        .apb_pwrite_i(apb_pwrite_r),
        .apb_pwdata_i(apb_pwdata_r),
        .apb_pstrb_i(apb_pstrb_r),
        .apb_pready_o(apb_pready_w),
        .apb_prdata_o(apb_prdata_w),
        .apb_pslverr_o(apb_pslverr_w),

        // Cache status, interrupts and debug.
        .cache_irq_o(cache_irq_w),
        // Registered external interrupts and time.
        .irq_meip_i(irq_meip_r),
        .irq_msip_i(irq_msip_r),
        .irq_mtip_i(irq_mtip_r),
        .mtime_i(mtime_r),
        .debug_o(debug_w)
    );

    // Fold only after each output has its own capture register.
    reg observation_r;
    always @(posedge clk_i) begin
        observation_r <=
            ^ic_axi_arid_r ^
            ^ic_axi_araddr_r ^
            ^ic_axi_arlen_r ^
            ^ic_axi_arsize_r ^
            ^ic_axi_arburst_r ^
            ^ic_axi_arvalid_r ^
            ^ic_axi_rready_r ^
            ^dc_axi_arid_r ^
            ^dc_axi_araddr_r ^
            ^dc_axi_arlen_r ^
            ^dc_axi_arsize_r ^
            ^dc_axi_arburst_r ^
            ^dc_axi_arvalid_r ^
            ^dc_axi_rready_r ^
            ^dc_axi_awid_r ^
            ^dc_axi_awaddr_r ^
            ^dc_axi_awlen_r ^
            ^dc_axi_awsize_r ^
            ^dc_axi_awburst_r ^
            ^dc_axi_awvalid_r ^
            ^dc_axi_wdata_r ^
            ^dc_axi_wstrb_r ^
            ^dc_axi_wlast_r ^
            ^dc_axi_wvalid_r ^
            ^dc_axi_bready_r ^
            ^apb_pready_r ^
            ^apb_prdata_r ^
            ^apb_pslverr_r ^
            ^cache_irq_r ^
            ^debug_r;
    end
    assign obs_o = observation_r;
endmodule
