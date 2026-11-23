// Self-checking gpu_regs unit test.
module tb_gpu_regs;
    logic clk_i = 0;
    logic rst_n_i = 0;
    logic [11:0] s_apb_paddr_i = 0;
    logic s_apb_psel_i = 0;
    logic s_apb_penable_i = 0;
    logic s_apb_pwrite_i = 0;
    logic [31:0] s_apb_pwdata_i = 0;
    logic [3:0] s_apb_pstrb_i = 0;
    logic s_apb_pready_o;
    logic [31:0] s_apb_prdata_o;
    logic s_apb_pslverr_o;
    logic enable_o;
    logic start_o;
    logic abort_o;
    logic soft_rst_o;
    logic [31:0] desc_base_o;
    logic [15:0] desc_count_o;
    logic wide_o;
    logic busy_i = 0;
    logic done_i = 0;
    logic error_i = 0;
    logic [31:0] err_code_i = 0;
    logic object_cfg_request_i = 0;
    logic object_cfg_valid_o;
    logic object_cfg_ready_i = 0;
    logic [63:0] object_cfg_live_o;
    logic [511:0] object_cfg_targets_o;
    logic [31:0] object_cfg_hit_base_o;
    logic [23:0] object_cfg_hit_max_o;
    logic [31:0] object_cfg_free_base_o;
    logic [23:0] object_cfg_free_max_o;
    logic object_result_valid_i = 0;
    logic object_result_ready_o;
    logic [23:0] object_result_hit_count_i = 0;
    logic [23:0] object_result_free_count_i = 0;
    logic [23:0] object_result_alive_count_i = 0;
    logic [1:0] object_result_overflow_i = 0;
    logic perf_vertex_i = 0;
    logic perf_triangle_i = 0;
    logic perf_quad_i = 0;
    logic [2:0] perf_pixel_count_i = 0;
    logic perf_texture_stall_i = 0;
    logic perf_read_wait_i = 0;
    logic perf_resolve_busy_i = 0;
    logic perf_object_busy_i = 0;
    logic irq_o;
    always #5 clk_i = !clk_i;
    edrv32_gpu_regs u_dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
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
        .start_o(start_o),
        .abort_o(abort_o),
        .soft_rst_o(soft_rst_o),
        .desc_base_o(desc_base_o),
        .desc_count_o(desc_count_o),
        .wide_o(wide_o),
        .busy_i(busy_i),
        .done_i(done_i),
        .error_i(error_i),
        .err_code_i(err_code_i),
        .object_cfg_request_i(object_cfg_request_i),
        .object_cfg_valid_o(object_cfg_valid_o),
        .object_cfg_ready_i(object_cfg_ready_i),
        .object_cfg_live_o(object_cfg_live_o),
        .object_cfg_targets_o(object_cfg_targets_o),
        .object_cfg_hit_base_o(object_cfg_hit_base_o),
        .object_cfg_hit_max_o(object_cfg_hit_max_o),
        .object_cfg_free_base_o(object_cfg_free_base_o),
        .object_cfg_free_max_o(object_cfg_free_max_o),
        .object_result_valid_i(object_result_valid_i),
        .object_result_ready_o(object_result_ready_o),
        .object_result_hit_count_i(object_result_hit_count_i),
        .object_result_free_count_i(object_result_free_count_i),
        .object_result_alive_count_i(object_result_alive_count_i),
        .object_result_overflow_i(object_result_overflow_i),
        .perf_vertex_i(perf_vertex_i),
        .perf_triangle_i(perf_triangle_i),
        .perf_quad_i(perf_quad_i),
        .perf_pixel_count_i(perf_pixel_count_i),
        .perf_texture_stall_i(perf_texture_stall_i),
        .perf_read_wait_i(perf_read_wait_i),
        .perf_resolve_busy_i(perf_resolve_busy_i),
        .perf_object_busy_i(perf_object_busy_i),
        .irq_o(irq_o)
    );
    task tick;
        @(posedge clk_i); #1;
    endtask
    task reset;
        rst_n_i = 0;
        repeat (3) tick();
        @(negedge clk_i); rst_n_i = 1;
    endtask
    initial begin
        #2000000; $fatal(1, "FAIL timeout");
    end
    task access(input bit wr, input int addr, input int value, input int strb,
                output int result);
        @(negedge clk_i);
        s_apb_psel_i = 1; s_apb_penable_i = 0;
        s_apb_paddr_i = 12'(addr); s_apb_pwdata_i = value;
        s_apb_pwrite_i = wr; s_apb_pstrb_i = 4'(strb);
        tick();
        @(negedge clk_i);
        s_apb_penable_i = 1;
        // Only setup data may affect the access phase.
        s_apb_paddr_i = 12'hffc; s_apb_pwdata_i = ~value;
        #1; result = s_apb_prdata_o;
        if (!s_apb_pready_o || s_apb_pslverr_o) $fatal(1, "FAIL APB response");
        tick();
        @(negedge clk_i); s_apb_psel_i = 0; s_apb_penable_i = 0;
    endtask
    task rd(input int addr, input int expected);
        int value;
        access(0,addr,0,15,value);
        if (value !== expected) $fatal(1,"FAIL regs %x expected %x actual %x",addr,expected,value);
    endtask
    task wr(input int addr, input int value, input int strb=15);
        int ignored;
        access(1,addr,value,strb,ignored);
    endtask
    initial begin
        reset();
        rd(0,'h60001); rd(8,2); rd(4,0); rd('h2c,0);
        for (int a='h40;a<'h80;a+=4) rd(a,0);
        for (int a='h110;a<'h180;a+=4) rd(a,0);
        wr(0,-1); rd(0,'h60001); wr('h2c,-1); rd('h2c,0);
        wr(4,15);
        if(!start_o || !abort_o || !soft_rst_o || !enable_o) $fatal(1,"FAIL CTRL pulses");
        tick();if(start_o || abort_o || soft_rst_o) $fatal(1,"FAIL pulse width");
        wr('h28,0);if(!start_o) $fatal(1,"FAIL DOORBELL");tick();
        wr(4,1); rd(4,1); wr('h20,'h1234567f); rd('h20,'h12345660);
        wr('h20,'haabbccdd,2); rd('h20,'h1234cc60);
        wr('h24,-1); rd('h24,65535); wr('h100,-1); rd('h100,1);
        wr('hc,3);
        @(negedge clk_i); done_i=1; tick();
        @(negedge clk_i); done_i=0; rd('h2c,1); rd('h10,1);
        if (!irq_o) $fatal(1,"FAIL DONE IRQ");
        wr('h10,1); if (irq_o) $fatal(1,"FAIL IRQ clear");
        @(negedge clk_i); error_i=1; err_code_i=4; tick();
        @(negedge clk_i); error_i=0; rd('h14,4); rd(8,6);
        wr('h10,2); rd('h14,0); rd(8,2);
        wr('h110,'h12345678); wr('h140,'h76543210);
        @(negedge clk_i); object_cfg_request_i=1; tick();
        @(negedge clk_i); object_cfg_request_i=0;
        wr('h110,-1); wr('h140,-1);
        if (!object_cfg_valid_o || object_cfg_live_o != 64'h12345678
            || object_cfg_targets_o[31:0] != 'h76543210) $fatal(1,"FAIL snapshot");
        object_cfg_ready_i=1; tick();
        @(negedge clk_i); object_result_valid_i=1;
        object_result_hit_count_i=9; object_result_free_count_i=7;
        object_result_alive_count_i=5; object_result_overflow_i=3; tick();
        @(negedge clk_i); object_result_valid_i=0;
        rd('h120,9); rd('h12c,7); rd('h130,5); rd('h134,3);
        @(negedge clk_i); perf_pixel_count_i=4; perf_vertex_i=1;
        tick(); @(negedge clk_i); perf_pixel_count_i=0; perf_vertex_i=0;
        tick(); rd('h44,1); rd('h50,4); rd('h64,0);
        $display("PASS gpu_regs reset/RW/RO/setup/IRQ/snapshot/PERF"); $finish;
    end
endmodule
