// File: tb_npu_top.sv
// Spec: npu-spec 2.4, 3, 4; edrv32-soc-spec 7.1.
// Description: Empty descriptor lists, exact CUR_DESC and IDLE soft reset through X10.
// Clock: clk_npu and clk_mem (independent).
`timescale 1ns/1ps
module tb_npu_top;
    logic  clk_npu_i = 0;
    logic  rst_npu_n_i = 0;
    logic  clk_mem_i = 0;
    logic  rst_mem_n_i = 0;
    logic [11:0] apb_paddr_i = 0;
    logic  apb_psel_i = 0;
    logic  apb_penable_i = 0;
    logic  apb_pwrite_i = 0;
    logic [31:0] apb_pwdata_i = 0;
    logic [3:0] apb_pstrb_i = 0;
    wire  apb_pready_o;
    wire [31:0] apb_prdata_o;
    wire  apb_pslverr_o;
    wire  unused_axi_awid_o;
    wire [31:0] unused_axi_awaddr_o;
    wire [3:0] unused_axi_awlen_o;
    wire  axi_awvalid_o;
    logic  axi_awready_i = 0;
    wire [255:0] unused_axi_wdata_o;
    wire [31:0] unused_axi_wstrb_o;
    wire  unused_axi_wlast_o;
    wire  axi_wvalid_o;
    logic  axi_wready_i = 0;
    logic  axi_bid_i = 0;
    logic [1:0] axi_bresp_i = 0;
    logic  axi_bvalid_i = 0;
    wire  unused_axi_bready_o;
    wire  unused_axi_arid_o;
    wire [31:0] unused_axi_araddr_o;
    wire [3:0] unused_axi_arlen_o;
    wire  axi_arvalid_o;
    logic  axi_arready_i = 0;
    logic  axi_rid_i = 0;
    logic [255:0] axi_rdata_i = 0;
    logic [1:0] axi_rresp_i = 0;
    logic  axi_rlast_i = 0;
    logic  axi_rvalid_i = 0;
    wire  unused_axi_rready_o;
    wire  irq_o;
    always #3.333 clk_npu_i = !clk_npu_i;
    always #4 clk_mem_i = !clk_mem_i;
    edrv32_npu u_dut (
        .clk_npu_i(clk_npu_i),
        .rst_npu_n_i(rst_npu_n_i),
        .clk_mem_i(clk_mem_i),
        .rst_mem_n_i(rst_mem_n_i),
        .apb_paddr_i(apb_paddr_i),
        .apb_psel_i(apb_psel_i),
        .apb_penable_i(apb_penable_i),
        .apb_pwrite_i(apb_pwrite_i),
        .apb_pwdata_i(apb_pwdata_i),
        .apb_pstrb_i(apb_pstrb_i),
        .apb_pready_o(apb_pready_o),
        .apb_prdata_o(apb_prdata_o),
        .apb_pslverr_o(apb_pslverr_o),
        .axi_awid_o(unused_axi_awid_o),
        .axi_awaddr_o(unused_axi_awaddr_o),
        .axi_awlen_o(unused_axi_awlen_o),
        .axi_awvalid_o(axi_awvalid_o),
        .axi_awready_i(axi_awready_i),
        .axi_wdata_o(unused_axi_wdata_o),
        .axi_wstrb_o(unused_axi_wstrb_o),
        .axi_wlast_o(unused_axi_wlast_o),
        .axi_wvalid_o(axi_wvalid_o),
        .axi_wready_i(axi_wready_i),
        .axi_bid_i(axi_bid_i),
        .axi_bresp_i(axi_bresp_i),
        .axi_bvalid_i(axi_bvalid_i),
        .axi_bready_o(unused_axi_bready_o),
        .axi_arid_o(unused_axi_arid_o),
        .axi_araddr_o(unused_axi_araddr_o),
        .axi_arlen_o(unused_axi_arlen_o),
        .axi_arvalid_o(axi_arvalid_o),
        .axi_arready_i(axi_arready_i),
        .axi_rid_i(axi_rid_i),
        .axi_rdata_i(axi_rdata_i),
        .axi_rresp_i(axi_rresp_i),
        .axi_rlast_i(axi_rlast_i),
        .axi_rvalid_i(axi_rvalid_i),
        .axi_rready_o(unused_axi_rready_o),
        .irq_o(irq_o)
    );
    always @(posedge clk_mem_i) begin
        if (rst_mem_n_i && (axi_arvalid_o || axi_awvalid_o || axi_wvalid_o))
            $fatal(1, "FAIL empty list issued AXI transaction time=%0t", $time);
    end
    task automatic apb(input bit write, input logic [11:0] addr,
                       input logic [31:0] value, output logic [31:0] result);
        @(negedge clk_mem_i);
        apb_psel_i = 1;
        apb_penable_i = 0;
        apb_pwrite_i = write;
        apb_paddr_i = addr;
        apb_pwdata_i = value;
        // Full-word writes must work even with pstrb=0.
        apb_pstrb_i = 0;
        @(negedge clk_mem_i);
        apb_penable_i = 1;
        do @(posedge clk_mem_i); while (!apb_pready_o);
        if (apb_pslverr_o) $fatal(1, "FAIL APB error addr=%03x", addr);
        result = apb_prdata_o;
        @(negedge clk_mem_i);
        apb_psel_i = 0;
        apb_penable_i = 0;
        apb_pwrite_i = 0;
    endtask
    task automatic read_check(input logic [11:0] addr, input logic [31:0] value);
        logic [31:0] actual;
        apb(0, addr, 0, actual);
        if (actual != value) $fatal(1, "FAIL addr=%03x expected=%08x actual=%08x time=%0t",
            addr, value, actual, $time);
    endtask
    initial begin
        logic [31:0] unused_result;
        repeat (5) @(negedge clk_mem_i);
        rst_mem_n_i = 1;
        @(negedge clk_npu_i);
        rst_npu_n_i = 1;
        read_check(12'h000, 32'h00060001);
        read_check(12'h110, 0);
        read_check(12'h008, 2);
        apb(1, 12'h00c, 1, unused_result);
        // ENABLE stays zero for both doorbells.
        for (int frame = 1; frame <= 2; frame++) begin
            apb(1, 12'h028, 32'h12345678, unused_result);
            wait (irq_o);
            read_check(12'h008, 2);
            read_check(12'h02c, 32'(frame));
            read_check(12'h110, 32'hffffffff);
            read_check(12'h004, 0);
            apb(1, 12'h010, 1, unused_result);
            if (irq_o) $fatal(1, "FAIL IRQ did not clear");
        end
        apb(1, 12'h004, 8, unused_result);
        read_check(12'h110, 0);
        read_check(12'h02c, 0);
        read_check(12'h040, 0);
        read_check(12'h00c, 0);
        if (irq_o) $fatal(1, "FAIL soft reset IRQ");
        $display("PASS top empty lists, CUR_DESC=COUNT-1, X10 and soft reset");
        $finish;
    end
    initial begin
        #2000000;
        $fatal(1, "FAIL top timeout");
    end
endmodule
