// File: edrv32_fpga_npu_top.v
// Spec: npu-spec 5.4, 7, 9; npu-plan N-W2.
// Description: Synthesis-measurement top for the complete NPU (edrv32_npu). All APB and
//              AXI256 inputs are driven by a clk_mem serial stimulus shift register; all
//              outputs are captured and folded by a registered 6-input XOR tree onto one
//              pin, so place-and-route keeps the whole NPU. irq_o is registered in clk_npu.
// Clock: clk_npu_i (NPU core) and clk_mem_i (APB/AXI side), asynchronous.
module edrv32_fpga_npu_top (
    // Measurement clocks and active-low reset key.
    input wire clk_npu_i,
    input wire clk_mem_i,
    input wire rst_n_i,

    // Serial stimulus in and folded observations out.
    input wire stim_i,
    output wire obs_o,
    output wire irq_obs_o
);
    // Sums of the edrv32_npu input and output port widths (clk_mem side).
    localparam STIM_BITS = 319;
    localparam OBS_BITS = 402;
    // Registered XOR tree, 6 inputs per LUT: 402 -> 67 -> 12 -> 2 -> 1.
    localparam L1_BITS = 67;
    localparam L2_BITS = 12;
    localparam L3_BITS = 2;

    wire rst_npu_n_w;
    wire rst_mem_n_w;
    reg [STIM_BITS-1:0] stim_r;
    wire [OBS_BITS-1:0] obs_w;
    reg [OBS_BITS-1:0] obs_r;
    wire [L1_BITS*6-1:0] obs_pad_w;
    reg [L1_BITS-1:0] l1_r;
    wire [L2_BITS*6-1:0] l1_pad_w;
    reg [L2_BITS-1:0] l2_r;
    wire [L3_BITS*6-1:0] l2_pad_w;
    reg [L3_BITS-1:0] l3_r;
    reg obs_bit_r;
    wire irq_w;
    reg irq_r;
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

    edrv32_reset_sync u_reset_npu (
        .clk_i(clk_npu_i),
        .rst_n_i(rst_n_i),
        .rst_n_o(rst_npu_n_w)
    );

    edrv32_reset_sync u_reset_mem (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_n_i),
        .rst_n_o(rst_mem_n_w)
    );

    // Stimulus is data, so the shift register is not reset.
    always @(posedge clk_mem_i) begin
        stim_r <= {stim_r[STIM_BITS-2:0], stim_i};
    end

    edrv32_npu u_npu (
        // Clocks and resets.
        .clk_npu_i(clk_npu_i),
        .rst_npu_n_i(rst_npu_n_w),
        .clk_mem_i(clk_mem_i),
        .rst_mem_n_i(rst_mem_n_w),

        // APB and AXI256 inputs from the stimulus register.
        .apb_paddr_i(stim_r[11:0]),
        .apb_psel_i(stim_r[12]),
        .apb_penable_i(stim_r[13]),
        .apb_pwrite_i(stim_r[14]),
        .apb_pwdata_i(stim_r[46:15]),
        .apb_pstrb_i(stim_r[50:47]),
        .axi_awready_i(stim_r[51]),
        .axi_wready_i(stim_r[52]),
        .axi_bid_i(stim_r[53]),
        .axi_bresp_i(stim_r[55:54]),
        .axi_bvalid_i(stim_r[56]),
        .axi_arready_i(stim_r[57]),
        .axi_rid_i(stim_r[58]),
        .axi_rdata_i(stim_r[314:59]),
        .axi_rresp_i(stim_r[316:315]),
        .axi_rlast_i(stim_r[317]),
        .axi_rvalid_i(stim_r[318]),

        // APB and AXI256 outputs to the observation capture.
        .apb_pready_o(apb_pready_w),
        .apb_prdata_o(apb_prdata_w),
        .apb_pslverr_o(apb_pslverr_w),
        .axi_awid_o(axi_awid_w),
        .axi_awaddr_o(axi_awaddr_w),
        .axi_awlen_o(axi_awlen_w),
        .axi_awvalid_o(axi_awvalid_w),
        .axi_wdata_o(axi_wdata_w),
        .axi_wstrb_o(axi_wstrb_w),
        .axi_wlast_o(axi_wlast_w),
        .axi_wvalid_o(axi_wvalid_w),
        .axi_bready_o(axi_bready_w),
        .axi_arid_o(axi_arid_w),
        .axi_araddr_o(axi_araddr_w),
        .axi_arlen_o(axi_arlen_w),
        .axi_arvalid_o(axi_arvalid_w),
        .axi_rready_o(axi_rready_w),

        // Interrupt.
        .irq_o(irq_w)
    );

    assign obs_w = {
        axi_rready_w,
        axi_arvalid_w,
        axi_arlen_w,
        axi_araddr_w,
        axi_arid_w,
        axi_bready_w,
        axi_wvalid_w,
        axi_wlast_w,
        axi_wstrb_w,
        axi_wdata_w,
        axi_awvalid_w,
        axi_awlen_w,
        axi_awaddr_w,
        axi_awid_w,
        apb_pslverr_w,
        apb_prdata_w,
        apb_pready_w
    };
    assign obs_pad_w = {{(L1_BITS*6-OBS_BITS){1'b0}}, obs_r};
    assign l1_pad_w = {{(L2_BITS*6-L1_BITS){1'b0}}, l1_r};
    assign l2_pad_w = {{(L3_BITS*6-L2_BITS){1'b0}}, l2_r};

    // Observation flops and the XOR tree carry data only, so they are not reset.
    always @(posedge clk_mem_i) begin
        obs_r <= obs_w;
    end

    genvar g_i;
    generate
        for (g_i = 0; g_i < L1_BITS; g_i = g_i + 1) begin : g_l1
            always @(posedge clk_mem_i) begin
                l1_r[g_i] <= ^obs_pad_w[g_i*6 +: 6];
            end
        end
        for (g_i = 0; g_i < L2_BITS; g_i = g_i + 1) begin : g_l2
            always @(posedge clk_mem_i) begin
                l2_r[g_i] <= ^l1_pad_w[g_i*6 +: 6];
            end
        end
        for (g_i = 0; g_i < L3_BITS; g_i = g_i + 1) begin : g_l3
            always @(posedge clk_mem_i) begin
                l3_r[g_i] <= ^l2_pad_w[g_i*6 +: 6];
            end
        end
    endgenerate

    always @(posedge clk_mem_i) begin
        obs_bit_r <= ^l3_r;
    end
    assign obs_o = obs_bit_r;

    // irq_o is a clk_npu level (npu-spec 3); observe it in its own domain.
    always @(posedge clk_npu_i) begin
        irq_r <= irq_w;
    end
    assign irq_obs_o = irq_r;
endmodule
