// File: edrv32_sys_cpu_tb.sv
// Spec: sys-subsys-testplan 3.6 SC-01--SC-08; cpu-spec 3.4, 7.1.
// Description: Run real ROM boot software through the CPU and system subsystems.
//              Observe UART, SIM_EXIT and benchmark retirement/HPM windows.
// Clock domains: clk_sys and clk_mem; unused engine clock ports use clk_mem.
/* verilator lint_off BLKSEQ */
module edrv32_sys_cpu_tb;
    /* verilator lint_off UNUSEDPARAM */
    `include "edrv32_soc_map.vh"
    /* verilator lint_on UNUSEDPARAM */
    reg clk_sys = 0;
    reg clk_mem = 0;
    always #(5.0e8 / real'(EDRV32_CLK_SYS_HZ)) clk_sys = ~clk_sys;
    always #4.0 clk_mem = ~clk_mem;
    reg rst_n = 0;
    reg mem_ready = 0;
    reg [15:0] gpio = 16'h0001;
    wire uart_rx;
    wire uart_tx;
    wire [1:0] scl_i;
    wire [1:0] sda_i;
    wire [1:0] peer_sda_oe;
    edrv32_axi64_if ibus();
    edrv32_axi64_if dbus();
    edrv32_axi64_if ddr();
    int unsigned ddr_latency = 20;
    int case_id = 1;
    int scratch_download = 0;
    longint unsigned cycle_count = 0;
    longint unsigned timeout_cycles = 100000000;
    bit [151:0] uart_tail = 0;
    bit download_ready = 0;
    string uart_line = "";
    int unsigned menu_count = 0;
    bit iterations_ready = 0;
    string image;
    bit gpio_trigger = 0;
    bit selected_port = 0;
    /* verilator lint_off SYNCASYNCNET */
    wire rst_sys_n;
    wire rst_mem_core_n;
    /* verilator lint_on SYNCASYNCNET */
    wire [11:0] apb_paddr;
    wire apb_psel;
    wire apb_penable;
    wire apb_pwrite;
    wire [31:0] apb_pwdata;
    wire [3:0] apb_pstrb;
    wire apb_pready;
    wire [31:0] apb_prdata;
    wire apb_pslverr;
    wire irq_meip;
    wire irq_msip;
    wire irq_mtip;
    wire [63:0] mtime;
    wire [63:0] debug;
    wire irq_cache;
    wire unused_rst_sys_por_n;
    wire unused_rst_mem_n;
    wire unused_rst_pix_n;
    wire unused_rst_cam0_n;
    wire unused_rst_cam1_n;
    wire unused_rst_eth_rx_n;
    wire unused_rst_eth_tx_n;
    wire [11:0] unused_media_apb_paddr;
    wire [15:0] unused_media_apb_psel;
    wire unused_media_apb_penable;
    wire unused_media_apb_pwrite;
    wire [31:0] unused_media_apb_pwdata;
    wire [3:0] unused_media_apb_pstrb;
    wire [15:0] unused_gpio;
    wire [15:0] unused_gpio_oe;
    wire [1:0] scl_o;
    wire [1:0] scl_oe;
    wire [1:0] sda_o;
    wire [1:0] sda_oe;
    wire sim_exit_valid;
    wire [31:0] sim_exit_code;

    edrv32_cpu_subsys u_cpu (
        // Clock and reset.
        .clk_i(clk_sys),
        .rst_n_i(rst_sys_n),

        // I$ AXI64 read master.
        .iaxi_arid_o(ibus.arid),
        .iaxi_araddr_o(ibus.araddr),
        .iaxi_arlen_o(ibus.arlen),
        .iaxi_arsize_o(ibus.arsize),
        .iaxi_arburst_o(ibus.arburst),
        .iaxi_arvalid_o(ibus.arvalid),
        .iaxi_arready_i(ibus.arready),
        .iaxi_rid_i(ibus.rid),
        .iaxi_rdata_i(ibus.rdata),
        .iaxi_rresp_i(ibus.rresp),
        .iaxi_rlast_i(ibus.rlast),
        .iaxi_rvalid_i(ibus.rvalid),
        .iaxi_rready_o(ibus.rready),

        // D$ AXI64 read/write master.
        .daxi_awid_o(dbus.awid),
        .daxi_awaddr_o(dbus.awaddr),
        .daxi_awlen_o(dbus.awlen),
        .daxi_awsize_o(dbus.awsize),
        .daxi_awburst_o(dbus.awburst),
        .daxi_awvalid_o(dbus.awvalid),
        .daxi_awready_i(dbus.awready),
        .daxi_wdata_o(dbus.wdata),
        .daxi_wstrb_o(dbus.wstrb),
        .daxi_wlast_o(dbus.wlast),
        .daxi_wvalid_o(dbus.wvalid),
        .daxi_wready_i(dbus.wready),
        .daxi_bid_i(dbus.bid),
        .daxi_bresp_i(dbus.bresp),
        .daxi_bvalid_i(dbus.bvalid),
        .daxi_bready_o(dbus.bready),
        .daxi_arid_o(dbus.arid),
        .daxi_araddr_o(dbus.araddr),
        .daxi_arlen_o(dbus.arlen),
        .daxi_arsize_o(dbus.arsize),
        .daxi_arburst_o(dbus.arburst),
        .daxi_arvalid_o(dbus.arvalid),
        .daxi_arready_i(dbus.arready),
        .daxi_rid_i(dbus.rid),
        .daxi_rdata_i(dbus.rdata),
        .daxi_rresp_i(dbus.rresp),
        .daxi_rlast_i(dbus.rlast),
        .daxi_rvalid_i(dbus.rvalid),
        .daxi_rready_o(dbus.rready),

        // APB cache control slave.
        .apb_paddr_i(apb_paddr),
        .apb_psel_i(apb_psel),
        .apb_penable_i(apb_penable),
        .apb_pwrite_i(apb_pwrite),
        .apb_pwdata_i(apb_pwdata),
        .apb_pstrb_i(apb_pstrb),
        .apb_pready_o(apb_pready),
        .apb_prdata_o(apb_prdata),
        .apb_pslverr_o(apb_pslverr),

        // Interrupts and debug.
        .irq_meip_i(irq_meip),
        .irq_msip_i(irq_msip),
        .irq_mtip_i(irq_mtip),
        .mtime_i(mtime),
        .debug_o(debug),
        .irq_o(irq_cache)
    );

    edrv32_sys_subsys u_sys (
        // Domain clocks and asynchronous reset/status.
        .clk_sys_i(clk_sys),
        .clk_mem_i(clk_mem),
        .clk_pix_i(clk_mem),
        .cam0_pclk_i(clk_mem),
        .cam1_pclk_i(clk_mem),
        .eth_rx_clk_i(clk_mem),
        .eth_tx_clk_i(clk_mem),
        .rst_n_i(rst_n),
        .mem_ready_i(mem_ready),

        // Sequenced domain resets (spec 2.10).
        .rst_sys_por_n_o(unused_rst_sys_por_n),
        .rst_sys_n_o(rst_sys_n),
        .rst_mem_core_n_o(rst_mem_core_n),
        .rst_mem_n_o(unused_rst_mem_n),
        .rst_pix_n_o(unused_rst_pix_n),
        .rst_cam0_n_o(unused_rst_cam0_n),
        .rst_cam1_n_o(unused_rst_cam1_n),
        .rst_eth_rx_n_o(unused_rst_eth_rx_n),
        .rst_eth_tx_n_o(unused_rst_eth_tx_n),

        // m0 AXI64 interface.
        .m0_arid_i(ibus.arid),
        .m0_araddr_i(ibus.araddr),
        .m0_arlen_i(ibus.arlen),
        .m0_arsize_i(ibus.arsize),
        .m0_arburst_i(ibus.arburst),
        .m0_arvalid_i(ibus.arvalid),
        .m0_arready_o(ibus.arready),
        .m0_rid_o(ibus.rid),
        .m0_rdata_o(ibus.rdata),
        .m0_rresp_o(ibus.rresp),
        .m0_rlast_o(ibus.rlast),
        .m0_rvalid_o(ibus.rvalid),
        .m0_rready_i(ibus.rready),

        // m1 AXI64 interface.
        .m1_awid_i(dbus.awid),
        .m1_awaddr_i(dbus.awaddr),
        .m1_awlen_i(dbus.awlen),
        .m1_awsize_i(dbus.awsize),
        .m1_awburst_i(dbus.awburst),
        .m1_awvalid_i(dbus.awvalid),
        .m1_awready_o(dbus.awready),
        .m1_wdata_i(dbus.wdata),
        .m1_wstrb_i(dbus.wstrb),
        .m1_wlast_i(dbus.wlast),
        .m1_wvalid_i(dbus.wvalid),
        .m1_wready_o(dbus.wready),
        .m1_bid_o(dbus.bid),
        .m1_bresp_o(dbus.bresp),
        .m1_bvalid_o(dbus.bvalid),
        .m1_bready_i(dbus.bready),
        .m1_arid_i(dbus.arid),
        .m1_araddr_i(dbus.araddr),
        .m1_arlen_i(dbus.arlen),
        .m1_arsize_i(dbus.arsize),
        .m1_arburst_i(dbus.arburst),
        .m1_arvalid_i(dbus.arvalid),
        .m1_arready_o(dbus.arready),
        .m1_rid_o(dbus.rid),
        .m1_rdata_o(dbus.rdata),
        .m1_rresp_o(dbus.rresp),
        .m1_rlast_o(dbus.rlast),
        .m1_rvalid_o(dbus.rvalid),
        .m1_rready_i(dbus.rready),

        // s6 AXI64 interface.
        .s6_awid_o(ddr.awid),
        .s6_awaddr_o(ddr.awaddr),
        .s6_awlen_o(ddr.awlen),
        .s6_awsize_o(ddr.awsize),
        .s6_awburst_o(ddr.awburst),
        .s6_awvalid_o(ddr.awvalid),
        .s6_awready_i(ddr.awready),
        .s6_wdata_o(ddr.wdata),
        .s6_wstrb_o(ddr.wstrb),
        .s6_wlast_o(ddr.wlast),
        .s6_wvalid_o(ddr.wvalid),
        .s6_wready_i(ddr.wready),
        .s6_bid_i(ddr.bid),
        .s6_bresp_i(ddr.bresp),
        .s6_bvalid_i(ddr.bvalid),
        .s6_bready_o(ddr.bready),
        .s6_arid_o(ddr.arid),
        .s6_araddr_o(ddr.araddr),
        .s6_arlen_o(ddr.arlen),
        .s6_arsize_o(ddr.arsize),
        .s6_arburst_o(ddr.arburst),
        .s6_arvalid_o(ddr.arvalid),
        .s6_arready_i(ddr.arready),
        .s6_rid_i(ddr.rid),
        .s6_rdata_i(ddr.rdata),
        .s6_rresp_i(ddr.rresp),
        .s6_rlast_i(ddr.rlast),
        .s6_rvalid_i(ddr.rvalid),
        .s6_rready_o(ddr.rready),

        // Media decoded APB interface.
        .media_apb_paddr_o(unused_media_apb_paddr),
        .media_apb_psel_o(unused_media_apb_psel),
        .media_apb_penable_o(unused_media_apb_penable),
        .media_apb_pwrite_o(unused_media_apb_pwrite),
        .media_apb_pwdata_o(unused_media_apb_pwdata),
        .media_apb_pstrb_o(unused_media_apb_pstrb),
        .media_apb_prdata_i(512'd0),
        .media_apb_pready_i(16'hFFFF),
        .media_apb_pslverr_i(16'hFFFF),

        // Cache decoded APB interface.
        .cache_apb_paddr_o(apb_paddr),
        .cache_apb_psel_o(apb_psel),
        .cache_apb_penable_o(apb_penable),
        .cache_apb_pwrite_o(apb_pwrite),
        .cache_apb_pwdata_o(apb_pwdata),
        .cache_apb_pstrb_o(apb_pstrb),
        .cache_apb_prdata_i(apb_prdata),
        .cache_apb_pready_i(apb_pready),
        .cache_apb_pslverr_i(apb_pslverr),

        // External interrupt sources.
        .irq_cache_i(irq_cache),
        .irq_src_i(8'd0),

        // clint pins and status.
        .mtime_o(mtime),
        .irq_mtip_o(irq_mtip),
        .irq_msip_o(irq_msip),

        // plic pins and status.
        .irq_meip_o(irq_meip),

        // uart pins and status.
        .uart0_rx_i(uart_rx),
        .uart0_tx_o(uart_tx),

        // gpio pins and status.
        .gpio_i(gpio),
        .gpio_o(unused_gpio),
        .gpio_oe_o(unused_gpio_oe),

        // i2c pins and status.
        .i2c0_scl_i(scl_i),
        .i2c0_scl_o(scl_o),
        .i2c0_scl_oe_o(scl_oe),
        .i2c0_sda_i(sda_i),
        .i2c0_sda_o(sda_o),
        .i2c0_sda_oe_o(sda_oe),

        // sysctrl pins and status.
        .sim_exit_valid_o(sim_exit_valid),
        .sim_exit_code_o(sim_exit_code)
    );

    // I$ exposes only the read half of its AXI interface.
    assign ibus.awid = 0;
    assign ibus.awaddr = 0;
    assign ibus.awlen = 0;
    assign ibus.awsize = 0;
    assign ibus.awburst = 0;
    assign ibus.awvalid = 0;
    assign ibus.wdata = 0;
    assign ibus.wstrb = 0;
    assign ibus.wlast = 0;
    assign ibus.wvalid = 0;
    assign ibus.bready = 1;

    edrv32_cpu_b2_memory u_ddr (
        .clk_i(clk_sys),
        .rst_n_i(rst_mem_core_n),
        .read_latency_i(ddr_latency),
        .bus(ddr)
    );
    edrv32_axi64_checker #(.INSTRUCTION(1)) u_icheck (
        .clk_i(clk_sys),
        .rst_n_i(rst_sys_n),
        .bus(ibus)
    );
    edrv32_axi64_checker u_dcheck (
        .clk_i(clk_sys),
        .rst_n_i(rst_sys_n),
        .bus(dbus)
    );
    uart_model u_uart (
        .tx_i(uart_tx),
        .rx_o(uart_rx)
    );
    sccb_model u_cam0 (
        .scl_i(scl_i[0]),
        .sda_i(sda_i[0]),
        .sda_oe_o(peer_sda_oe[0])
    );
    sccb_model u_cam1 (
        .scl_i(scl_i[1]),
        .sda_i(sda_i[1]),
        .sda_oe_o(peer_sda_oe[1])
    );
    assign scl_i = ~(scl_oe & ~scl_o);
    assign sda_i = ~((sda_oe & ~sda_o) | peer_sda_oe);

    initial begin : log_uart
        byte unsigned data;
        forever begin
            wait (u_uart.received.size() != 0);
            data = u_uart.received.pop_front();
            uart_tail = {uart_tail[143:0], data};
            if (uart_tail == "UART download ready") download_ready = 1;
            if (data == 8'h0a) begin
                if (uart_line == "Menu: 1=CoreMark 2=Peripheral tests 3=System info\r")
                    menu_count++;
                if (uart_line == {"Iterations input: decimal 1..4294967295 then Enter; ",
                                    "Enter selects default\r"}) iterations_ready = 1;
                uart_line = "";
            end else uart_line = {uart_line, string'(data)};
            $write("%c", data);
            $fflush();
        end
    end
    task automatic load_ddr(input string path);
        integer fd;
        integer parsed;
        string token;
        bit [31:0] addr;
        bit [31:0] value;
        fd = $fopen(path, "r");
        if (fd == 0) $fatal(1, "FAIL cannot open DDR image %s", path);
        addr = 32'h80000000;
        while ($fscanf(fd, "%s", token) == 1) begin
            if (token.substr(0, 0) == "@") begin
                parsed = $sscanf(token, "@%h", value);
                addr = 32'h80000000 + value;
            end else begin
                parsed = $sscanf(token, "%h", value);
                if (parsed != 1) $fatal(1, "FAIL invalid DDR image token %s", token);
                edrv32_axi64_memory_pkg::bus_store(addr, value[7:0]);
                addr++;
            end
        end
        $fclose(fd);
    endtask
    initial begin
        edrv32_axi64_memory_pkg::random_stalls = 0;
        edrv32_axi64_memory_pkg::delay_max = 0;
        void'($value$plusargs("CASE_ID=%d", case_id));
        void'($value$plusargs("DDR_LATENCY=%d", ddr_latency));
        void'($value$plusargs("TIMEOUT=%d", timeout_cycles));
        void'($value$plusargs("SCRATCH_DOWNLOAD=%d", scratch_download));
        if ($value$plusargs("DDR_HEX=%s", image)) load_ddr(image);
        if (case_id == 4 && scratch_download == 0) gpio[0] = 0;
        repeat (5) @(negedge clk_sys);
        rst_n = 1;
        repeat (7) @(negedge clk_mem);
        mem_ready = 1;
    end
    initial begin : uart_download
        integer fd;
        integer value;
        int unsigned length;
        string path;
        if ($value$plusargs("DOWNLOAD_BIN=%s", path)) begin
            void'($value$plusargs("DOWNLOAD_LENGTH=%d", length));
            wait (download_ready);
            // The ROM owns protocol parsing; the peer supplies the exact raw image contract.
            for (int n = 0; n < 4; n++) u_uart.send(8'(length >> (8*n)));
            fd = $fopen(path, "rb");
            if (fd == 0) $fatal(1, "FAIL cannot open download %s", path);
            value = $fgetc(fd);
            while (value != -1) begin
                u_uart.send(8'(value));
                value = $fgetc(fd);
            end
            $fclose(fd);
        end
    end
    initial begin : monitor_commands
        // SC-08 ends after both operations return; monitor never owns SIM_EXIT.
        wait (rst_n);
        if (case_id == 8) begin
            wait (menu_count == 1);
            u_uart.send(8'h33);
            u_uart.send(8'h0d);
            wait (menu_count == 2);
            u_uart.send(8'h31);
            u_uart.send(8'h0d);
            wait (iterations_ready);
            u_uart.send(8'h31);
            u_uart.send(8'h0a);
            wait (menu_count == 3);
            $display("PASS sys_cpu SC-08");
            $finish;
        end
    end
    initial begin
        wait (gpio_trigger);
        @(negedge clk_sys);
        gpio[1] = 1;
    end
    always @(posedge clk_sys) begin
        if (!rst_sys_n) selected_port <= 0;
        else begin
            if (case_id == 3 && u_sys.u_sysctrl.apb_psel_i &&
                u_sys.u_sysctrl.apb_penable_i && u_sys.u_sysctrl.apb_pwrite_i &&
                u_sys.u_sysctrl.apb_paddr_i == 12'h014 &&
                u_sys.u_sysctrl.apb_pwdata_i == 32'h53430003) gpio_trigger <= 1;
            if (u_sys.u_i2c.apb_psel_i && u_sys.u_i2c.apb_penable_i &&
                u_sys.u_i2c.apb_pwrite_i && u_sys.u_i2c.apb_paddr_i == 12'h004)
                selected_port <= u_sys.u_i2c.apb_pwdata_i[1];
            if (case_id == 5 && (scl_oe[!selected_port] || sda_oe[!selected_port]))
                $fatal(1, "FAIL unselected I2C port driven at %0t", $time);
        end
    end
    longint unsigned total_events[16];
    longint unsigned events[16];
    longint unsigned start_hpm[8];
    longint unsigned start_cycle;
    longint unsigned start_instret;
    bit measuring = 0;
    bit perf_enabled;
    bit boot_seen = 0;
    bit [31:0] app_entry = 32'h10000000;
    bit [31:0] perf_begin;
    bit [31:0] perf_end;
    bit [1:0] read_window = 0;
    longint unsigned read_start[2];
    longint unsigned fill_count[2];
    longint unsigned fill_cycles[2];
    longint unsigned miss_wait_cycles[2];
    initial begin
        perf_enabled = $value$plusargs("PERF_BEGIN=%h", perf_begin);
        void'($value$plusargs("PERF_END=%h", perf_end));
        void'($value$plusargs("APP_ENTRY=%h", app_entry));
    end
    task automatic report_window;
        $display("SC_WINDOW cycles=%0d instret=%0d",
                    u_cpu.u_core.u_csr.cycle_r - start_cycle,
                    u_cpu.u_core.u_csr.instret_r - start_instret);
        for (int e = 0; e < 16; e++)
            $display("SC_HPM window=0 event=%0d count=%0d", e+1, events[e]);
        for (int c = 0; c < 8; c++)
            $display("SC_CSR_HPM counter=%0d event=%0d count=%0d", c+3,
                        u_cpu.u_core.u_csr.event_r[c],
                        u_cpu.u_core.u_csr.counter_r[c]-start_hpm[c]);
        for (int channel = 0; channel < 2; channel++) begin
            $display("SC_FILL channel=%0d count=%0d service_cycles=%0d", channel,
                        fill_count[channel], fill_cycles[channel]);
            $display("SC_MISSWAIT channel=%0d cycles=%0d", channel, miss_wait_cycles[channel]);
        end
    endtask
    always @(posedge clk_sys) begin
        if (!rst_sys_n) begin
            cycle_count <= 0;
            measuring = 0;
            boot_seen = 0;
            read_window <= 0;
            for (int e = 0; e < 16; e++) begin
                total_events[e] = 0;
                events[e] = 0;
            end
            for (int channel = 0; channel < 2; channel++) begin
                fill_count[channel] = 0;
                fill_cycles[channel] = 0;
                miss_wait_cycles[channel] = 0;
            end
        end else begin
            cycle_count <= cycle_count + 1;
            for (int e = 0; e < 16; e++)
                total_events[e] += 64'(u_cpu.u_core.event_count_w[e*2 +: 2]);
            for (int lane = 0; lane < 2; lane++) begin
                if (u_cpu.u_core.trace_valid_w[lane]) begin
                    if (!boot_seen && u_cpu.u_core.trace_pc_w[lane*32 +: 32] == app_entry) begin
                        boot_seen = 1;
                        $display("SC_BOOT cycles=%0d instret=%0d", u_cpu.u_core.u_csr.cycle_r,
                                    u_cpu.u_core.u_csr.instret_r);
                    end
                    if (perf_enabled &&
                        u_cpu.u_core.trace_pc_w[lane*32 +: 32] == perf_begin) begin
                        measuring = 1;
                        start_cycle = u_cpu.u_core.u_csr.cycle_r;
                        start_instret = u_cpu.u_core.u_csr.instret_r;
                        for (int c = 0; c < 8; c++) start_hpm[c] = u_cpu.u_core.u_csr.counter_r[c];
                    end
                    if (perf_enabled && u_cpu.u_core.trace_pc_w[lane*32 +: 32] == perf_end) begin
                        report_window();
                        measuring = 0;
                    end
                end
            end
            if (measuring) begin
                for (int e = 0; e < 16; e++)
                    events[e] += 64'(u_cpu.u_core.event_count_w[e*2 +: 2]);
                miss_wait_cycles[0] += 64'(debug[27]);
                miss_wait_cycles[1] += 64'(debug[28]);
            end
            if (ibus.arvalid && ibus.arready) begin
                read_start[0] = cycle_count;
                read_window[0] <= measuring && ibus.arlen == 3;
            end
            if (dbus.arvalid && dbus.arready) begin
                read_start[1] = cycle_count;
                read_window[1] <= measuring && dbus.arlen == 3;
            end
            if (ibus.rvalid && ibus.rready && ibus.rlast) begin
                if (measuring && read_window[0]) begin
                    fill_count[0]++;
                    fill_cycles[0] += cycle_count - read_start[0];
                end
            end
            if (dbus.rvalid && dbus.rready && dbus.rlast) begin
                if (measuring && read_window[1]) begin
                    fill_count[1]++;
                    fill_cycles[1] += cycle_count - read_start[1];
                end
            end
            if (cycle_count >= timeout_cycles)
                $fatal(1, "FAIL SC timeout case=%0d cycles=%0d debug=%h", case_id,
                        cycle_count, debug);
            if (sim_exit_valid) begin
                if (case_id == 8) $fatal(1, "FAIL monitor wrote SIM_EXIT before menu return");
                if (sim_exit_code != 0)
                    $fatal(1, "FAIL SC-%02d SIM_EXIT=%h", case_id, sim_exit_code);
                if (case_id == 5) begin
                    if (u_cam0.writes != 8 || u_cam1.writes != 8)
                        $fatal(1, "FAIL SCCB write counts cam0=%0d cam1=%0d",
                                u_cam0.writes, u_cam1.writes);
                    for (int n = 0; n < 8; n++) begin
                        if (u_cam0.registers['h3000+n] != 8'('h40+n) ||
                            u_cam1.registers['h3000+n] != 8'('h50+n))
                            $fatal(1, "FAIL SCCB register index=%0d", n);
                    end
                end
                $display("SC_TOTAL cycles=%0d instret=%0d DDR_LATENCY=%0d",
                            u_cpu.u_core.u_csr.cycle_r, u_cpu.u_core.u_csr.instret_r, ddr_latency);
                for (int e = 0; e < 16; e++)
                    $display("SC_HPM window=total event=%0d count=%0d", e+1, total_events[e]);
                $display("PASS sys_cpu SC-%02d", case_id);
                $finish;
            end
        end
    end
endmodule
/* verilator lint_on BLKSEQ */
