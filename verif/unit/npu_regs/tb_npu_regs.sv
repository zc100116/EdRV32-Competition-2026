// File: tb_npu_regs.sv
// Spec: npu-spec 3-6; edrv32-soc-spec 4.2, 7.1.
// Description: Self-checking isolated regs protocol and architectural tests.
// Clock: clk_npu.
`timescale 1ns/1ps
module tb_npu_regs;
    logic  clk_i = 0;
    logic  rst_n_i = 0;
    logic [11:0] apb_paddr_i = 0;
    logic  apb_psel_i = 0;
    logic  apb_penable_i = 0;
    logic  apb_pwrite_i = 0;
    logic [31:0] apb_pwdata_i = 0;
    logic [3:0] apb_pstrb_i = 0;
    wire  apb_pready_o;
    wire [31:0] apb_prdata_o;
    wire  apb_pslverr_o;
    logic  busy_i = 0;
    logic  done_i = 0;
    logic  error_i = 0;
    logic [2:0] error_code_i = 0;
    logic [31:0] cur_desc_i = 0;
    logic [7:0] perf_event_i = 0;
    wire  start_o;
    wire  abort_o;
    wire  soft_reset_o;
    wire [31:0] desc_base_o;
    wire [31:0] desc_count_o;
    wire [127:0] bases_o;
    wire [1:0] unused_post_ctrl_w;
    wire [31:0] unused_post_base_w;
    wire [26:0] unused_post_int8_th_w;
    wire [31:0] unused_post_prob_th_w;
    wire  irq_o;
    always #5 clk_i = !clk_i;
    edrv32_npu_regs u_dut (
        .post_ctrl_o(unused_post_ctrl_w),
        .post_base_o(unused_post_base_w),
        .post_int8_th_o(unused_post_int8_th_w),
        .post_prob_th_o(unused_post_prob_th_w),
        .post_count_i(13'd37),
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .apb_paddr_i(apb_paddr_i),
        .apb_psel_i(apb_psel_i),
        .apb_penable_i(apb_penable_i),
        .apb_pwrite_i(apb_pwrite_i),
        .apb_pwdata_i(apb_pwdata_i),
        .apb_pstrb_i(apb_pstrb_i),
        .apb_pready_o(apb_pready_o),
        .apb_prdata_o(apb_prdata_o),
        .apb_pslverr_o(apb_pslverr_o),
        .busy_i(busy_i),
        .done_i(done_i),
        .error_i(error_i),
        .error_code_i(error_code_i),
        .cur_desc_i(cur_desc_i),
        .perf_event_i(perf_event_i),
        .start_o(start_o),
        .abort_o(abort_o),
        .soft_reset_o(soft_reset_o),
        .desc_base_o(desc_base_o),
        .desc_count_o(desc_count_o),
        .bases_o(bases_o),
        .irq_o(irq_o)
    );
    task automatic tick;
        @(posedge clk_i);
        @(negedge clk_i);
        #1;
    endtask
    task automatic check(input bit condition, input string label);
        if (!condition) $fatal(1, "FAIL %s time=%0t", label, $time);
    endtask
    initial begin
        #2000000;
        $fatal(1, "FAIL timeout");
    end
    task automatic read_check(input logic [11:0] addr, input logic [31:0] value);
        apb_paddr_i = addr;
        apb_psel_i = 1;
        apb_penable_i = 0;
        apb_pwrite_i = 0;
        tick;
        apb_penable_i = 1;
        #1;
        if (apb_prdata_o !== value) $fatal(1, "FAIL reg %03x expected=%08x actual=%08x",
            addr, value, apb_prdata_o);
        check(apb_pready_o && !apb_pslverr_o, "APB response");
        tick;
        apb_psel_i = 0;
        apb_penable_i = 0;
    endtask
    task automatic write_reg(input logic [11:0] addr, input logic [31:0] value);
        apb_paddr_i = addr;
        apb_pwdata_i = value;
        apb_psel_i = 1;
        apb_penable_i = 0;
        apb_pwrite_i = 1;
        tick;
        apb_penable_i = 1;
        tick;
        check(abort_o == ((addr == 12'h004) && value[2]), "ABORT trigger");
        check(soft_reset_o == ((addr == 12'h004) && value[3] && !busy_i), "SOFT_RST trigger");
        apb_psel_i = 0;
        apb_penable_i = 0;
        apb_pwrite_i = 0;
    endtask
    initial begin
        tick;
        rst_n_i = 1;
        read_check(12'h000, 32'h00060001);
        read_check(12'h008, 32'h2);
        for (int n = 0; n < 4; n++) begin
            write_reg(12'h100+12'(4*n), 32'h12340000+32'(n));
            read_check(12'h100+12'(4*n), 32'h12340000+32'(n));
        end
        check(bases_o == 128'h12340003123400021234000112340000, "base ordering");
        write_reg(12'h020, 32'h1000);
        write_reg(12'h024, 32'h3);
        check(desc_base_o == 32'h1000 && desc_count_o == 3, "descriptor config");
        // ENABLE is zero; the doorbell pulse is nevertheless asserted.
        apb_paddr_i = 12'h028;
        apb_psel_i = 1;
        apb_penable_i = 0;
        apb_pwrite_i = 1;
        tick;
        apb_penable_i = 1;
        tick;
        check(start_o, "ungated doorbell");
        busy_i = 1;
        tick;
        check(!start_o, "busy doorbell ignored");
        apb_psel_i = 0;
        apb_penable_i = 0;
        perf_event_i = 8'hff;
        repeat (7) tick;
        perf_event_i = 0;
        // SoC 7.1: the seventh event is still pending until the next edge.
        check(u_dut.perf_r[0] == 6, "PERF event is delayed exactly one edge");
        apb_paddr_i = 12'h040;
        apb_psel_i = 1;
        apb_penable_i = 0;
        tick;
        apb_penable_i = 1;
        #1;
        check(apb_prdata_o == 7, "PERF final event drains during setup");
        tick;
        apb_psel_i = 0;
        apb_penable_i = 0;
        for (int n = 0; n < 8; n++) read_check(12'h040+12'(4*n), 7);
        read_check(12'h060, 0);
        write_reg(12'h004, 9);
        read_check(12'h004, 1);
        read_check(12'h020, 32'h1000);
        write_reg(12'h00c, 3);
        done_i = 1;
        error_i = 1;
        error_code_i = 2;
        tick;
        done_i = 0;
        error_i = 0;
        busy_i = 0;
        check(irq_o, "enabled level interrupt");
        read_check(12'h010, 3);
        read_check(12'h014, 2);
        read_check(12'h008, 6);
        read_check(12'h02c, 1);
        write_reg(12'h010, 2);
        read_check(12'h014, 0);
        read_check(12'h010, 1);
        write_reg(12'h010, 1);
        check(!irq_o, "RW1C interrupt");
        write_reg(12'hffc, 32'hffffffff);
        read_check(12'hffc, 0);
        write_reg(12'h000, 0);
        read_check(12'h000, 32'h00060001);
        cur_desc_i = 32'd2;
        read_check(12'h110, 2);
        cur_desc_i = 0;
        write_reg(12'h004, 8);
        read_check(12'h004, 0);
        read_check(12'h008, 2);
        read_check(12'h020, 0);
        read_check(12'h024, 0);
        read_check(12'h02c, 0);
        read_check(12'h00c, 0);
        check(bases_o == 0, "soft reset clears configuration");
        for (int n = 0; n < 16; n++) read_check(12'h040+12'(4*n), 0);
        for (int n = 0; n < 8; n++) read_check(12'h114+12'(4*n), 0);
        write_reg(12'h114, 3);
        write_reg(12'h118, 32'h02000000);
        write_reg(12'h11c, 32'h180);
        write_reg(12'h120, 128);
        write_reg(12'h124, 127);
        write_reg(12'h128, 32'd4194304);
        read_check(12'h114, 3);
        read_check(12'h118, 32'h02000000);
        read_check(12'h11c, 32'h180);
        read_check(12'h120, 128);
        read_check(12'h124, 127);
        read_check(12'h128, 32'd4194304);
        // The execution event represents the final candidate B fence.
        busy_i = 1;
        read_check(12'h12c, 0);
        read_check(12'h130, 0);
        read_check(12'h02c, 0);
        done_i = 1;
        tick;
        done_i = 0;
        busy_i = 0;
        read_check(12'h12c, 37);
        read_check(12'h130, 1);
        read_check(12'h02c, 1);
        write_reg(12'h028, 0);
        read_check(12'h12c, 0);
        read_check(12'h130, 0);
        error_i = 1;
        error_code_i = 1;
        tick;
        error_i = 0;
        read_check(12'h130, 0);
        write_reg(12'h004, 8);
        for (int n = 0; n < 8; n++) read_check(12'h114+12'(4*n), 0);
        $display("PASS register architecture, triggers, interrupts, PERF and soft reset");
        $finish;
    end
endmodule
