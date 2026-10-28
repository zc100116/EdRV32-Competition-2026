// File: tb.sv
// Spec: sys-subsys-testplan SY-01--SY-06.
// Description: Self-checking APB and multi-clock reset sequencing tests.
// Clock: clk_sys and six asynchronous engine domains.
module tb;
    `include "edrv32_soc_map.vh"
    reg clk = 0;
    reg rst_n = 0;
    reg mem_ready = 0;
    always #5 clk = ~clk;
    reg [11:0] apb_paddr = 0;
    reg apb_psel = 0;
    reg apb_penable = 0;
    reg apb_pwrite = 0;
    reg [31:0] apb_pwdata = 0;
    reg [3:0] apb_pstrb = 0;
    wire [31:0] apb_prdata;
    wire apb_pready;
    wire apb_pslverr;
    wire soft_media;
    wire soft_soc;
    wire sim_valid;
    wire [31:0] sim_code;
    edrv32_periph_sysctrl u_sysctrl (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .apb_paddr_i(apb_paddr),
        .apb_psel_i(apb_psel),
        .apb_penable_i(apb_penable),
        .apb_pwrite_i(apb_pwrite),
        .apb_pwdata_i(apb_pwdata),
        .apb_pstrb_i(apb_pstrb),
        .apb_prdata_o(apb_prdata),
        .apb_pready_o(apb_pready),
        .apb_pslverr_o(apb_pslverr),
        .mem_ready_i(mem_ready),
        .soft_reset_media_o(soft_media),
        .soft_reset_soc_o(soft_soc),
        .sim_exit_valid_o(sim_valid),
        .sim_exit_code_o(sim_code)
    );
    task check(input bit condition, input string label_text);
        if (!condition) $fatal(1, "FAIL %s at %0t", label_text, $time);
    endtask
    task tick;
        @(posedge clk); #1;
    endtask
    task wr(input [11:0] addr, input [31:0] value, input [3:0] strb = 4'hF);
        @(negedge clk);
        apb_psel = 1;
        apb_paddr = addr;
        apb_pwrite = 1;
        apb_pwdata = value;
        apb_pstrb = strb;
        tick();
        check(!soft_media && !soft_soc && !sim_valid, "no request in SETUP");
        @(negedge clk); apb_penable = 1;
        tick();
        check(apb_pready && !apb_pslverr, "APB write response");
        check(soft_media == (addr == 'h018 && value[0]), "MEDIA write pulse");
        check(soft_soc == (addr == 'h018 && value[1]), "SOC write pulse");
        check(sim_valid == (addr == 'h01C), "SIM_EXIT write pulse");
        if (addr == 'h01C) check(sim_code === value, "SY-06 SIM_EXIT code");
        @(negedge clk);
        apb_psel = 0;
        apb_penable = 0;
        apb_pwrite = 0;
    endtask
    task rd(input [11:0] addr, input [31:0] expected_value);
        @(negedge clk);
        apb_psel = 1;
        apb_paddr = addr;
        apb_pwrite = 0;
        tick();
        @(negedge clk); apb_penable = 1;
        #1;
        if (apb_prdata !== expected_value)
            $fatal(1, "FAIL APB addr=%h expected=%h actual=%h at %0t",
                   addr, expected_value, apb_prdata, $time);
        check(apb_pready && !apb_pslverr, "APB read response");
        tick();
        @(negedge clk); apb_psel = 0; apb_penable = 0;
    endtask
    initial begin
        repeat (3) tick();
        @(negedge clk); rst_n = 1;
        rd('h000, 'h00060001);
        rd('h004, 'hED320001);
        rd('h008, EDRV32_CLK_SYS_HZ);
        rd('h00C, 0);
        @(negedge clk); mem_ready = 1;
        repeat (4) tick(); rd('h00C, 1);
        @(negedge clk); mem_ready = 0;
        repeat (4) tick(); rd('h00C, 0);
        rd('h010, 0); rd('h014, 0);
        wr('h010, 'h12345678, 0); rd('h010, 'h12345678);
        wr('h014, 'h9ABCDEF0, 1); rd('h014, 'h9ABCDEF0);
        wr('h018, 1); tick(); check(!soft_media && !soft_soc, "one-cycle media pulse");
        wr('h018, 2); tick(); check(!soft_media && !soft_soc, "one-cycle SOC pulse");
        wr('h018, 3); tick(); check(!soft_media && !soft_soc, "both request pulses");
        wr('h018, 0); tick(); check(!soft_media && !soft_soc, "zero request ignored");
        rd('h010, 'h12345678); rd('h014, 'h9ABCDEF0);
        wr('h01C, 0); tick(); check(!sim_valid, "one-cycle SIM_EXIT pulse");
        wr('h01C, 'h80000005); tick(); check(!sim_valid, "SIM_EXIT arbitrary value");
        wr('h000, 'hFFFFFFFF); rd('h000, 'h00060001);
        wr('h100, 'hFFFFFFFF); rd('h100, 0);
        rd('h018, 0); rd('h01C, 0);
        @(negedge clk); rst_n = 0;
        tick();
        @(negedge clk); rst_n = 1;
        rd('h010, 0); rd('h014, 0);
        $display("PASS SY-01 SY-02(registers) SY-06"); $finish;
    end
    initial begin
        #200000; $fatal(1, "FAIL timeout");
    end
endmodule
