// File: edrv32_fpga_media_top.v
// Spec: vin/disp/pix/geo/eth-spec 3; SoC 4.5, 5.2; media measurement task V-W1.
// Description: PDS resource/timing measurement only; never run on the board.
//              VIN and PIX streams connect directly. All remaining inputs use local-domain
//              serial stimulus; outputs use local-domain registered 6-input XOR trees.
//              clk_mem: 1322 stimulus, 1319 observation bits; IRQ: 5 bits separately.
//              clk_ext: 30 stimulus, 40 observation bits.
// Clock: clk_mem_i and clk_ext_i, asynchronous; both constrained at 125 MHz.
module edrv32_fpga_media_top (
    // Measurement clocks and asynchronous reset key.
    input wire clk_mem_i,
    input wire clk_ext_i,
    input wire rst_n_i,

    // Asynchronous serial stimulus and local-domain observations.
    input wire stim_i,
    output wire obs_mem_o,
    output wire obs_ext_o,
    output wire irq_obs_o
);
    localparam STIM_MEM_BITS = 1322;
    localparam OBS_MEM_BITS = 1319;
    localparam MEM_L1_BITS = 220;
    localparam MEM_L2_BITS = 37;
    localparam MEM_L3_BITS = 7;
    localparam MEM_L4_BITS = 2;
    localparam STIM_EXT_BITS = 30;
    localparam OBS_EXT_BITS = 40;
    localparam EXT_L1_BITS = 7;
    localparam EXT_L2_BITS = 2;

    wire rst_mem_n_w;
    wire rst_ext_n_w;
    reg [STIM_MEM_BITS-1:0] stim_mem_r;
    wire [OBS_MEM_BITS-1:0] obs_mem_w;
    reg [OBS_MEM_BITS-1:0] obs_mem_r;
    wire [MEM_L1_BITS*6-1:0] mem_l1_pad_w;
    reg [MEM_L1_BITS-1:0] mem_l1_r;
    wire [MEM_L2_BITS*6-1:0] mem_l2_pad_w;
    reg [MEM_L2_BITS-1:0] mem_l2_r;
    wire [MEM_L3_BITS*6-1:0] mem_l3_pad_w;
    reg [MEM_L3_BITS-1:0] mem_l3_r;
    wire [MEM_L4_BITS*6-1:0] mem_l4_pad_w;
    reg [MEM_L4_BITS-1:0] mem_l4_r;
    reg obs_mem_bit_r;
    reg [STIM_EXT_BITS-1:0] stim_ext_r;
    wire [OBS_EXT_BITS-1:0] obs_ext_w;
    reg [OBS_EXT_BITS-1:0] obs_ext_r;
    wire [EXT_L1_BITS*6-1:0] ext_l1_pad_w;
    reg [EXT_L1_BITS-1:0] ext_l1_r;
    wire [EXT_L2_BITS*6-1:0] ext_l2_pad_w;
    reg [EXT_L2_BITS-1:0] ext_l2_r;
    reg obs_ext_bit_r;
    reg [4:0] irq_r;
    reg irq_obs_r;

    // Internal clk_mem VIN/PIX streams (SoC 4.5), outside stimulus and observation.
    wire pix_in_valid_w;
    wire pix_in_ready_w;
    wire [31:0] pix_in_data_w;
    wire pix_in_sof_w;
    wire pix_in_eol_w;
    wire pix_in_eof_w;
    wire pix_out_valid_w;
    wire pix_out_ready_w;
    wire [31:0] pix_out_data_w;
    wire pix_out_sof_w;
    wire pix_out_eol_w;
    wire pix_out_eof_w;

    // Observed module outputs, including the separate clk_mem interrupt levels.
    wire vin_apb_pready_w;
    wire [31:0] vin_apb_prdata_w;
    wire vin_apb_pslverr_w;
    wire vin_p1_awid_w;
    wire [31:0] vin_p1_awaddr_w;
    wire [3:0] vin_p1_awlen_w;
    wire vin_p1_awvalid_w;
    wire [255:0] vin_p1_wdata_w;
    wire [31:0] vin_p1_wstrb_w;
    wire vin_p1_wlast_w;
    wire vin_p1_wvalid_w;
    wire vin_p1_bready_w;
    wire vin_p1_arid_w;
    wire [31:0] vin_p1_araddr_w;
    wire [3:0] vin_p1_arlen_w;
    wire vin_p1_arvalid_w;
    wire vin_p1_rready_w;
    wire vin_p1_urgent_w;
    wire vin_irq_w;
    wire disp_apb_pready_w;
    wire [31:0] disp_apb_prdata_w;
    wire disp_apb_pslverr_w;
    wire disp_p0_arid_w;
    wire [31:0] disp_p0_araddr_w;
    wire [3:0] disp_p0_arlen_w;
    wire disp_p0_arvalid_w;
    wire disp_p0_rready_w;
    wire disp_p0_urgent_w;
    wire [29:0] disp_tmds_sym_w;
    wire disp_irq_w;
    wire pix_apb_pready_w;
    wire [31:0] pix_apb_prdata_w;
    wire pix_apb_pslverr_w;
    wire pix_irq_w;
    wire geo_apb_pready_w;
    wire [31:0] geo_apb_prdata_w;
    wire geo_apb_pslverr_w;
    wire geo_p5_awid_w;
    wire [31:0] geo_p5_awaddr_w;
    wire [3:0] geo_p5_awlen_w;
    wire geo_p5_awvalid_w;
    wire [255:0] geo_p5_wdata_w;
    wire [31:0] geo_p5_wstrb_w;
    wire geo_p5_wlast_w;
    wire geo_p5_wvalid_w;
    wire geo_p5_bready_w;
    wire geo_p5_arid_w;
    wire [31:0] geo_p5_araddr_w;
    wire [3:0] geo_p5_arlen_w;
    wire geo_p5_arvalid_w;
    wire geo_p5_rready_w;
    wire geo_irq_w;
    wire [7:0] eth_txd_w;
    wire eth_tx_en_w;
    wire eth_tx_er_w;
    wire eth_mdc_w;
    wire eth_mdio_w;
    wire eth_mdio_oe_w;
    wire eth_phy_rst_n_w;
    wire eth_apb_pready_w;
    wire [31:0] eth_apb_prdata_w;
    wire eth_apb_pslverr_w;
    wire eth_axi_arid_w;
    wire [31:0] eth_axi_araddr_w;
    wire [3:0] eth_axi_arlen_w;
    wire eth_axi_arvalid_w;
    wire eth_axi_rready_w;
    wire eth_axi_awid_w;
    wire [31:0] eth_axi_awaddr_w;
    wire [3:0] eth_axi_awlen_w;
    wire eth_axi_awvalid_w;
    wire [255:0] eth_axi_wdata_w;
    wire [31:0] eth_axi_wstrb_w;
    wire eth_axi_wlast_w;
    wire eth_axi_wvalid_w;
    wire eth_axi_bready_w;
    wire eth_irq_w;

    edrv32_reset_sync u_reset_mem (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_n_i),
        .rst_n_o(rst_mem_n_w)
    );

    edrv32_reset_sync u_reset_ext (
        .clk_i(clk_ext_i),
        .rst_n_i(rst_n_i),
        .rst_n_o(rst_ext_n_w)
    );

    // Stimulus is data and is intentionally not reset (CLAUDE.md 5.2).
    always @(posedge clk_mem_i) begin
        stim_mem_r <= {stim_mem_r[STIM_MEM_BITS-2:0], stim_i};
    end

    always @(posedge clk_ext_i) begin
        stim_ext_r <= {stim_ext_r[STIM_EXT_BITS-2:0], stim_i};
    end

    edrv32_vin u_vin (
        // Memory and shared external clock domains, with local reset release.
        .clk_mem_i(clk_mem_i),
        .rst_mem_n_i(rst_mem_n_w),
        .cam0_pclk_i(clk_ext_i),
        .rst_cam0_n_i(rst_ext_n_w),
        .cam1_pclk_i(clk_ext_i),
        .rst_cam1_n_i(rst_ext_n_w),

        // Camera zero in clk_ext.
        .cam0_vsync_i(stim_ext_r[0]),
        .cam0_href_i(stim_ext_r[1]),
        .cam0_data_i(stim_ext_r[9:2]),

        // Camera one in clk_ext.
        .cam1_vsync_i(stim_ext_r[10]),
        .cam1_href_i(stim_ext_r[11]),
        .cam1_data_i(stim_ext_r[19:12]),

        // Control APB.
        .apb_paddr_i(stim_mem_r[11:0]),
        .apb_psel_i(stim_mem_r[12]),
        .apb_penable_i(stim_mem_r[13]),
        .apb_pwrite_i(stim_mem_r[14]),
        .apb_pwdata_i(stim_mem_r[46:15]),
        .apb_pstrb_i(stim_mem_r[50:47]),
        .apb_pready_o(vin_apb_pready_w),
        .apb_prdata_o(vin_apb_prdata_w),
        .apb_pslverr_o(vin_apb_pslverr_w),

        // P1 AXI256 master.
        .p1_awid_o(vin_p1_awid_w),
        .p1_awaddr_o(vin_p1_awaddr_w),
        .p1_awlen_o(vin_p1_awlen_w),
        .p1_awvalid_o(vin_p1_awvalid_w),
        .p1_awready_i(stim_mem_r[51]),
        .p1_wdata_o(vin_p1_wdata_w),
        .p1_wstrb_o(vin_p1_wstrb_w),
        .p1_wlast_o(vin_p1_wlast_w),
        .p1_wvalid_o(vin_p1_wvalid_w),
        .p1_wready_i(stim_mem_r[52]),
        .p1_bid_i(stim_mem_r[53]),
        .p1_bresp_i(stim_mem_r[55:54]),
        .p1_bvalid_i(stim_mem_r[56]),
        .p1_bready_o(vin_p1_bready_w),
        .p1_arid_o(vin_p1_arid_w),
        .p1_araddr_o(vin_p1_araddr_w),
        .p1_arlen_o(vin_p1_arlen_w),
        .p1_arvalid_o(vin_p1_arvalid_w),
        .p1_arready_i(stim_mem_r[57]),
        .p1_rid_i(stim_mem_r[58]),
        .p1_rdata_i(stim_mem_r[314:59]),
        .p1_rresp_i(stim_mem_r[316:315]),
        .p1_rlast_i(stim_mem_r[317]),
        .p1_rvalid_i(stim_mem_r[318]),
        .p1_rready_o(vin_p1_rready_w),
        .p1_urgent_o(vin_p1_urgent_w),

        // External PIX streams.
        .pix_in_valid_o(pix_in_valid_w),
        .pix_in_ready_i(pix_in_ready_w),
        .pix_in_data_o(pix_in_data_w),
        .pix_in_sof_o(pix_in_sof_w),
        .pix_in_eol_o(pix_in_eol_w),
        .pix_in_eof_o(pix_in_eof_w),
        .pix_out_valid_i(pix_out_valid_w),
        .pix_out_ready_o(pix_out_ready_w),
        .pix_out_data_i(pix_out_data_w),
        .pix_out_sof_i(pix_out_sof_w),
        .pix_out_eol_i(pix_out_eol_w),
        .pix_out_eof_i(pix_out_eof_w),

        // Interrupt.
        .irq_o(vin_irq_w)
    );

    edrv32_disp u_disp (
        // Clock domains and resets.
        .clk_mem_i(clk_mem_i),
        .rst_mem_n_i(rst_mem_n_w),
        .clk_pix_i(clk_ext_i),
        .rst_pix_n_i(rst_ext_n_w),

        // Media APB slave.
        .apb_paddr_i(stim_mem_r[330:319]),
        .apb_psel_i(stim_mem_r[331]),
        .apb_penable_i(stim_mem_r[332]),
        .apb_pwrite_i(stim_mem_r[333]),
        .apb_pwdata_i(stim_mem_r[365:334]),
        .apb_pstrb_i(stim_mem_r[369:366]),
        .apb_pready_o(disp_apb_pready_w),
        .apb_prdata_o(disp_apb_prdata_w),
        .apb_pslverr_o(disp_apb_pslverr_w),

        // P0 AXI256 read master.
        .p0_arid_o(disp_p0_arid_w),
        .p0_araddr_o(disp_p0_araddr_w),
        .p0_arlen_o(disp_p0_arlen_w),
        .p0_arvalid_o(disp_p0_arvalid_w),
        .p0_arready_i(stim_mem_r[370]),
        .p0_rid_i(stim_mem_r[371]),
        .p0_rdata_i(stim_mem_r[627:372]),
        .p0_rresp_i(stim_mem_r[629:628]),
        .p0_rlast_i(stim_mem_r[630]),
        .p0_rvalid_i(stim_mem_r[631]),
        .p0_rready_o(disp_p0_rready_w),
        .p0_urgent_o(disp_p0_urgent_w),

        // Parallel B/G/R TMDS and interrupt.
        .tmds_sym_o(disp_tmds_sym_w),
        .irq_o(disp_irq_w)
    );

    edrv32_pix u_pix (
        // Clock and reset.
        .clk_mem_i(clk_mem_i),
        .rst_mem_n_i(rst_mem_n_w),

        // VIN input stream.
        .pix_in_valid_i(pix_in_valid_w),
        .pix_in_ready_o(pix_in_ready_w),
        .pix_in_data_i(pix_in_data_w),
        .pix_in_sof_i(pix_in_sof_w),
        .pix_in_eol_i(pix_in_eol_w),
        .pix_in_eof_i(pix_in_eof_w),

        // VIN output stream.
        .pix_out_valid_o(pix_out_valid_w),
        .pix_out_ready_i(pix_out_ready_w),
        .pix_out_data_o(pix_out_data_w),
        .pix_out_sof_o(pix_out_sof_w),
        .pix_out_eol_o(pix_out_eol_w),
        .pix_out_eof_o(pix_out_eof_w),

        // Media APB slave.
        .apb_paddr_i(stim_mem_r[643:632]),
        .apb_psel_i(stim_mem_r[644]),
        .apb_penable_i(stim_mem_r[645]),
        .apb_pwrite_i(stim_mem_r[646]),
        .apb_pwdata_i(stim_mem_r[678:647]),
        .apb_pstrb_i(stim_mem_r[682:679]),
        .apb_pready_o(pix_apb_pready_w),
        .apb_prdata_o(pix_apb_prdata_w),
        .apb_pslverr_o(pix_apb_pslverr_w),

        // Frame interrupt.
        .irq_o(pix_irq_w)
    );

    edrv32_geo u_geo (
        // Clock and reset.
        .clk_mem_i(clk_mem_i),
        .rst_mem_n_i(rst_mem_n_w),

        // APB control.
        .apb_paddr_i(stim_mem_r[694:683]),
        .apb_psel_i(stim_mem_r[695]),
        .apb_penable_i(stim_mem_r[696]),
        .apb_pwrite_i(stim_mem_r[697]),
        .apb_pwdata_i(stim_mem_r[729:698]),
        .apb_pstrb_i(stim_mem_r[733:730]),
        .apb_pready_o(geo_apb_pready_w),
        .apb_prdata_o(geo_apb_prdata_w),
        .apb_pslverr_o(geo_apb_pslverr_w),

        // P5 AXI256 data plane.
        .p5_awid_o(geo_p5_awid_w),
        .p5_awaddr_o(geo_p5_awaddr_w),
        .p5_awlen_o(geo_p5_awlen_w),
        .p5_awvalid_o(geo_p5_awvalid_w),
        .p5_awready_i(stim_mem_r[734]),
        .p5_wdata_o(geo_p5_wdata_w),
        .p5_wstrb_o(geo_p5_wstrb_w),
        .p5_wlast_o(geo_p5_wlast_w),
        .p5_wvalid_o(geo_p5_wvalid_w),
        .p5_wready_i(stim_mem_r[735]),
        .p5_bid_i(stim_mem_r[736]),
        .p5_bresp_i(stim_mem_r[738:737]),
        .p5_bvalid_i(stim_mem_r[739]),
        .p5_bready_o(geo_p5_bready_w),
        .p5_arid_o(geo_p5_arid_w),
        .p5_araddr_o(geo_p5_araddr_w),
        .p5_arlen_o(geo_p5_arlen_w),
        .p5_arvalid_o(geo_p5_arvalid_w),
        .p5_arready_i(stim_mem_r[740]),
        .p5_rid_i(stim_mem_r[741]),
        .p5_rdata_i(stim_mem_r[997:742]),
        .p5_rresp_i(stim_mem_r[999:998]),
        .p5_rlast_i(stim_mem_r[1000]),
        .p5_rvalid_i(stim_mem_r[1001]),
        .p5_rready_o(geo_p5_rready_w),

        // Interrupt.
        .irq_o(geo_irq_w)
    );

    edrv32_eth u_eth (
        // Clocks and local-domain resets.
        .clk_mem_i(clk_mem_i),
        .rst_mem_n_i(rst_mem_n_w),
        .clk_eth_rx_i(clk_ext_i),
        .rst_eth_rx_n_i(rst_ext_n_w),
        .clk_eth_tx_i(clk_ext_i),
        .rst_eth_tx_n_i(rst_ext_n_w),

        // Receive stimulus and transmit observation in clk_ext.
        .eth_rxd_i(stim_ext_r[27:20]),
        .eth_rx_dv_i(stim_ext_r[28]),
        .eth_rx_er_i(stim_ext_r[29]),
        .eth_txd_o(eth_txd_w),
        .eth_tx_en_o(eth_tx_en_w),
        .eth_tx_er_o(eth_tx_er_w),

        // MDIO and PHY reset in clk_mem; no tristate IO in the measurement top.
        .eth_mdc_o(eth_mdc_w),
        .eth_mdio_o(eth_mdio_w),
        .eth_mdio_oe(eth_mdio_oe_w),
        .eth_mdio_i(stim_mem_r[1002]),
        .eth_phy_rst_n_o(eth_phy_rst_n_w),

        // APB control in clk_mem.
        .apb_paddr_i(stim_mem_r[1014:1003]),
        .apb_psel_i(stim_mem_r[1015]),
        .apb_penable_i(stim_mem_r[1016]),
        .apb_pwrite_i(stim_mem_r[1017]),
        .apb_pwdata_i(stim_mem_r[1049:1018]),
        .apb_pstrb_i(stim_mem_r[1053:1050]),
        .apb_pready_o(eth_apb_pready_w),
        .apb_prdata_o(eth_apb_prdata_w),
        .apb_pslverr_o(eth_apb_pslverr_w),

        // AXI256 data plane in clk_mem.
        .axi_arid_o(eth_axi_arid_w),
        .axi_araddr_o(eth_axi_araddr_w),
        .axi_arlen_o(eth_axi_arlen_w),
        .axi_arvalid_o(eth_axi_arvalid_w),
        .axi_arready_i(stim_mem_r[1054]),
        .axi_rid_i(stim_mem_r[1055]),
        .axi_rdata_i(stim_mem_r[1311:1056]),
        .axi_rresp_i(stim_mem_r[1313:1312]),
        .axi_rlast_i(stim_mem_r[1314]),
        .axi_rvalid_i(stim_mem_r[1315]),
        .axi_rready_o(eth_axi_rready_w),
        .axi_awid_o(eth_axi_awid_w),
        .axi_awaddr_o(eth_axi_awaddr_w),
        .axi_awlen_o(eth_axi_awlen_w),
        .axi_awvalid_o(eth_axi_awvalid_w),
        .axi_awready_i(stim_mem_r[1316]),
        .axi_wdata_o(eth_axi_wdata_w),
        .axi_wstrb_o(eth_axi_wstrb_w),
        .axi_wlast_o(eth_axi_wlast_w),
        .axi_wvalid_o(eth_axi_wvalid_w),
        .axi_wready_i(stim_mem_r[1317]),
        .axi_bid_i(stim_mem_r[1318]),
        .axi_bresp_i(stim_mem_r[1320:1319]),
        .axi_bvalid_i(stim_mem_r[1321]),
        .axi_bready_o(eth_axi_bready_w),

        // Interrupt in clk_mem.
        .irq_o(eth_irq_w)
    );

    // Every non-stream mem output is captured before the XOR tree.
    assign obs_mem_w = {
        eth_axi_bready_w,
        eth_axi_wvalid_w,
        eth_axi_wlast_w,
        eth_axi_wstrb_w,
        eth_axi_wdata_w,
        eth_axi_awvalid_w,
        eth_axi_awlen_w,
        eth_axi_awaddr_w,
        eth_axi_awid_w,
        eth_axi_rready_w,
        eth_axi_arvalid_w,
        eth_axi_arlen_w,
        eth_axi_araddr_w,
        eth_axi_arid_w,
        eth_apb_pslverr_w,
        eth_apb_prdata_w,
        eth_apb_pready_w,
        eth_phy_rst_n_w,
        eth_mdio_oe_w,
        eth_mdio_w,
        eth_mdc_w,
        geo_p5_rready_w,
        geo_p5_arvalid_w,
        geo_p5_arlen_w,
        geo_p5_araddr_w,
        geo_p5_arid_w,
        geo_p5_bready_w,
        geo_p5_wvalid_w,
        geo_p5_wlast_w,
        geo_p5_wstrb_w,
        geo_p5_wdata_w,
        geo_p5_awvalid_w,
        geo_p5_awlen_w,
        geo_p5_awaddr_w,
        geo_p5_awid_w,
        geo_apb_pslverr_w,
        geo_apb_prdata_w,
        geo_apb_pready_w,
        pix_apb_pslverr_w,
        pix_apb_prdata_w,
        pix_apb_pready_w,
        disp_p0_urgent_w,
        disp_p0_rready_w,
        disp_p0_arvalid_w,
        disp_p0_arlen_w,
        disp_p0_araddr_w,
        disp_p0_arid_w,
        disp_apb_pslverr_w,
        disp_apb_prdata_w,
        disp_apb_pready_w,
        vin_p1_urgent_w,
        vin_p1_rready_w,
        vin_p1_arvalid_w,
        vin_p1_arlen_w,
        vin_p1_araddr_w,
        vin_p1_arid_w,
        vin_p1_bready_w,
        vin_p1_wvalid_w,
        vin_p1_wlast_w,
        vin_p1_wstrb_w,
        vin_p1_wdata_w,
        vin_p1_awvalid_w,
        vin_p1_awlen_w,
        vin_p1_awaddr_w,
        vin_p1_awid_w,
        vin_apb_pslverr_w,
        vin_apb_prdata_w,
        vin_apb_pready_w
    };
    assign mem_l1_pad_w = {{(MEM_L1_BITS*6-OBS_MEM_BITS){1'b0}}, obs_mem_r};
    assign mem_l2_pad_w = {{(MEM_L2_BITS*6-MEM_L1_BITS){1'b0}}, mem_l1_r};
    assign mem_l3_pad_w = {{(MEM_L3_BITS*6-MEM_L2_BITS){1'b0}}, mem_l2_r};
    assign mem_l4_pad_w = {{(MEM_L4_BITS*6-MEM_L3_BITS){1'b0}}, mem_l3_r};

    always @(posedge clk_mem_i) begin
        obs_mem_r <= obs_mem_w;
    end

    // Every non-stream ext output is captured before the XOR tree.
    assign obs_ext_w = {
        eth_tx_er_w,
        eth_tx_en_w,
        eth_txd_w,
        disp_tmds_sym_w
    };
    assign ext_l1_pad_w = {{(EXT_L1_BITS*6-OBS_EXT_BITS){1'b0}}, obs_ext_r};
    assign ext_l2_pad_w = {{(EXT_L2_BITS*6-EXT_L1_BITS){1'b0}}, ext_l1_r};

    always @(posedge clk_ext_i) begin
        obs_ext_r <= obs_ext_w;
    end

    // Six-input reductions keep every observation stage within one LUT6.
    genvar g_i;
    generate
        for (g_i = 0; g_i < MEM_L1_BITS; g_i = g_i + 1) begin : g_mem_l1
            always @(posedge clk_mem_i) begin
                mem_l1_r[g_i] <= ^mem_l1_pad_w[g_i*6 +: 6];
            end
        end
        for (g_i = 0; g_i < MEM_L2_BITS; g_i = g_i + 1) begin : g_mem_l2
            always @(posedge clk_mem_i) begin
                mem_l2_r[g_i] <= ^mem_l2_pad_w[g_i*6 +: 6];
            end
        end
        for (g_i = 0; g_i < MEM_L3_BITS; g_i = g_i + 1) begin : g_mem_l3
            always @(posedge clk_mem_i) begin
                mem_l3_r[g_i] <= ^mem_l3_pad_w[g_i*6 +: 6];
            end
        end
        for (g_i = 0; g_i < MEM_L4_BITS; g_i = g_i + 1) begin : g_mem_l4
            always @(posedge clk_mem_i) begin
                mem_l4_r[g_i] <= ^mem_l4_pad_w[g_i*6 +: 6];
            end
        end
        for (g_i = 0; g_i < EXT_L1_BITS; g_i = g_i + 1) begin : g_ext_l1
            always @(posedge clk_ext_i) begin
                ext_l1_r[g_i] <= ^ext_l1_pad_w[g_i*6 +: 6];
            end
        end
        for (g_i = 0; g_i < EXT_L2_BITS; g_i = g_i + 1) begin : g_ext_l2
            always @(posedge clk_ext_i) begin
                ext_l2_r[g_i] <= ^ext_l2_pad_w[g_i*6 +: 6];
            end
        end
    endgenerate

    always @(posedge clk_mem_i) begin
        obs_mem_bit_r <= ^mem_l4_r;
    end
    assign obs_mem_o = obs_mem_bit_r;

    always @(posedge clk_ext_i) begin
        obs_ext_bit_r <= ^ext_l2_r;
    end
    assign obs_ext_o = obs_ext_bit_r;

    // All five IRQ levels belong to clk_mem (each module spec 3).
    always @(posedge clk_mem_i) begin
        irq_r <= {eth_irq_w, geo_irq_w, pix_irq_w, disp_irq_w, vin_irq_w};
        irq_obs_r <= ^irq_r;
    end
    assign irq_obs_o = irq_obs_r;
endmodule
