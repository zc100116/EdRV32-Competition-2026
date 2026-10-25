// File: tb.sv
// Spec: sys-subsys-spec 2.3, 5, 6; testplan AB-07.
// Description: Self-checking transactions, response scoreboards and protocol assertions.
// Clock domain: clk_sys and independent clk_mem.
module tb;
    reg clk = 0;
    reg rst_n = 0;
    always #10 clk = ~clk;
    integer cycles = 0;
    integer checks = 0;
    always @(posedge clk) cycles <= cycles + 1;
    initial begin
        #2000000;
        $fatal(1, "FAIL timeout");
    end
    reg [15:0] paddr = 0;
    reg psel = 0;
    reg penable = 0;
    reg pwrite = 0;
    reg [31:0] pwdata = 0;
    reg [3:0] pstrb = 0;
    wire [31:0] prdata;
    wire pready;
    wire pslverr;
    wire [11:0] slot_paddr;
    wire [15:0] slot_psel;
    wire slot_penable;
    wire slot_pwrite;
    wire [31:0] slot_pwdata;
    wire [3:0] slot_pstrb;
    wire [511:0] slot_prdata;
    wire [15:0] slot_pready;
    wire [15:0] slot_pslverr;
    reg media = 0;
    reg never_ready = 0;
    reg force_error = 0;
    integer delay_cycles = 0;
    integer waited = 0;
    integer transfers = 0;
    integer setup_cycles = 0;
    reg [15:0] expected_addr;
    reg expected_write;
    reg [31:0] expected_data;
    reg [3:0] expected_strb;
    wire [15:0] used_slots = media ? 16'h03ff : 16'h0073;
    reg clk_mem = 0;
    reg rst_mem_n = 0;
    integer mem_half = 20;
    // sys clock is 20 time units; exact media ratios are .5, .8333, 1 and 2.
    integer phase_request = 0;
    integer phase_applied = 0;
    always begin
        if (phase_request != phase_applied) begin
            #(phase);
            phase_applied = phase_request;
        end
        #(mem_half) clk_mem = ~clk_mem;
    end
    wire [15:0] dst_paddr;
    wire dst_psel;
    wire dst_penable;
    wire dst_pwrite;
    wire [31:0] dst_pwdata;
    wire [3:0] dst_pstrb;
    wire [31:0] dst_prdata;
    wire dst_pready;
    wire dst_pslverr;
    edrv32_apb_async_bridge dut (
        .clk_s_i(clk),
        .rst_s_n_i(rst_n),
        .clk_m_i(clk_mem),
        .rst_m_n_i(rst_mem_n),
        .s_apb_paddr_i(paddr),
        .s_apb_psel_i(psel),
        .s_apb_penable_i(penable),
        .s_apb_pwrite_i(pwrite),
        .s_apb_pwdata_i(pwdata),
        .s_apb_pstrb_i(pstrb),
        .s_apb_prdata_o(prdata),
        .s_apb_pready_o(pready),
        .s_apb_pslverr_o(pslverr),
        .m_apb_paddr_o(dst_paddr),
        .m_apb_psel_o(dst_psel),
        .m_apb_penable_o(dst_penable),
        .m_apb_pwrite_o(dst_pwrite),
        .m_apb_pwdata_o(dst_pwdata),
        .m_apb_pstrb_o(dst_pstrb),
        .m_apb_prdata_i(dst_prdata),
        .m_apb_pready_i(dst_pready),
        .m_apb_pslverr_i(dst_pslverr)
    );
    edrv32_bus_apb_decoder u_decoder (
        .clk_i(clk_mem),
        .rst_n_i(rst_mem_n),
        .apb_paddr_i(dst_paddr),
        .apb_psel_i(dst_psel),
        .apb_penable_i(dst_penable),
        .apb_pwrite_i(dst_pwrite),
        .apb_pwdata_i(dst_pwdata),
        .apb_pstrb_i(dst_pstrb),
        .apb_prdata_o(dst_prdata),
        .apb_pready_o(dst_pready),
        .apb_pslverr_o(dst_pslverr),
        .slot_paddr_o(slot_paddr),
        .slot_psel_o(slot_psel),
        .slot_penable_o(slot_penable),
        .slot_pwrite_o(slot_pwrite),
        .slot_pwdata_o(slot_pwdata),
        .slot_pstrb_o(slot_pstrb),
        .slot_prdata_i(slot_prdata),
        .slot_pready_i(slot_pready),
        .slot_pslverr_i(slot_pslverr)
    );
    genvar g;
    generate
        for (g = 0; g < 16; g = g + 1) begin : slots
            assign slot_prdata[g*32 +: 32] = used_slots[g] ?
                (32'hc0000000 | (32'(g) << 16) | {20'b0,slot_paddr}) : 32'b0;
            assign slot_pready[g] = !used_slots[g] ||
                (!never_ready && (waited >= delay_cycles));
            assign slot_pslverr[g] = !used_slots[g] || force_error;
        end
    endgenerate
    always @(posedge clk_mem) begin
        if (slot_psel == 0 || !slot_penable) waited <= 0;
        else waited <= waited + 1;
        if (rst_mem_n && slot_psel != 0) begin
            if (slot_psel !== (16'b1 << expected_addr[15:12]) ||
                slot_paddr !== expected_addr[11:0] || slot_pwrite !== expected_write ||
                slot_pstrb !== expected_strb ||
                (slot_pwrite && slot_pwdata !== expected_data))
                $fatal(1,"FAIL decoded APB payload addr=%h psel=%h data=%h t=%0t",
                    slot_paddr,slot_psel,slot_pwdata,$time);
            if (!used_slots[expected_addr[15:12]] && ((slot_psel & used_slots) != 0))
                $fatal(1,"FAIL reserved slot reached an actual peripheral");
            if (!slot_penable) setup_cycles <= setup_cycles + 1;
            if (slot_penable && (|(slot_psel & slot_pready))) transfers <= transfers + 1;
        end
    end
    task automatic access_check(input [15:0] addr,input wr,input [31:0] data,input [3:0] strb,
        input expected_error,input integer timeout_cycles);
        integer before_count;
        integer before_setup;
        integer count;
        reg [31:0] expected;
        begin
            before_count = transfers;
            before_setup = setup_cycles;
            expected_addr = addr; expected_write = wr;
            expected_data = data; expected_strb = strb;
            expected = used_slots[addr[15:12]] ?
                (32'hc0000000 | (32'(addr[15:12]) << 16) | {20'b0,addr[11:0]}) : 32'b0;
            if (timeout_cycles != 0) expected = 0;
            @(negedge clk);
            paddr = addr; pwrite = wr; pwdata = data; pstrb = strb; psel = 1; penable = 0;
            @(negedge clk); penable = 1;
            count = 0;
            do begin
                @(posedge clk);
                count = count + 1;
            end while (!pready);
            if (pslverr !== expected_error || prdata !== expected)
                $fatal(1,"FAIL APB response addr=%h exp=%h/%b got=%h/%b t=%0t",
                    addr,expected,expected_error,prdata,pslverr,$time);
            @(negedge clk); psel = 0; penable = 0;
            if (setup_cycles - before_setup != 1)
                $fatal(1,"FAIL expected one SETUP, got %0d",setup_cycles-before_setup);
            if (timeout_cycles == 0 && transfers-before_count != 1)
                $fatal(1,"FAIL transfer duplicated or lost count=%0d",transfers-before_count);
            if (timeout_cycles != 0 && transfers-before_count != 0)
                $fatal(1,"FAIL timed out transfer was accepted by peripheral");
            checks = checks + 1;
        end
    endtask
    integer slot;
    integer config_idx;
    integer transaction;
    integer seed = 32'h27182818;
    integer phase;
    initial begin
        media = 1;
        for (config_idx = 0; config_idx < 4; config_idx = config_idx + 1) begin
            case (config_idx)
                0: mem_half = 20;
                1: mem_half = 12;
                2: mem_half = 10;
                default: mem_half = 5;
            endcase
            rst_n = 0; rst_mem_n = 0;
            phase = int'($unsigned($random(seed)) % 17) + 1;
            phase_request = config_idx + 1;
            #(phase);
            repeat (3) @(negedge clk_mem); rst_mem_n = 1;
            repeat (3) @(negedge clk); rst_n = 1;
            // AB-07: each ratio, every media slot, repeated payloads and varied waits.
            for (transaction = 0; transaction < 8; transaction = transaction + 1) begin
                for (slot = 0; slot < 16; slot = slot + 1) begin
                    delay_cycles = (transaction + slot) % 7;
                    access_check({4'(slot),12'h004},1,
                        32'h12340000 | (32'(transaction) << 8) | 32'(slot),
                        4'(transaction+slot),slot >= 10,0);
                    access_check({4'(slot),12'h008},0,0,0,slot >= 10,0);
                end
            end
            force_error = 1;
            access_check(16'h3020,0,0,0,1,0);
            force_error = 0;
            never_ready = 1;
            access_check(16'h5024,1,32'hdeadbeef,4'ha,1,256);
            never_ready = 0;
            access_check(16'h5024,0,0,0,0,0);
        end
        // Both CDC ends reset together during a stalled request, then accept new traffic.
        @(negedge clk); psel = 1; penable = 0; paddr = 16'h1000;
        expected_addr = 16'h1000; expected_write = 0; expected_strb = 0; never_ready = 1;
        @(negedge clk); penable = 1;
        wait (slot_penable && slot_psel != 0);
        #1 rst_n = 0; rst_mem_n = 0; psel = 0; penable = 0;
        #1;
        if (dut.m_apb_psel_o !== 0 || pready !== 0)
            $fatal(1,"FAIL async reset control");
        repeat (3) @(negedge clk_mem); rst_mem_n = 1;
        repeat (3) @(negedge clk); rst_n = 1;
        never_ready = 0;
        access_check(16'h0000,0,0,0,0,0);
        $display("PASS APB decoder/CDC checks=%0d transfers=%0d",checks,transfers);
        $finish;
    end
endmodule
