// File: edrv32_sys_subsys.sv
// Spec: sys-subsys 3.4 (v0.2).
// Description: Interface timing stub; no peripheral functional implementation.
// Clock domains: clk_sys and clk_mem; behavioral transaction scheduling only.
module edrv32_sys_subsys (
    input logic clk_sys_i,
    input logic clk_mem_i,
    input logic clk_pix_i,
    input logic cam0_pclk_i,
    input logic cam1_pclk_i,
    input logic eth_rx_clk_i,
    input logic eth_tx_clk_i,
    input logic rst_n_i,
    input logic mem_ready_i,
    output logic rst_sys_n_o,
    output logic rst_mem_core_n_o,
    output logic rst_mem_n_o,
    output logic rst_pix_n_o,
    output logic rst_cam0_n_o,
    output logic rst_cam1_n_o,
    output logic rst_eth_rx_n_o,
    output logic rst_eth_tx_n_o,
    input logic [3:0] m0_arid_i,
    input logic [31:0] m0_araddr_i,
    input logic [7:0] m0_arlen_i,
    input logic [2:0] m0_arsize_i,
    input logic [1:0] m0_arburst_i,
    input logic m0_arvalid_i,
    output logic m0_arready_o,
    output logic [3:0] m0_rid_o,
    output logic [63:0] m0_rdata_o,
    output logic [1:0] m0_rresp_o,
    output logic m0_rlast_o,
    output logic m0_rvalid_o,
    input logic m0_rready_i,
    input logic [3:0] m1_awid_i,
    input logic [31:0] m1_awaddr_i,
    input logic [7:0] m1_awlen_i,
    input logic [2:0] m1_awsize_i,
    input logic [1:0] m1_awburst_i,
    input logic m1_awvalid_i,
    output logic m1_awready_o,
    input logic [63:0] m1_wdata_i,
    input logic [7:0] m1_wstrb_i,
    input logic m1_wlast_i,
    input logic m1_wvalid_i,
    output logic m1_wready_o,
    output logic [3:0] m1_bid_o,
    output logic [1:0] m1_bresp_o,
    output logic m1_bvalid_o,
    input logic m1_bready_i,
    input logic [3:0] m1_arid_i,
    input logic [31:0] m1_araddr_i,
    input logic [7:0] m1_arlen_i,
    input logic [2:0] m1_arsize_i,
    input logic [1:0] m1_arburst_i,
    input logic m1_arvalid_i,
    output logic m1_arready_o,
    output logic [3:0] m1_rid_o,
    output logic [63:0] m1_rdata_o,
    output logic [1:0] m1_rresp_o,
    output logic m1_rlast_o,
    output logic m1_rvalid_o,
    input logic m1_rready_i,
    output logic [3:0] s6_awid_o,
    output logic [31:0] s6_awaddr_o,
    output logic [7:0] s6_awlen_o,
    output logic [2:0] s6_awsize_o,
    output logic [1:0] s6_awburst_o,
    output logic s6_awvalid_o,
    input logic s6_awready_i,
    output logic [63:0] s6_wdata_o,
    output logic [7:0] s6_wstrb_o,
    output logic s6_wlast_o,
    output logic s6_wvalid_o,
    input logic s6_wready_i,
    input logic [3:0] s6_bid_i,
    input logic [1:0] s6_bresp_i,
    input logic s6_bvalid_i,
    output logic s6_bready_o,
    output logic [3:0] s6_arid_o,
    output logic [31:0] s6_araddr_o,
    output logic [7:0] s6_arlen_o,
    output logic [2:0] s6_arsize_o,
    output logic [1:0] s6_arburst_o,
    output logic s6_arvalid_o,
    input logic s6_arready_i,
    input logic [3:0] s6_rid_i,
    input logic [63:0] s6_rdata_i,
    input logic [1:0] s6_rresp_i,
    input logic s6_rlast_i,
    input logic s6_rvalid_i,
    output logic s6_rready_o,
    output logic [11:0] media_apb_paddr_o,
    output logic [15:0] media_apb_psel_o,
    output logic media_apb_penable_o,
    output logic media_apb_pwrite_o,
    output logic [31:0] media_apb_pwdata_o,
    output logic [3:0] media_apb_pstrb_o,
    input logic [511:0] media_apb_prdata_i,
    input logic [15:0] media_apb_pready_i,
    input logic [15:0] media_apb_pslverr_i,
    output logic [11:0] cache_apb_paddr_o,
    output logic cache_apb_psel_o,
    output logic cache_apb_penable_o,
    output logic cache_apb_pwrite_o,
    output logic [31:0] cache_apb_pwdata_o,
    output logic [3:0] cache_apb_pstrb_o,
    input logic [31:0] cache_apb_prdata_i,
    input logic cache_apb_pready_i,
    input logic cache_apb_pslverr_i,
    input logic irq_cache_i,
    input logic [15:8] irq_src_i,
    output logic irq_meip_o,
    output logic irq_msip_o,
    output logic irq_mtip_o,
    output logic [63:0] mtime_o,
    output logic uart0_tx_o,
    input logic uart0_rx_i,
    output logic [15:0] gpio_o,
    output logic [15:0] gpio_oe_o,
    input logic [15:0] gpio_i,
    output logic [1:0] i2c0_scl_o,
    output logic [1:0] i2c0_scl_oe_o,
    input logic [1:0] i2c0_scl_i,
    output logic [1:0] i2c0_sda_o,
    output logic [1:0] i2c0_sda_oe_o,
    input logic [1:0] i2c0_sda_i,
    output logic sim_exit_valid_o,
    output logic [31:0] sim_exit_code_o
);
    wire unused_stub_inputs = &{
        clk_pix_i,
        cam0_pclk_i,
        cam1_pclk_i,
        eth_rx_clk_i,
        eth_tx_clk_i,
        m0_arid_i,
        m0_arburst_i,
        m1_awid_i,
        m1_awburst_i,
        m1_wlast_i,
        m1_arid_i,
        m1_arburst_i,
        s6_awready_i,
        s6_wready_i,
        s6_bid_i,
        s6_bresp_i,
        s6_bvalid_i,
        s6_arready_i,
        s6_rid_i,
        s6_rdata_i,
        s6_rresp_i,
        s6_rlast_i,
        s6_rvalid_i,
        irq_cache_i,
        irq_src_i,
        gpio_i,
        i2c0_scl_i,
        i2c0_sda_i
    };
    import edrv32_axi64_memory_pkg::*;
    // The generated map intentionally also contains constants for other clients.
    /* verilator lint_off UNUSEDPARAM */
    `include "edrv32_soc_map.vh"
    /* verilator lint_on UNUSEDPARAM */
    // The timing stub uses separate backdoor arrays from the reference scoreboard.
    initial begin : preload
        string path;
        bit [63:0] rom[2048];
        bit [63:0] sram[32768];
        if ($value$plusargs("ROM_HEX=%s", path)) begin
            $readmemh(path, rom);
            for (int n = 0; n < 2048; n++)
                for (int b = 0; b < 8; b++)
                    bus_store(EDRV32_ROM_BASE + 32'(n*8+b), rom[n][b*8 +: 8]);
        end
        if ($value$plusargs("SRAM_HEX=%s", path)) begin
            $readmemh(path, sram);
            for (int n = 0; n < 32768; n++)
                for (int b = 0; b < 8; b++)
                    bus_store(EDRV32_SRAM_BASE + 32'(n*8+b), sram[n][b*8 +: 8]);
        end
    end
    function automatic int region(
        input bit [31:0] addr
    );
        if (addr < EDRV32_ROM_BASE + EDRV32_ROM_SIZE) return 0;
        if (addr >= EDRV32_SRAM_BASE && addr - EDRV32_SRAM_BASE < EDRV32_SRAM_SIZE)
            return 1;
        if (addr >= EDRV32_CLINT_BASE && addr - EDRV32_CLINT_BASE < EDRV32_CLINT_SIZE)
            return 2;
        if (addr >= EDRV32_PLIC_BASE && addr - EDRV32_PLIC_BASE < EDRV32_PLIC_SIZE)
            return 3;
        if (addr >= EDRV32_SYS_APB_BASE && addr - EDRV32_SYS_APB_BASE < EDRV32_SYS_APB_SIZE)
            return 4;
        if (addr >= EDRV32_MEDIA_APB_BASE &&
            addr - EDRV32_MEDIA_APB_BASE < EDRV32_MEDIA_APB_SIZE) return 5;
        if (addr >= EDRV32_DDR_BASE) return 6;
        return -1;
    endfunction
    task automatic apb_access(
        input bit wr,
        input bit [31:0] addr,
        input bit [31:0] data,
        input bit [3:0] strb,
        output bit [31:0] result,
        output bit [1:0] resp
    );
        int slot;
        bit ready_seen;
        slot = int'(addr[15:12]);
        result = 0;
        resp = 2;
        if (region(addr) == 5 && slot < 10) begin
            @(negedge clk_mem_i);
            media_apb_paddr_o = addr[11:0];
            media_apb_psel_o = 16'b1 << slot;
            media_apb_pwrite_o = wr;
            media_apb_pwdata_o = data;
            media_apb_pstrb_o = strb;
            media_apb_penable_o = 0;
            @(negedge clk_mem_i);
            media_apb_penable_o = 1;
            ready_seen = 0;
            for (int n = 0; n < 256 && !ready_seen; n++) begin
                @(posedge clk_mem_i);
                if (media_apb_pready_i[slot]) begin
                    result = media_apb_prdata_i[slot*32 +: 32];
                    resp = media_apb_pslverr_i[slot] ? 2 : 0;
                    ready_seen = 1;
                end
            end
            @(negedge clk_mem_i);
            media_apb_psel_o = 0;
            media_apb_penable_o = 0;
        end else if (region(addr) == 4 && slot == 5) begin
            @(negedge clk_sys_i);
            cache_apb_paddr_o = addr[11:0];
            cache_apb_psel_o = 1;
            cache_apb_pwrite_o = wr;
            cache_apb_pwdata_o = data;
            cache_apb_pstrb_o = strb;
            @(negedge clk_sys_i);
            cache_apb_penable_o = 1;
            ready_seen = 0;
            for (int n = 0; n < 256 && !ready_seen; n++) begin
                @(posedge clk_sys_i);
                if (cache_apb_pready_i) begin
                    result = cache_apb_prdata_i;
                    resp = cache_apb_pslverr_i ? 2 : 0;
                    ready_seen = 1;
                end
            end
            @(negedge clk_sys_i);
            cache_apb_psel_o = 0;
            cache_apb_penable_o = 0;
        end
    endtask
    initial begin : m0_read
        bit [31:0] addr;
        int len;
        int size;
        int target;
        bit [31:0] apb_data;
        bit [1:0] resp;
        m0_arready_o = 0;
        m0_rvalid_o = 0;
        m0_rid_o = 0;
        m0_rdata_o = 0;
        m0_rresp_o = 0;
        m0_rlast_o = 0;
        forever begin
            wait (rst_sys_n_o);
            @(negedge clk_sys_i);
            m0_arready_o = 1;
            do @(posedge clk_sys_i); while (!m0_arvalid_i);
            addr = m0_araddr_i;
            len = int'(m0_arlen_i);
            size = int'(m0_arsize_i);
            target = region(addr);
            resp = (target < 0 || (1 && target >= 2 && target <= 5))
                    ? 3 : ((target >= 2 && target <= 5) ? 2 : 0);
            @(negedge clk_sys_i);
            m0_arready_o = 0;
            if (target == 5 && resp != 3 && len == 0 && size == 2 && addr[1:0] == 0)
                apb_access(0, addr, 0, 0, apb_data, resp);
            for (int n = 0; n <= len; n++) begin
                m0_rdata_o = resp == 0 ? read_data({addr[31:3], 3'b0}, 8) : 0;
                if (target == 5 && resp == 0)
                    m0_rdata_o = 64'(apb_data) << (addr[2] ? 32 : 0);
                m0_rresp_o = resp;
                m0_rlast_o = n == len;
                m0_rvalid_o = 1;
                do @(posedge clk_sys_i); while (!m0_rready_i);
                @(negedge clk_sys_i);
                addr += 32'b1 << size;
            end
            m0_rvalid_o = 0;
        end
    end
    initial begin : m1_read
        bit [31:0] addr;
        int len;
        int size;
        int target;
        bit [31:0] apb_data;
        bit [1:0] resp;
        m1_arready_o = 0;
        m1_rvalid_o = 0;
        m1_rid_o = 0;
        m1_rdata_o = 0;
        m1_rresp_o = 0;
        m1_rlast_o = 0;
        forever begin
            wait (rst_sys_n_o);
            @(negedge clk_sys_i);
            m1_arready_o = 1;
            do @(posedge clk_sys_i); while (!m1_arvalid_i);
            addr = m1_araddr_i;
            len = int'(m1_arlen_i);
            size = int'(m1_arsize_i);
            target = region(addr);
            resp = (target < 0 || (0 && target >= 2 && target <= 5))
                    ? 3 : ((target >= 2 && target <= 5) ? 2 : 0);
            @(negedge clk_sys_i);
            m1_arready_o = 0;
            if (target == 5 && resp != 3 && len == 0 && size == 2 && addr[1:0] == 0)
                apb_access(0, addr, 0, 0, apb_data, resp);
            for (int n = 0; n <= len; n++) begin
                m1_rdata_o = resp == 0 ? read_data({addr[31:3], 3'b0}, 8) : 0;
                if (target == 5 && resp == 0)
                    m1_rdata_o = 64'(apb_data) << (addr[2] ? 32 : 0);
                m1_rresp_o = resp;
                m1_rlast_o = n == len;
                m1_rvalid_o = 1;
                do @(posedge clk_sys_i); while (!m1_rready_i);
                @(negedge clk_sys_i);
                addr += 32'b1 << size;
            end
            m1_rvalid_o = 0;
        end
    end
    initial begin : m1_write
        bit [31:0] addr;
        bit [31:0] unused_apb_data;
        bit [31:0] data;
        bit [3:0] strb;
        int len;
        int size;
        int target;
        bit [1:0] resp;
        m1_awready_o = 0;
        m1_wready_o = 0;
        m1_bvalid_o = 0;
        m1_bid_o = 0;
        m1_bresp_o = 0;
        sim_exit_valid_o = 0;
        sim_exit_code_o = 0;
        forever begin
            wait (rst_sys_n_o);
            @(negedge clk_sys_i);
            m1_awready_o = 1;
            do @(posedge clk_sys_i); while (!m1_awvalid_i);
            addr = m1_awaddr_i;
            len = int'(m1_awlen_i);
            size = int'(m1_awsize_i);
            target = region(addr);
            resp = target < 0 ? 3 : (target == 0 || (target >= 2 && target <= 5) ? 2 : 0);
            @(negedge clk_sys_i);
            m1_awready_o = 0;
            m1_wready_o = 1;
            for (int n = 0; n <= len; n++) begin
                do @(posedge clk_sys_i); while (!m1_wvalid_i);
                data = addr[2] ? m1_wdata_i[63:32] : m1_wdata_i[31:0];
                strb = addr[2] ? m1_wstrb_i[7:4] : m1_wstrb_i[3:0];
                if (target == 1 || target == 6) begin
                    for (int b = 0; b < 8; b++)
                        if (m1_wstrb_i[b])
                            bus_store({addr[31:3], 3'b0} + 32'(b), m1_wdata_i[b*8 +: 8]);
                end
                @(negedge clk_sys_i);
                if (n != len) addr += 32'b1 << size;
            end
            m1_wready_o = 0;
            if ((target == 4 || target == 5) && len == 0 && size == 2 && addr[1:0] == 0)
                apb_access(1, addr, data, strb, unused_apb_data, resp);
            if (addr == EDRV32_SYSCTRL_BASE + 'h01c) begin
                sim_exit_code_o = data;
                sim_exit_valid_o = 1;
            end
            m1_bresp_o = resp;
            m1_bvalid_o = 1;
            do @(posedge clk_sys_i); while (!m1_bready_i);
            @(negedge clk_sys_i);
            m1_bvalid_o = 0;
            sim_exit_valid_o = 0;
        end
    end
    // Reset interface timing uses the repository's CDC/reset primitives (spec 2.10).
    wire mem_ready_sync;
    wire mem_release_sync;
    wire mem_request_n = rst_n_i && mem_ready_sync;
    wire sys_request_n = rst_n_i && mem_release_sync;
    edrv32_cdc_sync_bit u_ready_sync (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_n_i),
        .bit_i(mem_ready_i),
        .bit_o(mem_ready_sync)
    );
    edrv32_reset_sync u_mem_reset (
        .clk_i(clk_mem_i),
        .rst_n_i(mem_request_n),
        .rst_n_o(rst_mem_core_n_o)
    );
    assign rst_mem_n_o = rst_mem_core_n_o;
    edrv32_cdc_sync_bit u_release_sync (
        .clk_i(clk_sys_i),
        .rst_n_i(rst_n_i),
        .bit_i(rst_mem_n_o),
        .bit_o(mem_release_sync)
    );
    edrv32_reset_sync u_sys_reset (
        .clk_i(clk_sys_i),
        .rst_n_i(sys_request_n),
        .rst_n_o(rst_sys_n_o)
    );
    edrv32_reset_sync u_pix_reset (
        .clk_i(clk_pix_i),
        .rst_n_i(rst_mem_n_o),
        .rst_n_o(rst_pix_n_o)
    );
    edrv32_reset_sync u_cam0_reset (
        .clk_i(cam0_pclk_i),
        .rst_n_i(rst_mem_n_o),
        .rst_n_o(rst_cam0_n_o)
    );
    edrv32_reset_sync u_cam1_reset (
        .clk_i(cam1_pclk_i),
        .rst_n_i(rst_mem_n_o),
        .rst_n_o(rst_cam1_n_o)
    );
    edrv32_reset_sync u_eth_rx_reset (
        .clk_i(eth_rx_clk_i),
        .rst_n_i(rst_mem_n_o),
        .rst_n_o(rst_eth_rx_n_o)
    );
    edrv32_reset_sync u_eth_tx_reset (
        .clk_i(eth_tx_clk_i),
        .rst_n_i(rst_mem_n_o),
        .rst_n_o(rst_eth_tx_n_o)
    );
    initial begin
        media_apb_paddr_o = 0;
        media_apb_psel_o = 0;
        media_apb_penable_o = 0;
        media_apb_pwrite_o = 0;
        media_apb_pwdata_o = 0;
        media_apb_pstrb_o = 0;
        cache_apb_paddr_o = 0;
        cache_apb_psel_o = 0;
        cache_apb_penable_o = 0;
        cache_apb_pwrite_o = 0;
        cache_apb_pwdata_o = 0;
        cache_apb_pstrb_o = 0;
    end
    assign mtime_o = 0;
    assign irq_meip_o = 0;
    assign irq_msip_o = 0;
    assign irq_mtip_o = 0;
    assign uart0_tx_o = uart0_rx_i;
    assign gpio_o = 0;
    assign gpio_oe_o = 0;
    assign i2c0_scl_o = 0;
    assign i2c0_scl_oe_o = 0;
    assign i2c0_sda_o = 0;
    assign i2c0_sda_oe_o = 0;
    assign s6_awid_o = 4'd0;
    assign s6_awaddr_o = 32'd0;
    assign s6_awlen_o = 8'd0;
    assign s6_awsize_o = 3'd0;
    assign s6_awburst_o = 2'd1;
    assign s6_awvalid_o = 1'd0;
    assign s6_wdata_o = 64'd0;
    assign s6_wstrb_o = 8'd0;
    assign s6_wlast_o = 1'd0;
    assign s6_wvalid_o = 1'd0;
    assign s6_bready_o = 1'd0;
    assign s6_arid_o = 4'd0;
    assign s6_araddr_o = 32'd0;
    assign s6_arlen_o = 8'd0;
    assign s6_arsize_o = 3'd0;
    assign s6_arburst_o = 2'd1;
    assign s6_arvalid_o = 1'd0;
    assign s6_rready_o = 1'd0;
endmodule
