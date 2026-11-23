// File: tb.sv
// Spec: gpu-soc-testplan ST-14; gpu-soc-spec 5.3, 8.1.
// Description: Directed release-order and SYSCTRL media soft-reset checks.
//              Check every engine against its destination clock edges.
// Clock: sys, mem, pix, gpu, aud, eth_rx and eth_tx.
module tb;
    reg rst_n = 0;
    reg mem_ready = 0;
    reg [11:0] addr = 0;
    reg select_apb = 0;
    reg enable_apb = 0;
    wire [31:0] read_data;
    wire ready_apb;
    wire error_apb;
    wire media_request;
    wire soc_request;
    wire exit_valid;
    wire [31:0] exit_code;
    wire rst_sys_por_n;
    wire rst_sys_n;
    wire rst_mem_core_n;
    wire rst_mem_copy_n;
    time release_request = 0;
    bit media_reset = 0;
    task check(input bit condition, input string label_text);
        if (!condition) $fatal(1, "FAIL %s at %0t", label_text, $time);
    endtask
    reg clk_sys = 0;
    always #5 clk_sys = ~clk_sys;
    reg clk_mem = 0;
    always #7 clk_mem = ~clk_mem;
    wire rst_mem_n;
    reg clk_pix = 0;
    always #9 clk_pix = ~clk_pix;
    wire rst_pix_n;
    reg clk_gpu = 0;
    always #3 clk_gpu = ~clk_gpu;
    wire rst_gpu_n;
    reg clk_aud = 0;
    always #41 clk_aud = ~clk_aud;
    wire rst_aud_n;
    reg clk_eth_rx = 0;
    always #17 clk_eth_rx = ~clk_eth_rx;
    wire rst_eth_rx_n;
    reg clk_eth_tx = 0;
    always #19 clk_eth_tx = ~clk_eth_tx;
    wire rst_eth_tx_n;
    edrv32_periph_sysctrl_gpu u_sysctrl (
        .clk_i(clk_sys),
        .rst_n_i(rst_sys_por_n),
        .apb_paddr_i(addr),
        .apb_psel_i(select_apb),
        .apb_penable_i(enable_apb),
        .apb_pwrite_i(select_apb),
        .apb_pwdata_i(32'd1),
        .apb_pstrb_i(4'hF),
        .apb_prdata_o(read_data),
        .apb_pready_o(ready_apb),
        .apb_pslverr_o(error_apb),
        .mem_ready_i(mem_ready),
        .soft_reset_media_o(media_request),
        .soft_reset_soc_o(soc_request),
        .sim_exit_valid_o(exit_valid),
        .sim_exit_code_o(exit_code)
    );
    edrv32_soc_reset_ctrl_gpu u_reset (
        .clk_sys_i(clk_sys),
        .clk_mem_i(clk_mem),
        .clk_pix_i(clk_pix),
        .clk_gpu_i(clk_gpu),
        .clk_aud_i(clk_aud),
        .clk_eth_rx_i(clk_eth_rx),
        .clk_eth_tx_i(clk_eth_tx),
        .rst_n_i(rst_n),
        .mem_ready_i(mem_ready),
        .soft_reset_media_i(media_request),
        .soft_reset_soc_i(soc_request),
        .rst_sys_por_n_o(rst_sys_por_n),
        .rst_sys_n_o(rst_sys_n),
        .rst_mem_core_n_o(rst_mem_core_n),
        .rst_mem_n_o(rst_mem_n),
        .rst_pix_n_o(rst_pix_n),
        .rst_gpu_n_o(rst_gpu_n),
        .rst_aud_n_o(rst_aud_n),
        .rst_eth_rx_n_o(rst_eth_rx_n),
        .rst_eth_tx_n_o(rst_eth_tx_n)
    );
    edrv32_reset_copy u_copy (
        .clk_i(clk_mem),
        .rst_n_i(rst_mem_n),
        .rst_n_o(rst_mem_copy_n)
    );
    wire [5:0] media_n = {rst_mem_n, rst_pix_n, rst_gpu_n,
                         rst_aud_n, rst_eth_rx_n, rst_eth_tx_n};
    always @(posedge rst_mem_core_n) release_request = $time;
    always @(negedge rst_mem_n) if (media_reset) release_request = $time + 160;
    always @(posedge rst_sys_n) begin
        check(rst_mem_copy_n, "ST-14 memory copy precedes system release");
    end
    always @(negedge rst_sys_n or negedge rst_mem_core_n or negedge rst_sys_por_n) begin
        if (media_reset) $fatal(1, "FAIL ST-14 media reset affected system/core at %0t", $time);
    end
    function automatic time second_edge(input time request_time, input time half_period);
        time first_edge;
        first_edge = half_period;
        while (first_edge <= request_time) first_edge = first_edge + 2 * half_period;
        second_edge = first_edge + 2 * half_period;
    endfunction
    time last_mem = 0;
    always @(posedge clk_mem) begin
        last_mem = $time;
    end
    always @(posedge rst_mem_n) begin
        check(rst_mem_core_n, "ST-14 mem follows memory core");
        check(last_mem == $time, "ST-14 mem releases on destination edge");
        check($time == second_edge(release_request, 7),
              "ST-14 mem joins common media release batch");
    end
    time last_pix = 0;
    always @(posedge clk_pix) begin
        last_pix = $time;
    end
    always @(posedge rst_pix_n) begin
        check(rst_mem_core_n, "ST-14 pix follows memory core");
        check(last_pix == $time, "ST-14 pix releases on destination edge");
        check($time == second_edge(release_request, 9),
              "ST-14 pix joins common media release batch");
    end
    time last_gpu = 0;
    always @(posedge clk_gpu) begin
        last_gpu = $time;
    end
    always @(posedge rst_gpu_n) begin
        check(rst_mem_core_n, "ST-14 gpu follows memory core");
        check(last_gpu == $time, "ST-14 gpu releases on destination edge");
        check($time == second_edge(release_request, 3),
              "ST-14 gpu joins common media release batch");
    end
    time last_aud = 0;
    always @(posedge clk_aud) begin
        last_aud = $time;
    end
    always @(posedge rst_aud_n) begin
        check(rst_mem_core_n, "ST-14 aud follows memory core");
        check(last_aud == $time, "ST-14 aud releases on destination edge");
        check($time == second_edge(release_request, 41),
              "ST-14 aud joins common media release batch");
    end
    time last_eth_rx = 0;
    always @(posedge clk_eth_rx) begin
        last_eth_rx = $time;
    end
    always @(posedge rst_eth_rx_n) begin
        check(rst_mem_core_n, "ST-14 eth_rx follows memory core");
        check(last_eth_rx == $time, "ST-14 eth_rx releases on destination edge");
        check($time == second_edge(release_request, 17),
              "ST-14 eth_rx joins common media release batch");
    end
    time last_eth_tx = 0;
    always @(posedge clk_eth_tx) begin
        last_eth_tx = $time;
    end
    always @(posedge rst_eth_tx_n) begin
        check(rst_mem_core_n, "ST-14 eth_tx follows memory core");
        check(last_eth_tx == $time, "ST-14 eth_tx releases on destination edge");
        check($time == second_edge(release_request, 19),
              "ST-14 eth_tx joins common media release batch");
    end
    initial begin
        #22; rst_n = 1;
        repeat (20) @(negedge clk_sys);
        check(rst_sys_por_n && !rst_mem_core_n && media_n == 0 && !rst_sys_n,
              "ST-14 all engines wait for memory readiness");
        #2; mem_ready = 1;
        wait (&media_n && rst_sys_n);
        #1; addr = 12'h004;
        #1; check(read_data == 32'hED32_0002, "ST-14 GPU CHIP_ID");
        repeat (2) begin
            @(negedge clk_sys); addr = 12'h018; select_apb = 1;
            @(negedge clk_sys); enable_apb = 1;
            @(negedge clk_sys); select_apb = 0; enable_apb = 0; media_reset = 1;
            @(negedge rst_mem_n);
            #1;
            check(media_n == 0, "ST-14 media domains assert together");
            check(ready_apb && !error_apb && !soc_request && !exit_valid,
                  "ST-14 MEDIA write completes without other requests");
            repeat (15) begin
                @(posedge clk_sys); #1;
                check(media_n == 0, "ST-14 hold all engines for sixteen system clocks");
            end
            wait (&media_n);
            #1; check(rst_sys_n && rst_mem_core_n && rst_sys_por_n,
                      "ST-14 system and memory fabric survive media reset");
            media_reset = 0;
        end
        #2; rst_n = 0;
        #1; check({rst_sys_por_n, rst_sys_n, rst_mem_core_n, media_n} == 0,
                  "ST-14 asynchronous external assertion in every domain");
        $display("PASS ST-14 release order and two SYSCTRL media resets");
        $finish;
    end
    initial begin
        #200000; $fatal(1, "FAIL ST-14 timeout");
    end
endmodule
