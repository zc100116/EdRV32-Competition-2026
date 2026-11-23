// File: tb.sv
// Spec: aud-spec 4, 6; edrv32-soc-spec 4.3, 7.1.
// Description: APB setup capture, byte strobes, register masks, IRQ and soft reset.
// Clock domain: clk_mem test clock.
module tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [11:0] s_apb_paddr_i = 0;
    reg s_apb_psel_i = 0;
    reg s_apb_penable_i = 0;
    reg s_apb_pwrite_i = 0;
    reg [31:0] s_apb_pwdata_i = 0;
    reg [3:0] s_apb_pstrb_i = 0;
    wire s_apb_pready_o;
    wire [31:0] s_apb_prdata_o;
    wire s_apb_pslverr_o;
    wire enable_o;
    wire restart_o;
    wire clear_error_o;
    wire [31:0] ring_base_o;
    wire [23:0] ring_size_o;
    wire [23:0] wr_ptr_o;
    reg [23:0] rd_ptr_i = 0;
    reg [23:0] avail_i = 0;
    reg busy_i = 0;
    reg error_i = 0;
    reg underrun_i = 0;
    wire irq_o;
    edrv32_aud_regs u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .s_apb_paddr_i(s_apb_paddr_i),
        .s_apb_psel_i(s_apb_psel_i),
        .s_apb_penable_i(s_apb_penable_i),
        .s_apb_pwrite_i(s_apb_pwrite_i),
        .s_apb_pwdata_i(s_apb_pwdata_i),
        .s_apb_pstrb_i(s_apb_pstrb_i),
        .s_apb_pready_o(s_apb_pready_o),
        .s_apb_prdata_o(s_apb_prdata_o),
        .s_apb_pslverr_o(s_apb_pslverr_o),
        .enable_o(enable_o),
        .restart_o(restart_o),
        .clear_error_o(clear_error_o),
        .ring_base_o(ring_base_o),
        .ring_size_o(ring_size_o),
        .wr_ptr_o(wr_ptr_o),
        .rd_ptr_i(rd_ptr_i),
        .avail_i(avail_i),
        .busy_i(busy_i),
        .error_i(error_i),
        .underrun_i(underrun_i),
        .irq_o(irq_o)
    );
    task access(input reg wr, input [11:0] addr, input [31:0] data_in,
        input [3:0] strb, input [31:0] expected);
        begin
            @(negedge clk);
            s_apb_psel_i = 1;
            s_apb_penable_i = 0;
            s_apb_paddr_i = addr;
            s_apb_pwrite_i = wr;
            s_apb_pwdata_i = data_in;
            s_apb_pstrb_i = strb;
            @(negedge clk);
            s_apb_penable_i = 1;
            // Access decode must use the setup capture, including strobe/data.
            s_apb_paddr_i = 'hffc;
            s_apb_pwdata_i = ~data_in;
            s_apb_pwrite_i = !wr;
            s_apb_pstrb_i = ~strb;
            #1;
            if (!s_apb_pready_o || s_apb_pslverr_o ||
                (!wr && s_apb_prdata_o !== expected))
                $fatal(1, "FAIL APB addr=%h expected=%h actual=%h", addr, expected,
                    s_apb_prdata_o);
            @(negedge clk);
            s_apb_psel_i = 0;
            s_apb_penable_i = 0;
        end
    endtask
    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        access(0, 'h000, 0, 0, 'h10001);
        access(0, 'h008, 0, 0, 2);
        access(1, 'h100, 'h123457ff, 15, 0);
        access(0, 'h100, 0, 0, 'h12345600);
        access(1, 'h104, 'hff1235ff, 15, 0);
        access(0, 'h104, 0, 0, 'h123400);
        access(1, 'h108, 'hff12345f, 15, 0);
        access(1, 'h108, 'h00005600, 2, 0);
        access(0, 'h108, 0, 0, 'h125640);
        access(1, 'h004, 1, 1, 0);
        access(1, 'h100, 0, 15, 0);
        access(0, 'h100, 0, 0, 'h12345600);
        access(1, 'h110, 128, 15, 0);
        access(0, 'h010, 0, 0, 0);
        @(negedge clk);
        avail_i = 128;
        repeat (2) @(negedge clk);
        avail_i = 96;
        repeat (2) @(negedge clk);
        access(0, 'h010, 0, 0, 'h100);
        access(1, 'h00c, 'h102, 15, 0);
        if (!irq_o) $fatal(1, "FAIL low IRQ");
        access(1, 'h010, 'h100, 15, 0);
        if (irq_o) $fatal(1, "FAIL low W1C");
        error_i = 1;
        @(negedge clk);
        error_i = 0;
        access(0, 'h008, 0, 0, 6);
        access(0, 'h014, 0, 0, 1);
        access(1, 'h010, 2, 15, 0);
        access(0, 'h014, 0, 0, 0);
        underrun_i = 1;
        @(negedge clk);
        underrun_i = 0;
        repeat (2) @(negedge clk);
        access(0, 'h114, 0, 0, 1);
        busy_i = 1;
        access(1, 'h004, 8, 1, 0);
        if (enable_o) $fatal(1, "FAIL soft reset enable");
        access(0, 'h100, 0, 0, 'h12345600);
        busy_i = 0;
        repeat (3) @(negedge clk);
        access(0, 'h100, 0, 0, 0);
        access(0, 'h114, 0, 0, 0);
        access(0, 'h020, 0, 0, 0);
        access(0, 'h028, 0, 0, 0);
        $display("PASS registers: setup capture, strobes, LOW, error, underrun, reset");
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "FAIL timeout");
    end
endmodule
