// File: tb.sv
// Spec: sys-subsys-spec 2.3, 2.10; S-T1b regression.
// Description: Odd media APB transaction history survives MEDIA and SOC soft resets.
//              Score each external APB transfer and reject stale or duplicated AXI responses.
// Clock domain: clk_sys and independent clk_mem.
module tb;
    reg clk_sys_i = 0;
    reg clk_mem_i = 0;
    always #5 clk_sys_i = ~clk_sys_i;
    always #7 clk_mem_i = ~clk_mem_i;
    reg clk_npu_i = 0;
    always #11 clk_npu_i = ~clk_npu_i;
    reg rst_n_i = 0;
    reg mem_ready_i = 1;
    wire rst_sys_por_n_o;
    wire rst_sys_n_o;
    wire rst_mem_core_n_o;
    wire rst_mem_n_o;
    wire rst_pix_n_o;
    wire rst_npu_n_o;
    wire rst_cam0_n_o;
    wire rst_cam1_n_o;
    wire rst_eth_rx_n_o;
    wire rst_eth_tx_n_o;
    wire m0_arready_o;
    wire [3:0] m0_rid_o;
    wire [63:0] m0_rdata_o;
    wire [1:0] m0_rresp_o;
    wire m0_rlast_o;
    wire m0_rvalid_o;
    reg [3:0] m1_awid_i = 0;
    reg [31:0] m1_awaddr_i = 0;
    reg [7:0] m1_awlen_i = 0;
    reg [2:0] m1_awsize_i = 0;
    reg [1:0] m1_awburst_i = 0;
    reg m1_awvalid_i = 0;
    wire m1_awready_o;
    reg [63:0] m1_wdata_i = 0;
    reg [7:0] m1_wstrb_i = 0;
    reg m1_wlast_i = 0;
    reg m1_wvalid_i = 0;
    wire m1_wready_o;
    wire [3:0] m1_bid_o;
    wire [1:0] m1_bresp_o;
    wire m1_bvalid_o;
    reg m1_bready_i = 0;
    reg [3:0] m1_arid_i = 0;
    reg [31:0] m1_araddr_i = 0;
    reg [7:0] m1_arlen_i = 0;
    reg [2:0] m1_arsize_i = 0;
    reg [1:0] m1_arburst_i = 0;
    reg m1_arvalid_i = 0;
    wire m1_arready_o;
    wire [3:0] m1_rid_o;
    wire [63:0] m1_rdata_o;
    wire [1:0] m1_rresp_o;
    wire m1_rlast_o;
    wire m1_rvalid_o;
    reg m1_rready_i = 0;
    wire [3:0] s6_awid_o;
    wire [31:0] s6_awaddr_o;
    wire [7:0] s6_awlen_o;
    wire [2:0] s6_awsize_o;
    wire [1:0] s6_awburst_o;
    wire s6_awvalid_o;
    wire [63:0] s6_wdata_o;
    wire [7:0] s6_wstrb_o;
    wire s6_wlast_o;
    wire s6_wvalid_o;
    wire s6_bready_o;
    wire [3:0] s6_arid_o;
    wire [31:0] s6_araddr_o;
    wire [7:0] s6_arlen_o;
    wire [2:0] s6_arsize_o;
    wire [1:0] s6_arburst_o;
    wire s6_arvalid_o;
    wire s6_rready_o;
    wire [11:0] media_apb_paddr_o;
    wire [15:0] media_apb_psel_o;
    wire media_apb_penable_o;
    wire media_apb_pwrite_o;
    wire [31:0] media_apb_pwdata_o;
    wire [3:0] media_apb_pstrb_o;
    wire [511:0] media_apb_prdata_i;
    wire [15:0] media_apb_pready_i;
    wire [15:0] media_apb_pslverr_i;
    wire [11:0] cache_apb_paddr_o;
    wire cache_apb_psel_o;
    wire cache_apb_penable_o;
    wire cache_apb_pwrite_o;
    wire [31:0] cache_apb_pwdata_o;
    wire [3:0] cache_apb_pstrb_o;
    wire [63:0] mtime_o;
    wire irq_mtip_o;
    wire irq_msip_o;
    wire irq_meip_o;
    wire uart0_tx_o;
    wire [15:0] gpio_o;
    wire [15:0] gpio_oe_o;
    wire [1:0] i2c0_scl_o;
    wire [1:0] i2c0_scl_oe_o;
    wire [1:0] i2c0_sda_o;
    wire [1:0] i2c0_sda_oe_o;
    wire sim_exit_valid_o;
    wire [31:0] sim_exit_code_o;

    edrv32_sys_subsys u_dut (
        .clk_sys_i(clk_sys_i),
        .clk_mem_i(clk_mem_i),
        .clk_pix_i(clk_mem_i),
        .clk_npu_i(clk_npu_i),
        .cam0_pclk_i(clk_mem_i),
        .cam1_pclk_i(clk_mem_i),
        .eth_rx_clk_i(clk_mem_i),
        .eth_tx_clk_i(clk_mem_i),
        .rst_n_i(rst_n_i),
        .mem_ready_i(mem_ready_i),
        .rst_sys_por_n_o(rst_sys_por_n_o),
        .rst_sys_n_o(rst_sys_n_o),
        .rst_mem_core_n_o(rst_mem_core_n_o),
        .rst_mem_n_o(rst_mem_n_o),
        .rst_pix_n_o(rst_pix_n_o),
        .rst_npu_n_o(rst_npu_n_o),
        .rst_cam0_n_o(rst_cam0_n_o),
        .rst_cam1_n_o(rst_cam1_n_o),
        .rst_eth_rx_n_o(rst_eth_rx_n_o),
        .rst_eth_tx_n_o(rst_eth_tx_n_o),
        .m0_arid_i('0),
        .m0_araddr_i('0),
        .m0_arlen_i('0),
        .m0_arsize_i('0),
        .m0_arburst_i('0),
        .m0_arvalid_i('0),
        .m0_arready_o(m0_arready_o),
        .m0_rid_o(m0_rid_o),
        .m0_rdata_o(m0_rdata_o),
        .m0_rresp_o(m0_rresp_o),
        .m0_rlast_o(m0_rlast_o),
        .m0_rvalid_o(m0_rvalid_o),
        .m0_rready_i('0),
        .m1_awid_i(m1_awid_i),
        .m1_awaddr_i(m1_awaddr_i),
        .m1_awlen_i(m1_awlen_i),
        .m1_awsize_i(m1_awsize_i),
        .m1_awburst_i(m1_awburst_i),
        .m1_awvalid_i(m1_awvalid_i),
        .m1_awready_o(m1_awready_o),
        .m1_wdata_i(m1_wdata_i),
        .m1_wstrb_i(m1_wstrb_i),
        .m1_wlast_i(m1_wlast_i),
        .m1_wvalid_i(m1_wvalid_i),
        .m1_wready_o(m1_wready_o),
        .m1_bid_o(m1_bid_o),
        .m1_bresp_o(m1_bresp_o),
        .m1_bvalid_o(m1_bvalid_o),
        .m1_bready_i(m1_bready_i),
        .m1_arid_i(m1_arid_i),
        .m1_araddr_i(m1_araddr_i),
        .m1_arlen_i(m1_arlen_i),
        .m1_arsize_i(m1_arsize_i),
        .m1_arburst_i(m1_arburst_i),
        .m1_arvalid_i(m1_arvalid_i),
        .m1_arready_o(m1_arready_o),
        .m1_rid_o(m1_rid_o),
        .m1_rdata_o(m1_rdata_o),
        .m1_rresp_o(m1_rresp_o),
        .m1_rlast_o(m1_rlast_o),
        .m1_rvalid_o(m1_rvalid_o),
        .m1_rready_i(m1_rready_i),
        .s6_awid_o(s6_awid_o),
        .s6_awaddr_o(s6_awaddr_o),
        .s6_awlen_o(s6_awlen_o),
        .s6_awsize_o(s6_awsize_o),
        .s6_awburst_o(s6_awburst_o),
        .s6_awvalid_o(s6_awvalid_o),
        .s6_awready_i('0),
        .s6_wdata_o(s6_wdata_o),
        .s6_wstrb_o(s6_wstrb_o),
        .s6_wlast_o(s6_wlast_o),
        .s6_wvalid_o(s6_wvalid_o),
        .s6_wready_i('0),
        .s6_bid_i('0),
        .s6_bresp_i('0),
        .s6_bvalid_i('0),
        .s6_bready_o(s6_bready_o),
        .s6_arid_o(s6_arid_o),
        .s6_araddr_o(s6_araddr_o),
        .s6_arlen_o(s6_arlen_o),
        .s6_arsize_o(s6_arsize_o),
        .s6_arburst_o(s6_arburst_o),
        .s6_arvalid_o(s6_arvalid_o),
        .s6_arready_i('0),
        .s6_rid_i('0),
        .s6_rdata_i('0),
        .s6_rresp_i('0),
        .s6_rlast_i('0),
        .s6_rvalid_i('0),
        .s6_rready_o(s6_rready_o),
        .media_apb_paddr_o(media_apb_paddr_o),
        .media_apb_psel_o(media_apb_psel_o),
        .media_apb_penable_o(media_apb_penable_o),
        .media_apb_pwrite_o(media_apb_pwrite_o),
        .media_apb_pwdata_o(media_apb_pwdata_o),
        .media_apb_pstrb_o(media_apb_pstrb_o),
        .media_apb_prdata_i(media_apb_prdata_i),
        .media_apb_pready_i(media_apb_pready_i),
        .media_apb_pslverr_i(media_apb_pslverr_i),
        .cache_apb_paddr_o(cache_apb_paddr_o),
        .cache_apb_psel_o(cache_apb_psel_o),
        .cache_apb_penable_o(cache_apb_penable_o),
        .cache_apb_pwrite_o(cache_apb_pwrite_o),
        .cache_apb_pwdata_o(cache_apb_pwdata_o),
        .cache_apb_pstrb_o(cache_apb_pstrb_o),
        .cache_apb_prdata_i('0),
        .cache_apb_pready_i(1'b1),
        .cache_apb_pslverr_i('0),
        .irq_cache_i('0),
        .irq_src_i('0),
        .mtime_o(mtime_o),
        .irq_mtip_o(irq_mtip_o),
        .irq_msip_o(irq_msip_o),
        .irq_meip_o(irq_meip_o),
        .uart0_rx_i(1'b1),
        .uart0_tx_o(uart0_tx_o),
        .gpio_i('0),
        .gpio_o(gpio_o),
        .gpio_oe_o(gpio_oe_o),
        .i2c0_scl_i(2'b11),
        .i2c0_scl_o(i2c0_scl_o),
        .i2c0_scl_oe_o(i2c0_scl_oe_o),
        .i2c0_sda_i(2'b11),
        .i2c0_sda_o(i2c0_sda_o),
        .i2c0_sda_oe_o(i2c0_sda_oe_o),
        .sim_exit_valid_o(sim_exit_valid_o),
        .sim_exit_code_o(sim_exit_code_o)
    );

    reg media_pending = 0;
    reg [15:0] expected_addr = 0;
    reg expected_write = 0;
    reg [31:0] expected_data = 0;
    reg [3:0] expected_strb = 0;
    reg [31:0] scratch = 0;
    integer setup_count = 0;
    integer transfer_count = 0;
    integer wait_count = 0;
    integer checks = 0;
    reg monitor_soft = 0;

    // Engine register state resets; the APB transaction scoreboard retains its history.
    always @(posedge clk_mem_i or negedge rst_mem_n_o) begin
        if (!rst_mem_n_o) scratch <= 0;
        else if (media_apb_penable_o && |(media_apb_psel_o & media_apb_pready_i) &&
                 media_apb_pwrite_o) scratch <= media_apb_pwdata_o;
    end
    genvar slot;
    generate
        for (slot = 0; slot < 16; slot = slot + 1) begin : g_slot
            assign media_apb_prdata_i[slot*32 +: 32] =
                scratch ^ (32'hD0000000 | (32'(slot) << 16) | {20'd0, media_apb_paddr_o});
            assign media_apb_pready_i[slot] = wait_count == 5;
            assign media_apb_pslverr_i[slot] = 0;
        end
    endgenerate
    always @(posedge clk_mem_i) begin
        if (!rst_n_i) begin
            wait_count <= 0;
            setup_count <= 0;
            transfer_count <= 0;
        end else begin
            if (media_apb_psel_o == 0 || !media_apb_penable_o) wait_count <= 0;
            else wait_count <= wait_count + 1;
            if (rst_mem_core_n_o && media_apb_psel_o != 0) begin
                if (!media_pending)
                    $fatal(1, "FAIL replay without a pending media request at %0t", $time);
                if (media_apb_psel_o !== (16'b1 << expected_addr[15:12]) ||
                    media_apb_paddr_o !== expected_addr[11:0] ||
                    media_apb_pwrite_o !== expected_write ||
                    media_apb_pstrb_o !== expected_strb ||
                    (expected_write && media_apb_pwdata_o !== expected_data))
                    $fatal(1, "FAIL media APB payload addr=%h psel=%h at %0t",
                           media_apb_paddr_o, media_apb_psel_o, $time);
                if (!media_apb_penable_o) setup_count <= setup_count + 1;
                if (media_apb_penable_o && |(media_apb_psel_o & media_apb_pready_i))
                    transfer_count <= transfer_count + 1;
            end
        end
    end
    // spec 2.10: neither CDC endpoint nor the media decoder follows software reset.
    always @(posedge clk_sys_i) begin
        if (monitor_soft && (!u_dut.u_media_apb_async.rst_s_n_i ||
            !u_dut.u_media_apb_async.rst_m_n_i || !u_dut.u_media_apb_decoder.rst_n_i))
            $fatal(1, "FAIL media APB reset boundary changed during software reset at %0t", $time);
    end
    task automatic idle_check;
        repeat (16) begin
            @(posedge clk_sys_i);
            if (m1_bvalid_o || m1_rvalid_o)
                $fatal(1, "FAIL unsolicited AXI response B=%b R=%b at %0t",
                       m1_bvalid_o, m1_rvalid_o, $time);
        end
    endtask
    task automatic write_word(input [31:0] addr, input [31:0] data,
                              input bit cancelled_by_reset = 0);
        @(negedge clk_sys_i);
        m1_awid_i = 4'hA;
        m1_awaddr_i = addr;
        m1_awlen_i = 0;
        m1_awsize_i = 2;
        m1_awburst_i = 1;
        m1_awvalid_i = 1;
        do @(posedge clk_sys_i); while (!m1_awready_o);
        @(negedge clk_sys_i);
        m1_awvalid_i = 0;
        m1_wdata_i = addr[2] ? {data, 32'd0} : {32'd0, data};
        m1_wstrb_i = addr[2] ? 8'hF0 : 8'h0F;
        m1_wlast_i = 1;
        m1_wvalid_i = 1;
        do @(posedge clk_sys_i); while (!m1_wready_o);
        @(negedge clk_sys_i);
        m1_wvalid_i = 0;
        if (!cancelled_by_reset) begin
            do @(posedge clk_sys_i); while (!m1_bvalid_o);
            if (m1_bresp_o !== 0 || m1_bid_o !== 4'hA)
                $fatal(1, "FAIL AXI write addr=%h resp=%h id=%h at %0t",
                       addr, m1_bresp_o, m1_bid_o, $time);
            @(negedge clk_sys_i);
        end
    endtask
    task automatic read_word(input [31:0] addr, input [31:0] expected);
        reg [63:0] expected_bus;
        expected_bus = addr[2] ? {expected, 32'd0} : {32'd0, expected};
        @(negedge clk_sys_i);
        m1_arid_i = 4'hB;
        m1_araddr_i = addr;
        m1_arlen_i = 0;
        m1_arsize_i = 2;
        m1_arburst_i = 1;
        m1_arvalid_i = 1;
        do @(posedge clk_sys_i); while (!m1_arready_o);
        @(negedge clk_sys_i);
        m1_arvalid_i = 0;
        do @(posedge clk_sys_i); while (!m1_rvalid_o);
        if (m1_rresp_o !== 0 || m1_rid_o !== 4'hB || !m1_rlast_o ||
            m1_rdata_o !== expected_bus)
            $fatal(1, "FAIL AXI read addr=%h expected=%h actual=%h resp=%h id=%h at %0t",
                   addr, expected_bus, m1_rdata_o, m1_rresp_o, m1_rid_o, $time);
        @(negedge clk_sys_i);
    endtask
    task automatic media_access(input [15:0] addr, input bit wr, input [31:0] data);
        integer before_setup;
        integer before_transfer;
        reg [31:0] expected;
        before_setup = setup_count;
        before_transfer = transfer_count;
        media_pending = 1;
        expected_addr = addr;
        expected_write = wr;
        expected_data = data;
        expected_strb = wr ? 4'hF : 0;
        expected = scratch ^ (32'hD0000000 | (32'(addr[15:12]) << 16) | {20'd0, addr[11:0]});
        if (wr) write_word(32'h41000000 | {16'd0, addr}, data);
        else read_word(32'h41000000 | {16'd0, addr}, expected);
        media_pending = 0;
        if (setup_count != before_setup + 1 || transfer_count != before_transfer + 1)
            $fatal(1, "FAIL stale response or repeated APB setup=%0d transfers=%0d at %0t",
                   setup_count - before_setup, transfer_count - before_transfer, $time);
        checks = checks + 1;
        idle_check();
    endtask
    integer scenario;
    initial begin
        m1_bready_i = 1;
        m1_rready_i = 1;
        for (scenario = 0; scenario < 2; scenario = scenario + 1) begin
            // Start each scenario with one transaction: both CDC toggles have odd history.
            @(negedge clk_sys_i); rst_n_i = 0;
            repeat (5) @(negedge clk_sys_i);
            rst_n_i = 1;
            wait (rst_sys_n_o && rst_mem_n_o && rst_npu_n_o);
            idle_check();
            media_access(16'h3004, 1, 32'h1234A5A5);
            if (transfer_count != 1) $fatal(1, "FAIL reset scenario must start after odd count");
            monitor_soft = 1;
            write_word(32'h40006018, scenario == 0 ? 1 : 2, scenario == 1);
            wait (!rst_mem_n_o);
            #1;
            if (rst_sys_n_o !== (scenario == 0) || rst_npu_n_o ||
                !rst_sys_por_n_o || !rst_mem_core_n_o)
                $fatal(1, "FAIL software reset selection scenario=%0d at %0t", scenario, $time);
            wait (rst_sys_n_o && rst_mem_n_o && rst_npu_n_o);
            idle_check();
            monitor_soft = 0;
            // Different slots and payloads distinguish fresh requests from an old response.
            media_access(16'h9008, 0, 0);
            media_access(16'hA004, 1, 32'h5A5A6789);
            media_access(16'hB000, 0, 0);
            $display("PASS %s soft reset after odd media APB history", scenario == 0 ? "MEDIA" : "SOC");
        end
        $display("PASS sys_subsys_reset checks=%0d", checks);
        $finish;
    end
    initial begin
        #200000;
        $fatal(1, "FAIL sys_subsys_reset timeout");
    end
endmodule
