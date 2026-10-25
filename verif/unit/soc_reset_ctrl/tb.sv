// File: tb.sv
// Spec: sys-subsys-testplan SY-01--SY-06.
// Description: Self-checking APB and multi-clock reset sequencing tests.
// Clock: clk_sys and six asynchronous engine domains.
module tb;
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
        .rst_n_i(rst_sys_por_n),
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
    reg clk_mem = 0;
    always #7 clk_mem = ~clk_mem;
    reg clk_pix = 0;
    always #9 clk_pix = ~clk_pix;
    reg clk_cam0 = 0;
    always #11 clk_cam0 = ~clk_cam0;
    reg clk_cam1 = 0;
    always #13 clk_cam1 = ~clk_cam1;
    reg clk_eth_rx = 0;
    always #17 clk_eth_rx = ~clk_eth_rx;
    reg clk_eth_tx = 0;
    always #19 clk_eth_tx = ~clk_eth_tx;
    wire rst_sys_por_n;
    wire rst_sys_n;
    wire rst_mem_core_n;
    wire rst_mem_n;
    wire rst_pix_n;
    wire rst_cam0_n;
    wire rst_cam1_n;
    wire rst_eth_rx_n;
    wire rst_eth_tx_n;
    edrv32_soc_reset_ctrl u_reset (
        .clk_sys_i(clk),
        .clk_mem_i(clk_mem),
        .clk_pix_i(clk_pix),
        .clk_cam0_i(clk_cam0),
        .clk_cam1_i(clk_cam1),
        .clk_eth_rx_i(clk_eth_rx),
        .clk_eth_tx_i(clk_eth_tx),
        .rst_n_i(rst_n),
        .mem_ready_i(mem_ready),
        .soft_reset_media_i(soft_media),
        .soft_reset_soc_i(soft_soc),
        .rst_sys_por_n_o(rst_sys_por_n),
        .rst_sys_n_o(rst_sys_n),
        .rst_mem_core_n_o(rst_mem_core_n),
        .rst_mem_n_o(rst_mem_n),
        .rst_pix_n_o(rst_pix_n),
        .rst_cam0_n_o(rst_cam0_n),
        .rst_cam1_n_o(rst_cam1_n),
        .rst_eth_rx_n_o(rst_eth_rx_n),
        .rst_eth_tx_n_o(rst_eth_tx_n)
    );
    time soft_end = 0;
    bit monitor_soft = 0;
    bit media_only = 0;
    time media_request_time = 0;
    always @(posedge rst_mem_core_n) media_request_time = $time;
    function automatic time second_edge(input time request_time, input time half_period);
        time first_edge;
        first_edge = half_period;
        while (first_edge <= request_time) first_edge = first_edge + 2 * half_period;
        second_edge = first_edge + 2 * half_period;
    endfunction
    // Every reset release must coincide with a rising edge of its own clock.
    time last_sys_por = 0;
    always @(posedge clk) last_sys_por = $time;
    always @(posedge rst_sys_por_n) begin
        check(clk === 1'b1 && last_sys_por == $time, "sys_por synchronous release");
    end
    time last_sys = 0;
    always @(posedge clk) last_sys = $time;
    always @(posedge rst_sys_n) begin
        check(clk === 1'b1 && last_sys == $time, "sys synchronous release");
        if (monitor_soft) check($time >= soft_end, "sys sixteen-cycle hold");
        check(rst_mem_n, "SY-04/05 system released after memory engine");
    end
    time last_mem_core = 0;
    always @(posedge clk_mem) last_mem_core = $time;
    always @(posedge rst_mem_core_n) begin
        check(clk_mem === 1'b1 && last_mem_core == $time, "mem_core synchronous release");
    end
    time last_mem = 0;
    always @(posedge clk_mem) last_mem = $time;
    always @(posedge rst_mem_n) begin
        check(rst_mem_core_n, "mem release follows memory core");
        check($time == second_edge(monitor_soft ? soft_end : media_request_time, 7),
              "mem releases after exactly two destination clocks");
        check(clk_mem === 1'b1 && last_mem == $time, "mem synchronous release");
        if (monitor_soft) check($time >= soft_end, "mem sixteen-cycle hold");
    end
    time last_pix = 0;
    always @(posedge clk_pix) last_pix = $time;
    always @(posedge rst_pix_n) begin
        check(rst_mem_core_n, "pix release follows memory core");
        check($time == second_edge(monitor_soft ? soft_end : media_request_time, 9),
              "pix releases after exactly two destination clocks");
        check(clk_pix === 1'b1 && last_pix == $time, "pix synchronous release");
        if (monitor_soft) check($time >= soft_end, "pix sixteen-cycle hold");
    end
    time last_cam0 = 0;
    always @(posedge clk_cam0) last_cam0 = $time;
    always @(posedge rst_cam0_n) begin
        check(rst_mem_core_n, "cam0 release follows memory core");
        check($time == second_edge(monitor_soft ? soft_end : media_request_time, 11),
              "cam0 releases after exactly two destination clocks");
        check(clk_cam0 === 1'b1 && last_cam0 == $time, "cam0 synchronous release");
        if (monitor_soft) check($time >= soft_end, "cam0 sixteen-cycle hold");
    end
    time last_cam1 = 0;
    always @(posedge clk_cam1) last_cam1 = $time;
    always @(posedge rst_cam1_n) begin
        check(rst_mem_core_n, "cam1 release follows memory core");
        check($time == second_edge(monitor_soft ? soft_end : media_request_time, 13),
              "cam1 releases after exactly two destination clocks");
        check(clk_cam1 === 1'b1 && last_cam1 == $time, "cam1 synchronous release");
        if (monitor_soft) check($time >= soft_end, "cam1 sixteen-cycle hold");
    end
    time last_eth_rx = 0;
    always @(posedge clk_eth_rx) last_eth_rx = $time;
    always @(posedge rst_eth_rx_n) begin
        check(rst_mem_core_n, "eth_rx release follows memory core");
        check($time == second_edge(monitor_soft ? soft_end : media_request_time, 17),
              "eth_rx releases after exactly two destination clocks");
        check(clk_eth_rx === 1'b1 && last_eth_rx == $time, "eth_rx synchronous release");
        if (monitor_soft) check($time >= soft_end, "eth_rx sixteen-cycle hold");
    end
    time last_eth_tx = 0;
    always @(posedge clk_eth_tx) last_eth_tx = $time;
    always @(posedge rst_eth_tx_n) begin
        check(rst_mem_core_n, "eth_tx release follows memory core");
        check($time == second_edge(monitor_soft ? soft_end : media_request_time, 19),
              "eth_tx releases after exactly two destination clocks");
        check(clk_eth_tx === 1'b1 && last_eth_tx == $time, "eth_tx synchronous release");
        if (monitor_soft) check($time >= soft_end, "eth_tx sixteen-cycle hold");
    end
    always @(posedge clk) begin
        #1;
        if (monitor_soft) begin
            check(rst_sys_por_n && rst_mem_core_n, "power-on and memory core survive soft reset");
            if (media_only) check(rst_sys_n, "SY-03 media reset leaves system running");
        end
    end
    wire [5:0] media_resets = {rst_mem_n, rst_pix_n, rst_cam0_n,
                             rst_cam1_n, rst_eth_rx_n, rst_eth_tx_n};
    wire [8:0] all_resets = {rst_sys_por_n, rst_sys_n, rst_mem_core_n, media_resets};
    task wait_release;
        wait (rst_sys_n && (&media_resets));
        #1;
        check(all_resets === 9'h1FF, "all domains released");
    endtask
    task software_reset(input bit soc_request);
        media_only = !soc_request;
        wr('h018, soc_request ? 2 : 1);
        @(negedge rst_mem_n);
        soft_end = $time + 160;
        monitor_soft = 1;
        #1;
        check(media_resets === 6'd0, "SY-03/04 all media domains assert together");
        check(rst_sys_n == !soc_request, "SY-03/04 system reset selection");
        repeat (15) begin
            tick();
            check(media_resets === 6'd0, "SY-03/04 sixteen system clocks");
            if (soc_request) check(!rst_sys_n, "SY-04 system held in reset");
        end
        wait_release();
        monitor_soft = 0;
        rd('h010, 'hA5A51234); rd('h014, 'h5A5AFEDC);
    endtask
    initial begin
        repeat (3) tick();
        check(all_resets === 9'd0, "SY-05 external reset all domains");
        @(negedge clk); rst_n = 1;
        repeat (25) tick();
        check(rst_sys_por_n && !rst_mem_core_n && !rst_sys_n && media_resets === 6'd0,
              "SY-05 wait for delayed memory readiness");
        #2; mem_ready = 1;
        wait_release();
        rd('h00C, 1);
        wr('h010, 'hA5A51234); wr('h014, 'h5A5AFEDC);
        software_reset(0);
        software_reset(1);
        // SY-02 scratch is retained by both software resets, cleared by reset input.
        #2; rst_n = 0;
        #1; check(all_resets === 9'd0, "asynchronous reset assertion between clocks");
        mem_ready = 0;
        repeat (4) tick();
        @(negedge clk); rst_n = 1;
        repeat (10) tick();
        check(!rst_sys_n && !rst_mem_core_n, "second power-on waits for memory");
        #2; mem_ready = 1;
        wait_release(); rd('h010, 0); rd('h014, 0);
        $display("PASS SY-02 SY-03 SY-04 SY-05"); $finish;
    end
    initial begin
        #200000; $fatal(1, "FAIL timeout");
    end
endmodule
